"""
app/score_following/position_tracker.py
────────────────────────────────────────
Translates the raw frame-level output of OnlineDTW into musically
meaningful position information:

  frame index  →  measure number, page number, progress (0–1)

Also decides when to emit "preload next page" and "turn page" events.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import List, Optional, Tuple

from app.core.config import settings
from app.score_following.reference_builder import ReferenceBuilder

logger = logging.getLogger(__name__)


@dataclass
class ScorePosition:
    measure: int           = 1
    page: int              = 1
    page_progress: float   = 0.0    # 0–1 within the current page
    global_progress: float = 0.0    # 0–1 over the whole score
    confidence: float      = 0.0

    should_preload_next: bool = False
    should_turn_page: bool    = False
    next_page: Optional[int]  = None


class PositionTracker:
    """
    Stateful mapper from (reference_frame, confidence) → ScorePosition.

    Parameters
    ----------
    builder : ReferenceBuilder
        Must have been built already (builder.build() called).
    preload_thr : float
        page_progress above which the next page should be pre-loaded.
    turn_thr : float
        page_progress above which the page should actually change.
    """

    def __init__(
        self,
        builder: ReferenceBuilder,
        preload_thr: float = settings.PRELOAD_THRESHOLD,
        turn_thr: float = settings.PAGE_TURN_THRESHOLD,
    ) -> None:
        self._b = builder
        self._preload_thr = preload_thr
        self._turn_thr = turn_thr

        self._n_frames: int = len(builder.chroma)
        self._current_page: int = 1
        self._preload_emitted: bool = False
        self._turn_emitted: bool = False

        # page_map: [(page, first_frame, last_frame)]
        self._page_map: List[Tuple[int, int, int]] = builder.page_map
        self._total_pages: int = max((p for p, *_ in self._page_map), default=1)

    # ── Public ───────────────────────────────────────────────────────────────────

    def update(self, frame: int, confidence: float) -> ScorePosition:
        """
        Convert a raw DTW frame index to a full ScorePosition.

        Call once per OnlineDTW.step() result.
        """
        frame = max(0, min(frame, self._n_frames - 1))

        measure        = self._b.frame_to_measure(frame)
        page           = self._b.frame_to_page(frame)
        page_progress  = self._page_progress(frame, page)
        global_progress= frame / max(self._n_frames - 1, 1)

        # Page change detection
        if page != self._current_page:
            logger.info("Page changed %d → %d (measure %d)", self._current_page, page, measure)
            self._current_page = page
            self._preload_emitted = False
            self._turn_emitted    = False

        should_preload = False
        should_turn    = False
        next_page      = page + 1 if page < self._total_pages else None

        if next_page is not None:
            if page_progress >= self._preload_thr and not self._preload_emitted:
                should_preload = True
                self._preload_emitted = True

            if page_progress >= self._turn_thr and not self._turn_emitted:
                should_turn = True
                self._turn_emitted = True

        return ScorePosition(
            measure=measure,
            page=page,
            page_progress=round(page_progress, 4),
            global_progress=round(global_progress, 4),
            confidence=round(confidence, 4),
            should_preload_next=should_preload,
            should_turn_page=should_turn,
            next_page=next_page,
        )

    def seek_to_measure(self, measure: int) -> int:
        """
        Return the best reference frame for a given measure number.
        Used when the user manually navigates to a measure.
        """
        target_s = None
        for midi, onset, dur, m, _ in self._b.note_events:
            if m == measure:
                target_s = onset
                break

        if target_s is None:
            return 0

        return int(target_s * self._b.frame_rate)

    # ── Private ──────────────────────────────────────────────────────────────────

    def _page_progress(self, frame: int, page: int) -> float:
        """Progress within the current page: 0.0 (start) → 1.0 (end)."""
        for pg, first, last in self._page_map:
            if pg == page:
                span = last - first
                if span <= 0:
                    return 0.0
                return (frame - first) / span
        return 0.0
