"""
app/core/exceptions.py
──────────────────────
Domain-level exceptions that map cleanly to HTTP status codes in the API layer.
"""
from fastapi import HTTPException, status


class ScoreNotFoundError(HTTPException):
    def __init__(self, score_id: str):
        super().__init__(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Score '{score_id}' not found",
        )


class OMRError(HTTPException):
    def __init__(self, detail: str):
        super().__init__(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"OMR failed: {detail}",
        )


class AudioError(HTTPException):
    def __init__(self, detail: str):
        super().__init__(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Audio error: {detail}",
        )


class SessionNotFoundError(HTTPException):
    def __init__(self, session_id: str):
        super().__init__(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Session '{session_id}' not found",
        )
