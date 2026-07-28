"""
app/api/endpoints/scores.py  (complete with PDF serving)
"""
from pathlib import Path
from typing import List, Optional

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
    title: Optional[str] = Form(None),
    composer: Optional[str] = Form(None),
    db: AsyncSession = Depends(get_db),
):
    pdf_bytes = await file.read()
    return await ScoreService(db).import_pdf(
        pdf_bytes=pdf_bytes,
        filename=file.filename or "score.pdf",
        title=title,
        composer=composer,
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


@router.delete("/{score_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_score(score_id: str, db: AsyncSession = Depends(get_db)):
    await ScoreService(db).delete_score(score_id)


@router.post("/{score_id}/favorite")
async def toggle_favorite(score_id: str, db: AsyncSession = Depends(get_db)):
    is_fav = await ScoreService(db).toggle_favorite(score_id)
    return {"is_favorite": is_fav}
