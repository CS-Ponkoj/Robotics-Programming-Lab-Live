import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select

from app import create_app
from config import Settings
from graders.python_function import (
    PlaygroundInputError,
    PythonFunctionGrader,
    parse_playground_arguments,
)
from models import (
    Assignment,
    AssignmentActivity,
    AuditEvent,
    HintInteraction,
    LearningEvent,
    StudySession,
    Submission,
)
from sandbox import SubprocessSandbox


ASSIGNMENT_2_ANSWER = """
import math

def calculate_bug_route(start, hit, corner_a, corner_b, leave, goal):
    distance = lambda a, b: math.hypot(b[0] - a[0], b[1] - a[1])
    approach = distance(start, hit)
    boundary = (
        distance(hit, corner_a)
        + distance(corner_a, corner_b)
        + distance(corner_b, leave)
    )
    departure = distance(leave, goal)
    return approach, boundary, departure, approach + boundary + departure
"""

ASSIGNMENT_2_INPUTS = "(0, 0), (4, 0), (4, -1), (6, -1), (6, 0), (10, 0)"


def function_assignment() -> Assignment:
    return Assignment(
        id=99,
        stable_id="playground-test",
        version=3,
        title="Playground test",
        grader_type="python_function",
        grader_config={
            "function_name": "calculate_values",
            "criteria": [
                {"id": "sum", "label": "Sum", "weight": 50},
                {"id": "product", "label": "Product", "weight": 50},
            ],
            # Protected cases must never influence a playground call.
            "cases": [{"arguments": [2, 3], "expected": [5, 6]}],
        },
    )


def test_playground_arguments_accept_only_literal_values():
    assert parse_playground_arguments("") == []
    assert parse_playground_arguments("(2, 1), 4.5, [1, 2], {'a': 1}, None,") == [
        (2, 1),
        4.5,
        [1, 2],
        {"a": 1},
        None,
    ]


def test_playground_arguments_accept_simple_fractions_from_the_instructions():
    assert parse_playground_arguments("(11/3, 23/4), -1/2, {0: 3/4}") == [
        (11 / 3, 23 / 4),
        -0.5,
        {0: 0.75},
    ]


@pytest.mark.parametrize(
    "text",
    [
        "__import__('os').system('echo unsafe')",
        "open('secret.txt')",
        "1 + 1",
        "1/0",
        "(1/2)/3",
        "2 * 3",
        "x/2",
        "'a'/2",
        "1" + "0" * 400 + "/3",
        "x",
        "*[1, 2]",
        "first=1",
        "1e999",
        "(1, 2",
        "), print('escape'), (",
        ", ".join(["1"] * 21),
    ],
)
def test_playground_arguments_reject_code_and_unbounded_values(text):
    with pytest.raises(PlaygroundInputError):
        parse_playground_arguments(text)


def test_playground_labels_each_returned_value_without_grading():
    outcome = PythonFunctionGrader(SubprocessSandbox()).try_arguments(
        function_assignment(),
        "def calculate_values(first, second):\n"
        "    print('called', first, second)\n"
        "    return first + second, first * second",
        [4, 5],
    )

    assert outcome.success is True
    assert outcome.call == "calculate_values(4, 5)"
    assert outcome.returned == "(9, 20)"
    assert outcome.return_count == 2
    assert outcome.expected_return_count == 2
    assert outcome.values == [
        {"label": "Sum", "value": 9, "display": "9"},
        {"label": "Product", "value": 20, "display": "20"},
    ]
    assert outcome.output.strip() == "called 4 5"


def test_playground_reports_wrong_return_shape_and_runtime_errors():
    grader = PythonFunctionGrader(SubprocessSandbox())
    extra = grader.try_arguments(
        function_assignment(),
        "def calculate_values(first, second):\n    return 1, 2, 3",
        [1, 1],
    )
    assert extra.success is True
    assert extra.return_count == 3
    assert [item["label"] for item in extra.values] == ["Sum", "Product", "Extra value 3"]

    scalar = grader.try_arguments(
        function_assignment(),
        "def calculate_values(first, second):\n    return first / second",
        [3, 2],
    )
    assert scalar.success is True
    assert scalar.returned == "1.5"
    assert scalar.return_count is None
    assert scalar.values == []

    failed = grader.try_arguments(
        function_assignment(),
        "def calculate_values(first, second):\n    return first / second",
        [1, 0],
    )
    assert failed.success is False
    assert "ZeroDivisionError" in failed.error


