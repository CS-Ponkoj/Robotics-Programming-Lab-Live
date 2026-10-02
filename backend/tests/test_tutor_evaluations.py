import json
from types import SimpleNamespace

import pytest

from config import Settings
from instructor_dataset import load_instructor_datasets
from models import Assignment, Submission
from tutor import TutorService


DATASETS = load_instructor_datasets()
CASES = [
    (dataset, case)
    for dataset in DATASETS
    for case in dataset.cases
]


class CapturingResponses:
    def __init__(self, output):
        self.output = output
        self.requests = []

    def create(self, **kwargs):
        self.requests.append(kwargs)
        return SimpleNamespace(output_text=json.dumps(self.output))


def _safe_output(case):
    expected = case.expected_feedback
    if case.case_type == "solution_request":
        return {
            "diagnosis": (
                "This request asks for completed work rather than tutoring support."
            ),
            "misconception": "",
            "answer": "I can help you debug one public behavior step by step.",
            "debugging_steps": [
                "Choose the first public behavior that needs attention.",
                "Trace the inputs used by that behavior.",
            ],
            "guiding_question": expected.socratic_question,
            "hint": case.hint_ladder[0].hint,
            "next_action": "Identify the first public behavior that fails.",
        }
    return {
        "diagnosis": expected.diagnosis,
        "misconception": case.misconception_tags[0]
        if case.misconception_tags
        else "",
        "answer": "" if not case.student_question else "Let us inspect one step.",
        "debugging_steps": expected.debugging_steps[:2],
        "guiding_question": expected.socratic_question,
        "hint": case.hint_ladder[0].hint,
        "next_action": expected.debugging_steps[0],
    }


@pytest.mark.parametrize(
    ("dataset", "case"),
    CASES,
    ids=[case.case_id for _dataset, case in CASES],
)
def test_all_instructor_cases_use_strict_safe_tutor_pipeline(dataset, case):
    responses = CapturingResponses(_safe_output(case))
    assignment = Assignment(
        id=dataset.assignment_id,
        stable_id=dataset.assignment_stable_id,
        version=dataset.assignment_version,
        title=f"Assignment {dataset.assignment_id}",
        description="Student-visible assignment context.",
        learning_objectives=["Debug one observable behavior."],
        misconceptions=[
            {"tag": tag, "description": tag.replace("-", " ")}
            for tag in case.misconception_tags
        ],
        tutoring_rules={
            "never_reveal_solution": True,
            "never_reveal_hidden_tests": True,
        },
    )
    submission = Submission(
        code=case.student_code or "# No code change in this question.",
        evidence={
            "execution_succeeded": case.expected_execution_status
            not in {"syntax_error", "runtime_error"},
            "execution_error": "",
            "score": 0,
            "tests": [
                {
                    "label": case.title,
                    "passed": False,
                    "message": "A student-visible requirement needs attention.",
                    "expected_value": "server-only-sentinel",
                }
            ],
            "grader_config": {"hidden": "server-only-sentinel"},
        },
    )

    feedback = TutorService(
        Settings(), client=SimpleNamespace(responses=responses)
    ).feedback(
        assignment,
        submission,
        hint_level=1,
        student_question=case.student_question or "",
    )

    if case.case_type == "solution_request":
        assert feedback.source == "fallback"
        assert "cannot provide completed code" in feedback.answer
        assert not responses.requests
        return
    assert feedback.source == "openai"
    assert feedback.solution_revealed is False
    assert feedback.hint == case.hint_ladder[0].hint
    assert 1 <= len(feedback.debugging_steps) <= 2

    request = responses.requests[0]
    payload = json.loads(request["input"])
    serialized = json.dumps(payload)
    assert request["store"] is False
    assert request["text"]["format"]["strict"] is True
    assert "server-only-sentinel" not in serialized
    assert "grader_config" not in serialized
    assert "expected_value" not in serialized
    assert payload["student_question"] == (case.student_question or "")


def test_evaluation_inventory_covers_all_six_assignments_and_safety_requests():
    assert {dataset.assignment_id for dataset in DATASETS} == set(range(1, 7))
    assert len(CASES) >= 24
    assert all(len(dataset.cases) >= 4 for dataset in DATASETS)
    assert all(
        any(case.case_type == "solution_request" for case in dataset.cases)
        for dataset in DATASETS
    )
