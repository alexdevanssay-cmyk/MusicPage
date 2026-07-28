"""
app/core/config.py
──────────────────
Centralised settings loaded from environment / .env file.
All paths are created on first import so the application starts cleanly.
"""
from pathlib import Path
from typing import Optional
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    # ── App ───────────────────────────────────────────────────────────────────
    APP_NAME: str = "MusicPage"
    VERSION: str = "1.0.0"
    DEBUG: bool = False
    HOST: str = "0.0.0.0"
    PORT: int = 8000
    CORS_ORIGINS: list[str] = ["*"]          # tighten in production

    # ── Database ──────────────────────────────────────────────────────────────
    DATABASE_URL: str = "sqlite+aiosqlite:///./data/musicpage.db"

    # ── Storage ───────────────────────────────────────────────────────────────
    DATA_DIR:     Path = Path("./data")
    SCORES_DIR:   Path = Path("./data/scores")    # original PDFs
    MUSICXML_DIR: Path = Path("./data/musicxml")  # OMR output
    CHROMA_DIR:   Path = Path("./data/chroma")    # pre-computed reference features

    # ── Audio ─────────────────────────────────────────────────────────────────
    SAMPLE_RATE:       int = 22050   # Hz – good balance of quality vs. latency
    HOP_LENGTH:        int = 512     # frames between STFT columns ≈ 23 ms
    N_FFT:             int = 2048
    N_CHROMA:          int = 12
    AUDIO_CHUNK_SECS:  float = 0.093 # ≈ 2 × HOP_LENGTH / SAMPLE_RATE

    # ── Score Following ───────────────────────────────────────────────────────
    DTW_WINDOW:        int   = 150   # Sakoe-Chiba band (reference frames)
    SMOOTH_FRAMES:     int   = 7     # Median-filter length for position smoothing
    PRELOAD_THRESHOLD: float = 0.80  # Trigger pre-load of next page
    PAGE_TURN_THRESHOLD: float = 0.95

    # ── OMR ───────────────────────────────────────────────────────────────────
    OMR_BACKEND: str = "oemer"       # "oemer" | "audiveris"
    AUDIVERIS_JAR: Optional[str] = None  # path to audiveris-5.x.jar

    def model_post_init(self, __context) -> None:  # pydantic v2 lifecycle hook
        for d in (self.DATA_DIR, self.SCORES_DIR, self.MUSICXML_DIR, self.CHROMA_DIR):
            d.mkdir(parents=True, exist_ok=True)


settings = Settings()
