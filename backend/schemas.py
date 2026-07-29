from typing import Any, Literal

from pydantic import BaseModel, Field


class AssignmentStudent(BaseModel):
    id: int
    stable_id: str
    version: int
    title: str
    description: str
    assignment_html: str
    starter_code: str
    language: str
    learning_objectives: list[str] = Field(default_factory=list)
    public_tests: list[dict[str, Any]] = Field(default_factory=list)
    rubric: list[dict[str, Any]] = Field(default_factory=list)
    simulation_config: dict[str, Any] = Field(default_factory=dict)
    has_solution: bool = False
    solution_html: str = ""
    vals: dict[str, Any] = Field(default_factory=dict)


class AssignmentListResponse(BaseModel):
    assignments: list[AssignmentStudent]


class SubmissionRequest(BaseModel):
    code: str = Field(min_length=1)
    student_id: str = Field(default="anonymous", max_length=120)
    use_ai_tutor: bool = False


class TestEvidence(BaseModel):
    test_id: str
    label: str
    passed: bool
    message: str
    visibility: Literal["public", "hidden"] = "hidden"


class TutorFeedback(BaseModel):
    diagnosis: str = ""
    misconception: str = ""
    hint_level: int = 1
    guiding_question: str = ""
    hint: str = ""
    next_action: str = ""
    solution_revealed: bool = False
    source: Literal["openai", "fallback"] = "fallback"


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
    score: int
    hint: str = ""
    evidence: list[TestEvidence] = Field(default_factory=list)
    tutor_feedback: TutorFeedback | None = None


class HintRequest(BaseModel):
    submission_id: str
    hint_level: int = Field(default=1, ge=1, le=4)


class SolutionRequest(BaseModel):
    submission_id: str


class AdminAssignmentPayload(BaseModel):
    id: int | None = None
    stable_id: str
    version: int = Field(default=1, ge=1)
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
