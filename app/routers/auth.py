from fastapi import APIRouter, Cookie, HTTPException, Response, Request

from app.db import get_pool
from app.dependencies import get_current_session
from app.models import LoginRequest, MfaVerifyRequest, ResetPasswordRequest, SignUpRequest
from app.config import get_settings

router = APIRouter(prefix="/api/auth", tags=["Authentication"])


@router.post("/signup", status_code=201)
async def signup(payload: SignUpRequest):
    result = await get_pool().fetchval(
        "SELECT app_auth.sign_up($1, $2, $3)", str(payload.email), payload.password, payload.display_name
    )
    if result.get("error"):
        raise HTTPException(status_code=409, detail={"code": "SIGNUP_FAILED", "message": result["error"]})
    return {"user_id": result["user_id"]}


@router.post("/login")
async def login(payload: LoginRequest, response: Response, request: Request):
    result = await get_pool().fetchval(
        "SELECT app_auth.sign_in($1, $2, $3::inet, $4)",
        str(payload.email), payload.password, request.client.host if request.client else None, request.headers.get("user-agent")
    )
    if result.get("error"):
        raise HTTPException(status_code=401, detail={"code": "INVALID_CREDENTIALS", "message": result["error"]})
    response.set_cookie(
        "user_session", result["session_token"], httponly=True, secure=get_settings().cookie_secure,
        samesite="lax", max_age=7 * 24 * 60 * 60, path="/"
    )
    return {"user_id": result["user_id"], "email": result["email"]}


@router.post("/logout")
async def logout(response: Response, user_session: str | None = Cookie(default=None)):
    if user_session:
        await get_pool().fetchval("SELECT app_auth.logout($1)", user_session)
    response.delete_cookie("user_session", path="/")
    return {"success": True}


@router.post("/mfa/verify")
async def verify_mfa(payload: MfaVerifyRequest):
    result = await get_pool().fetchval("SELECT app_auth.verify_mfa($1::uuid, $2)", str(payload.user_id), payload.code)
    if not result.get("verified"):
        raise HTTPException(status_code=400, detail={"code": "MFA_NOT_READY", "message": result["message"]})
    return result


@router.post("/reset-password")
async def reset_password(payload: ResetPasswordRequest):
    result = await get_pool().fetchval("SELECT app_auth.reset_password($1, $2)", payload.token, payload.password)
    if result.get("error"):
        raise HTTPException(status_code=400, detail={"code": "RESET_FAILED", "message": result["error"]})
    return result
