"""
app/models/database.py
──────────────────────
SQLAlchemy 2.0 async ORM models.
Run `alembic upgrade head` (or call create_all()) to initialise the schema.
"""
from datetime import datetime
from typing import Any

from sqlalchemy import (
    Boolean, Column, DateTime, Float, ForeignKey,
    Integer, JSON, String, Text,
)
from sqlalchemy.ext.asyncio import (
    AsyncSession, async_sessionmaker, create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase, relationship

from app.core.config import settings


# ── Engine & session factory ────────────────────────────────────────────────────

engine = create_async_engine(
    settings.DATABASE_URL,
    echo=settings.DEBUG,
    future=True,
)

AsyncSessionLocal: async_sessionmaker[AsyncSession] = async_sessionmaker(
    engine, expire_on_commit=False
)


# ── Base ────────────────────────────────────────────────────────────────────────

class Base(DeclarativeBase):
    pass


# ── Tables ──────────────────────────────────────────────────────────────────────

class Score(Base):
    """One row per imported PDF score."""
    __tablename__ = "scores"

    id            = Column(String, primary_key=True)
    title         = Column(String, nullable=False)
    composer      = Column(String, default="")
    pdf_path      = Column(String, nullable=False)
    musicxml_path = Column(String)
    chroma_path   = Column(String)          # pre-computed reference chroma (npy)

    total_pages   = Column(Integer, default=0)
    total_measures= Column(Integer, default=0)
    duration_secs = Column(Float, default=0.0)
    tempo_bpm     = Column(Float, default=120.0)
    time_signature= Column(String, default="4/4")

    is_analyzed   = Column(Boolean, default=False)
    is_favorite   = Column(Boolean, default=False)
    created_at    = Column(DateTime, default=datetime.utcnow)
    last_opened   = Column(DateTime)

    pages    = relationship("ScorePage",   back_populates="score", cascade="all, delete-orphan")
    measures = relationship("Measure",     back_populates="score", cascade="all, delete-orphan")
    sessions = relationship("PlaySession", back_populates="score", cascade="all, delete-orphan")


class ScorePage(Base):
    """Maps page numbers to measure ranges."""
    __tablename__ = "score_pages"

    id           = Column(Integer, primary_key=True, autoincrement=True)
    score_id     = Column(String, ForeignKey("scores.id"), nullable=False)
    page_number  = Column(Integer, nullable=False)
    first_measure= Column(Integer)
    last_measure = Column(Integer)
    image_path   = Column(String)   # optional rasterised page for fast rendering

    score = relationship("Score", back_populates="pages")


class Measure(Base):
    """Stores the note events for each measure (as flat JSON list)."""
    __tablename__ = "measures"

    id             = Column(Integer, primary_key=True, autoincrement=True)
    score_id       = Column(String, ForeignKey("scores.id"), nullable=False)
    measure_number = Column(Integer, nullable=False)
    page_number    = Column(Integer, nullable=False)
    onset_secs     = Column(Float, default=0.0)    # onset from start of piece (seconds)
    duration_secs  = Column(Float, default=0.0)    # duration of measure (seconds)
    tempo_bpm      = Column(Float)
    time_signature = Column(String)
    # List of {pitch_midi, onset_offset_secs, duration_secs}
    notes: Any     = Column(JSON, default=list)

    score = relationship("Score", back_populates="measures")


class PlaySession(Base):
    """Records each playing session for history / analytics."""
    __tablename__ = "play_sessions"

    id                  = Column(String, primary_key=True)
    score_id            = Column(String, ForeignKey("scores.id"), nullable=False)
    started_at          = Column(DateTime, default=datetime.utcnow)
    ended_at            = Column(DateTime)
    last_measure        = Column(Integer, default=0)
    completion_pct      = Column(Float, default=0.0)
    avg_confidence      = Column(Float, default=0.0)

    score = relationship("Score", back_populates="sessions")


class AppSettings(Base):
    """Key-value store for user-configurable settings."""
    __tablename__ = "app_settings"

    key   = Column(String, primary_key=True)
    value = Column(Text)


# ── Dependency injection helper ─────────────────────────────────────────────────

async def get_db() -> AsyncSession:  # type: ignore[return]
    async with AsyncSessionLocal() as session:
        yield session


async def create_tables() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
