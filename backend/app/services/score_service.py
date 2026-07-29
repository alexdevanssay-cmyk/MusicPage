"""
app/services/score_service.py
──────────────────────────────
Business logic for score management:
  • Import PDF (save, OMR, parse, pre-compute chroma)
  • CRUD on Score / ScorePage / Measure rows
  • Retrieve pre-computed reference data for score following
"""
from __future__ import annotations

import json
import logging
import shutil
import uuid
from datetime import datetime
from pathlib import Path
from typing import List, Optional

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.exceptions import ScoreNotFoundError
from app.models.database import Measure, Score, ScorePage
from app.models.schemas import ScoreListItem, ScoreResponse
from app.services.omr_service import OMRService
from app.score_following.reference_builder import ReferenceBuilder

logger = logging.getLogger(__name__)


class ScoreService:
    def __init__(self, db: AsyncSession) -> None:
        self._db = db
        self._omr = OMRService()

    # ── Import ────────────────────────────────────────────────────────────────────

    async def import_pdf(
        self,
        pdf_bytes: bytes,
        filename: str,
        title: Optional[str] = None,
        composer: Optional[str] = None,
        midi_bytes: Optional[bytes] = None,
        midi_filename: Optional[str] = None,
    ) -> ScoreResponse:
        """
        Full import pipeline:
          1. Save PDF to disk
          2. Run OMR → MusicXML
          3. Parse MusicXML → measures / notes
          4. Pre-compute reference chroma and save as .npy
          5. Persist everything to SQLite
        """
        score_id = str(uuid.uuid4())
        stem = Path(filename).stem

        # Save PDF
        pdf_path = settings.SCORES_DIR / f"{score_id}_{stem}.pdf"
        pdf_path.write_bytes(pdf_bytes)

        # Create DB record (un-analysed first)
        score_title = title or stem.replace("_", " ").replace("-", " ").title()
        score = Score(
            id=score_id,
            title=score_title,
            composer=composer or "",
            pdf_path=str(pdf_path),
            is_analyzed=False,
            created_at=datetime.utcnow(),
        )
        self._db.add(score)
        await self._db.flush()

        xml_dir = settings.MUSICXML_DIR / score_id
        xml_dir.mkdir(parents=True, exist_ok=True)
        try:
            if midi_bytes:
                # Real reference straight from a MIDI/MusicXML file (no OMR).
                ext = Path(midi_filename or "score.mid").suffix or ".mid"
                ref_path = xml_dir / f"{stem}{ext}"
                ref_path.write_bytes(midi_bytes)
                await self._analyse_score(score, ref_path)
            else:
                # Fall back to OMR on the PDF (stub if the OMR engine is absent).
                xml_path = await self._omr.convert(pdf_path, xml_dir)
                await self._analyse_score(score, xml_path)
        except Exception as exc:
            logger.error("Analysis failed for %s: %s", score_id, exc)
            # Score is still saved (un-analysed)

        await self._db.commit()
        await self._db.refresh(score)

        return ScoreResponse.model_validate(score)

    # ── Analysis ──────────────────────────────────────────────────────────────────

    async def _analyse_score(self, score: Score, xml_path: Path) -> None:
        """Parse MusicXML, build measures, pre-compute chroma."""
        builder = ReferenceBuilder(xml_path)
        chroma = builder.build()

        # Persist chroma
        chroma_path = settings.CHROMA_DIR / f"{score.id}.npy"
        builder.save(chroma_path)

        # Build measure map: group note events by measure number
        measure_map: dict[int, dict] = {}
        for midi, onset, dur, m_num, p_num in builder.note_events:
            if m_num not in measure_map:
                measure_map[m_num] = {
                    "measure_number": m_num,
                    "page_number": p_num,
                    "onset_secs": onset,
                    "duration_secs": 0.0,
                    "notes": [],
                }
            measure_map[m_num]["notes"].append({
                "pitch_midi": midi,
                "onset_offset_secs": onset - measure_map[m_num]["onset_secs"],
                "duration_secs": dur,
            })
            end = onset + dur
            m_onset = measure_map[m_num]["onset_secs"]
            measure_map[m_num]["duration_secs"] = max(
                measure_map[m_num]["duration_secs"], end - m_onset
            )

        for m_num, data in sorted(measure_map.items()):
            measure = Measure(
                score_id=score.id,
                measure_number=data["measure_number"],
                page_number=data["page_number"],
                onset_secs=data["onset_secs"],
                duration_secs=data["duration_secs"],
                notes=data["notes"],
            )
            self._db.add(measure)

        # Page map
        page_seen: set[int] = set()
        page_measures: dict[int, list[int]] = {}
        for m_num, data in measure_map.items():
            p = data["page_number"]
            page_measures.setdefault(p, []).append(m_num)

        for p_num, measures in sorted(page_measures.items()):
            page = ScorePage(
                score_id=score.id,
                page_number=p_num,
                first_measure=min(measures),
                last_measure=max(measures),
            )
            self._db.add(page)

        # Update score metadata
        total_pages = max(page_measures.keys()) if page_measures else 1
        score.musicxml_path = str(xml_path)
        score.chroma_path = str(chroma_path)
        score.total_pages = total_pages
        score.total_measures = len(measure_map)
        score.duration_secs = builder.total_secs
        score.is_analyzed = True

        logger.info(
            "Score analysed: %s | %d pages, %d measures, %.1fs",
            score.id, total_pages, len(measure_map), builder.total_secs,
        )

    # ── CRUD ──────────────────────────────────────────────────────────────────────

    async def list_scores(self) -> List[ScoreListItem]:
        result = await self._db.execute(
            select(Score).order_by(Score.created_at.desc())
        )
        scores = result.scalars().all()
        return [ScoreListItem.model_validate(s) for s in scores]

    async def get_score(self, score_id: str) -> ScoreResponse:
        score = await self._db.get(Score, score_id)
        if not score:
            raise ScoreNotFoundError(score_id)
        # Update last_opened
        score.last_opened = datetime.utcnow()
        await self._db.commit()
        return ScoreResponse.model_validate(score)

    async def delete_score(self, score_id: str) -> None:
        score = await self._db.get(Score, score_id)
        if not score:
            raise ScoreNotFoundError(score_id)

        # Clean up files
        for path_attr in ("pdf_path", "musicxml_path", "chroma_path"):
            p = getattr(score, path_attr)
            if p and Path(p).exists():
                try:
                    Path(p).unlink()
                except OSError:
                    pass

        xml_dir = settings.MUSICXML_DIR / score_id
        if xml_dir.exists():
            shutil.rmtree(xml_dir, ignore_errors=True)

        await self._db.delete(score)
        await self._db.commit()

    async def toggle_favorite(self, score_id: str) -> bool:
        score = await self._db.get(Score, score_id)
        if not score:
            raise ScoreNotFoundError(score_id)
        score.is_favorite = not score.is_favorite
        await self._db.commit()
        return score.is_favorite

    # ── Reference data ────────────────────────────────────────────────────────────

    async def get_reference_builder(self, score_id: str) -> ReferenceBuilder:
        """Return a fully-built ReferenceBuilder for a given score."""
        score = await self._db.get(Score, score_id)
        if not score:
            raise ScoreNotFoundError(score_id)
        if not score.is_analyzed or not score.musicxml_path:
            raise ScoreNotFoundError(f"Score {score_id} has not been analysed yet")

        builder = ReferenceBuilder(Path(score.musicxml_path))

        if score.chroma_path and Path(score.chroma_path).exists():
            # Fast path: load pre-computed chroma
            builder.chroma = ReferenceBuilder.load(Path(score.chroma_path))
            # We still need note_events and page_map for position mapping
            builder.note_events = await self._load_note_events(score_id)
            builder._rebuild_page_map()
        else:
            builder.build()

        return builder

    async def _load_note_events(self, score_id: str):
        result = await self._db.execute(
            select(Measure)
            .where(Measure.score_id == score_id)
            .order_by(Measure.measure_number)
        )
        measures = result.scalars().all()
        events = []
        for m in measures:
            for n in (m.notes or []):
                events.append((
                    n["pitch_midi"],
                    m.onset_secs + n["onset_offset_secs"],
                    n["duration_secs"],
                    m.measure_number,
                    m.page_number,
                ))
        return sorted(events, key=lambda e: e[1])
