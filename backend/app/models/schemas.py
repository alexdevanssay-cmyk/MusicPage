"""
app/models/schemas.py
─────────────────────
Pydantic v2 schemas for request validation and response serialisation.
"""
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field


# ── Score ───────────────────────────────────────────────────────────────────────

class ScoreBase(BaseModel):
    title: str
    composer: Optional[str] = ""


class ScoreCreate(ScoreBase):
    pass


class ScoreResponse(ScoreBase):
    id: str
    total_pages: int
    total_measures: int
    duration_secs: float
    tempo_bpm: float
    time_signature: str
    is_analyzed: bool
    is_favorite: bool
    created_at: datetime
    last_opened: Optional[datetime] = None

    model_config = {"from_attributes": True}


class ScoreListItem(BaseModel):
    id: str
    title: str
    composer: str
    total_pages: int
    is_analyzed: bool
    is_favorite: bool
    created_at: datetime
    last_opened: Optional[datetime] = None

    model_config = {"from_attributes": True}


# ── Pages ────────────────────────────────────────────────────────────────────────

class PageInfo(BaseModel):
    page_number: int
    first_measure: int
    last_measure: int


# ── Position ─────────────────────────────────────────────────────────────────────

class PositionUpdate(BaseModel):
    """Emitted by the backend over WebSocket when position changes."""
    measure: int
    page: int
    progress: float = Field(..., ge=0.0, le=1.0, description="0–1 within current page")
    global_progress: float = Field(..., ge=0.0, le=1.0, description="0–1 in entire score")
    confidence: float = Field(..., ge=0.0, le=1.0)
    should_preload_next: bool = False
    should_turn_page: bool = False


# ── Session ──────────────────────────────────────────────────────────────────────

class SessionCreate(BaseModel):
    score_id: str


class SessionResponse(BaseModel):
    id: str
    score_id: str
    started_at: datetime

    model_config = {"from_attributes": True}


# ── WebSocket messages ────────────────────────────────────────────────────────────

class WsStartSession(BaseModel):
    type: str = "start_session"
    score_id: str


class WsStopSession(BaseModel):
    type: str = "stop_session"


class WsManualPosition(BaseModel):
    type: str = "manual_position"
    measure: int


class WsPositionUpdate(PositionUpdate):
    type: str = "position_update"


class WsPageChange(BaseModel):
    type: str = "page_change"
    from_page: int
    to_page: int


class WsPreload(BaseModel):
    type: str = "preload_next_page"
    page: int


class WsError(BaseModel):
    type: str = "error"
    message: str


# ── Settings ─────────────────────────────────────────────────────────────────────

class UserSettings(BaseModel):
    mic_sensitivity: float = Field(default=1.0, ge=0.1, le=5.0)
    preload_threshold: float = Field(default=0.80, ge=0.5, le=0.99)
    page_turn_threshold: float = Field(default=0.95, ge=0.5, le=0.99)
    dark_mode: bool = False
    audio_device_id: Optional[str] = None
