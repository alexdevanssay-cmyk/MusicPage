"""
app/score_following/reference_builder.py
─────────────────────────────────────────
Converts a MusicXML file into the reference chroma sequence used by OnlineDTW.

Pipeline
─────────
MusicXML
  → music21 parse
  → flat note list  [(pitch_midi, onset_secs, duration_secs, measure, page)]
  → piano-roll matrix  (F frames × 128 pitches)
  → chroma matrix       (F frames × 12)   ← saved to disk as .npy

Frame rate is determined by settings.SAMPLE_RATE / settings.HOP_LENGTH ≈ 43 fps
at default settings, giving ~23 ms per frame – well below the 100 ms target.
"""
from __future__ import annotations

import logging
from pathlib import Path
from typing import List, Tuple

import numpy as np
import music21 as m21
from music21 import converter, note, chord, tempo

from app.core.config import settings

logger = logging.getLogger(__name__)

# Type alias: (pitch_midi, onset_secs, duration_secs, measure_number, page_number)
NoteEvent = Tuple[int, float, float, int, int]


class ReferenceBuilder:
    """
    Build the reference chroma sequence for a given MusicXML score.

    Parameters
    ----------
    musicxml_path : Path
        Path to a MusicXML (.xml / .mxl) file.
    bpm_override : float | None
        Force a specific BPM (useful when the PDF has no tempo marking).
    """

    def __init__(
        self,
        musicxml_path: Path,
        bpm_override: float | None = None,
        hop_length: int | None = None,
        sr: int | None = None,
    ) -> None:
        self.path = Path(musicxml_path)
        self.bpm_override = bpm_override
        self.hop_length = hop_length or settings.HOP_LENGTH
        self.sr = sr or settings.SAMPLE_RATE
        self.frame_rate: float = self.sr / self.hop_length   # frames per second

        # Populated by build()
        self.note_events: List[NoteEvent] = []
        self.chroma: np.ndarray = np.empty((0, 12), dtype=np.float32)
        self.total_secs: float = 0.0
        self.page_map: List[Tuple[int, int, int]] = []  # (page, first_frame, last_frame)

    # ── Public API ──────────────────────────────────────────────────────────────

    def build(self) -> np.ndarray:
        """
        Parse MusicXML and return the reference chroma matrix (N_frames × 12).
        The result is also stored in self.chroma.
        """
        logger.info("Parsing MusicXML: %s", self.path)
        score = converter.parse(str(self.path))

        note_events = self._extract_notes(score)
        self.note_events = note_events

        if not note_events:
            raise ValueError(f"No notes found in {self.path}")

        self.total_secs = max(on + dur for _, on, dur, *_ in note_events)
        n_frames = int(np.ceil(self.total_secs * self.frame_rate)) + 1

        piano_roll = self._build_piano_roll(note_events, n_frames)
        self.chroma = self._piano_roll_to_chroma(piano_roll)

        self._build_page_map(note_events, n_frames)

        logger.info(
            "Reference built: %d frames, %.1f s, %d unique pitches",
            n_frames, self.total_secs, len({e[0] for e in note_events}),
        )
        return self.chroma

    def save(self, path: Path) -> None:
        """Persist chroma matrix to disk as a .npy file."""
        np.save(str(path), self.chroma)
        logger.info("Saved reference chroma to %s", path)

    def _rebuild_page_map(self) -> None:
        """
        Reconstruct page_map from self.note_events (no full re-parse needed).
        Called by ScoreService after loading note_events from the database.
        """
        if not self.note_events:
            self.page_map = []
            return
        total_secs = max(on + dur for _, on, dur, *_ in self.note_events)
        n_frames = int(np.ceil(total_secs * self.frame_rate)) + 1
        self._build_page_map(self.note_events, n_frames)

    @classmethod
    def load(cls, path: Path) -> np.ndarray:
        """Load a previously-saved chroma matrix."""
        return np.load(str(path)).astype(np.float32)

    def frame_to_measure(self, frame: int) -> int:
        """
        Map a reference frame index to a (1-based) measure number.
        Uses bisect for O(log n) lookup instead of a linear scan.
        """
        if not self.note_events:
            return 1
        onset_s = frame / self.frame_rate
        # Binary search on sorted onset times
        import bisect
        onsets  = [e[1] for e in self.note_events]   # already sorted
        measures= [e[3] for e in self.note_events]
        idx = bisect.bisect_right(onsets, onset_s)
        idx = max(0, min(idx, len(measures) - 1))
        return int(measures[idx])

    def frame_to_page(self, frame: int) -> int:
        """Map a reference frame index to a 1-based page number."""
        for page, first, last in self.page_map:
            if first <= frame <= last:
                return page
        return 1

    # ── Private helpers ──────────────────────────────────────────────────────────

    def _extract_notes(self, score: m21.stream.Score) -> List[NoteEvent]:
        """
        Walk the score tree and collect all sounding note events.
        Handles polyphonic staves, chords, and multiple tempo changes.
        """
        events: List[NoteEvent] = []

        # Build a tempo map: list of (quarterLength_offset, bpm)
        tempo_map = self._build_tempo_map(score)

        # Page numbers are not always present in MusicXML; we attempt to
        # extract them from system breaks or fallback to 1.
        page_breaks = self._find_page_breaks(score)

        flat = score.flatten()

        for el in flat.notes:
            offset_ql = float(el.offset)
            onset_s = self._ql_to_seconds(offset_ql, tempo_map)
            measure_n = el.measureNumber or 1
            page_n = self._measure_to_page(measure_n, page_breaks)

            if isinstance(el, note.Note):
                events.append((
                    el.pitch.midi,
                    onset_s,
                    float(el.duration.quarterLength) * 60.0 / self._bpm_at(offset_ql, tempo_map),
                    measure_n,
                    page_n,
                ))
            elif isinstance(el, chord.Chord):
                dur_s = float(el.duration.quarterLength) * 60.0 / self._bpm_at(offset_ql, tempo_map)
                for p in el.pitches:
                    events.append((p.midi, onset_s, dur_s, measure_n, page_n))

        events.sort(key=lambda e: e[1])
        return events

    def _build_piano_roll(self, events: List[NoteEvent], n_frames: int) -> np.ndarray:
        """Build a binary piano roll matrix (n_frames × 128)."""
        roll = np.zeros((n_frames, 128), dtype=np.float32)
        for midi, onset, dur, _, _ in events:
            if not (0 <= midi < 128):
                continue
            f_on  = int(onset * self.frame_rate)
            f_off = min(int((onset + dur) * self.frame_rate) + 1, n_frames)
            roll[f_on:f_off, midi] = 1.0
        return roll

    @staticmethod
    def _piano_roll_to_chroma(roll: np.ndarray) -> np.ndarray:
        """Fold piano roll into chroma by summing over octaves and L2-normalising."""
        n_frames = roll.shape[0]
        chroma = np.zeros((n_frames, 12), dtype=np.float32)
        for midi_pitch in range(128):
            chroma[:, midi_pitch % 12] += roll[:, midi_pitch]

        # L2-normalise each frame
        norms = np.linalg.norm(chroma, axis=1, keepdims=True)
        norms = np.where(norms < 1e-7, 1.0, norms)
        return chroma / norms

    def _build_page_map(self, events: List[NoteEvent], n_frames: int) -> None:
        """Build list of (page, first_frame, last_frame) tuples."""
        page_frames: dict[int, list[int]] = {}
        for _, onset, dur, _, page in events:
            f_on  = int(onset * self.frame_rate)
            f_off = min(int((onset + dur) * self.frame_rate) + 1, n_frames)
            page_frames.setdefault(page, []).extend([f_on, f_off])

        self.page_map = []
        for page, frames in sorted(page_frames.items()):
            self.page_map.append((page, min(frames), max(frames)))

    # ── Tempo helpers ────────────────────────────────────────────────────────────

    def _build_tempo_map(self, score: m21.stream.Score) -> List[Tuple[float, float]]:
        """Returns [(offset_ql, bpm), ...] sorted by offset."""
        if self.bpm_override:
            return [(0.0, self.bpm_override)]

        tempos: List[Tuple[float, float]] = []
        for el in score.flatten().getElementsByClass(tempo.MetronomeMark):
            bpm = el.number or 120.0
            tempos.append((float(el.offset), float(bpm)))

        if not tempos:
            tempos = [(0.0, 120.0)]
        return sorted(tempos, key=lambda x: x[0])

    @staticmethod
    def _bpm_at(offset_ql: float, tempo_map: List[Tuple[float, float]]) -> float:
        bpm = tempo_map[0][1]
        for off, b in tempo_map:
            if off <= offset_ql:
                bpm = b
            else:
                break
        return bpm

    @staticmethod
    def _ql_to_seconds(offset_ql: float, tempo_map: List[Tuple[float, float]]) -> float:
        """Convert a quarter-length offset to wall-clock seconds."""
        secs = 0.0
        prev_off = 0.0
        prev_bpm = tempo_map[0][1]

        for off, bpm in tempo_map[1:]:
            if off > offset_ql:
                break
            secs += (off - prev_off) * 60.0 / prev_bpm
            prev_off, prev_bpm = off, bpm

        secs += (offset_ql - prev_off) * 60.0 / prev_bpm
        return secs

    @staticmethod
    def _find_page_breaks(score: m21.stream.Score) -> List[int]:
        """
        Return list of measure numbers that start a new page.
        Falls back to splitting every 12 measures (typical for A4 paper).
        """
        breaks: List[int] = [1]
        found_any = False
        for el in score.flatten():
            if isinstance(el, m21.layout.SystemLayout) and el.isNew:
                m = el.measureNumber
                if m and m not in breaks:
                    breaks.append(m)
                    found_any = True

        if not found_any:
            # Heuristic fallback: new page every 12 measures
            all_measures = sorted({
                n.measureNumber
                for n in score.flatten().notes
                if n.measureNumber
            })
            if all_measures:
                for i, m in enumerate(all_measures):
                    if (i % 12) == 0 and m not in breaks:
                        breaks.append(m)

        return sorted(set(breaks))

    def _measure_to_page(self, measure: int, breaks: List[int]) -> int:
        """Return 1-based page number for a given measure."""
        page = 1
        for i, start in enumerate(breaks):
            if measure >= start:
                page = i + 1
        return page
