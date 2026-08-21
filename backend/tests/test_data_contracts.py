import pytest
from pydantic import ValidationError

from data_contracts import (
    ExecutionStatus,
    classify_execution_status,
    normalize_assignment_structured_data,
    normalize_event_data,
)


def valid_assignment_data():
    return {
        "learning_objectives": ["Interpret structured grader evidence."],
        "execution_settings": {
            "runtime": "python3.11",
            "timeout_seconds": 5,
            "allowed_imports": ["math"],
        },
        "public_tests": [{"id": "execution", "label": "Program executes"}],
        "rubric": [
            {
                "criterion": "Correctness",
                "description": "Produces the required result.",
                "weight": 100,
            }
        ],
        "misconceptions": [
            {"tag": "wrong-formula", "description": "Uses the wrong formula."}
        ],
        "tutoring_rules": {"max_hint_level": 4},
        "simulation_config": {"enabled": False},
        "asset_manifest": [],
        "grader_config": {"expected_values": {"answer": 42}},
    }


@pytest.mark.parametrize(
    ("success", "error", "expected"),
    [
        (True, "", ExecutionStatus.COMPLETED),
        (False, "SyntaxError: invalid syntax", ExecutionStatus.SYNTAX_ERROR),
        (False, "TimeoutError: execution exceeded 5 seconds", ExecutionStatus.TIMEOUT),
        (False, "Import of socket is not allowed", ExecutionStatus.REJECTED),
        (
            False,
            "The secure grader is temporarily unavailable.",
            ExecutionStatus.GRADER_UNAVAILABLE,
        ),
        (False, "NameError: answer is not defined", ExecutionStatus.RUNTIME_ERROR),
    ],
)
def test_execution_errors_use_stable_statuses(success, error, expected):
    assert classify_execution_status(success, error) == expected


def test_assignment_json_contract_normalizes_valid_data():
    normalized = normalize_assignment_structured_data(valid_assignment_data())

    assert normalized["execution_settings"]["network_enabled"] is False
    assert normalized["tutoring_rules"]["ai_enabled_by_default"] is False
    assert normalized["public_tests"][0]["id"] == "execution"


def test_assignment_json_contract_rejects_duplicate_test_ids():
    data = valid_assignment_data()
    data["public_tests"].append(
        {"id": "execution", "label": "Duplicate program test"}
    )

    with pytest.raises(ValidationError, match="unique IDs"):
        normalize_assignment_structured_data(data)


def test_assignment_json_contract_rejects_malformed_rubric():
    data = valid_assignment_data()
    data["rubric"][0]["weight"] = 120

    with pytest.raises(ValidationError):
        normalize_assignment_structured_data(data)


def test_learning_event_contract_accepts_known_shape():
    assert normalize_event_data(
        "workspace_file_selected",
        {"path": "src/controller.py", "editable": True},
    ) == {"path": "src/controller.py", "editable": True}


def test_learning_event_contract_rejects_unknown_metadata():
    with pytest.raises(ValidationError):
        normalize_event_data(
            "assignment_opened",
            {"source": "assignment_catalog", "password": "must-not-be-stored"},
        )
