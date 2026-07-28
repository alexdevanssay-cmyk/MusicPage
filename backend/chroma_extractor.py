"""
app/audio/chroma_extractor.py
──────────────────────────────
Converts raw PCM audio chunks into 12-dimensional chroma vectors in real-time.

Design choices for 2026
───────────────────────
• librosa.feature.chroma_cqt  →  uses a Constant-Q Transform which gives
  better pitch resolution at low frequencies than STFT-based chroma.

• Buffer management  →  incoming chunks are accumulated in a ring buffer
  so that each chroma frame is computed over a full N_FFT window while
  advancing by HOP_LENGTH, maintaining temporal continuity across packets.

• Latency estimate   →  with sr=22050 and hop=512, one frame ≈ 23 ms.
  A 4-frame window ≈ 93 ms, well within the 100 ms requirement.

• Noise gate         →  frames below -60 dBFS are zero-padded chroma
  to avoid noisy pitch estimates during silence.
"""
from __future__ import annotations

import numpy as np
import librosa
from collections import deque
from typing import Deque, List, Optional

from app.core.config import settings


class ChromaExtractor:
    """
    Stateful, streaming chroma extractor.

    Usage::

        ex = ChromaExtractor()
        # When audio chunk arrives (float32 PCM, any length):
        frames = ex.push(pcm_chunk)
        for chroma_12 in frames:
            position = dtw.step(chroma_12)
    """

    # Silence threshold: RMS below this → emit zero chroma
    NOISE_GATE_RMS: float = 10 ** (-60 / 20)   # −60 dBFS

    def __init__(
        self,
        sr: int = settings.SAMPLE_RATE,
        hop_length: int = settings.HOP_LENGTH,
        n_fft: int = settings.N_FFT,
        n_chroma: int = settings.N_CHROMA,
        mic_gain: float = 1.0,
    ) -> None:
        self.sr = sr
        self.hop = hop_length
        self.n_fft = n_fft
        self.n_chroma = n_chroma
        self.gain = mic_gain

        # Ring buffer: keeps the last n_fft samples so CQT sees a full window
        self._buf: np.ndarray = np.zeros(n_fft, dtype=np.float32)

    # ── Public API ───────────────────────────────────────────────────────────────

    def push(self, pcm: bytes | np.ndarray, sensitivity: float = 1.0) -> List[np.ndarray]:
        """
        Ingest raw PCM data and return a list of chroma frames produced.

        Parameters
        ----------
        pcm         : bytes or float32 ndarray
            Raw audio samples.  Bytes assumed to be float32 little-endian.
        sensitivity : float
            Multiplied into the signal before extraction (user mic sensitivity).

        Returns
        -------
        List of chroma vectors (each shape (12,)).
        """
        if isinstance(pcm, (bytes, bytearray)):
            audio = np.frombuffer(pcm, dtype=np.float32).copy()
        else:
            audio = np.asarray(pcm, dtype=np.float32)

        audio *= self.gain * sensitivity

        # Append incoming samples to the ring buffer
        combined = np.concatenate([self._buf, audio])

        # How many complete hops do we have?
        n_new = len(audio)
        if n_new < self.hop:
            # Not enough data yet – just update buffer and return []
            self._buf = np.roll(self._buf, -n_new)
            self._buf[-n_new:] = audio
            return []

        # Slide over the new audio in hop-sized steps
        chromavecs: List[np.ndarray] = []
        start = 0
        while start + self.n_fft <= len(combined):
            window = combined[start:start + self.n_fft]
            c = self._compute_chroma(window)
            chromavecs.append(c)
            start += self.hop

        # Keep the last n_fft samples in the buffer
        tail = combined[max(0, len(combined) - self.n_fft):]
        self._buf = np.zeros(self.n_fft, dtype=np.float32)
        self._buf[-len(tail):] = tail

        return chromavecs

    def reset(self) -> None:
        """Clear internal buffer (call when starting a new session)."""
        self._buf = np.zeros(self.n_fft, dtype=np.float32)

    # ── Private ──────────────────────────────────────────────────────────────────

    def _compute_chroma(self, window: np.ndarray) -> np.ndarray:
        """Compute a single L2-normalised chroma vector from an n_fft window."""
        rms = float(np.sqrt(np.mean(window ** 2)))

        if rms < self.NOISE_GATE_RMS:
            return np.zeros(self.n_chroma, dtype=np.float32)

        try:
            # chroma_cqt is more pitch-accurate than chroma_stft
            cqt_chroma = librosa.feature.chroma_cqt(
                y=window,
                sr=self.sr,
                hop_length=self.n_fft,   # single frame – hop == window length
                n_chroma=self.n_chroma,
            )
            c = cqt_chroma[:, 0].astype(np.float32)
        except Exception:
            # CQT can fail on very short/silent windows – fall back to STFT chroma
            stft_chroma = librosa.feature.chroma_stft(
                y=window,
                sr=self.sr,
                n_fft=self.n_fft,
                hop_length=self.n_fft,
                n_chroma=self.n_chroma,
            )
            c = stft_chroma[:, 0].astype(np.float32)

        norm = np.linalg.norm(c)
        if norm > 1e-7:
            c /= norm

        return c
