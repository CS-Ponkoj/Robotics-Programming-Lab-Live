import logging
import os
import secrets
import threading
import time
from contextlib import asynccontextmanager
from datetime import timedelta
from pathlib import Path
from uuid import uuid4

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, Response
from sqlalchemy import select
from sqlalchemy.orm import Session, sessionmaker

from account_sync import seed_demo_accounts, sync_accounts_from_json
from assignment_repository import (
    AssignmentRepository,
    to_admin_payload,
    to_student_assignment,
)
from auth_service import (
    authenticate_user,
    change_password,
    consume_password_reset_token,
    create_password_reset_token,
    create_session,
    create_user,
    generate_temporary_password,
    hash_token,
    normalize_email,
    normalize_login_id,
    normalize_participant_code,
    record_audit,
    revoke_session_token,
    revoke_user_sessions,
    user_for_session_token,
    verify_password,
)
from config import Settings, get_settings
from data_contracts import normalize_event_data
from database import Base, build_engine
from email_service import EmailService
from graders import PythonVariableGrader, Ros2TopicGrader
from models import (
    Assignment,
    HintInteraction,
    StudySession,
    Submission,
    User,
    utc_now,
)
from research_service import (
    build_research_dataset,
    csv_bytes,
    get_user_study_session,
    participant_label,
    record_learning_event,
    student_research_payload,
    xlsx_bytes,
)
from sandbox import build_sandbox
from ros2_executor import DockerRos2Executor
from schemas import (
    AdminAssignmentPayload,
    AdminPasswordReset,
    AdminStudentCreate,
    AdminStudentCreated,
    AdminStudentUpdate,
    AdminUserResponse,
    AssignmentListResponse,
    AssignmentStudent,
    AuthenticatedUser,
    ChangePasswordRequest,
    EmailTestRequest,
    ForgotPasswordRequest,
    HintRequest,
    LoginRequest,
    LoginResponse,
    LearningEventRequest,
    ResetPasswordRequest,
    SolutionRequest,
    StudyHeartbeatRequest,
    StudySessionResponse,
    StudySessionStartRequest,
    SubmissionRequest,
    SubmissionResponse,
    TutorQuestionRequest,
)
from tutor import TutorService
from validation import validate_assignment


logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)
BASE_DIR = Path(__file__).resolve().parent
STATIC_DIR = BASE_DIR / "static"


