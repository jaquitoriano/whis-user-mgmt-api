from typing import Any
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field


class ErrorResponse(BaseModel):
    error: dict[str, str]


class SignUpRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=12)
    display_name: str | None = None


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class MfaVerifyRequest(BaseModel):
    user_id: UUID
    code: str = Field(min_length=6, max_length=6)


class ResetPasswordRequest(BaseModel):
    token: str
    password: str = Field(min_length=12)


class GrantRoleRequest(BaseModel):
    subject_id: UUID
    resource_id: str
    relation: str


class ConfigRequest(BaseModel):
    scope: str = "system"
    key: str
    value: Any


class ReservationRequest(BaseModel):
    metric_name: str
    quantity: float = Field(gt=0)


class JobRequest(BaseModel):
    job_type: str
    payload: dict[str, Any] = Field(default_factory=dict)
    run_at: str | None = None
    max_attempts: int = Field(default=5, ge=1, le=100)
