"""
app/score_following/performance_stats.py
─────────────────────────────────────────
Live performance statistics derived from the follower's per-frame output.

Feeds the app's performance overlay: elapsed time, tracking confidence, the
performer's tempo relative to the score (and an absolute BPM when the reference
tempo is known), and an estimate of how many audible deviations ("wrong notes"
/ rhythm slips) have occurred.

Everything is computed incrementally from (reference position, confidence) so it
adds negligible cost to the real-time loop.
"""
from __future__ import annotations

from collections import deque
from typing import Deque, Optional, Tuple


class PerformanceStats:
    def __init__(
        self,
        fps: float,
        base_bpm: Optional[float] = None,
        tempo_window_s: float = 1.5,   # window for the rolling tempo estimate
        low_conf: float = 0.35,        # below this = a possible deviation
        high_conf: float = 0.55,       # must recover above this to re-arm
        min_bad_frames: int = 3,       # sustain before counting a wrong note
    ) -> None:
        self.fps = fps
        self.base_bpm = base_bpm
        self._low = low_conf
        self._high = high_conf
        self._min_bad = min_bad_frames

        self.frames = 0
        self._conf_sum = 0.0
        self.cur_conf = 0.0            # smoothed, for display

        self._pos_hist: Deque[Tuple[int, int]] = deque(
            maxlen=max(2, int(tempo_window_s * fps))
        )
        self.cur_tempo_rel = 1.0       # 1.0 == score's written tempo
        self._tempo_sum = 0.0
        self._tempo_n = 0
        self.tempo_min = 1.0
        self.tempo_max = 1.0

        self.wrong_notes = 0
        self._in_error = False
        self._bad_run = 0

    # ── Ingest one processed frame ────────────────────────────────────────────
    def update(self, frame_idx: int, ref_pos: int, confidence: float) -> None:
        self.frames += 1
        self._conf_sum += confidence
        # exponential smoothing so the displayed value is not jittery
        self.cur_conf = 0.85 * self.cur_conf + 0.15 * confidence if self.frames > 1 else confidence

        # ── tempo: slope of reference position vs observation frames ──────────
        self._pos_hist.append((frame_idx, ref_pos))
        if len(self._pos_hist) >= 2:
            f0, p0 = self._pos_hist[0]
            f1, p1 = self._pos_hist[-1]
            if f1 > f0:
                raw = max(0.0, (p1 - p0) / (f1 - f0))
                # smooth the displayed tempo so brief stalls/catch-ups don't make
                # the BPM readout swing wildly
                self.cur_tempo_rel = 0.9 * self.cur_tempo_rel + 0.1 * raw
                self._tempo_sum += self.cur_tempo_rel
                self._tempo_n += 1
                self.tempo_min = min(self.tempo_min, self.cur_tempo_rel)
                self.tempo_max = max(self.tempo_max, self.cur_tempo_rel)

        # ── wrong-note / deviation detection (hysteresis on confidence) ───────
        if confidence < self._low:
            self._bad_run += 1
            if not self._in_error and self._bad_run >= self._min_bad:
                self.wrong_notes += 1
                self._in_error = True
        else:
            self._bad_run = 0
            if self._in_error and confidence >= self._high:
                self._in_error = False

    # ── Derived values ────────────────────────────────────────────────────────
    @property
    def elapsed_s(self) -> float:
        return self.frames / self.fps if self.fps else 0.0

    @property
    def avg_conf(self) -> float:
        return self._conf_sum / self.frames if self.frames else 0.0

    def bpm(self) -> Optional[float]:
        if self.base_bpm is None:
            return None
        return round(self.base_bpm * self.cur_tempo_rel, 1)

    # ── Payloads ──────────────────────────────────────────────────────────────
    def live(self) -> dict:
        """Compact per-update stats for the live overlay."""
        return {
            "elapsed": round(self.elapsed_s, 1),
            "confidence": round(self.cur_conf, 3),
            "tempo_rel": round(self.cur_tempo_rel, 3),
            "bpm": self.bpm(),
            "wrong_notes": self.wrong_notes,
        }

    def summary(self) -> dict:
        """Whole-piece stats, sent when the session stops."""
        avg_rel = self._tempo_sum / self._tempo_n if self._tempo_n else 1.0
        return {
            "type": "session_summary",
            "duration": round(self.elapsed_s, 1),
            "avg_confidence": round(self.avg_conf, 3),
            "wrong_notes": self.wrong_notes,
            "avg_tempo_rel": round(avg_rel, 3),
            "tempo_rel_range": [round(self.tempo_min, 3), round(self.tempo_max, 3)],
            "avg_bpm": round(self.base_bpm * avg_rel, 1) if self.base_bpm else None,
            "base_bpm": round(self.base_bpm, 1) if self.base_bpm else None,
        }