def create_app(
    settings: Settings | None = None,
    database_url: str | None = None,
    ros2_executor_factory=None,
) -> FastAPI:
    configured = settings or get_settings()
    configured.validate_runtime()
    selected_database_url = database_url or configured.database_url
    engine = build_engine(selected_database_url)
    local_session = sessionmaker(bind=engine, expire_on_commit=False)

    @asynccontextmanager
    async def lifespan(application: FastAPI):
        if configured.auto_create_schema:
            Base.metadata.create_all(engine)
        with local_session() as session:
            AssignmentRepository(session).sync_seed_assignments()
            seed_demo_accounts(
                session,
                configured.enable_demo_accounts,
                student_password=configured.demo_student_password,
                instructor_password=configured.demo_instructor_password,
            )
            application.state.account_import_report = sync_accounts_from_json(
                session, configured.study_accounts_file
            )
        yield
        engine.dispose()

    application = FastAPI(
        title="Robotics Programming Lab API",
        version="5.0.0",
        lifespan=lifespan,
        docs_url=None if configured.environment.lower() == "production" else "/docs",
        redoc_url=None if configured.environment.lower() == "production" else "/redoc",
        openapi_url=(
            None
            if configured.environment.lower() == "production"
            else "/openapi.json"
        ),
    )
    application.state.settings = configured
    application.state.SessionLocal = local_session
    application.state.email_outbox = []
    application.state.login_failures = {}
    application.state.demo_sessions = {}
    application.state.demo_submissions = {}
    application.state.demo_session_lock = threading.Lock()
    application.state.rate_limits = {}
    application.state.rate_limit_lock = threading.Lock()
    application.state.execution_slots = threading.BoundedSemaphore(
        configured.max_concurrent_executions
    )
    application.state.ros2_executor_factory = ros2_executor_factory or (
        lambda timeout: DockerRos2Executor(
            image=configured.ros2_grader_image,
            timeout_seconds=timeout,
        )
    )
    application.add_middleware(
        CORSMiddleware,
        allow_origins=configured.cors_origins,
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @application.middleware("http")
    async def security_headers(request: Request, call_next):
        content_length = request.headers.get("content-length")
        if content_length:
            try:
                request_bytes = int(content_length)
            except ValueError:
                return JSONResponse(
                    status_code=400,
                    content={"error": "Invalid Content-Length header."},
                )
            if request_bytes > configured.max_request_bytes:
                return JSONResponse(
                    status_code=413,
                    content={"error": "Request body is too large."},
                )
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Permissions-Policy"] = (
            "camera=(), microphone=(), geolocation=()"
        )
        return response

    @application.exception_handler(HTTPException)
    async def http_error(_request: Request, error: HTTPException):
        return JSONResponse(
            status_code=error.status_code,
            content={"error": str(error.detail)},
            headers=error.headers,
        )

    @application.exception_handler(RequestValidationError)
    async def validation_error(_request: Request, error: RequestValidationError):
        safe_details = [
            {
                "type": item.get("type", "validation_error"),
                "location": [str(part) for part in item.get("loc", ())],
                "message": item.get("msg", "Invalid value."),
            }
            for item in error.errors()
        ]
        return JSONResponse(
            status_code=400,
            content={"error": "Invalid request.", "details": safe_details},
        )

    def session_dependency(request: Request):
        with request.app.state.SessionLocal() as session:
            yield session

    def bearer_token(request: Request) -> str | None:
        authorization = request.headers.get("Authorization", "")
        scheme, _, token = authorization.partition(" ")
        if scheme.lower() != "bearer" or not token.strip():
            return None
        return token.strip()

    def demo_session_record(request: Request, token: str | None = None):
        raw_token = token or bearer_token(request)
        if not raw_token:
            return None
        token_hash = hash_token(raw_token)
        now = utc_now()
        with request.app.state.demo_session_lock:
            expired = [
                key
                for key, value in request.app.state.demo_sessions.items()
                if value["expires_at"] <= now
            ]
            for key in expired:
                request.app.state.demo_sessions.pop(key, None)
                stale_submissions = [
                    submission_id
                    for submission_id, entry in request.app.state.demo_submissions.items()
                    if entry["token_hash"] == key
                ]
                for submission_id in stale_submissions:
                    request.app.state.demo_submissions.pop(submission_id, None)
            record = request.app.state.demo_sessions.get(token_hash)
        if record is None:
            return None
        return token_hash, record

    def demo_user_for_token(
        request: Request,
        session: Session,
        token: str | None,
    ) -> User | None:
        record = demo_session_record(request, token)
        if record is None:
            return None
        user = session.get(User, record[1]["user_id"])
        if user is None or not user.is_active or user.role != "student":
            return None
        return user

    def is_ephemeral_demo(request: Request, user: User) -> bool:
        record = demo_session_record(request)
        return bool(record is not None and record[1]["user_id"] == user.id)

    def create_demo_session(request: Request, user: User):
        raw_token = secrets.token_urlsafe(32)
        token_hash = hash_token(raw_token)
        expires_at = utc_now() + timedelta(
            hours=max(1, request.app.state.settings.auth_session_hours)
        )
        with request.app.state.demo_session_lock:
            request.app.state.demo_sessions[token_hash] = {
                "user_id": user.id,
                "expires_at": expires_at,
            }
        return raw_token, expires_at

    def revoke_demo_session(request: Request, token: str | None) -> bool:
        if not token:
            return False
        token_hash = hash_token(token)
        with request.app.state.demo_session_lock:
            removed = request.app.state.demo_sessions.pop(token_hash, None)
            submission_ids = [
                submission_id
                for submission_id, entry in request.app.state.demo_submissions.items()
                if entry["token_hash"] == token_hash
            ]
            for submission_id in submission_ids:
                request.app.state.demo_submissions.pop(submission_id, None)
        return removed is not None

    def current_user(
        request: Request,
        session: Session = Depends(session_dependency),
    ) -> User:
        token = bearer_token(request)
        user = demo_user_for_token(request, session, token)
        if user is None:
            user = user_for_session_token(session, token)
        if user is None:
            raise HTTPException(401, "Authentication required.")
        return user

    def instructor_user(
        user: User = Depends(current_user),
    ) -> User:
        if user.role != "instructor":
            raise HTTPException(403, "Instructor access required.")
        return user

    def enforce_rate_limit(
        request: Request,
        user: User,
        *,
        bucket: str,
        requests_per_minute: int,
    ) -> None:
        if requests_per_minute <= 0:
            return
        # Authenticated quotas follow the account. Client-controlled forwarding
        # headers must not allow a student to bypass the execution limit.
        demo_record = demo_session_record(request)
        identity = demo_record[0] if demo_record is not None else user.id
        key = f"{bucket}:{identity}"
        now = time.monotonic()
        cutoff = now - 60.0
        with request.app.state.rate_limit_lock:
            recent = [
                timestamp
                for timestamp in request.app.state.rate_limits.get(key, [])
                if timestamp >= cutoff
            ]
            if len(recent) >= requests_per_minute:
                retry_after = max(1, int(60 - (now - recent[0])))
                request.app.state.rate_limits[key] = recent
                raise HTTPException(
                    429,
                    "Too many requests. Please wait and try again.",
                    headers={"Retry-After": str(retry_after)},
                )
            recent.append(now)
            request.app.state.rate_limits[key] = recent

    def execute_with_capacity(request: Request, operation):
        slots = request.app.state.execution_slots
        if not slots.acquire(blocking=False):
            raise HTTPException(
                503,
                "The grader is busy. Please try again shortly.",
                headers={"Retry-After": "2"},
            )
        try:
            return operation()
        finally:
            slots.release()

    def admin_dependency(
        request: Request,
        x_admin_token: str | None = Header(default=None),
        session: Session = Depends(session_dependency),
    ) -> User | None:
        token = request.app.state.settings.admin_api_token
        if token and x_admin_token == token:
            return None
        bearer = bearer_token(request)
        user = demo_user_for_token(request, session, bearer)
        if user is None:
            user = user_for_session_token(session, bearer)
        if user is not None:
            if user.role == "instructor":
                return user
            raise HTTPException(403, "Instructor access required.")
        if x_admin_token:
            raise HTTPException(401, "Invalid instructor token.")
        raise HTTPException(401, "Instructor authentication required.")

    def user_payload(user: User, *, is_demo: bool | None = None) -> dict:
        return AuthenticatedUser(
            id=user.id,
            login_id=user.login_id,
            role=user.role,
            email=user.email,
            participant_code=user.participant_code,
            is_demo=user.is_demo if is_demo is None else is_demo,
            must_change_password=user.must_change_password,
        ).model_dump()

    def admin_user_payload(user: User) -> dict:
        return AdminUserResponse(
            **user_payload(user),
            is_active=user.is_active,
            created_at=user.created_at,
            last_login_at=user.last_login_at,
        ).model_dump()

    def send_password_email(
        request: Request,
        session: Session,
        user: User,
        *,
        purpose: str,
    ) -> bool:
        if not user.email:
            return False
        raw_token = create_password_reset_token(
            session,
            user,
            duration_minutes=request.app.state.settings.password_reset_minutes,
            purpose=purpose,
        )
        return EmailService(
            request.app.state.settings, request.app.state.email_outbox
        ).send_password_link(
            email=user.email,
            login_id=user.login_id,
            token=raw_token,
            purpose=purpose,
        )

    def get_assignment_or_404(
        session: Session, assignment_id: int, include_drafts: bool = False
    ) -> Assignment:
        assignment = AssignmentRepository(session).get(
            assignment_id, include_drafts=include_drafts
        )
        if assignment is None:
            raise HTTPException(404, "Assignment not found.")
        return assignment

    def grader_for(assignment: Assignment, request: Request):
        settings_value = request.app.state.settings
        timeout = float(
            (assignment.execution_settings or {}).get(
                "timeout_seconds", settings_value.execution_timeout_seconds
            )
        )
        if assignment.grader_type == "ros2_topic":
            return Ros2TopicGrader(
                request.app.state.ros2_executor_factory(timeout)
            )
        if assignment.grader_type != "python_variables":
            raise HTTPException(422, f"Unsupported grader: {assignment.grader_type}.")
        sandbox = build_sandbox(
            settings_value.sandbox_backend,
            settings_value.sandbox_image,
            timeout,
            remote_url=settings_value.sandbox_url,
            remote_api_token=settings_value.sandbox_api_token,
            remote_http_timeout_seconds=(
                settings_value.sandbox_http_timeout_seconds
            ),
        )
        return PythonVariableGrader(sandbox)

    def require_code(request_body: SubmissionRequest, request: Request) -> None:
        if not request_body.code.strip():
            raise HTTPException(400, "A non-empty code string is required.")
        if len(request_body.code) > request.app.state.settings.max_submission_chars:
            raise HTTPException(413, "Submitted code is too large.")

    def store_submission(
        request: Request,
        session: Session,
        assignment: Assignment,
        body: SubmissionRequest,
        mode: str,
        result,
        user: User,
        study_session: StudySession | None,
    ) -> Submission:
        evidence = {
            "data_schema_version": assignment.data_schema_version,
            "execution_succeeded": result.execution_succeeded,
            "execution_status": result.execution_status.value,
            "passed": result.passed,
            "score": result.score,
            "execution_error": result.execution_error,
            "code_output": result.code_output,
            "tested_names": result.tested_names,
            "tests": [item.model_dump() for item in result.evidence],
        }
        submission = Submission(
            id=str(uuid4()),
            assignment_id=assignment.id,
            assignment_version=assignment.version,
            data_schema_version=assignment.data_schema_version,
            student_id=user.login_id,
            user_id=user.id,
            study_session_id=study_session.id if study_session else None,
            mode=mode,
            code=body.code,
            execution_succeeded=result.execution_succeeded,
            execution_status=result.execution_status.value,
            passed=result.passed,
            score=result.score,
            evidence=evidence,
        )
        if is_ephemeral_demo(request, user):
            token_record = demo_session_record(request)
            if token_record is None:
                raise HTTPException(401, "Demo session has expired.")
            with request.app.state.demo_session_lock:
                request.app.state.demo_submissions[submission.id] = {
                    "token_hash": token_record[0],
                    "submission": submission,
                }
            return submission
        session.add(submission)
        session.commit()
        session.refresh(submission)
        return submission

    def study_session_for_submission(
        request: Request,
        session: Session,
        body: SubmissionRequest,
        user: User,
    ) -> StudySession | None:
        if is_ephemeral_demo(request, user):
            return None
        value = get_user_study_session(session, body.study_session_id, user)
        if body.study_session_id and value is None:
            raise HTTPException(404, "Study session not found.")
        return value

    def submission_for_request(
        request: Request,
        session: Session,
        user: User,
        submission_id: str,
        assignment_id: int,
        assignment_version: int | None = None,
    ) -> Submission | None:
        if is_ephemeral_demo(request, user):
            token_record = demo_session_record(request)
            if token_record is None:
                return None
            with request.app.state.demo_session_lock:
                entry = request.app.state.demo_submissions.get(submission_id)
            if entry is None or entry["token_hash"] != token_record[0]:
                return None
            submission = entry["submission"]
            if submission.assignment_id != assignment_id:
                return None
            if (
                assignment_version is not None
                and submission.assignment_version != assignment_version
            ):
                return None
            return submission
        conditions = [
            Submission.id == submission_id,
            Submission.assignment_id == assignment_id,
        ]
        if assignment_version is not None:
            conditions.append(Submission.assignment_version == assignment_version)
        return session.scalar(select(Submission).where(*conditions))

    def record_submission_event(
        session: Session,
        *,
        study_session: StudySession | None,
        user: User,
        assignment: Assignment,
        submission: Submission,
        ai_tutor_requested: bool,
    ) -> None:
        if study_session is None:
            return
        record_learning_event(
            session,
            study_session=study_session,
            user=user,
            event_type=(
                "assignment_run" if submission.mode == "run" else "assignment_submitted"
            ),
            assignment_id=assignment.id,
            assignment_version=assignment.version,
            event_data={
                "submission_id": submission.id,
                "execution_succeeded": submission.execution_succeeded,
                "execution_status": submission.execution_status,
                "passed": submission.passed,
                "score": submission.score,
                "ai_tutor_requested": ai_tutor_requested,
            },
        )

    def response_for(
        assignment: Assignment,
        submission: Submission,
        tutor_feedback=None,
    ) -> dict:
        evidence = submission.evidence
        tests = evidence.get("tests", [])
        response = SubmissionResponse(
            id=assignment.id,
            submission_id=submission.id,
            assignment_version=submission.assignment_version,
            tested_vals=evidence.get("tested_names", []),
            pass_=submission.passed,
            unittest_results=[item.get("message", "") for item in tests],
            unittest_pass_results=[
                bool(item.get("passed", False)) for item in tests
            ],
            code_exec_result=evidence.get("execution_error", ""),
            code_output=evidence.get("code_output", ""),
            ex_success=submission.execution_succeeded,
            execution_status=submission.execution_status,
            score=submission.score,
            hint=tutor_feedback.hint if tutor_feedback else "",
            evidence=tests,
            tutor_feedback=tutor_feedback,
        )
        return response.model_dump(by_alias=True)

    @application.get("/health")
    def health():
        try:
            with engine.connect() as connection:
                connection.execute(select(1))
        except Exception as error:
            logger.exception("Database health check failed.")
            raise HTTPException(503, "Database unavailable.") from error
        response = {
            "status": "ok",
            "api_version": "5.0.0",
        }
        if configured.environment.lower() == "production":
            response["release"] = os.getenv("RENDER_GIT_COMMIT", "unknown")[:12]
        else:
            response.update(
                {
                    "database": engine.dialect.name,
                    "sandbox": configured.sandbox_backend,
                }
            )
        return response

    @application.post("/auth/login", response_model=LoginResponse)
    def login(
        body: LoginRequest,
        request: Request,
        session: Session = Depends(session_dependency),
    ):
        login_id = normalize_login_id(body.login_id)
        cutoff = utc_now() - timedelta(minutes=15)
        recent_failures = [
            value
            for value in request.app.state.login_failures.get(login_id, [])
            if value >= cutoff
        ]
        if len(recent_failures) >= 5:
            raise HTTPException(429, "Too many login attempts. Try again later.")
        user = authenticate_user(session, login_id, body.password)
        if user is None:
            recent_failures.append(utc_now())
            request.app.state.login_failures[login_id] = recent_failures
            raise HTTPException(401, "Invalid login ID or password.")
        request.app.state.login_failures.pop(login_id, None)
        raw_token, auth_session = create_session(
            session,
            user,
            duration_hours=request.app.state.settings.auth_session_hours,
        )
        record_audit(
            session,
            action="auth.login",
            resource_type="user",
            resource_id=user.id,
            actor_user_id=user.id,
        )
        return {
            "token": raw_token,
            "expires_at": auth_session.expires_at,
            "user": user_payload(user, is_demo=False),
        }

    @application.post("/auth/demo", response_model=LoginResponse)
    def demo_login(
        request: Request,
        session: Session = Depends(session_dependency),
    ):
        if not request.app.state.settings.enable_demo_accounts:
            raise HTTPException(404, "Demo access is not available.")
        user = session.scalar(
            select(User)
            .where(
                User.login_id == "student",
                User.role == "student",
                User.is_active.is_(True),
            )
        )
        if user is None:
            raise HTTPException(503, "Demo student account is unavailable.")
        raw_token, expires_at = create_demo_session(request, user)
        return {
            "token": raw_token,
            "expires_at": expires_at,
            "user": user_payload(user, is_demo=True),
        }

    @application.get("/auth/me", response_model=AuthenticatedUser)
    def auth_me(request: Request, user: User = Depends(current_user)):
        return user_payload(user, is_demo=is_ephemeral_demo(request, user))

    @application.post("/auth/logout")
    def logout(
        request: Request,
        session: Session = Depends(session_dependency),
        user: User = Depends(current_user),
    ):
        token = bearer_token(request)
        if revoke_demo_session(request, token):
            return {"logged_out": True}
        revoke_session_token(session, token)
        record_audit(
            session,
            action="auth.logout",
            resource_type="user",
            resource_id=user.id,
            actor_user_id=user.id,
        )
        return {"logged_out": True}

    @application.post("/auth/change-password")
    def auth_change_password(
        body: ChangePasswordRequest,
        request: Request,
        session: Session = Depends(session_dependency),
        user: User = Depends(current_user),
    ):
        if is_ephemeral_demo(request, user):
            raise HTTPException(403, "Demo accounts cannot change passwords.")
        if not verify_password(body.current_password, user.password_hash):
            raise HTTPException(400, "Current password is incorrect.")
        change_password(session, user, body.new_password)
        record_audit(
            session,
            action="auth.password_changed",
            resource_type="user",
            resource_id=user.id,
            actor_user_id=user.id,
        )
        return {"password_changed": True, "login_required": True}

    @application.post("/auth/forgot-password", status_code=202)
    def forgot_password(
        body: ForgotPasswordRequest,
        request: Request,
        session: Session = Depends(session_dependency),
    ):
        if not request.app.state.settings.enable_password_reset:
            raise HTTPException(404, "Not found.")
        identifier = body.identifier.strip().lower()
        user = session.scalar(
            select(User).where(
                (User.login_id == normalize_login_id(identifier))
                | (User.email == normalize_email(identifier))
            )
        )
        if user is not None and user.is_active and user.email:
            try:
                send_password_email(
                    request, session, user, purpose="password_reset"
                )
                record_audit(
                    session,
                    action="auth.password_reset_requested",
                    resource_type="user",
                    resource_id=user.id,
                    actor_user_id=None,
                )
            except Exception:
                logger.exception("Password reset email delivery failed.")
        return {
            "message": (
                "If an account matches that information, "
                "a password reset link has been sent."
            )
        }

    @application.post("/auth/reset-password")
    def reset_password(
        body: ResetPasswordRequest,
        request: Request,
        session: Session = Depends(session_dependency),
    ):
        if not request.app.state.settings.enable_password_reset:
            raise HTTPException(404, "Not found.")
        consumed = consume_password_reset_token(session, body.token)
        if consumed is None:
            raise HTTPException(400, "The password reset link is invalid or expired.")
        _, user = consumed
        change_password(session, user, body.new_password)
        record_audit(
            session,
            action="auth.password_reset_completed",
            resource_type="user",
            resource_id=user.id,
            actor_user_id=user.id,
        )
        return {"password_reset": True, "login_required": True}

    @application.post(
        "/research/sessions",
        response_model=StudySessionResponse,
        status_code=201,
    )
    def start_study_session(
        body: StudySessionStartRequest,
        request: Request,
        session: Session = Depends(session_dependency),
        user: User = Depends(current_user),
    ):
        if user.role != "student":
            raise HTTPException(403, "Student access required.")
        if is_ephemeral_demo(request, user):
            raise HTTPException(
                409,
                "Demo progress is kept only in this browser session.",
            )
        client_session_id = body.client_session_id.strip()
        existing = session.scalar(
            select(StudySession).where(
                StudySession.user_id == user.id,
                StudySession.client_session_id == client_session_id,
            )
        )
        if existing is not None:
            return existing
        study_session = StudySession(
            user_id=user.id,
            client_session_id=client_session_id,
            participant_code=user.participant_code,
        )
        session.add(study_session)
        session.commit()
        session.refresh(study_session)
        return study_session

    @application.post(
        "/research/sessions/{study_session_id}/heartbeat",
        response_model=StudySessionResponse,
    )
    def study_heartbeat(
        study_session_id: str,
        body: StudyHeartbeatRequest,
        session: Session = Depends(session_dependency),
        user: User = Depends(current_user),
    ):
        study_session = get_user_study_session(session, study_session_id, user)
        if study_session is None:
            raise HTTPException(404, "Study session not found.")
        if study_session.ended_at is not None:
            raise HTTPException(409, "Study session has ended.")
        if body.assignment_id is not None:
            assignment = get_assignment_or_404(session, body.assignment_id)
            if (
                body.assignment_version is not None
                and body.assignment_version != assignment.version
            ):
                raise HTTPException(409, "Assignment version is no longer current.")
        study_session.active_seconds += body.active_seconds
        study_session.last_active_at = utc_now()
        session.commit()
        session.refresh(study_session)
        return study_session

    @application.post(
        "/research/sessions/{study_session_id}/events",
        status_code=201,
    )
    def create_learning_event(
        study_session_id: str,
        body: LearningEventRequest,
        session: Session = Depends(session_dependency),
        user: User = Depends(current_user),
    ):
        import json

        study_session = get_user_study_session(session, study_session_id, user)
        if study_session is None:
            raise HTTPException(404, "Study session not found.")
        if study_session.ended_at is not None:
            raise HTTPException(409, "Study session has ended.")
        if len(json.dumps(body.event_data)) > 4_000:
            raise HTTPException(413, "Learning event data is too large.")
        try:
            event_data = normalize_event_data(body.event_type.value, body.event_data)
        except ValueError as error:
            raise HTTPException(400, "Learning event data is invalid.") from error
        if body.assignment_id is not None:
            assignment = get_assignment_or_404(session, body.assignment_id)
            if body.assignment_version not in {None, assignment.version}:
                raise HTTPException(409, "Assignment version is no longer current.")
        event = record_learning_event(
            session,
            study_session=study_session,
            user=user,
            event_type=body.event_type,
            assignment_id=body.assignment_id,
            assignment_version=body.assignment_version,
            event_data=event_data,
            client_occurred_at=body.client_occurred_at,
        )
        return {"event_id": event.id, "recorded": True}

    @application.post(
        "/research/sessions/{study_session_id}/end",
        response_model=StudySessionResponse,
    )
    def end_study_session(
        study_session_id: str,
        session: Session = Depends(session_dependency),
        user: User = Depends(current_user),
    ):
        study_session = get_user_study_session(session, study_session_id, user)
        if study_session is None:
            raise HTTPException(404, "Study session not found.")
        if study_session.ended_at is None:
            study_session.ended_at = utc_now()
            study_session.last_active_at = utc_now()
            session.commit()
            session.refresh(study_session)
        return study_session

    @application.get("/research/me")
    def my_research_data(
        request: Request,
        session: Session = Depends(session_dependency),
        user: User = Depends(current_user),
    ):
        if user.role != "student":
            raise HTTPException(403, "Student access required.")
        if is_ephemeral_demo(request, user):
            raise HTTPException(
                409,
                "Demo progress is temporary and has no saved research data.",
            )
        return student_research_payload(session, user)

    @application.get("/admin/research/summary")
    def admin_research_summary(
        session: Session = Depends(session_dependency),
        _actor: User | None = Depends(admin_dependency),
    ):
        dataset = build_research_dataset(session)
        students = session.scalars(
            select(User).where(User.role == "student")
        ).all()
        ids_by_participant = {
            participant_label(student): student.id
            for student in students
        }
        return {
            "participants": [
                {
                    **row,
                    "student_id": ids_by_participant.get(row["participant_code"]),
                }
                for row in dataset["student_summary"]
            ]
        }

    @application.get("/admin/research/students/{student_id}")
    def admin_student_research_data(
        student_id: str,
        session: Session = Depends(session_dependency),
        _actor: User | None = Depends(admin_dependency),
    ):
        student = session.get(User, student_id)
        if student is None or student.role != "student":
            raise HTTPException(404, "Student account not found.")
        return student_research_payload(session, student)

    @application.get("/admin/research/export")
    def admin_research_export(
        dataset_name: str = "student_summary",
        format: str = "csv",
        session: Session = Depends(session_dependency),
        _actor: User | None = Depends(admin_dependency),
    ):
        dataset = build_research_dataset(session)
        if format == "xlsx":
            content = xlsx_bytes(dataset)
            return Response(
                content=content,
                media_type=(
                    "application/vnd.openxmlformats-officedocument."
                    "spreadsheetml.sheet"
                ),
                headers={
                    "Content-Disposition": (
                        'attachment; filename="robotics_study_dataset.xlsx"'
                    )
                },
            )
        if format != "csv" or dataset_name not in dataset:
            raise HTTPException(400, "Choose a supported research export.")
        content = csv_bytes(dataset[dataset_name])
        return Response(
            content=content,
            media_type="text/csv; charset=utf-8",
            headers={
                "Content-Disposition": (
                    f'attachment; filename="{dataset_name}.csv"'
                )
            },
        )

    @application.get(
        "/assignments",
        response_model=AssignmentListResponse,
    )
    @application.get(
        "/assignments/",
        response_model=AssignmentListResponse,
        include_in_schema=False,
    )
    def list_assignments(
        session: Session = Depends(session_dependency),
        _user: User = Depends(current_user),
    ):
        assignments = AssignmentRepository(session).list_published()
        return {"assignments": [to_student_assignment(item) for item in assignments]}

    @application.get(
        "/assignments/{assignment_id}",
        response_model=AssignmentStudent,
    )
    def get_assignment(
        assignment_id: int,
        session: Session = Depends(session_dependency),
        _user: User = Depends(current_user),
    ):
        return to_student_assignment(get_assignment_or_404(session, assignment_id))

    @application.post("/assignments/{assignment_id}/run")
    def run_assignment(
        assignment_id: int,
        body: SubmissionRequest,
        request: Request,
        session: Session = Depends(session_dependency),
        user: User = Depends(current_user),
    ):
        enforce_rate_limit(
            request,
            user,
            bucket="execution",
            requests_per_minute=request.app.state.settings.execution_requests_per_minute,
        )
        require_code(body, request)
        assignment = get_assignment_or_404(session, assignment_id)
        study_session = study_session_for_submission(request, session, body, user)
        grader = grader_for(assignment, request)
        result = execute_with_capacity(
            request,
            lambda: grader.run(assignment, body.code),
        )
        submission = store_submission(
            request,
            session,
            assignment,
            body,
            "run",
            result,
            user=user,
            study_session=study_session,
        )
        record_submission_event(
            session,
            study_session=study_session,
            user=user,
            assignment=assignment,
            submission=submission,
            ai_tutor_requested=body.use_ai_tutor,
        )
        return response_for(assignment, submission)

    def submit_core(
        assignment_id: int,
        body: SubmissionRequest,
        request: Request,
        session: Session,
        user: User,
    ):
        enforce_rate_limit(
            request,
            user,
            bucket="execution",
            requests_per_minute=request.app.state.settings.execution_requests_per_minute,
        )
        if body.use_ai_tutor:
            enforce_rate_limit(
                request,
                user,
                bucket="tutor",
                requests_per_minute=request.app.state.settings.tutor_requests_per_minute,
            )
        require_code(body, request)
        assignment = get_assignment_or_404(session, assignment_id)
        study_session = study_session_for_submission(request, session, body, user)
        grader = grader_for(assignment, request)
        result = execute_with_capacity(
            request,
            lambda: grader.grade(assignment, body.code),
        )
        submission = store_submission(
            request,
            session,
            assignment,
            body,
            "submit",
            result,
            user=user,
            study_session=study_session,
        )
        tutor_feedback = None
        if body.use_ai_tutor and not result.passed:
            tutor_feedback = TutorService(request.app.state.settings).feedback(
                assignment, submission, hint_level=1
            )
            if not is_ephemeral_demo(request, user):
                session.add(
                    HintInteraction(
                        submission_id=submission.id,
                        hint_level=1,
                        feedback=tutor_feedback.model_dump(),
                    )
                )
                session.commit()
        record_submission_event(
            session,
            study_session=study_session,
            user=user,
            assignment=assignment,
            submission=submission,
            ai_tutor_requested=body.use_ai_tutor,
        )
        return response_for(assignment, submission, tutor_feedback)

    @application.post("/assignments/{assignment_id}/submit")
    def submit_assignment(
        assignment_id: int,
        body: SubmissionRequest,
        request: Request,
        session: Session = Depends(session_dependency),
        user: User = Depends(current_user),
    ):
        return submit_core(assignment_id, body, request, session, user)

    @application.post("/grade/{assignment_id}", include_in_schema=False)
    def legacy_grade(
        assignment_id: int,
        body: SubmissionRequest,
        request: Request,
        session: Session = Depends(session_dependency),
        user: User = Depends(current_user),
    ):
        return submit_core(assignment_id, body, request, session, user)

    @application.post("/assignments/{assignment_id}/hint")
    def request_hint(
        assignment_id: int,
        body: HintRequest,
        request: Request,
        session: Session = Depends(session_dependency),
        user: User = Depends(current_user),
    ):
        enforce_rate_limit(
            request,
            user,
            bucket="tutor",
            requests_per_minute=request.app.state.settings.tutor_requests_per_minute,
        )
        assignment = get_assignment_or_404(session, assignment_id)
        submission = submission_for_request(
            request,
            session,
            user,
            body.submission_id,
            assignment_id,
        )
        if submission is None:
            raise HTTPException(404, "Submission not found.")
        if submission.student_id != user.login_id:
            raise HTTPException(404, "Submission not found.")
        feedback = TutorService(request.app.state.settings).feedback(
            assignment, submission, hint_level=body.hint_level
        )
        if not is_ephemeral_demo(request, user):
            session.add(
                HintInteraction(
                    submission_id=submission.id,
                    hint_level=body.hint_level,
                    feedback=feedback.model_dump(),
                )
            )
            session.commit()
        study_session = get_user_study_session(
            session, submission.study_session_id, user
        )
        if study_session is not None:
            record_learning_event(
                session,
                study_session=study_session,
                user=user,
                event_type="hint_requested",
                assignment_id=assignment.id,
                assignment_version=submission.assignment_version,
                event_data={
                    "submission_id": submission.id,
                    "hint_level": body.hint_level,
                    "source": feedback.source,
                },
            )
        return feedback

    @application.post("/assignments/{assignment_id}/tutor")
    def ask_tutor(
        assignment_id: int,
        body: TutorQuestionRequest,
        request: Request,
        session: Session = Depends(session_dependency),
        user: User = Depends(current_user),
    ):
        enforce_rate_limit(
            request,
            user,
            bucket="tutor",
            requests_per_minute=request.app.state.settings.tutor_requests_per_minute,
        )
        assignment = get_assignment_or_404(session, assignment_id)
        submission = submission_for_request(
            request,
            session,
            user,
            body.submission_id,
            assignment_id,
        )
        if submission is None or submission.student_id != user.login_id:
            raise HTTPException(404, "Submission not found.")

        feedback = TutorService(request.app.state.settings).feedback(
            assignment,
            submission,
            hint_level=body.hint_level,
            student_question=body.question,
        )
        if not is_ephemeral_demo(request, user):
            stored_feedback = feedback.model_dump()
            stored_feedback["interaction_type"] = "student_question"
            session.add(
                HintInteraction(
                    submission_id=submission.id,
                    hint_level=body.hint_level,
                    feedback=stored_feedback,
                )
            )
            session.commit()

        study_session = get_user_study_session(
            session, submission.study_session_id, user
        )
        if study_session is not None:
            record_learning_event(
                session,
                study_session=study_session,
                user=user,
                event_type="hint_requested",
                assignment_id=assignment.id,
                assignment_version=submission.assignment_version,
                event_data={
                    "submission_id": submission.id,
                    "hint_level": body.hint_level,
                    "source": feedback.source,
                    "interaction_type": "student_question",
                    "question_length": len(body.question),
                },
            )
        return feedback

    @application.post("/assignments/{assignment_id}/solution")
    def reveal_solution(
        assignment_id: int,
        body: SolutionRequest,
        request: Request,
        session: Session = Depends(session_dependency),
        user: User = Depends(current_user),
    ):
        assignment = get_assignment_or_404(session, assignment_id)
        submission = submission_for_request(
            request,
            session,
            user,
            body.submission_id,
            assignment_id,
            assignment.version,
        )
        if submission is None:
            raise HTTPException(
                403,
                "Run or submit this assignment version before revealing its solution.",
            )
        if submission.student_id != user.login_id:
            raise HTTPException(
                403,
                "Run or submit this assignment version before revealing its solution.",
            )
        study_session = get_user_study_session(
            session, submission.study_session_id, user
        )
        if study_session is not None:
            record_learning_event(
                session,
                study_session=study_session,
                user=user,
                event_type="solution_revealed",
                assignment_id=assignment.id,
                assignment_version=submission.assignment_version,
                event_data={"submission_id": submission.id},
            )
        return {
            "assignment_id": assignment.id,
            "assignment_version": assignment.version,
            "solution_html": assignment.solution_html,
        }

    @application.get("/images/{image_id}")
    def serve_image(image_id: int):
        image = STATIC_DIR / f"image{image_id}.png"
        if not image.is_file():
            raise HTTPException(404, "Image not found.")
        return FileResponse(image, media_type="image/png")

    @application.get(
        "/admin/assignments",
        dependencies=[Depends(admin_dependency)],
    )
    def admin_list(session: Session = Depends(session_dependency)):
        return {
            "assignments": [
                to_admin_payload(item).model_dump()
                for item in AssignmentRepository(session).list_all()
            ]
        }

    @application.post(
        "/admin/assignments",
        dependencies=[Depends(admin_dependency)],
        status_code=201,
    )
    def admin_create(
        payload: AdminAssignmentPayload,
        session: Session = Depends(session_dependency),
    ):
        existing = session.scalar(
            select(Assignment).where(Assignment.stable_id == payload.stable_id)
        )
        if existing is not None or (
            payload.id is not None and session.get(Assignment, payload.id) is not None
        ):
            raise HTTPException(409, "Assignment ID or stable ID already exists.")
        if payload.status == "published":
            payload = payload.model_copy(update={"status": "draft"})
        assignment = AssignmentRepository(session).create(payload)
        return to_admin_payload(assignment)

    @application.put(
        "/admin/assignments/{assignment_id}",
        dependencies=[Depends(admin_dependency)],
    )
    def admin_update(
        assignment_id: int,
        payload: AdminAssignmentPayload,
        session: Session = Depends(session_dependency),
    ):
        assignment = get_assignment_or_404(
            session, assignment_id, include_drafts=True
        )
        duplicate = session.scalar(
            select(Assignment).where(
                Assignment.stable_id == payload.stable_id,
                Assignment.id != assignment_id,
            )
        )
        if duplicate is not None:
            raise HTTPException(409, "Assignment stable ID already exists.")
        updated = AssignmentRepository(session).update(assignment, payload)
        return to_admin_payload(updated)

    @application.post(
        "/admin/assignments/{assignment_id}/validate",
        dependencies=[Depends(admin_dependency)],
    )
    def admin_validate(
        assignment_id: int,
        request: Request,
        session: Session = Depends(session_dependency),
    ):
        assignment = get_assignment_or_404(
            session, assignment_id, include_drafts=True
        )
        errors = validate_assignment(
            assignment, grader_for(assignment, request)
        )
        return {"valid": not errors, "errors": errors}

    @application.post(
        "/admin/assignments/{assignment_id}/publish",
        dependencies=[Depends(admin_dependency)],
    )
    def admin_publish(
        assignment_id: int,
        request: Request,
        session: Session = Depends(session_dependency),
    ):
        assignment = get_assignment_or_404(
            session, assignment_id, include_drafts=True
        )
        errors = validate_assignment(
            assignment, grader_for(assignment, request)
        )
        if errors:
            raise HTTPException(422, " ".join(errors))
        assignment.status = "published"
        session.commit()
        return {"published": True, "id": assignment.id, "version": assignment.version}

    @application.get("/admin/students")
    def admin_students(
        session: Session = Depends(session_dependency),
        _actor: User | None = Depends(admin_dependency),
    ):
        students = session.scalars(
            select(User).where(User.role == "student").order_by(User.login_id)
        ).all()
        return {"students": [admin_user_payload(user) for user in students]}

    @application.post(
        "/admin/students",
        response_model=AdminStudentCreated,
        status_code=201,
    )
    def admin_create_student(
        body: AdminStudentCreate,
        request: Request,
        session: Session = Depends(session_dependency),
        actor: User | None = Depends(admin_dependency),
    ):
        if body.send_invitation_email and not request.app.state.settings.enable_email_features:
            raise HTTPException(404, "Not found.")
        email = normalize_email(body.email)
        if email and ("@" not in email or email.startswith("@") or email.endswith("@")):
            raise HTTPException(400, "Enter a valid email address.")
        if body.send_invitation_email and not email:
            raise HTTPException(400, "An email address is required for invitations.")
        email_service = EmailService(
            request.app.state.settings, request.app.state.email_outbox
        )
        if body.send_invitation_email and not email_service.configured:
            raise HTTPException(
                503,
                "Real email delivery is not configured. Add SMTP settings "
                "to backend/.env and restart the backend.",
            )
        temporary_password = body.temporary_password or generate_temporary_password()
        try:
            user = create_user(
                session,
                login_id=body.login_id,
                password=temporary_password,
                role="student",
                email=email,
                participant_code=body.participant_code,
                is_active=body.active,
                must_change_password=body.send_invitation_email,
                created_by=actor.id if actor else None,
            )
        except ValueError as error:
            raise HTTPException(409, str(error)) from error

        email_sent = False
        if body.send_invitation_email:
            try:
                email_sent = send_password_email(
                    request, session, user, purpose="account_activation"
                )
            except Exception as error:
                user.is_active = False
                session.commit()
                raise HTTPException(
                    502,
                    "The account was created but the invitation email failed. "
                    "The account was disabled.",
                ) from error
        record_audit(
            session,
            action="student.created",
            resource_type="user",
            resource_id=user.id,
            actor_user_id=actor.id if actor else None,
            details={
                "login_id": user.login_id,
                "participant_code": user.participant_code,
                "invitation_email": email_sent,
            },
        )
        return {
            "user": admin_user_payload(user),
            "temporary_password": (
                None if body.send_invitation_email else temporary_password
            ),
            "email_sent": email_sent,
        }

    @application.patch(
        "/admin/students/{student_id}",
        response_model=AdminUserResponse,
    )
    def admin_update_student(
        student_id: str,
        body: AdminStudentUpdate,
        session: Session = Depends(session_dependency),
        actor: User | None = Depends(admin_dependency),
    ):
        user = session.get(User, student_id)
        if user is None or user.role != "student":
            raise HTTPException(404, "Student account not found.")
        if "email" in body.model_fields_set:
            email = normalize_email(body.email)
            if email and ("@" not in email or email.startswith("@") or email.endswith("@")):
                raise HTTPException(400, "Enter a valid email address.")
            duplicate = (
                session.scalar(
                    select(User).where(User.email == email, User.id != user.id)
                )
                if email
                else None
            )
            if duplicate is not None:
                raise HTTPException(409, "Email address already exists.")
            user.email = email
        if "participant_code" in body.model_fields_set:
            participant_code = normalize_participant_code(body.participant_code)
            duplicate_participant = (
                session.scalar(
                    select(User).where(
                        User.role == "student",
                        User.participant_code == participant_code,
                        User.id != user.id,
                    )
                )
                if participant_code
                else None
            )
            if duplicate_participant is not None:
                raise HTTPException(409, "Participant code already exists.")
            user.participant_code = participant_code
        if body.active is not None:
            user.is_active = body.active
        session.commit()
        if body.active is False:
            revoke_user_sessions(session, user.id)
        record_audit(
            session,
            action="student.updated",
            resource_type="user",
            resource_id=user.id,
            actor_user_id=actor.id if actor else None,
            details={
                "login_id": user.login_id,
                "active": user.is_active,
                "participant_code": user.participant_code,
            },
        )
        session.refresh(user)
        return admin_user_payload(user)

    @application.post(
        "/admin/students/{student_id}/reset-password",
        response_model=AdminStudentCreated,
    )
    def admin_reset_student_password(
        student_id: str,
        body: AdminPasswordReset,
        request: Request,
        session: Session = Depends(session_dependency),
        actor: User | None = Depends(admin_dependency),
    ):
        user = session.get(User, student_id)
        if user is None or user.role != "student":
            raise HTTPException(404, "Student account not found.")
        if body.send_email:
            if not request.app.state.settings.enable_email_features:
                raise HTTPException(404, "Not found.")
            if not user.email:
                raise HTTPException(400, "The student has no email address.")
            email_service = EmailService(
                request.app.state.settings, request.app.state.email_outbox
            )
            if not email_service.configured:
                raise HTTPException(
                    503,
                    "Real email delivery is not configured. Add SMTP settings "
                    "to backend/.env and restart the backend.",
                )
            try:
                email_sent = send_password_email(
                    request, session, user, purpose="password_reset"
                )
            except Exception as error:
                raise HTTPException(502, "Password reset email delivery failed.") from error
            temporary_password = None
        else:
            temporary_password = (
                body.temporary_password or generate_temporary_password()
            )
            change_password(session, user, temporary_password)
            email_sent = False
        record_audit(
            session,
            action="student.password_reset",
            resource_type="user",
            resource_id=user.id,
            actor_user_id=actor.id if actor else None,
            details={"login_id": user.login_id, "email_sent": email_sent},
        )
        session.refresh(user)
        return {
            "user": admin_user_payload(user),
            "temporary_password": temporary_password,
            "email_sent": email_sent,
        }

    @application.post("/admin/accounts/import")
    def admin_import_accounts(
        request: Request,
        session: Session = Depends(session_dependency),
        actor: User | None = Depends(admin_dependency),
    ):
        report = sync_accounts_from_json(
            session, request.app.state.settings.study_accounts_file
        )
        request.app.state.account_import_report = report
        record_audit(
            session,
            action="account.json_imported",
            resource_type="account_file",
            resource_id=None,
            actor_user_id=actor.id if actor else None,
            details={
                "created": len(report["created"]),
                "updated": len(report["updated"]),
                "errors": len(report["errors"]),
            },
        )
        return report

    @application.get("/admin/email/status")
    def admin_email_status(
        request: Request,
        _actor: User | None = Depends(admin_dependency),
    ):
        if not request.app.state.settings.enable_email_features:
            raise HTTPException(404, "Not found.")
        return EmailService(
            request.app.state.settings, request.app.state.email_outbox
        ).status()

    @application.post("/admin/email/test")
    def admin_email_test(
        body: EmailTestRequest,
        request: Request,
        actor: User | None = Depends(admin_dependency),
        session: Session = Depends(session_dependency),
    ):
        if not request.app.state.settings.enable_email_features:
            raise HTTPException(404, "Not found.")
        recipient = normalize_email(body.recipient)
        if not recipient or "@" not in recipient:
            raise HTTPException(400, "Enter a valid recipient email address.")
        service = EmailService(
            request.app.state.settings, request.app.state.email_outbox
        )
        if not service.configured:
            raise HTTPException(
                503,
                "Real email delivery is not configured. Add SMTP settings "
                "to backend/.env and restart the backend.",
            )
        try:
            service.send_test_message(recipient)
        except Exception as error:
            logger.exception("SMTP test email delivery failed.")
            raise HTTPException(
                502,
                "The SMTP server rejected the test email. Check backend logs "
                "and the SMTP settings in backend/.env.",
            ) from error
        record_audit(
            session,
            action="email.test_sent",
            resource_type="email",
            resource_id=None,
            actor_user_id=actor.id if actor else None,
            details={"recipient": recipient},
        )
        return {"sent": True, "recipient": recipient}

    return application


app = create_app()
