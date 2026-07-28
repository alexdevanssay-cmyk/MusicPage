"""
app/api/router.py
──────────────────
Aggregates all API sub-routers.
"""
from fastapi import APIRouter
from app.api.endpoints.scores import router as scores_router

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(scores_router)
