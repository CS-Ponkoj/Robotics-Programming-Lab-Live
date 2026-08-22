from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from data_contracts import (
    CURRENT_DATA_SCHEMA_VERSION,
    ClientLearningEventType,
    ExecutionStatus,
    normalize_assignment_structured_data,
)


class AssignmentProjectFile(BaseModel):
    path: str
    content: str = ""
    editable: bool = False


class AssignmentStudent(BaseModel):
    id: int
    stable_id: str
    version: int
    data_schema_version: Literal[CURRENT_DATA_SCHEMA_VERSION]
    title: str
    description: str
    assignment_html: str
    starter_code: str
    language: str
    learning_objectives: list[str] = Field(default_factory=list)
    public_tests: list[dict[str, Any]] = Field(default_factory=list)
    rubric: list[dict[str, Any]] = Field(default_factory=list)
    simulation_config: dict[str, Any] = Field(default_factory=dict)
    project_files: list[AssignmentProjectFile] = Field(default_factory=list)
    editable_file_path: str | None = None
    has_solution: bool = False
    solution_html: str = ""
    vals: dict[str, Any] = Field(default_factory=dict)


class AssignmentListResponse(BaseModel):
    assignments: list[AssignmentStudent]


class SubmissionRequest(BaseModel):
    code: str = Field(min_length=1)
    student_id: str = Field(default="anonymous", max_length=120)
    use_ai_tutor: bool = False
    study_session_id: str | None = Field(default=None, max_length=36)


class TestEvidence(BaseModel):
    test_id: str
    label: str
    passed: bool
    message: str
    visibility: Literal["public", "hidden"] = "hidden"


class TutorFeedback(BaseModel):
    diagnosis: str = ""
    misconception: str = ""
    answer: str = ""
    debugging_steps: list[str] = Field(default_factory=list)
    hint_level: int = 1
    guiding_question: str = ""
    hint: str = ""
    next_action: str = ""
    solution_revealed: bool = False
    source: Literal["openai", "fallback"] = "fallback"


class TutorGeneratedContent(BaseModel):
    """Strict provider output contract before it reaches the student UI."""

    model_config = ConfigDict(extra="forbid")

    diagnosis: str = Field(min_length=1, max_length=500)
    misconception: str = Field(max_length=300)
    answer: str = Field(max_length=700)
    debugging_steps: list[str] = Field(min_length=1, max_length=3)
    guiding_question: str = Field(min_length=1, max_length=400)
    hint: str = Field(min_length=1, max_length=400)
    next_action: str = Field(min_length=1, max_length=300)


class SubmissionResponse(BaseModel):
    id: int
    submission_id: str
    assignment_version: int
    tested_vals: list[str]
    pass_: bool = Field(serialization_alias="pass")
    unittest_results: list[str]
    unittest_pass_results: list[bool]
    code_exec_result: str
    code_output: str
    ex_success: bool
    execution_status: ExecutionStatus
    score: int
    hint: str = ""
    evidence: list[TestEvidence] = Field(default_factory=list)
    tutor_feedback: TutorFeedback | None = None


class HintRequest(BaseModel):
    submission_id: str
    hint_level: int = Field(default=1, ge=1, le=4)


class TutorQuestionRequest(BaseModel):
    submission_id: str = Field(min_length=1, max_length=36)
    question: str = Field(min_length=3, max_length=500)
    hint_level: int = Field(default=1, ge=1, le=4)

    @field_validator("question")
    @classmethod
    def normalize_question(cls, value: str) -> str:
        normalized = value.strip()
        if len(normalized) < 3:
            raise ValueError("Question must contain at least 3 visible characters.")
        return normalized


class SolutionRequest(BaseModel):
    submission_id: str


