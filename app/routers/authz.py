from fastapi import APIRouter, Depends, HTTPException

from app.db import get_pool
from app.dependencies import get_current_session
from app.models import GrantRoleRequest

router = APIRouter(prefix="/api/permissions", tags=["Authorization"])


@router.get("/check")
async def check_permission(resource_id: str, action: str, session: dict = Depends(get_current_session)):
    allowed = await get_pool().fetchval(
        "SELECT authz.check_permission($1::uuid, $2, $3)", session["user_id"], resource_id, action
    )
    return {"allowed": allowed}


@router.post("/grant")
async def grant_role(payload: GrantRoleRequest, session: dict = Depends(get_current_session)):
    admin = await get_pool().fetchval(
        "SELECT authz.check_permission($1::uuid, $2, $3)", session["user_id"], payload.resource_id, "admin"
    )
    if not admin:
        raise HTTPException(status_code=403, detail={"code": "FORBIDDEN", "message": "Permission denied"})
    await get_pool().execute(
        "SELECT authz.grant_role($1::uuid, $2, $3)", str(payload.subject_id), payload.resource_id, payload.relation
    )
    return {"success": True}
