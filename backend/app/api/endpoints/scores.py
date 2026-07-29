"""
app/api/endpoints/scores.py  (complete with PDF serving)
"""
import base64
import bisect
from pathlib import Path
from typing import List, Optional

import numpy as np
from fastapi import APIRouter, Depends, File, Form, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import ScoreNotFoundError
from app.models.database import Score, get_db
from app.models.schemas import ScoreListItem, ScoreResponse
from app.services.score_service import ScoreService

router = APIRouter(prefix="/scores", tags=["scores"])


@router.get("/", response_model=List[ScoreListItem])
async def list_scores(db: AsyncSession = Depends(get_db)):
    return await ScoreService(db).list_scores()


@router.post("/", response_model=ScoreResponse, status_code=status.HTTP_201_CREATED)
async def import_score(
    file: UploadFile = File(...),
    midi: Optional[UploadFile] = File(None),
    title: Optional[str] = Form(None),
    composer: Optional[str] = Form(None),
    db: AsyncSession = Depends(get_db),
):
    """
    Import a score. `file` is the PDF (for display). Optionally attach a
    `midi` (.mid/.midi/.xml/.musicxml) to build a real note-level reference —
    otherwise OMR runs on the PDF (a stub if the OMR engine isn't installed).
    """
    pdf_bytes = await file.read()
    midi_bytes = await midi.read() if midi is not None else None
    return await ScoreService(db).import_pdf(
        pdf_bytes=pdf_bytes,
        filename=file.filename or "score.pdf",
        title=title,
        composer=composer,
        midi_bytes=midi_bytes,
        midi_filename=midi.filename if midi is not None else None,
    )


@router.get("/{score_id}", response_model=ScoreResponse)
async def get_score(score_id: str, db: AsyncSession = Depends(get_db)):
    return await ScoreService(db).get_score(score_id)


@router.get("/{score_id}/pdf")
async def serve_pdf(score_id: str, db: AsyncSession = Depends(get_db)):
    """Stream the original PDF bytes to the Flutter PDF viewer."""
    score: Score | None = await db.get(Score, score_id)
    if not score:
        raise ScoreNotFoundError(score_id)
    pdf_path = Path(score.pdf_path)
    if not pdf_path.exists():
        raise ScoreNotFoundError(f"PDF file missing for {score_id}")
    return FileResponse(str(pdf_path), media_type="application/pdf")


@router.get("/{score_id}/reference_bundle")
async def reference_bundle(score_id: str, db: AsyncSession = Depends(get_db)):
    """
    Export the precomputed following data for one score so an Android/iOS client
    can follow it entirely on-device (no server). The reference chroma and the
    per-frame measure map are base64-packed float32/int16 little-endian arrays.
    """
    svc = ScoreService(db)
    builder = await svc.get_reference_builder(score_id)  # raises if not analysed
    score = await db.get(Score, score_id)

    chroma = np.asarray(builder.chroma, dtype=np.float32)
    n = int(len(chroma))
    fps = float(builder.frame_rate)

    # per-frame measure number (bisect over sorted note onsets, once)
    if builder.note_events:
        onsets = [e[1] for e in builder.note_events]
        meas = [e[3] for e in builder.note_events]
        measures = np.empty(n, dtype=np.int16)
        for f in range(n):
            idx = bisect.bisect_right(onsets, f / fps)
            idx = max(0, min(idx, len(meas) - 1))
            measures[f] = meas[idx]
    else:
        measures = np.ones(n, dtype=np.int16)

    page_map = [[int(p), int(a), int(b)] for (p, a, b) in builder.page_map]
    total_pages = max((p for p, *_ in builder.page_map), default=1) if builder.page_map else 1

    return {
        "score_id": score_id,
        "title": score.title,
        "composer": score.composer or "",
        "frame_rate": fps,
        "total_frames": n,
        "total_pages": total_pages,
        "base_bpm": float(score.tempo_bpm) if getattr(score, "tempo_bpm", None) else None,
        "page_map": page_map,
        "chroma_b64": base64.b64encode(chroma.tobytes()).decode("ascii"),
        "measures_b64": base64.b64encode(measures.tobytes()).decode("ascii"),
    }


@router.delete("/{score_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_score(score_id: str, db: AsyncSession = Depends(get_db)):
    await ScoreService(db).delete_score(score_id)


@router.post("/{score_id}/favorite")
async def toggle_favorite(score_id: str, db: AsyncSession = Depends(get_db)):
    is_fav = await ScoreService(db).toggle_favorite(score_id)
    return {"is_favorite": is_fav}
