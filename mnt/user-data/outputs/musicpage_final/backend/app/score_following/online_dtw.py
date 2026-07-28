"""
app/score_following/online_dtw.py
──────────────────────────────────
Real-time Online Dynamic Time Warping for score following.

Algorithm reference:
  Dixon, S. (2005).  Live Tracking of Musical Performances Using On-Line Time Warping.
  Proc. ICMC, pp. 92–95.

Key design choices
──────────────────
• Feature space  : 12-dimensional chroma vectors (pitch-class energy).
  Chroma is instrument-agnostic and handles transient notes gracefully.

• Distance       : Cosine distance (1 – cosine_similarity).
  Normalised chroma vectors make cosine distance scale-invariant.

• Step condition : Three predecessors – diagonal, horizontal, vertical.
  Allows arbitrary speed ratios while penalising pure slippage.

• Window         : Sakoe-Chiba band of ±W around the running diagonal.
  Keeps time complexity O(W) per frame instead of O(N).

• Smoothing      : Median filter over the last K estimated positions.
  Suppresses brief errors without adding significant latency.
"""
from __future__ import annotations

import numpy as np
from collections import deque
from dataclasses import dataclass, field
from typing import Deque


@dataclass
class DTWState:
    """Snapshot of the follower's internal state (useful for serialisation)."""
    t: int                 = 0      # observation frames processed
    position: int          = 0      # smoothed reference frame estimate
    raw_position: int      = 0      # unsmoothed estimate
    confidence: float      = 0.0    # 0–1
    cost: float            = 0.0    # accumulated DTW cost at current position


class OnlineDTW:
    """
    Incremental score follower.

    Usage::

        follower = OnlineDTW(reference_chroma)   # shape (N, 12)
        for frame in audio_stream:
            chroma = extract_chroma(frame)       # shape (12,)
            position, confidence = follower.step(chroma)
    """

    def __init__(
        self,
        reference: np.ndarray,      # (N, 12) normalised chroma sequence
        window: int = 150,          # Sakoe-Chiba half-bandwidth (frames)
        smooth_k: int = 7,          # median-filter length
        max_speed_ratio: float = 3.0,  # max ref/obs ratio (prevents runaway)
    ) -> None:
        if reference.ndim != 2 or reference.shape[1] != 12:
            raise ValueError("reference must have shape (N, 12)")

        self._ref: np.ndarray = reference.astype(np.float32)   # (N, 12)
        self.N = len(reference)
        self.W = window
        self.smooth_k = smooth_k
        self.max_speed_ratio = max_speed_ratio

        # Previous accumulated-cost column (shape N), initialised to ∞
        self._prev: np.ndarray = np.full(self.N, np.inf, dtype=np.float32)
        self._prev[0] = 0.0

        # State
        self._t: int = 0              # observation counter
        self._n: int = 0              # current raw position in reference
        self._pos_history: Deque[int] = deque(maxlen=smooth_k)
        self._cost_history: Deque[float] = deque(maxlen=20)

        self.state = DTWState()

    # ── Public API ──────────────────────────────────────────────────────────────

    def step(self, observation: np.ndarray) -> tuple[int, float]:
        """
        Process one chroma frame (shape 12).

        Returns
        -------
        position   : int   Smoothed index into the reference sequence.
        confidence : float Value in [0, 1].  Higher = more certain.
        """
        obs = np.asarray(observation, dtype=np.float32)
        if obs.shape != (12,):
            raise ValueError(f"Expected shape (12,), got {obs.shape}")

        self._t += 1

        # ── Compute new accumulated-cost column ────────────────────────────────
        cur = np.full(self.N, np.inf, dtype=np.float32)

        n_lo = max(0, self._n - self.W)
        n_hi = min(self.N - 1, self._n + self.W)

        for i in range(n_lo, n_hi + 1):
            d = self._cosine_dist(self._ref[i], obs)

            # Three predecessors (Dixon 2005, eq. 1)
            preds = (
                self._prev[i],                                   # horizontal
                (self._prev[i - 1] if i > 0 else np.inf),       # diagonal
                (cur[i - 1]        if i > 0 else np.inf),       # vertical
            )
            best_pred = min(preds)
            cur[i] = d + (0.0 if np.isinf(best_pred) else best_pred)

        self._prev = cur

        # ── Find best match in window ──────────────────────────────────────────
        window_slice = cur[n_lo:n_hi + 1]
        best_offset = int(np.argmin(window_slice))
        raw_pos = n_lo + best_offset
        best_cost = float(cur[raw_pos])

        self._cost_history.append(best_cost)
        self._pos_history.append(raw_pos)

        # Enforce forward-only motion (score doesn't go backwards)
        raw_pos = max(raw_pos, self._n)

        self._n = raw_pos
        smoothed = int(np.median(list(self._pos_history)))
        smoothed = min(smoothed, self.N - 1)

        # ── Confidence ────────────────────────────────────────────────────────
        max_cost = max(self._cost_history) if self._cost_history else 1.0
        confidence = max(0.0, 1.0 - best_cost / (max_cost + 1e-8))
        confidence = round(float(confidence), 4)

        # ── Update state ──────────────────────────────────────────────────────
        self.state = DTWState(
            t=self._t,
            position=smoothed,
            raw_position=raw_pos,
            confidence=confidence,
            cost=best_cost,
        )

        return smoothed, confidence

    def seek(self, reference_frame: int) -> None:
        """Manually jump to a reference position (e.g. after page turn override)."""
        self._n = max(0, min(reference_frame, self.N - 1))
        self._pos_history.clear()
        self._cost_history.clear()
        # Rebuild prev column: set cost 0 at target, ∞ elsewhere
        self._prev = np.full(self.N, np.inf, dtype=np.float32)
        self._prev[self._n] = 0.0

    def reset(self) -> None:
        """Full reset to beginning of score."""
        self.seek(0)
        self._t = 0
        self.state = DTWState()

    # ── Private helpers ─────────────────────────────────────────────────────────

    @staticmethod
    def _cosine_dist(a: np.ndarray, b: np.ndarray) -> float:
        """Cosine distance ∈ [0, 1].  0 = identical direction, 1 = orthogonal."""
        na = np.linalg.norm(a)
        nb = np.linalg.norm(b)
        if na < 1e-7 or nb < 1e-7:
            return 1.0
        return float(1.0 - np.dot(a, b) / (na * nb))
