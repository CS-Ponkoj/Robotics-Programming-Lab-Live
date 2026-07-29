import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from sqlalchemy import select
from sqlalchemy.orm import Session, sessionmaker

from assignment_repository import (
    AssignmentRepository,
    to_admin_payload,
    to_student_assignment,
)
from config import Settings, get_settings
from database import Base, build_engine
from graders import PythonVariableGrader
from models import Assignment, HintInteraction, Submission
from sandbox import build_sandbox
from schemas import (
    AdminAssignmentPayload,
    AssignmentListResponse,
    AssignmentStudent,
    HintRequest,
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
        yield
        engine.dispose()

    application = FastAPI(
        title="Robotics Programming Lab API",
        version="2.0.0",
        lifespan=lifespan,
    )
    application.state.settings = configured
    application.state.SessionLocal = local_session
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

    def admin_dependency(
        request: Request,
        x_admin_token: str | None = Header(default=None),
    ) -> None:
        token = request.app.state.settings.admin_api_token
        if not token:
            raise HTTPException(503, "Instructor administration is not configured.")
        if x_admin_token != token:
            raise HTTPException(401, "Invalid instructor token.")

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
            student_id=body.student_id,
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
    ):
        require_code(body, request)
        assignment = get_assignment_or_404(session, assignment_id)
        result = grader_for(assignment, request).run(assignment, body.code)
        submission = store_submission(session, assignment, body, "run", result)
        return response_for(assignment, submission)

    def submit_core(
        assignment_id: int,
        body: SubmissionRequest,
        request: Request,
        session: Session,
    ):
        require_code(body, request)
        assignment = get_assignment_or_404(session, assignment_id)
        result = grader_for(assignment, request).grade(assignment, body.code)
        submission = store_submission(session, assignment, body, "submit", result)
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
    ):
        return submit_core(assignment_id, body, request, session)

    @application.post("/grade/{assignment_id}", include_in_schema=False)
    def legacy_grade(
        assignment_id: int,
        body: SubmissionRequest,
        request: Request,
        session: Session = Depends(session_dependency),
    ):
        return submit_core(assignment_id, body, request, session)

    @application.post("/assignments/{assignment_id}/hint")
    def request_hint(
        assignment_id: int,
        body: HintRequest,
        request: Request,
        session: Session = Depends(session_dependency),
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

    return application


app = create_app()
