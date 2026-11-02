import secrets
from datetime import UTC, datetime, timedelta

import jwt

from app.config import get_settings

SESSION_COOKIE = "user_session"


def create_session_token(user_id: str) -> str:
    return jwt.encode(
        {
            "sub": user_id,
            "iat": datetime.now(UTC),
            "exp": datetime.now(UTC) + timedelta(days=7),
        },
        get_settings().jwt_secret,
        algorithm="HS256",
    )


def decode_session_token(token: str) -> str:
    payload = jwt.decode(token, get_settings().jwt_secret, algorithms=["HS256"])
    return str(payload["sub"])


def new_raw_token() -> str:
    return secrets.token_urlsafe(32)
