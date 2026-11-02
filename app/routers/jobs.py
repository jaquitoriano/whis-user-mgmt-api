from fastapi import APIRouter, Depends, HTTPException

from app.db import get_pool
from app.dependencies import get_current_session
from app.models import JobRequest

router = APIRouter(prefix="/api/jobs", tags=["Jobs"])


@router.post("")
async def enqueue(payload: JobRequest, session: dict = Depends(get_current_session)):
    job_id = await get_pool().fetchval(
        "SELECT app_queue.enqueue($1, $2::jsonb, COALESCE($3::timestamptz, now()), $4)",
        payload.job_type, payload.payload, payload.run_at, payload.max_attempts
    )
    return {"id": str(job_id), "status": "queued"}


@router.get("/status")
async def status(job_id: str, session: dict = Depends(get_current_session)):
    job = await get_pool().fetchrow(
        "SELECT id, job_type, status, attempts, last_error, created_at, updated_at FROM app_queue.jobs WHERE id=$1::uuid",
        job_id
    )
    if job is None:
        raise HTTPException(status_code=404, detail={"code": "NOT_FOUND", "message": "Job not found"})
    return dict(job)
