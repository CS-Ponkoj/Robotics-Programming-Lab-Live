"""Versioned data contracts for assignments, grading, and research events.

These contracts standardize JSON stored in database columns while keeping the
database models provider-neutral for SQLite development and PostgreSQL staging.
"""

from enum import StrEnum
from typing import Any, Annotated

from pydantic import BaseModel, ConfigDict, Field, TypeAdapter, model_validator


CURRENT_DATA_SCHEMA_VERSION = 1

NonEmptyText = Annotated[str, Field(min_length=1, max_length=500)]


class ExecutionStatus(StrEnum):
    COMPLETED = "completed"
    SYNTAX_ERROR = "syntax_error"
    RUNTIME_ERROR = "runtime_error"
    TIMEOUT = "timeout"
    REJECTED = "rejected"
    GRADER_UNAVAILABLE = "grader_unavailable"
    INTERNAL_ERROR = "internal_error"
    EXECUTION_ERROR = "execution_error"


EXECUTION_STATUS_VALUES = tuple(item.value for item in ExecutionStatus)


class SubmissionMode(StrEnum):
    RUN = "run"
    SUBMIT = "submit"


SUBMISSION_MODE_VALUES = tuple(item.value for item in SubmissionMode)


def classify_execution_status(success: bool, error: str = "") -> ExecutionStatus:
    """Map executor-specific text to a stable, research-safe status."""
    if success:
        return ExecutionStatus.COMPLETED
    normalized = error.casefold()
    if "syntaxerror" in normalized or "syntax error" in normalized:
        return ExecutionStatus.SYNTAX_ERROR
    if "timeout" in normalized or "timed out" in normalized or "exceeded" in normalized:
        return ExecutionStatus.TIMEOUT
    if any(
        phrase in normalized
        for phrase in ("not allowed", "unsafe", "too large", "rejected")
    ):
        return ExecutionStatus.REJECTED
    if any(
        phrase in normalized
        for phrase in (
            "temporarily unavailable",
            "grader is starting",
            "docker sandbox unavailable",
            "could not connect",
        )
    ):
        return ExecutionStatus.GRADER_UNAVAILABLE
    if any(
        phrase in normalized
        for phrase in ("invalid response", "worker failed", "internal error")
    ):
        return ExecutionStatus.INTERNAL_ERROR
    if error.strip():
        return ExecutionStatus.RUNTIME_ERROR
    return ExecutionStatus.EXECUTION_ERROR


class ContractModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class PublicTestDefinition(ContractModel):
    id: NonEmptyText
    label: NonEmptyText


class RubricCriterion(ContractModel):
    criterion: NonEmptyText
    description: NonEmptyText
    weight: float = Field(ge=0, le=100)


class MisconceptionDefinition(ContractModel):
    tag: NonEmptyText
    description: NonEmptyText


class ExecutionSettings(ContractModel):
    runtime: NonEmptyText
    timeout_seconds: float = Field(gt=0, le=120)
    allowed_imports: list[NonEmptyText] = Field(default_factory=list)
    editable_file: str | None = Field(default=None, min_length=1, max_length=500)
    network_enabled: bool = False
    simulation_enabled: bool = False


class TutoringRules(ContractModel):
    max_hint_level: int = Field(default=4, ge=1, le=10)
    start_with_question: bool = True
    never_reveal_solution: bool = True
    never_reveal_hidden_tests: bool = True
    ai_enabled_by_default: bool = False
    tone: str = Field(default="encouraging and concise", max_length=200)


class SimulationConfig(ContractModel):
    enabled: bool = False
    provider: str | None = Field(default=None, max_length=120)
    scenario: str | None = Field(default=None, max_length=300)


class ProjectFileAsset(ContractModel):
    kind: str = Field(pattern="^project_file$")
    path: str = Field(min_length=1, max_length=500)
    editable: bool = False
    content: str = ""


class AssignmentStructuredData(ContractModel):
    learning_objectives: list[NonEmptyText]
    execution_settings: ExecutionSettings
    public_tests: list[PublicTestDefinition]
    rubric: list[RubricCriterion]
    misconceptions: list[MisconceptionDefinition | NonEmptyText]
    tutoring_rules: TutoringRules
    simulation_config: SimulationConfig
    asset_manifest: list[ProjectFileAsset | NonEmptyText]
    grader_config: dict[str, Any]

    @model_validator(mode="after")
    def unique_public_test_ids(self):
        test_ids = [item.id for item in self.public_tests]
        if len(test_ids) != len(set(test_ids)):
            raise ValueError("public_tests must use unique IDs")
        return self


