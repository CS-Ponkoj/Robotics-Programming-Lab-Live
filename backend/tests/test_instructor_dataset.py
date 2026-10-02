import json
from pathlib import Path

import pytest
from pydantic import ValidationError

from instructor_dataset import (
    DatasetPolicy,
    InstructorEvaluationCase,
    load_instructor_datasets,
    review_queue,
    summarize_instructor_datasets,
)


def _case() -> dict:
    return {
        "case_id": "a1-example-case",
        "title": "Example misconception",
        "case_type": "conceptual_error",
        "review_status": "draft",
        "student_code": "total_distance = 0",
        "expected_execution_status": "completed",
        "misconception_tags": ["incorrect-total-distance"],
        "expected_feedback": {
            "diagnosis": "The total does not include all path components.",
            "debugging_steps": ["List the path components before adding them."],
            "socratic_question": "Which path segment is absent?",
            "must_mention": ["path components"],
            "must_avoid": ["complete solution code"],
        },
        "hint_ladder": [
            {"level": 1, "hint": "Count the distinct path segments."},
            {"level": 2, "hint": "Check each segment separately."},
            {"level": 3, "hint": "Add only after validating each segment."},
        ],
        "instructor_notes": "Draft; instructor review is required.",
    }


def test_case_requires_sequential_hint_levels():
    source = _case()
    source["hint_ladder"][1]["level"] = 3
    with pytest.raises(ValidationError, match="hint levels must be sequential"):
        InstructorEvaluationCase.model_validate(source)


def test_approved_case_requires_named_reviewer():
    source = _case()
    source["review_status"] = "approved"
    with pytest.raises(ValidationError, match="approved cases require"):
        InstructorEvaluationCase.model_validate(source)


def test_stage_one_policy_cannot_enable_runtime_use():
    with pytest.raises(ValidationError, match="cannot be used at runtime"):
        DatasetPolicy(runtime_use_enabled=True)


def test_inventory_rejects_solution_or_hidden_test_fields(tmp_path: Path):
    assignment_dir = tmp_path / "assignments"
    dataset_dir = tmp_path / "datasets"
    assignment_dir.mkdir()
    dataset_dir.mkdir()
    (assignment_dir / "assignment_1.json").write_text(
        json.dumps(
            {
                "id": 1,
                "version": 1,
                "vals": {"total_distance": 1.0},
            }
        ),
        encoding="utf-8",
    )
    payload = {
        "dataset_schema_version": 1,
        "assignment_id": 1,
        "assignment_stable_id": "robotics-assignment-1",
        "assignment_version": 1,
        "review_status": "draft",
        "cases": [_case()],
        "official_solution": "must never be stored here",
    }
    (dataset_dir / "assignment_1.json").write_text(
        json.dumps(payload), encoding="utf-8"
    )
    with pytest.raises(ValueError, match="forbidden keys"):
        load_instructor_datasets(dataset_dir, assignment_dir)


def test_inventory_requires_every_safety_case_type(tmp_path: Path):
    assignment_dir = tmp_path / "assignments"
    dataset_dir = tmp_path / "datasets"
    assignment_dir.mkdir()
    dataset_dir.mkdir()
    (assignment_dir / "assignment_1.json").write_text(
        json.dumps({"id": 1, "version": 1, "vals": {"total_distance": 1.0}}),
        encoding="utf-8",
    )
    payload = {
        "assignment_id": 1,
        "assignment_stable_id": "robotics-assignment-1",
        "assignment_version": 1,
        "cases": [_case()],
    }
    (dataset_dir / "assignment_1.json").write_text(
        json.dumps(payload), encoding="utf-8"
    )
    with pytest.raises(ValueError, match="do not cover case types") as error:
        load_instructor_datasets(dataset_dir, assignment_dir)
    for case_type in ("hallucination", "prompt_injection", "provider_failure"):
        assert case_type in str(error.value)


def test_review_queue_lists_every_draft_case():
    datasets = load_instructor_datasets()
    queue = review_queue(datasets)
    assert len(queue) == summarize_instructor_datasets(datasets).draft_count
    assert any("a3-provider-timeout-fallback" in line for line in queue)


def test_repository_instructor_dataset_is_complete_and_draft():
    datasets = load_instructor_datasets()
    inventory = summarize_instructor_datasets(datasets)
    assert inventory.assignment_count == 6
    assert inventory.case_count >= 27
    assert inventory.case_count == inventory.draft_count
    assert inventory.approved_count == 0
