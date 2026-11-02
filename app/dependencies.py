from fastapi import Cookie, HTTPException, Request

from app.db import get_pool


async def get_current_session(request: Request, user_session: str | None = Cookie(default=None)) -> dict:
    token = user_session
    if token is None:
        authorization = request.headers.get("authorization")
        if authorization and authorization.lower().startswith("bearer "):
            token = authorization.split(" ", 1)[1].strip()
    if not token:
        raise HTTPException(status_code=401, detail={"code": "UNAUTHENTICATED", "message": "Session required"})

    result = await get_pool().fetchval("SELECT app_auth.validate_session($1)", token)
    if not result or result.get("error"):
        raise HTTPException(status_code=401, detail={"code": "UNAUTHENTICATED", "message": "Invalid or expired session"})
    return result


async def require_permission(session: dict, resource_id: str, action: str) -> None:
    allowed = await get_pool().fetchval(
        "SELECT app_authz.check_permission($1::uuid, $2, $3)", session["user_id"], resource_id, action
    )
    if not allowed:
        raise HTTPException(status_code=403, detail={"code": "FORBIDDEN", "message": "Permission denied"})