def normalize_assignment_structured_data(values: dict[str, Any]) -> dict[str, Any]:
    """Validate and normalize every JSON field stored for an assignment."""
    structured = AssignmentStructuredData.model_validate(
        {
            "learning_objectives": values.get("learning_objectives", []),
            "execution_settings": values.get("execution_settings", {}),
            "public_tests": values.get("public_tests", []),
            "rubric": values.get("rubric", []),
            "misconceptions": values.get("misconceptions", []),
            "tutoring_rules": values.get("tutoring_rules", {}),
            "simulation_config": values.get("simulation_config", {}),
            "asset_manifest": values.get("asset_manifest", []),
            "grader_config": values.get("grader_config", {}),
        }
    ).model_dump(mode="json")
    result = dict(values)
    result.update(structured)
    return result


class LearningEventType(StrEnum):
    ASSIGNMENT_OPENED = "assignment_opened"
    AI_TUTOR_TOGGLED = "ai_tutor_toggled"
    WORKSPACE_TAB_CHANGED = "workspace_tab_changed"
    WORKSPACE_FILE_SELECTED = "workspace_file_selected"
    ASSIGNMENT_RUN = "assignment_run"
    ASSIGNMENT_SUBMITTED = "assignment_submitted"
    HINT_REQUESTED = "hint_requested"
    SOLUTION_REVEALED = "solution_revealed"


class ClientLearningEventType(StrEnum):
    ASSIGNMENT_OPENED = LearningEventType.ASSIGNMENT_OPENED
    AI_TUTOR_TOGGLED = LearningEventType.AI_TUTOR_TOGGLED
    WORKSPACE_TAB_CHANGED = LearningEventType.WORKSPACE_TAB_CHANGED
    WORKSPACE_FILE_SELECTED = LearningEventType.WORKSPACE_FILE_SELECTED


AUTOMATIC_LEARNING_EVENT_TYPES = frozenset(
    {
        LearningEventType.ASSIGNMENT_RUN.value,
        LearningEventType.ASSIGNMENT_SUBMITTED.value,
        LearningEventType.HINT_REQUESTED.value,
        LearningEventType.SOLUTION_REVEALED.value,
    }
)


class AssignmentOpenedEventData(ContractModel):
    source: str = Field(default="assignment_catalog", min_length=1, max_length=120)


class AiTutorToggledEventData(ContractModel):
    enabled: bool


class WorkspaceTabChangedEventData(ContractModel):
    tab_index: int = Field(ge=0, le=10)


class WorkspaceFileSelectedEventData(ContractModel):
    path: str = Field(min_length=1, max_length=500)
    editable: bool


class SubmissionEventData(ContractModel):
    submission_id: str = Field(min_length=1, max_length=36)
    execution_succeeded: bool
    execution_status: ExecutionStatus
    passed: bool
    score: int = Field(ge=0, le=100)
    ai_tutor_requested: bool


class HintRequestedEventData(ContractModel):
    submission_id: str = Field(min_length=1, max_length=36)
    hint_level: int = Field(ge=1, le=10)
    source: str = Field(min_length=1, max_length=80)
    interaction_type: str = Field(
        default="progressive_hint",
        pattern="^(progressive_hint|student_question)$",
    )
    question_length: int | None = Field(default=None, ge=3, le=500)

    @model_validator(mode="after")
    def validate_question_metadata(self):
        if self.interaction_type == "student_question":
            if self.question_length is None:
                raise ValueError("question_length is required for student questions")
        elif self.question_length is not None:
            raise ValueError(
                "question_length is only valid for student-question interactions"
            )
        return self


class SolutionRevealedEventData(ContractModel):
    submission_id: str = Field(min_length=1, max_length=36)


EVENT_DATA_ADAPTERS = {
    LearningEventType.ASSIGNMENT_OPENED.value: TypeAdapter(AssignmentOpenedEventData),
    LearningEventType.AI_TUTOR_TOGGLED.value: TypeAdapter(AiTutorToggledEventData),
    LearningEventType.WORKSPACE_TAB_CHANGED.value: TypeAdapter(
        WorkspaceTabChangedEventData
    ),
    LearningEventType.WORKSPACE_FILE_SELECTED.value: TypeAdapter(
        WorkspaceFileSelectedEventData
    ),
    LearningEventType.ASSIGNMENT_RUN.value: TypeAdapter(SubmissionEventData),
    LearningEventType.ASSIGNMENT_SUBMITTED.value: TypeAdapter(SubmissionEventData),
    LearningEventType.HINT_REQUESTED.value: TypeAdapter(HintRequestedEventData),
    LearningEventType.SOLUTION_REVEALED.value: TypeAdapter(SolutionRevealedEventData),
}


def normalize_event_data(event_type: str, event_data: dict[str, Any]) -> dict[str, Any]:
    """Validate and normalize metadata for one allowlisted event type."""
    adapter = EVENT_DATA_ADAPTERS.get(str(event_type))
    if adapter is None:
        raise ValueError(f"Unsupported learning event type: {event_type}")
    return adapter.validate_python(event_data).model_dump(mode="json")
