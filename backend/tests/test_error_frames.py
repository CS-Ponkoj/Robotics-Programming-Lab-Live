import pytest
from fastapi.testclient import TestClient

from app import create_app
from config import Settings
from graders.base import safe_error_frames
from graders.python_function import PythonFunctionGrader
from models import Assignment
from sandbox import SubprocessSandbox


NESTED_ERROR = (
    "print('before the error')\n"
    "def helper(value):\n"
    "    return value / 0\n"
    "def calculate_values(first, second):\n"
    "    return helper(first), second\n"
    "calculate_values(1, 2)\n"
)


def test_worker_returns_the_student_call_stack_outermost_first():
    result = SubprocessSandbox().execute(NESTED_ERROR, [])

    assert result["success"] is False
    assert result["error"].startswith("ZeroDivisionError at line 3 of submission")
    assert result["frames"] == [
        {"line": 6, "name": "<module>"},
        {"line": 5, "name": "calculate_values"},
        {"line": 3, "name": "helper"},
    ]
    assert result["output"] == "before the error\n"


@pytest.mark.parametrize(
    "code",
    [
        "def broken(:\n    pass\n",
        "import os\n",
    ],
)
def test_syntax_errors_and_rejections_carry_no_frames(code):
    result = SubprocessSandbox().execute(code, [])
    assert result["success"] is False
    assert result["frames"] == []


def test_deep_recursion_keeps_only_the_last_twenty_frames():
    result = SubprocessSandbox().execute(
        "def down(n):\n    return down(n + 1)\ndown(0)\n", []
    )
    assert result["success"] is False
    assert len(result["frames"]) == 20
    assert all(frame["name"] == "down" for frame in result["frames"])


@pytest.mark.parametrize(
    "raw, expected",
    [
        (None, []),
        ("frames", []),
        (
            [{"line": 3, "name": "helper"}, {"line": 1, "name": "<module>"}],
            [{"line": 3, "name": "helper"}, {"line": 1, "name": "<module>"}],
        ),
        (
            [
                {"line": 0, "name": "zero"},
                {"line": True, "name": "bool"},
                {"line": "3", "name": "text"},
                {"line": 2, "name": "x; import os"},
                {"line": 2, "name": "<lambda>"},
                ["not", "a", "dict"],
                {"line": 4, "name": "kept"},
            ],
            [{"line": 4, "name": "kept"}],
        ),
        ([{"line": index + 1, "name": "f"} for index in range(30)], [
            {"line": index + 1, "name": "f"} for index in range(10, 30)
        ]),
    ],
)
def test_frames_are_sanitized_before_leaving_the_grader(raw, expected):
    assert safe_error_frames(raw) == expected


def function_assignment() -> Assignment:
    return Assignment(
        id=99,
        stable_id="frames-test",
        version=1,
        title="Frames test",
        grader_type="python_function",
        grader_config={
            "function_name": "calculate_values",
            "criteria": [
                {"id": "a", "label": "A", "weight": 50},
                {"id": "b", "label": "B", "weight": 50},
            ],
            "cases": [{"arguments": [0, 3], "expected": [0, 3]}],
        },
    )


def test_a_failing_student_run_reports_frames():
    result = PythonFunctionGrader(SubprocessSandbox()).grade(
        function_assignment(), NESTED_ERROR
    )
    assert result.execution_succeeded is False
    assert [frame["name"] for frame in result.error_frames] == [
        "<module>",
        "calculate_values",
        "helper",
    ]


def test_hidden_scenario_failures_never_report_frames():
    """The student's module runs fine; only a hidden input makes it fail."""
    result = PythonFunctionGrader(SubprocessSandbox()).grade(
        function_assignment(),
        "def calculate_values(first, second):\n"
        "    return 1 / first, second\n",
    )
    assert result.execution_succeeded is False
    assert result.error_frames == []


@pytest.fixture()
def client(tmp_path):
    settings = Settings(
        database_url="sqlite://",
        admin_api_token="test-admin",
        openai_api_key=None,
        study_accounts_file=tmp_path / "study_accounts.json",
    )
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as value:
        yield value


def test_submit_response_includes_frames_for_the_terminal(client):
    token = client.post("/auth/demo").json()["token"]
    headers = {"Authorization": f"Bearer {token}"}
    response = client.post(
        "/assignments/2/submit",
        json={
            "code": (
                "def calculate_bug_route(start, hit, corner_a, corner_b, leave, goal):\n"
                "    return missing_name\n"
                "calculate_bug_route(1, 2, 3, 4, 5, 6)\n"
            )
        },
        headers=headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["ex_success"] is False
    assert body["error_frames"] == [
        {"line": 3, "name": "<module>"},
        {"line": 2, "name": "calculate_bug_route"},
    ]

    ok = client.post(
        "/assignments/2/submit",
        json={"code": "def calculate_bug_route(*points):\n    return 0, 0, 0, 0\n"},
        headers=headers,
    )
    assert ok.json()["error_frames"] == []
