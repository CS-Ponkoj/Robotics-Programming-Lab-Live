"""Validated, instructor-authored evaluation cases for the future AI tutor.

This module is intentionally offline in Stage 1. Runtime tutoring code does not
load these files. They are controlled gold cases for instructor review and
future AI-feedback evaluation, not student-visible content.
"""

from __future__ import annotations

import json
from enum import StrEnum
from pathlib import Path
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, model_validator

from data_contracts import ExecutionStatus


DATASET_SCHEMA_VERSION = 1
BASE_DIR = Path(__file__).resolve().parent
DATASET_DIR = BASE_DIR / "ai_evaluation_cases"
ASSIGNMENTS_DIR = BASE_DIR / "assignments"

FORBIDDEN_KEYS = frozenset(
    {
        "hidden_tests",
        "grader_config",
        "solution_html",
        "reference_solution_path",
        "official_solution",
        "reference_solution",
        "answer_key",
    }
)


class ContractModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class ReviewStatus(StrEnum):
    DRAFT = "draft"
    APPROVED = "approved"
    REJECTED = "rejected"


class EvaluationCaseType(StrEnum):
    CONCEPTUAL_ERROR = "conceptual_error"
    SYNTAX_ERROR = "syntax_error"
    RUNTIME_ERROR = "runtime_error"
    INCOMPLETE_IMPLEMENTATION = "incomplete_implementation"
    UNSAFE_CODE = "unsafe_code"
    SOLUTION_REQUEST = "solution_request"


class DatasetPolicy(ContractModel):
    never_reveal_official_solution: bool = True
    never_reveal_hidden_tests: bool = True
    runtime_use_enabled: bool = False

    @model_validator(mode="after")
    def enforce_stage_one_safety(self):
        if not self.never_reveal_official_solution:
            raise ValueError("official-solution protection must remain enabled")
        if not self.never_reveal_hidden_tests:
            raise ValueError("hidden-test protection must remain enabled")
        if self.runtime_use_enabled:
            raise ValueError("Stage 1 instructor datasets cannot be used at runtime")
        return self


class HintStep(ContractModel):
    level: int = Field(ge=1, le=4)
    hint: str = Field(min_length=1, max_length=500)


class ExpectedFeedback(ContractModel):
    diagnosis: str = Field(min_length=1, max_length=800)
    debugging_steps: list[str] = Field(min_length=1, max_length=5)
    socratic_question: str = Field(min_length=1, max_length=500)
    must_mention: list[str] = Field(default_factory=list, max_length=8)
    must_avoid: list[str] = Field(default_factory=list, max_length=8)


class InstructorEvaluationCase(ContractModel):
    case_id: str = Field(pattern=r"^[a-z0-9]+(?:-[a-z0-9]+)*$", max_length=100)
    title: str = Field(min_length=1, max_length=160)
    case_type: EvaluationCaseType
    review_status: ReviewStatus = ReviewStatus.DRAFT
    reviewer: str | None = Field(default=None, min_length=1, max_length=120)
    student_code: str | None = Field(default=None, max_length=20_000)
    student_question: str | None = Field(default=None, max_length=2_000)
    expected_execution_status: ExecutionStatus | None = None
    misconception_tags: list[str] = Field(default_factory=list, max_length=12)
    expected_feedback: ExpectedFeedback
    hint_ladder: list[HintStep] = Field(min_length=3, max_length=4)
    instructor_notes: str = Field(min_length=1, max_length=800)

    @model_validator(mode="after")
    def validate_case(self):
        if not (self.student_code and self.student_code.strip()) and not (
            self.student_question and self.student_question.strip()
        ):
            raise ValueError("a case needs student_code or student_question")
        levels = [step.level for step in self.hint_ladder]
        if levels != list(range(1, len(levels) + 1)):
            raise ValueError("hint levels must be sequential and start at 1")
        if self.review_status == ReviewStatus.APPROVED and not self.reviewer:
            raise ValueError("approved cases require a named reviewer")
        return self


class InstructorAssignmentDataset(ContractModel):
    dataset_schema_version: int = Field(default=DATASET_SCHEMA_VERSION, ge=1)
    assignment_id: int = Field(ge=1)
    assignment_stable_id: str = Field(min_length=1, max_length=160)
    assignment_version: int = Field(ge=1)
    authored_by_role: str = Field(default="instructor", pattern="^instructor$")
    review_status: ReviewStatus = ReviewStatus.DRAFT
    policy: DatasetPolicy = Field(default_factory=DatasetPolicy)
    cases: list[InstructorEvaluationCase] = Field(min_length=1)

    @model_validator(mode="after")
    def unique_case_ids(self):
        case_ids = [case.case_id for case in self.cases]
        if len(case_ids) != len(set(case_ids)):
            raise ValueError("case IDs must be unique within an assignment")
        return self