@pytest.fixture()
def app_client(tmp_path):
    settings = Settings(
        database_url="sqlite://",
        admin_api_token="test-admin",
        openai_api_key=None,
        study_accounts_file=tmp_path / "study_accounts.json",
    )
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as client:
        yield client


def bearer(client, path="/auth/login", **body):
    response = client.post(path, json=body) if body else client.post(path)
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['token']}"}


def practice_row_counts(client):
    models = (
        Submission,
        HintInteraction,
        StudySession,
        AuditEvent,
        LearningEvent,
        AssignmentActivity,
    )
    with client.app.state.SessionLocal() as session:
        return {
            model.__tablename__: session.scalar(select(func.count()).select_from(model))
            for model in models
        }


@pytest.mark.parametrize("demo", [False, True])
def test_playground_route_runs_student_code_without_saving_rows(app_client, demo):
    headers = (
        bearer(app_client, "/auth/demo")
        if demo
        else bearer(app_client, login_id="student", password="student")
    )
    before = practice_row_counts(app_client)

    response = app_client.post(
        "/assignments/2/playground",
        json={"code": ASSIGNMENT_2_ANSWER, "arguments": ASSIGNMENT_2_INPUTS},
        headers=headers,
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["graded"] is False
    assert payload["success"] is True
    assert payload["execution_status"] == "completed"
    assert payload["call"].startswith("calculate_bug_route((0, 0), (4, 0)")
    assert payload["return_count"] == payload["expected_return_count"] == 4
    assert [item["value"] for item in payload["values"]] == [4.0, 4.0, 4.0, 12.0]
    assert [item["display"] for item in payload["values"]] == ["4.0", "4.0", "4.0", "12.0"]
    assert "score" not in payload and "passed" not in payload
    assert practice_row_counts(app_client) == before


def test_playground_route_never_exposes_protected_assignment_data(app_client):
    headers = bearer(app_client, login_id="student", password="student")
    source = json.loads(
        (Path(__file__).parents[1] / "assignments/assignment_2.json").read_text(
            encoding="utf-8"
        )
    )
    response = app_client.post(
        "/assignments/2/playground",
        json={
            "code": "def calculate_bug_route(*points):\n    return 0, 0, 0, 0",
            "arguments": ASSIGNMENT_2_INPUTS,
        },
        headers=headers,
    )

    assert response.status_code == 200
    text = response.text
    for case in source["grader_config"]["cases"]:
        assert json.dumps(case["expected"]) not in text
    assert "expected" not in response.json() or response.json().get("expected") is None


def test_playground_route_validates_input_role_and_assignment_type(app_client):
    assert (
        app_client.post(
            "/assignments/2/playground", json={"code": "x = 1", "arguments": ""}
        ).status_code
        == 401
    )
    headers = bearer(app_client, login_id="student", password="student")

    unsafe = app_client.post(
        "/assignments/2/playground",
        json={"code": ASSIGNMENT_2_ANSWER, "arguments": "__import__('os')"},
        headers=headers,
    )
    # Input errors use the standard 400 shape with a details list.
    assert unsafe.status_code == 400
    assert unsafe.json()["details"][0]["type"] == "parse"
    assert "Inputs can contain only" in unsafe.json()["error"]

    ros = app_client.post(
        "/assignments/5/playground",
        json={"code": "x = 1", "arguments": ""},
        headers=headers,
    )
    assert ros.status_code == 422

    blank = app_client.post(
        "/assignments/2/playground",
        json={"code": "   ", "arguments": ""},
        headers=headers,
    )
    assert blank.status_code == 400

    oversized = app_client.post(
        "/assignments/2/playground",
        json={"code": "x = 1\n" * 40_000, "arguments": ""},
        headers=headers,
    )
    assert oversized.status_code == 413

    too_long = app_client.post(
        "/assignments/2/playground",
        json={"code": ASSIGNMENT_2_ANSWER, "arguments": "1," * 1_500},
        headers=headers,
    )
    # Request-schema limits use the API's standard 400 validation response.
    assert too_long.status_code == 400


def test_student_assignment_names_playground_function_only_for_function_graders(
    app_client,
):
    headers = bearer(app_client, login_id="student", password="student")
    function_assignment_payload = app_client.get("/assignments/2", headers=headers).json()
    ros_payload = app_client.get("/assignments/5", headers=headers).json()

    assert function_assignment_payload["playground_function"] == "calculate_bug_route"
    assert ros_payload["playground_function"] is None