class AdminAssignmentPayload(BaseModel):
    id: int | None = None
    stable_id: str
    version: int = Field(default=1, ge=1)
    data_schema_version: Literal[CURRENT_DATA_SCHEMA_VERSION] = (
        CURRENT_DATA_SCHEMA_VERSION
    )
    title: str
    description: str = ""
    assignment_html: str = ""
    starter_code: str = ""
    language: str = "python"
    status: Literal["draft", "published", "archived"] = "draft"
    learning_objectives: list[str] = Field(default_factory=list)
    execution_settings: dict[str, Any] = Field(default_factory=dict)
    public_tests: list[dict[str, Any]] = Field(default_factory=list)
    rubric: list[dict[str, Any]] = Field(default_factory=list)
    misconceptions: list[dict[str, Any] | str] = Field(default_factory=list)
    tutoring_rules: dict[str, Any] = Field(default_factory=dict)
    simulation_config: dict[str, Any] = Field(default_factory=dict)
    asset_manifest: list[dict[str, Any] | str] = Field(default_factory=list)
    grader_type: str = "python_variables"
    grader_config: dict[str, Any] = Field(default_factory=dict)
    solution_html: str = ""
    reference_solution_path: str | None = None

    @model_validator(mode="after")
    def validate_structured_assignment_fields(self):
        normalized = normalize_assignment_structured_data(self.model_dump())
        for field_name in (
            "learning_objectives",
            "execution_settings",
            "public_tests",
            "rubric",
            "misconceptions",
            "tutoring_rules",
            "simulation_config",
            "asset_manifest",
            "grader_config",
        ):
            setattr(self, field_name, normalized[field_name])
        return self


class LoginRequest(BaseModel):
    login_id: str = Field(min_length=1, max_length=120)
    password: str = Field(min_length=1, max_length=128)


class AuthenticatedUser(BaseModel):
    id: str
    login_id: str
    role: Literal["student", "instructor"]
    email: str | None = None
    participant_code: str | None = None
    is_demo: bool = False
    must_change_password: bool = False


class LoginResponse(BaseModel):
    token: str
    expires_at: datetime
    user: AuthenticatedUser


class ChangePasswordRequest(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=8, max_length=128)


class ForgotPasswordRequest(BaseModel):
    identifier: str = Field(min_length=1, max_length=320)


class ResetPasswordRequest(BaseModel):
    token: str = Field(min_length=20, max_length=500)
    new_password: str = Field(min_length=8, max_length=128)


class EmailTestRequest(BaseModel):
    recipient: str = Field(min_length=3, max_length=320)


class AdminStudentCreate(BaseModel):
    login_id: str = Field(min_length=1, max_length=120)
    temporary_password: str | None = Field(default=None, min_length=8, max_length=128)
    email: str | None = Field(default=None, max_length=320)
    participant_code: str | None = Field(default=None, max_length=120)
    active: bool = True
    send_invitation_email: bool = False


class AdminStudentUpdate(BaseModel):
    email: str | None = Field(default=None, max_length=320)
    participant_code: str | None = Field(default=None, max_length=120)
    active: bool | None = None


class AdminPasswordReset(BaseModel):
    temporary_password: str | None = Field(default=None, min_length=8, max_length=128)
    send_email: bool = False


class AdminUserResponse(AuthenticatedUser):
    is_active: bool
    created_at: datetime
    last_login_at: datetime | None = None


class AdminStudentCreated(BaseModel):
    user: AdminUserResponse
    temporary_password: str | None = None
    email_sent: bool = False


class StudySessionStartRequest(BaseModel):
    client_session_id: str = Field(min_length=8, max_length=120)


class StudySessionResponse(BaseModel):
    id: str
    participant_code: str | None = None
    started_at: datetime
    last_active_at: datetime
    ended_at: datetime | None = None
    active_seconds: int


class StudyHeartbeatRequest(BaseModel):
    active_seconds: int = Field(ge=1, le=60)
    assignment_id: int | None = Field(default=None, ge=1)
    assignment_version: int | None = Field(default=None, ge=1)

    @model_validator(mode="after")
    def require_assignment_version_pair(self):
        if (self.assignment_id is None) != (self.assignment_version is None):
            raise ValueError(
                "assignment_id and assignment_version must be provided together"
            )
        return self


class LearningEventRequest(BaseModel):
    event_type: ClientLearningEventType
    assignment_id: int | None = Field(default=None, ge=1)
    assignment_version: int | None = Field(default=None, ge=1)
    event_data: dict[str, Any] = Field(default_factory=dict)
    client_occurred_at: datetime | None = None

    @model_validator(mode="after")
    def validate_event_contract(self):
        if (self.assignment_id is None) != (self.assignment_version is None):
            raise ValueError(
                "assignment_id and assignment_version must be provided together"
            )
        return self