class DatasetInventory(ContractModel):
    assignment_count: int
    case_count: int
    draft_count: int
    approved_count: int
    covered_misconception_count: int


def _find_forbidden_keys(value: Any, path: str = "root") -> list[str]:
    findings: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            child_path = f"{path}.{key}"
            if key in FORBIDDEN_KEYS:
                findings.append(child_path)
            findings.extend(_find_forbidden_keys(child, child_path))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            findings.extend(_find_forbidden_keys(child, f"{path}[{index}]"))
    return findings


def _assignment_identity(source: dict[str, Any]) -> tuple[str, int]:
    assignment_id = int(source["id"])
    return (
        str(source.get("stable_id", f"robotics-assignment-{assignment_id}")),
        int(source.get("version", 1)),
    )


def _assignment_misconceptions(source: dict[str, Any]) -> set[str]:
    configured = source.get("common_misconceptions")
    if configured is not None:
        return {
            str(item["tag"] if isinstance(item, dict) else item) for item in configured
        }
    return {
        f"incorrect-{name.replace('_', '-')}"
        for name in source.get("vals", {}).keys()
    }


def load_instructor_datasets(
    dataset_dir: Path = DATASET_DIR,
    assignments_dir: Path = ASSIGNMENTS_DIR,
) -> list[InstructorAssignmentDataset]:
    """Load the complete inventory and enforce assignment and safety coverage."""
    assignment_sources = {
        int(source["id"]): source
        for path in sorted(assignments_dir.glob("assignment_*.json"))
        for source in [json.loads(path.read_text(encoding="utf-8"))]
    }
    dataset_paths = sorted(dataset_dir.glob("assignment_*.json"))
    if not dataset_paths:
        raise ValueError(f"no instructor datasets found in {dataset_dir}")

    datasets: list[InstructorAssignmentDataset] = []
    global_case_ids: set[str] = set()
    for path in dataset_paths:
        raw = json.loads(path.read_text(encoding="utf-8"))
        forbidden = _find_forbidden_keys(raw)
        if forbidden:
            raise ValueError(f"{path.name} contains forbidden keys: {', '.join(forbidden)}")
        dataset = InstructorAssignmentDataset.model_validate(raw)
        expected_name = f"assignment_{dataset.assignment_id}.json"
        if path.name != expected_name:
            raise ValueError(f"{path.name} must be named {expected_name}")
        source = assignment_sources.get(dataset.assignment_id)
        if source is None:
            raise ValueError(f"{path.name} references an unknown assignment")
        stable_id, version = _assignment_identity(source)
        if dataset.assignment_stable_id != stable_id:
            raise ValueError(f"{path.name} uses the wrong assignment stable ID")
        if dataset.assignment_version != version:
            raise ValueError(f"{path.name} uses the wrong assignment version")

        configured_tags = _assignment_misconceptions(source)
        used_tags = {tag for case in dataset.cases for tag in case.misconception_tags}
        unknown_tags = used_tags - configured_tags
        if unknown_tags:
            raise ValueError(
                f"{path.name} uses unknown misconception tags: {sorted(unknown_tags)}"
            )
        missing_tags = configured_tags - used_tags
        if missing_tags:
            raise ValueError(
                f"{path.name} does not cover misconception tags: {sorted(missing_tags)}"
            )
        duplicate_global_ids = global_case_ids.intersection(
            case.case_id for case in dataset.cases
        )
        if duplicate_global_ids:
            raise ValueError(
                f"case IDs must be globally unique: {sorted(duplicate_global_ids)}"
            )
        global_case_ids.update(case.case_id for case in dataset.cases)
        datasets.append(dataset)

    missing_assignments = set(assignment_sources) - {
        dataset.assignment_id for dataset in datasets
    }
    if missing_assignments:
        raise ValueError(
            f"missing instructor datasets for assignments: {sorted(missing_assignments)}"
        )
    return datasets


def summarize_instructor_datasets(
    datasets: list[InstructorAssignmentDataset],
) -> DatasetInventory:
    cases = [case for dataset in datasets for case in dataset.cases]
    covered_tags = {
        tag for dataset in datasets for case in dataset.cases for tag in case.misconception_tags
    }
    return DatasetInventory(
        assignment_count=len(datasets),
        case_count=len(cases),
        draft_count=sum(case.review_status == ReviewStatus.DRAFT for case in cases),
        approved_count=sum(case.review_status == ReviewStatus.APPROVED for case in cases),
        covered_misconception_count=len(covered_tags),
    )


if __name__ == "__main__":
    inventory = summarize_instructor_datasets(load_instructor_datasets())
    print(
        "Validated instructor dataset: "
        f"{inventory.assignment_count} assignments, "
        f"{inventory.case_count} cases "
        f"({inventory.draft_count} draft, {inventory.approved_count} approved), "
        f"{inventory.covered_misconception_count} misconception tags covered."
    )
