from fastapi import APIRouter, Depends, HTTPException

from app.db import get_pool
from app.dependencies import get_current_session
from app.models import ReservationRequest

router = APIRouter(prefix="/api/meter", tags=["Metering"])


@router.get("/usage")
async def usage(metric_name: str, session: dict = Depends(get_current_session)):
    result = await get_pool().fetchrow(
        "SELECT quantity, period FROM meter.period_usage WHERE user_id=$1::uuid AND metric_name=$2 AND period=to_char(now(), 'YYYY-MM')",
        session["user_id"], metric_name
    )
    return {"metric_name": metric_name, "quantity": float(result["quantity"] if result else 0), "period": result["period"] if result else __import__("datetime").datetime.now().strftime("%Y-%m")}


@router.post("/reserve")
async def reserve(payload: ReservationRequest, session: dict = Depends(get_current_session)):
    result = await get_pool().fetchval(
        "SELECT meter.reserve($1::uuid, $2, $3)", session["user_id"], payload.metric_name, payload.quantity
    )
    if result.get("error"):
        raise HTTPException(status_code=429, detail={"code": "QUOTA_EXCEEDED", "message": result["error"]})
    return result
