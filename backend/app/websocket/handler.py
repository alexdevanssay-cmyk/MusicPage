"""
app/websocket/handler.py
─────────────────────────
WebSocket endpoint that manages one real-time score-following session per client.

Protocol
─────────
Client → Server (JSON text frames):
  {"type": "start_session", "score_id": "...", "sensitivity": 1.0}
  {"type": "stop_session"}
  {"type": "manual_position", "measure": 5}

Client → Server (binary frames):
  Raw float32 PCM audio at settings.SAMPLE_RATE Hz.

Server → Client (JSON text frames):
  {"type": "session_started", "score_id": "...", "total_pages": 4, ...}
  {"type": "position_update", "measure": 10, "page": 2, "progress": 0.45, ...}
  {"type": "preload_next_page", "page": 3}
  {"type": "page_change", "from_page": 2, "to_page": 3}
  {"type": "error", "message": "..."}
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import threading
import time
from typing import Optional

import numpy as np

from fastapi import WebSocket, WebSocketDisconnect
from sqlalchemy.ext.asyncio import AsyncSession

from app.audio.chroma_extractor import ChromaExtractor
from app.core.config import settings
from app.models.database import AsyncSessionLocal
from app.score_following.online_dtw import OnlineDTW
from app.score_following.performance_stats import PerformanceStats
from app.score_following.position_tracker import PositionTracker
from app.services.score_service import ScoreService

logger = logging.getLogger(__name__)

# ── Live diagnostics (opt-in via MUSICPAGE_DIAG=1) ──────────────────────────────
# When enabled, every processed chroma frame appends one CSV row so the follower's
# behaviour can be watched and tuned against a real performance.
_DIAG_ENABLED = os.environ.get("MUSICPAGE_DIAG") == "1"
_DIAG_FILE = os.environ.get("MUSICPAGE_DIAG_FILE", "diag.csv")
_diag_lock = threading.Lock()
_diag_fh = None


def _diag_write(row: str) -> None:
    if not _DIAG_ENABLED:
        return
    global _diag_fh
    with _diag_lock:
        if _diag_fh is None:
            _diag_fh = open(_DIAG_FILE, "a", buffering=1, encoding="utf-8")
            _diag_fh.write(
                "ts,dtw_t,ref_frame,dtw_cost,confidence,chroma_norm,"
                "measure,page,progress,global\n"
            )
        _diag_fh.write(row + "\n")


class SessionState:
    """All mutable state for one active WebSocket session."""

    def __init__(self, score_id: str, sensitivity: float) -> None:
        self.score_id = score_id
        self.sensitivity = sensitivity
        self.dtw: Optional[OnlineDTW] = None
        self.tracker: Optional[PositionTracker] = None
        self.extractor: Optional[ChromaExtractor] = None
        self.stats: Optional[PerformanceStats] = None
        self.is_following = False
        self.last_page = 1
        self.audio_chunks = 0


async def ws_session_handler(websocket: WebSocket) -> None:
    """
    Main WebSocket handler.  One coroutine per connected client.
    """
    await websocket.accept()
    client = websocket.client
    logger.info("WS connected: %s", client)

    state: Optional[SessionState] = None

    try:
        while True:
            # Receive either binary (audio) or text (control)
            message = await websocket.receive()

            # The low-level receive() surfaces a client disconnect as a message
            # dict (it does not raise WebSocketDisconnect).  Detect it and exit
            # cleanly instead of looping into receive() again — which would raise
            # RuntimeError and log a spurious traceback on every disconnect.
            if message["type"] == "websocket.disconnect":
                break

            # ── Binary: audio chunk ─────────────────────────────────────────────
            if "bytes" in message and message["bytes"]:
                if state is None or not state.is_following:
                    continue

                pcm_bytes: bytes = message["bytes"]
                state.audio_chunks += 1
                if state.audio_chunks == 1 or state.audio_chunks % 40 == 0:
                    import numpy as _np
                    _a = _np.frombuffer(pcm_bytes, dtype=_np.float32)
                    _rms = float(_np.sqrt(_np.mean(_a ** 2))) if _a.size else 0.0
                    logger.info("AUDIO_IN chunk#%d bytes=%d rms=%.5f",
                                state.audio_chunks, len(pcm_bytes), _rms)
                await _process_audio(websocket, state, pcm_bytes)

            # ── Text: control message ───────────────────────────────────────────
            elif "text" in message and message["text"]:
                data = json.loads(message["text"])
                msg_type = data.get("type")

                if msg_type == "start_session":
                    state = await _start_session(websocket, data)

                elif msg_type == "stop_session":
                    if state:
                        state.is_following = False
                        logger.info("Session stopped: %s", state.score_id)
                        if state.stats is not None:
                            await websocket.send_text(json.dumps(state.stats.summary()))

                elif msg_type == "manual_position":
                    if state and state.tracker and state.dtw:
                        measure = int(data.get("measure", 1))
                        ref_frame = state.tracker.seek_to_measure(measure)
                        state.dtw.seek(ref_frame)
                        logger.info("Manual seek to measure %d (frame %d)", measure, ref_frame)

    except WebSocketDisconnect:
        logger.info("WS disconnected: %s", client)
    except Exception as exc:
        logger.exception("WS error: %s", exc)
        try:
            await websocket.send_text(json.dumps({"type": "error", "message": str(exc)}))
        except Exception:
            pass


# ── Session start ─────────────────────────────────────────────────────────────────

async def _start_session(websocket: WebSocket, data: dict) -> Optional[SessionState]:
    score_id  = data.get("score_id")
    sensitivity = float(data.get("sensitivity", 1.0))

    if not score_id:
        await _send_error(websocket, "score_id is required")
        return None

    async with AsyncSessionLocal() as db:
        svc = ScoreService(db)
        try:
            builder = await svc.get_reference_builder(score_id)
        except Exception as exc:
            await _send_error(websocket, str(exc))
            return None

    # Instantiate the following pipeline
    extractor = ChromaExtractor(mic_gain=sensitivity)
    dtw       = OnlineDTW(
        builder.chroma,
        window=settings.DTW_WINDOW,
        smooth_k=settings.SMOOTH_FRAMES,
        stay_penalty=settings.DTW_STAY_PENALTY,
    )
    tracker   = PositionTracker(
        builder,
        preload_thr=settings.PRELOAD_THRESHOLD,
        turn_thr=settings.PAGE_TURN_THRESHOLD,
    )

    state = SessionState(score_id, sensitivity)
    state.extractor = extractor
    state.dtw = dtw
    state.tracker = tracker
    state.stats = PerformanceStats(
        fps=builder.frame_rate, base_bpm=getattr(builder, "base_bpm", None)
    )
    state.is_following = True

    total_pages = max((p for p, *_ in builder.page_map), default=1) if builder.page_map else 1
    await websocket.send_text(json.dumps({
        "type": "session_started",
        "score_id": score_id,
        "total_pages": total_pages,
        "total_frames": len(builder.chroma),
        "frame_rate": builder.frame_rate,
    }))

    logger.info("Session started for score %s", score_id)
    return state


# ── Audio processing ──────────────────────────────────────────────────────────────

def _compute_events(state: SessionState, pcm_bytes: bytes) -> list[dict]:
    """
    Pure-CPU part of processing one audio chunk: extract chroma, run the DTW
    follower, and build the list of outbound event dicts (in order).

    This is deliberately synchronous and free of any I/O so it can be run in a
    worker thread via ``asyncio.to_thread`` — librosa/numba feature extraction
    is CPU-bound (and pays a one-off JIT cost on first use), so running it on
    the event loop would block all WebSocket traffic for the session.
    """
    events: list[dict] = []
    for chroma in state.extractor.push(pcm_bytes, state.sensitivity):
        ref_frame, confidence = state.dtw.step(chroma)
        position = state.tracker.update(ref_frame, confidence)
        if state.stats is not None:
            state.stats.update(state.dtw.state.t, ref_frame, confidence)

        if _DIAG_ENABLED:
            _diag_write(
                f"{time.time():.3f},{state.dtw.state.t},{ref_frame},"
                f"{state.dtw.state.cost:.4f},{confidence:.4f},"
                f"{float(np.linalg.norm(chroma)):.3f},{position.measure},"
                f"{position.page},{position.page_progress:.4f},"
                f"{position.global_progress:.4f}"
            )

        if position.should_preload_next and position.next_page:
            events.append({"type": "preload_next_page", "page": position.next_page})

        if position.should_turn_page and position.next_page:
            events.append({
                "type": "page_change",
                "from_page": position.page,
                "to_page": position.next_page,
            })
            state.last_page = position.next_page

        payload = {
            "type": "position_update",
            "measure": position.measure,
            "page": position.page,
            "progress": position.page_progress,
            "global_progress": position.global_progress,
            "confidence": position.confidence,
        }
        if state.stats is not None:
            payload["stats"] = state.stats.live()
        events.append(payload)
    return events


async def _process_audio(
    websocket: WebSocket, state: SessionState, pcm_bytes: bytes
) -> None:
    """
    Process one incoming audio chunk:
      1. Extract chroma frames + run the follower off the event loop (thread)
      2. Emit the resulting position/page events over the WebSocket
    """
    events = await asyncio.to_thread(_compute_events, state, pcm_bytes)
    for event in events:
        await websocket.send_text(json.dumps(event))


# ── Utility ───────────────────────────────────────────────────────────────────────

async def _send_error(websocket: WebSocket, message: str) -> None:
    await websocket.send_text(json.dumps({"type": "error", "message": message}))
