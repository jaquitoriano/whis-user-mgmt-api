from fastapi import APIRouter, Depends, HTTPException, Query

from app.db import get_pool
from app.dependencies import get_current_session
from app.models import ConfigRequest

router = APIRouter(prefix="/api/config", tags=["Configuration"])


@router.get("")
async def get_config(scope: str = "system", key: str = Query(...), version: int | None = None, session: dict = Depends(get_current_session)):
    value = await get_pool().fetchval("SELECT app_config.get($1, $2, $3)", scope, key, version)
    if value is None:
        raise HTTPException(status_code=404, detail={"code": "NOT_FOUND", "message": "Configuration not found"})
    return {"scope": scope, "key": key, "value": value}


@router.put("")
async def set_config(payload: ConfigRequest, session: dict = Depends(get_current_session)):
    version = await get_pool().fetchval(
        "SELECT app_config.set($1, $2, $3::jsonb, $4::uuid)", payload.scope, payload.key, payload.value, session["user_id"]
    )
    return {"scope": payload.scope, "key": payload.key, "version": version, "value": payload.value}
