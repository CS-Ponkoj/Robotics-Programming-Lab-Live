"""Secret-minimized execution API for the dedicated sandbox container."""

from __future__ import annotations

import os
import secrets
import threading
from collections.abc import Callable

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from sandbox import Sandbox, SubprocessSandbox


class ExecutionRequest(BaseModel):
    code: str = Field(min_length=1, max_length=50_000)
    result_names: list[str] = Field(default_factory=list, max_length=100)
    timeout_seconds: float = Field(default=5.0, gt=0, le=10.0)


def create_sandbox_service(
    *,
    api_token: str | None = None,
    max_concurrent_executions: int | None = None,
    executor_factory: Callable[[float], Sandbox] | None = None,
) -> FastAPI:
    configured_token = api_token if api_token is not None else os.getenv(
        "SANDBOX_API_TOKEN", ""
    )
    configured_slots = max_concurrent_executions or int(
        os.getenv("SANDBOX_MAX_CONCURRENT_EXECUTIONS", "2")
    )
    factory = executor_factory or (
        lambda timeout: SubprocessSandbox(timeout_seconds=timeout)
    )

    application = FastAPI(
        title="Robotics Programming Lab Sandbox",
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
    )
    application.state.api_token = configured_token
    application.state.execution_slots = threading.BoundedSemaphore(
        max(1, configured_slots)
    )
    application.state.executor_factory = factory

    @application.middleware("http")
    async def request_limits(request: Request, call_next):
        content_length = request.headers.get("content-length")
        if content_length:
            try:
                request_bytes = int(content_length)
            except ValueError:
                return JSONResponse(
                    status_code=400,
                    content={"error": "Invalid request size."},
                )
            if request_bytes > 100_000:
                return JSONResponse(
                    status_code=413,
                    content={"error": "Request body is too large."},
                )
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        return response

    @application.exception_handler(HTTPException)
    async def http_error(_request: Request, error: HTTPException):
        return JSONResponse(
            status_code=error.status_code,
            content={"error": str(error.detail)},
        )

    @application.exception_handler(RequestValidationError)
    async def validation_error(
        _request: Request,
        _error: RequestValidationError,
    ):
        return JSONResponse(
            status_code=400,
            content={"error": "Invalid execution request."},
        )

    def require_token(authorization: str | None) -> None:
        scheme, _, supplied = (authorization or "").partition(" ")
        expected = application.state.api_token
        if (
            not expected
            or scheme.lower() != "bearer"
            or not secrets.compare_digest(supplied, expected)
        ):
            raise HTTPException(401, "Authentication required.")

    @application.get("/health")
    def health():
        if not application.state.api_token:
            raise HTTPException(503, "Sandbox service is not configured.")
        return {"status": "ok", "isolation": "dedicated-service"}

    @application.post("/execute")
    def execute(
        body: ExecutionRequest,
        authorization: str | None = Header(default=None),
    ):
        require_token(authorization)
        slots = application.state.execution_slots
        if not slots.acquire(blocking=False):
            raise HTTPException(503, "Sandbox capacity is temporarily full.")
        try:
            executor = application.state.executor_factory(body.timeout_seconds)
            return executor.execute(body.code, body.result_names)
        finally:
            slots.release()

    return application


app = create_sandbox_service()
