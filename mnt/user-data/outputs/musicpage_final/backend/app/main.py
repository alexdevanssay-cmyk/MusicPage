"""
app/main.py
────────────
FastAPI application factory and lifespan management.
"""
from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from typing import AsyncGenerator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.router import api_router
from app.core.config import settings
from app.models.database import create_tables
from app.websocket.handler import ws_session_handler

logging.basicConfig(
    level=logging.DEBUG if settings.DEBUG else logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s  %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Application startup / shutdown."""
    logger.info("Starting %s v%s", settings.APP_NAME, settings.VERSION)
    await create_tables()
    yield
    logger.info("Shutting down.")


app = FastAPI(
    title=settings.APP_NAME,
    version=settings.VERSION,
    lifespan=lifespan,
)

# ── CORS (all origins for local development; tighten in production) ───────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── REST routes ───────────────────────────────────────────────────────────────────
app.include_router(api_router)


# ── WebSocket ─────────────────────────────────────────────────────────────────────
@app.websocket("/ws/follow")
async def websocket_follow(websocket):  # type: ignore[no-untyped-def]
    await ws_session_handler(websocket)


# ── Health check ──────────────────────────────────────────────────────────────────
@app.get("/health")
async def health() -> dict:
    return {"status": "ok", "version": settings.VERSION}
