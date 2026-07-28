"""
run.py
───────
Entry point – starts the uvicorn server.
Usage:
    python run.py                  # default host/port from settings
    python run.py --reload         # development mode with auto-reload
"""
import uvicorn
from app.core.config import settings

if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
        log_level="debug" if settings.DEBUG else "info",
    )
