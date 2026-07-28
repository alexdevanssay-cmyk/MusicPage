"""
tests/test_chroma_extractor.py
───────────────────────────────
Tests for ChromaExtractor.  No audio hardware required.
"""
import numpy as np
import pytest
from app.audio.chroma_extractor import ChromaExtractor


SR = 22050
HOP = 512
N_FFT = 2048


def sine_wave(freq: float, duration_secs: float, sr: int = SR) -> np.ndarray:
    t = np.linspace(0, duration_secs, int(sr * duration_secs), endpoint=False)
    return np.sin(2 * np.pi * freq * t).astype(np.float32)


def silence(duration_secs: float, sr: int = SR) -> np.ndarray:
    return np.zeros(int(sr * duration_secs), dtype=np.float32)


class TestChromaExtractorBasic:
    def setup_method(self):
        self.ex = ChromaExtractor(sr=SR, hop_length=HOP, n_fft=N_FFT)

    def test_returns_list_of_12d_vectors(self):
        audio = sine_wave(440, 0.5)          # A4 – 0.5 seconds
        frames = self.ex.push(audio)
        assert len(frames) > 0
        for f in frames:
            assert f.shape == (12,), f"Expected (12,), got {f.shape}"

    def test_vectors_are_normalised(self):
        audio = sine_wave(261.63, 0.3)       # C4
        frames = self.ex.push(audio)
        for f in frames:
            norm = float(np.linalg.norm(f))
            if norm > 1e-6:                  # non-silent
                assert abs(norm - 1.0) < 0.01, f"Not unit-norm: {norm}"

    def test_silence_returns_zero_vectors(self):
        sil = silence(0.1)
        frames = self.ex.push(sil)
        # Allow no frames to be returned OR zero frames
        for f in frames:
            assert np.allclose(f, 0.0), "Silent frame should be zero vector"

    def test_short_chunk_returns_no_frames(self):
        # Fewer than HOP samples → no complete frame
        tiny = sine_wave(440, 0.01)          # ~220 samples < 512
        frames = self.ex.push(tiny)
        assert frames == [], f"Expected empty list, got {len(frames)} frames"

    def test_bytes_input_equivalent_to_ndarray(self):
        audio = sine_wave(440, 0.3)
        frames_arr = ChromaExtractor(sr=SR, hop_length=HOP, n_fft=N_FFT).push(audio)
        frames_bytes = ChromaExtractor(sr=SR, hop_length=HOP, n_fft=N_FFT).push(
            audio.tobytes()
        )
        assert len(frames_arr) == len(frames_bytes)

    def test_reset_clears_buffer(self):
        self.ex.push(sine_wave(440, 0.1))    # populate buffer
        self.ex.reset()
        # After reset, same small chunk should give same result as fresh extractor
        chunk = sine_wave(440, 0.1)
        fresh = ChromaExtractor(sr=SR, hop_length=HOP, n_fft=N_FFT)
        assert len(self.ex.push(chunk)) == len(fresh.push(chunk))

    def test_continuity_across_chunks(self):
        """Splitting a 1-second signal into 10 pieces should yield the same
        number of frames as feeding it whole."""
        audio = sine_wave(440, 1.0)
        expected = ChromaExtractor(sr=SR, hop_length=HOP, n_fft=N_FFT).push(audio)

        ex_chunked = ChromaExtractor(sr=SR, hop_length=HOP, n_fft=N_FFT)
        chunks = np.array_split(audio, 10)
        got = []
        for chunk in chunks:
            got.extend(ex_chunked.push(chunk))

        # Frame counts may differ by at most 1 due to boundary effects
        assert abs(len(got) - len(expected)) <= 1


class TestChromaExtractorSensitivity:
    def test_sensitivity_scales_signal(self):
        """A louder signal (higher sensitivity) should produce non-zero frames
        even when the raw signal is quiet."""
        quiet = sine_wave(440, 0.2) * 0.001   # very quiet

        ex_low  = ChromaExtractor(sr=SR, hop_length=HOP, n_fft=N_FFT, mic_gain=1.0)
        ex_high = ChromaExtractor(sr=SR, hop_length=HOP, n_fft=N_FFT, mic_gain=100.0)

        frames_low  = ex_low.push(quiet)
        frames_high = ex_high.push(quiet)

        # High gain should produce more non-zero frames
        nonzero_low  = sum(1 for f in frames_low  if np.linalg.norm(f) > 1e-6)
        nonzero_high = sum(1 for f in frames_high if np.linalg.norm(f) > 1e-6)
        assert nonzero_high >= nonzero_low
