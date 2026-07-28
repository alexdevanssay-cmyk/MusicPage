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
from typing import Optional

from fastapi import WebSocket, WebSocketDisconnect
from sqlalchemy.ext.asyncio import AsyncSession

from app.audio.chroma_extractor import ChromaExtractor
from app.core.config import settings
from app.models.database import AsyncSessionLocal
from app.score_following.online_dtw import OnlineDTW
from app.score_following.position_tracker import PositionTracker
from app.services.score_service import ScoreService

logger = logging.getLogger(__name__)


class SessionState:
    """All mutable state for one active WebSocket session."""

    def __init__(self, score_id: str, sensitivity: float) -> None:
        self.score_id = score_id
        self.sensitivity = sensitivity
        self.dtw: Optional[OnlineDTW] = None
        self.tracker: Optional[PositionTracker] = None
        self.extractor: Optional[ChromaExtractor] = None
        self.is_following = False
        self.last_page = 1


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

            # ── Binary: audio chunk ─────────────────────────────────────────────
            if "bytes" in message and message["bytes"]:
                if state is None or not state.is_following:
                    continue

                pcm_bytes: bytes = message["bytes"]
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
    dtw       = OnlineDTW(builder.chroma, window=settings.DTW_WINDOW)
    tracker   = PositionTracker(
        builder,
        preload_thr=settings.PRELOAD_THRESHOLD,
        turn_thr=settings.PAGE_TURN_THRESHOLD,
    )

    state = SessionState(score_id, sensitivity)
    state.extractor = extractor
    state.dtw = dtw
    state.tracker = tracker
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

async def _process_audio(
    websocket: WebSocket, state: SessionState, pcm_bytes: bytes
) -> None:
    """
    Process one incoming audio chunk:
      1. Extract chroma frames
      2. Feed each frame to OnlineDTW
      3. Emit position updates over WebSocket
    """
    chroma_frames = state.extractor.push(pcm_bytes, state.sensitivity)

    for chroma in chroma_frames:
        ref_frame, confidence = state.dtw.step(chroma)
        position = state.tracker.update(ref_frame, confidence)

        payload = {
            "type": "position_update",
            "measure": position.measure,
            "page": position.page,
            "progress": position.page_progress,
            "global_progress": position.global_progress,
            "confidence": position.confidence,
        }

        if position.should_preload_next and position.next_page:
            await websocket.send_text(json.dumps({
                "type": "preload_next_page",
                "page": position.next_page,
            }))

        if position.should_turn_page and position.next_page:
            await websocket.send_text(json.dumps({
                "type": "page_change",
                "from_page": position.page,
                "to_page": position.next_page,
            }))
            state.last_page = position.next_page

        await websocket.send_text(json.dumps(payload))


# ── Utility ───────────────────────────────────────────────────────────────────────

async def _send_error(websocket: WebSocket, message: str) -> None:
    await websocket.send_text(json.dumps({"type": "error", "message": message}))
