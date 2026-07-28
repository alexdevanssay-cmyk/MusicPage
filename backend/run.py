"""
run.py
───────
Entry point – starts the uvicorn server.
Usage:
    python run.py                  # default host/port from settings
    python run.py --reload         # development mode with auto-reload
"""
import sys

import uvicorn

from app.core.config import settings

if __name__ == "__main__":
    frozen = getattr(sys, "frozen", False)

    if settings.DEBUG and not frozen:
        # Import-string form enables auto-reload in development.
        uvicorn.run(
            "app.main:app",
            host=settings.HOST,
            port=settings.PORT,
            reload=True,
            log_level="debug",
        )
    else:
        # Pass the application object directly.  This is required inside a
        # PyInstaller bundle, where uvicorn cannot re-import "app.main:app"
        # from an import string.
        from app.main import app

        uvicorn.run(
            app,
            host=settings.HOST,
            port=settings.PORT,
            log_level="info",
        )
