import logging
from contextlib import asynccontextmanager
from datetime import timedelta
from pathlib import Path

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
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
    normalize_email,
    normalize_login_id,
    record_audit,
    revoke_session_token,
    revoke_user_sessions,
    user_for_session_token,
    verify_password,
)
from config import Settings, get_settings
from database import Base, build_engine
from email_service import EmailService
from graders import PythonVariableGrader
from models import Assignment, HintInteraction, Submission, User, utc_now
from sandbox import build_sandbox
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
    ResetPasswordRequest,
    SolutionRequest,
    SubmissionRequest,
    SubmissionResponse,
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
) -> FastAPI:
    configured = settings or get_settings()
    selected_database_url = database_url or configured.database_url
    engine = build_engine(selected_database_url)
    local_session = sessionmaker(bind=engine, expire_on_commit=False)

    @asynccontextmanager
    async def lifespan(application: FastAPI):
        Base.metadata.create_all(engine)
        with local_session() as session:
            AssignmentRepository(session).sync_seed_assignments()
            seed_demo_accounts(session, configured.enable_demo_accounts)
            application.state.account_import_report = sync_accounts_from_json(
                session, configured.study_accounts_file
            )
        yield
        engine.dispose()

    application = FastAPI(
        title="Robotics Programming Lab API",
        version="2.0.0",
        lifespan=lifespan,
    )
    application.state.settings = configured
    application.state.SessionLocal = local_session
    application.state.email_outbox = []
    application.state.login_failures = {}
    application.add_middleware(
        CORSMiddleware,
        allow_origins=configured.cors_origins,
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @application.exception_handler(HTTPException)
    async def http_error(_request: Request, error: HTTPException):
        return JSONResponse(
            status_code=error.status_code,
            content={"error": str(error.detail)},
        )

    @application.exception_handler(RequestValidationError)
    async def validation_error(_request: Request, error: RequestValidationError):
        return JSONResponse(
            status_code=400,
            content={"error": "Invalid request.", "details": error.errors()},
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

    def current_user(
        request: Request,
        session: Session = Depends(session_dependency),
    ) -> User:
        user = user_for_session_token(session, bearer_token(request))
        if user is None:
            raise HTTPException(401, "Authentication required.")
        return user

    def optional_user(
        request: Request,
        session: Session = Depends(session_dependency),
    ) -> User | None:
        return user_for_session_token(session, bearer_token(request))

    def instructor_user(
        user: User = Depends(current_user),
    ) -> User:
        if user.role != "instructor":
            raise HTTPException(403, "Instructor access required.")
        return user

    def admin_dependency(
        request: Request,
        x_admin_token: str | None = Header(default=None),
        session: Session = Depends(session_dependency),
    ) -> User | None:
        token = request.app.state.settings.admin_api_token
        if token and x_admin_token == token:
            return None
        user = user_for_session_token(session, bearer_token(request))
        if user is not None:
            if user.role == "instructor":
                return user
            raise HTTPException(403, "Instructor access required.")
        if x_admin_token:
            raise HTTPException(401, "Invalid instructor token.")
        raise HTTPException(401, "Instructor authentication required.")

    def user_payload(user: User) -> dict:
        return AuthenticatedUser(
            id=user.id,
            login_id=user.login_id,
            role=user.role,
            email=user.email,
            participant_code=user.participant_code,
            is_demo=user.is_demo,
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
        if assignment.grader_type != "python_variables":
            raise HTTPException(422, f"Unsupported grader: {assignment.grader_type}.")
        settings_value = request.app.state.settings
        timeout = float(
            (assignment.execution_settings or {}).get(
                "timeout_seconds", settings_value.execution_timeout_seconds
            )
        )
        sandbox = build_sandbox(
            settings_value.sandbox_backend,
            settings_value.sandbox_image,
            timeout,
        )
        return PythonVariableGrader(sandbox)

    def require_code(request_body: SubmissionRequest, request: Request) -> None:
        if not request_body.code.strip():
            raise HTTPException(400, "A non-empty code string is required.")
        if len(request_body.code) > request.app.state.settings.max_submission_chars:
            raise HTTPException(413, "Submitted code is too large.")

    def store_submission(
        session: Session,
        assignment: Assignment,
        body: SubmissionRequest,
        mode: str,
        result,
        user: User | None = None,
    ) -> Submission:
        evidence = {
            "execution_succeeded": result.execution_succeeded,
            "passed": result.passed,
            "score": result.score,
            "execution_error": result.execution_error,
            "code_output": result.code_output,
            "tested_names": result.tested_names,
            "tests": [item.model_dump() for item in result.evidence],
        }
        submission = Submission(
            assignment_id=assignment.id,
            assignment_version=assignment.version,
            student_id=user.login_id if user is not None else body.student_id,
            mode=mode,
            code=body.code,
            execution_succeeded=result.execution_succeeded,
            passed=result.passed,
            score=result.score,
            evidence=evidence,
        )
        session.add(submission)
        session.commit()
        session.refresh(submission)
        return submission

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
            score=submission.score,
            hint=tutor_feedback.hint if tutor_feedback else "",
            evidence=tests,
            tutor_feedback=tutor_feedback,
        )
        return response.model_dump(by_alias=True)

    @application.get("/health")
    def health():
        return {
            "status": "ok",
            "api_version": "2.0.0",
            "database": engine.dialect.name,
            "sandbox": configured.sandbox_backend,
        }

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
            "user": user_payload(user),
        }

    @application.get("/auth/me", response_model=AuthenticatedUser)
    def auth_me(user: User = Depends(current_user)):
        return user_payload(user)

    @application.post("/auth/logout")
    def logout(
        request: Request,
        session: Session = Depends(session_dependency),
        user: User = Depends(current_user),
    ):
        revoke_session_token(session, bearer_token(request))
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
        session: Session = Depends(session_dependency),
        user: User = Depends(current_user),
    ):
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
        session: Session = Depends(session_dependency),
    ):
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

    @application.get(
        "/assignments",
        response_model=AssignmentListResponse,
    )
    @application.get(
        "/assignments/",
        response_model=AssignmentListResponse,
        include_in_schema=False,
    )
    def list_assignments(session: Session = Depends(session_dependency)):
        assignments = AssignmentRepository(session).list_published()
        return {"assignments": [to_student_assignment(item) for item in assignments]}

    @application.get(
        "/assignments/{assignment_id}",
        response_model=AssignmentStudent,
    )
    def get_assignment(
        assignment_id: int, session: Session = Depends(session_dependency)
    ):
        return to_student_assignment(get_assignment_or_404(session, assignment_id))

    @application.post("/assignments/{assignment_id}/run")
    def run_assignment(
        assignment_id: int,
        body: SubmissionRequest,
        request: Request,
        session: Session = Depends(session_dependency),
        user: User | None = Depends(optional_user),
    ):
        require_code(body, request)
        assignment = get_assignment_or_404(session, assignment_id)
        result = grader_for(assignment, request).run(assignment, body.code)
        submission = store_submission(
            session, assignment, body, "run", result, user=user
        )
        return response_for(assignment, submission)

    def submit_core(
        assignment_id: int,
        body: SubmissionRequest,
        request: Request,
        session: Session,
        user: User | None = None,
    ):
        require_code(body, request)
        assignment = get_assignment_or_404(session, assignment_id)
        result = grader_for(assignment, request).grade(assignment, body.code)
        submission = store_submission(
            session, assignment, body, "submit", result, user=user
        )
        tutor_feedback = None
        if body.use_ai_tutor and not result.passed:
            tutor_feedback = TutorService(request.app.state.settings).feedback(
                assignment, submission, hint_level=1
            )
            session.add(
                HintInteraction(
                    submission_id=submission.id,
                    hint_level=1,
                    feedback=tutor_feedback.model_dump(),
                )
            )
            session.commit()
        return response_for(assignment, submission, tutor_feedback)

    @application.post("/assignments/{assignment_id}/submit")
    def submit_assignment(
        assignment_id: int,
        body: SubmissionRequest,
        request: Request,
        session: Session = Depends(session_dependency),
        user: User | None = Depends(optional_user),
    ):
        return submit_core(assignment_id, body, request, session, user)

    @application.post("/grade/{assignment_id}", include_in_schema=False)
    def legacy_grade(
        assignment_id: int,
        body: SubmissionRequest,
        request: Request,
        session: Session = Depends(session_dependency),
        user: User | None = Depends(optional_user),
    ):
        return submit_core(assignment_id, body, request, session, user)

    @application.post("/assignments/{assignment_id}/hint")
    def request_hint(
        assignment_id: int,
        body: HintRequest,
        request: Request,
        session: Session = Depends(session_dependency),
        user: User | None = Depends(optional_user),
    ):
        assignment = get_assignment_or_404(session, assignment_id)
        submission = session.scalar(
            select(Submission).where(
                Submission.id == body.submission_id,
                Submission.assignment_id == assignment_id,
            )
        )
        if submission is None:
            raise HTTPException(404, "Submission not found.")
        if user is not None and submission.student_id != user.login_id:
            raise HTTPException(404, "Submission not found.")
        feedback = TutorService(request.app.state.settings).feedback(
            assignment, submission, hint_level=body.hint_level
        )
        session.add(
            HintInteraction(
                submission_id=submission.id,
                hint_level=body.hint_level,
                feedback=feedback.model_dump(),
            )
        )
        session.commit()
        return feedback

    @application.post("/assignments/{assignment_id}/solution")
    def reveal_solution(
        assignment_id: int,
        body: SolutionRequest,
        session: Session = Depends(session_dependency),
        user: User | None = Depends(optional_user),
    ):
        assignment = get_assignment_or_404(session, assignment_id)
        submission = session.scalar(
            select(Submission).where(
                Submission.id == body.submission_id,
                Submission.assignment_id == assignment_id,
                Submission.assignment_version == assignment.version,
            )
        )
        if submission is None:
            raise HTTPException(
                403,
                "Run or submit this assignment version before revealing its solution.",
            )
        if user is not None and submission.student_id != user.login_id:
            raise HTTPException(
                403,
                "Run or submit this assignment version before revealing its solution.",
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
            user.participant_code = (
                (body.participant_code or "").strip() or None
            )
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
