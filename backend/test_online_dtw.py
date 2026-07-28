"""
tests/test_online_dtw.py
─────────────────────────
Unit tests for OnlineDTW.

These tests run without any audio hardware or network access.
They verify correctness and robustness of the core algorithm.
"""
import numpy as np
import pytest
from app.score_following.online_dtw import OnlineDTW


# ── Fixtures ──────────────────────────────────────────────────────────────────

def make_chroma(pitch_class: int, n_frames: int = 1) -> np.ndarray:
    """Return a one-hot chroma vector (or matrix of identical rows)."""
    row = np.zeros(12, dtype=np.float32)
    row[pitch_class % 12] = 1.0
    return np.tile(row, (n_frames, 1)) if n_frames > 1 else row


def make_scale_reference(length: int = 60) -> np.ndarray:
    """
    Reference: chromatic scale cycling C→B repeated.
    Gives a predictable known-position test case.
    """
    rows = []
    for i in range(length):
        rows.append(make_chroma(i % 12))
    return np.array(rows, dtype=np.float32)


# ── Tests ─────────────────────────────────────────────────────────────────────

class TestOnlineDTWInit:
    def test_accepts_valid_reference(self):
        ref = make_scale_reference(50)
        dtw = OnlineDTW(ref, window=20)
        assert dtw.N == 50

    def test_rejects_wrong_shape(self):
        with pytest.raises(ValueError):
            OnlineDTW(np.zeros((50, 10)))  # 10 ≠ 12 chroma bins

    def test_rejects_1d_input(self):
        with pytest.raises(ValueError):
            OnlineDTW(np.zeros(50))


class TestOnlineDTWStep:
    def test_returns_valid_position_and_confidence(self):
        ref = make_scale_reference(30)
        dtw = OnlineDTW(ref, window=15)
        pos, conf = dtw.step(make_chroma(0))
        assert 0 <= pos < 30
        assert 0.0 <= conf <= 1.0

    def test_perfect_match_advances_forward(self):
        """
        Feeding the exact reference frames in order should yield a
        monotonically advancing (or equal) position.
        """
        ref = make_scale_reference(40)
        dtw = OnlineDTW(ref, window=20)
        positions = []
        for i in range(40):
            pos, _ = dtw.step(ref[i])
            positions.append(pos)

        # Position must be non-decreasing (forward-only constraint)
        for a, b in zip(positions, positions[1:]):
            assert b >= a, f"Position went backwards: {a} → {b}"

    def test_reaches_near_end_for_full_playthrough(self):
        """After playing the full reference, position should be near the end."""
        n = 80
        ref = make_scale_reference(n)
        dtw = OnlineDTW(ref, window=30)
        pos = 0
        for i in range(n):
            pos, _ = dtw.step(ref[i])
        # Final position should be in the last 20% of the reference
        assert pos >= int(n * 0.7), f"Expected pos ≥ {int(n * 0.7)}, got {pos}"

    def test_tolerates_note_errors(self):
        """
        Inject 20% wrong pitches; follower should still track the correct region.
        """
        rng = np.random.default_rng(42)
        n = 60
        ref = make_scale_reference(n)
        dtw = OnlineDTW(ref, window=25)

        final_pos = 0
        for i in range(n):
            if rng.random() < 0.2:
                # Wrong note
                obs = make_chroma(rng.integers(0, 12))
            else:
                obs = ref[i]
            final_pos, _ = dtw.step(obs)

        assert final_pos >= int(n * 0.6), (
            f"Follower lost track with 20% errors: pos={final_pos}"
        )

    def test_seek_resets_to_target(self):
        ref = make_scale_reference(50)
        dtw = OnlineDTW(ref, window=20)
        # Run a few steps
        for i in range(10):
            dtw.step(ref[i])
        assert dtw.state.raw_position > 0

        # Seek to beginning
        dtw.seek(0)
        assert dtw._n == 0

    def test_reset_clears_state(self):
        ref = make_scale_reference(30)
        dtw = OnlineDTW(ref, window=15)
        for i in range(15):
            dtw.step(ref[i])
        dtw.reset()
        assert dtw._t == 0
        assert dtw._n == 0

    def test_silence_does_not_crash(self):
        """All-zero chroma (silence) must be handled gracefully."""
        ref = make_scale_reference(20)
        dtw = OnlineDTW(ref, window=10)
        silence = np.zeros(12, dtype=np.float32)
        for _ in range(10):
            pos, conf = dtw.step(silence)
        assert 0 <= pos < 20

    def test_tempo_double_speed(self):
        """
        Reference at normal speed, observations at double speed (skip every other frame).
        The follower should still advance through the reference.
        """
        n = 60
        ref = make_scale_reference(n)
        dtw = OnlineDTW(ref, window=30)
        pos = 0
        # Feed only even-indexed frames (2× speed)
        for i in range(0, n, 2):
            pos, _ = dtw.step(ref[i])
        assert pos >= int(n * 0.4)

    def test_tempo_half_speed(self):
        """
        Observations at half speed (each frame repeated twice).
        Position should still advance.
        """
        n = 40
        ref = make_scale_reference(n)
        dtw = OnlineDTW(ref, window=20)
        pos = 0
        for i in range(n):
            for _ in range(2):   # each frame twice
                pos, _ = dtw.step(ref[i])
        assert pos >= int(n * 0.5)


class TestCosineDistance:
    def test_identical_vectors_zero_distance(self):
        v = np.array([1.0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], dtype=np.float32)
        assert OnlineDTW._cosine_dist(v, v) == pytest.approx(0.0, abs=1e-6)

    def test_orthogonal_vectors_distance_one(self):
        a = np.array([1.0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], dtype=np.float32)
        b = np.array([0, 1.0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], dtype=np.float32)
        assert OnlineDTW._cosine_dist(a, b) == pytest.approx(1.0, abs=1e-6)

    def test_zero_vector_returns_one(self):
        a = np.zeros(12, dtype=np.float32)
        b = make_chroma(0)
        assert OnlineDTW._cosine_dist(a, b) == 1.0
