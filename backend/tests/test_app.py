from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app import create_app
from config import Settings


CORRECT_ASSIGNMENT_2 = """
distance_to_obstacle = 4
perimeter_of_obstacle = 6
distance_from_obstacle_to_goal = 4
total_path_length = 14
"""

INCORRECT_ASSIGNMENT_2 = """
distance_to_obstacle = 0
perimeter_of_obstacle = 0
distance_from_obstacle_to_goal = 0
total_path_length = 0
"""

COURSE_MATERIALS = Path(__file__).resolve().parents[2] / "course_materials"
OFFICIAL_SOLUTIONS = {
    1: COURSE_MATERIALS
    / "content"
    / "Obstacle Avoidance"
    / "Assignment_Bug_Algorithm"
    / "Scenario_1"
    / "math_question_1_solution.py",
    2: COURSE_MATERIALS
    / "content"
    / "Obstacle Avoidance"
    / "Assignment_Bug_Algorithm"
    / "Scenario_2"
    / "Programing_Question_1_solution.py",
    3: COURSE_MATERIALS
    / "content"
    / "Obstacle Avoidance"
    / "Assignment_OA"
    / "question_1_solution.py",
    4: COURSE_MATERIALS
    / "content"
    / "Obstacle Avoidance"
    / "Assignment_VFH"
    / "question_1_VFH_solution.py",
}


@pytest.fixture()
def client(tmp_path):
    settings = Settings(
        database_url="sqlite://",
        admin_api_token="test-admin",
        openai_api_key=None,
        study_accounts_file=tmp_path / "study_accounts.json",
    )
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as value:
        login = value.post(
            "/auth/login",
            json={"login_id": "student", "password": "student"},
        )
        assert login.status_code == 200
        value.headers.update(
            {"Authorization": f"Bearer {login.json()['token']}"}
        )
        yield value


def test_health_reports_fastapi_platform(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "api_version": "4.1.0",
        "database": "sqlite",
        "sandbox": "subprocess",
    }
    assert response.headers["X-Content-Type-Options"] == "nosniff"
    assert response.headers["X-Frame-Options"] == "DENY"


def test_production_configuration_rejects_ephemeral_or_open_defaults(tmp_path):
    settings = Settings(
        environment="production",
        database_url=f"sqlite:///{(tmp_path / 'unsafe.db').as_posix()}",
        auto_create_schema=True,
        allowed_origins="*",
    )

    with pytest.raises(RuntimeError, match="Invalid production configuration"):
        create_app(settings=settings)


def test_production_configuration_requires_isolated_execution():
    settings = Settings(
        environment="production",
        database_url="postgresql+psycopg://user:pass@database.test/study",
        auto_create_schema=False,
        allowed_origins="https://study.example.test",
        sandbox_backend="subprocess",
    )

    with pytest.raises(RuntimeError, match="remote or docker isolation"):
        settings.validate_runtime()


def test_production_configuration_accepts_complete_remote_sandbox():
    settings = Settings(
        environment="production",
        database_url="postgresql+psycopg://user:pass@database.test/study",
        auto_create_schema=False,
        allowed_origins="https://study.example.test",
        sandbox_backend="remote",
        sandbox_url="sandbox.internal:10000",
        sandbox_api_token="sandbox-token-with-safe-length",
    )

    settings.validate_runtime()


def test_cors_allows_only_the_configured_frontend(tmp_path):
    settings = Settings(
        database_url="sqlite://",
        allowed_origins="https://approved.example.test",
        study_accounts_file=tmp_path / "study_accounts.json",
    )
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as value:
        allowed = value.options(
            "/auth/login",
            headers={
                "Origin": "https://approved.example.test",
                "Access-Control-Request-Method": "POST",
            },
        )
        rejected = value.options(
            "/auth/login",
            headers={
                "Origin": "https://untrusted.example.test",
                "Access-Control-Request-Method": "POST",
            },
        )

    assert allowed.status_code == 200
    assert (
        allowed.headers["Access-Control-Allow-Origin"]
        == "https://approved.example.test"
    )
    assert "Access-Control-Allow-Origin" not in rejected.headers


def test_assignment_routes_require_authentication(client):
    authorization = client.headers.pop("Authorization")
    try:
        requests = [
            client.get("/assignments"),
            client.get("/assignments/2"),
            client.post("/assignments/2/run", json={"code": "print('hello')"}),
            client.post("/assignments/2/submit", json={"code": "answer = 1"}),
            client.post(
                "/assignments/2/hint",
                json={"submission_id": "missing", "hint_level": 1},
            ),
            client.post(
                "/assignments/2/solution",
                json={"submission_id": "missing"},
            ),
        ]
    finally:
        client.headers["Authorization"] = authorization

    assert all(response.status_code == 401 for response in requests)


def test_execution_rate_limit_returns_retry_guidance(tmp_path):
    settings = Settings(
        database_url="sqlite://",
        openai_api_key=None,
        study_accounts_file=tmp_path / "study_accounts.json",
        execution_requests_per_minute=2,
    )
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as value:
        login = value.post(
            "/auth/login",
            json={"login_id": "student", "password": "student"},
        )
        headers = {"Authorization": f"Bearer {login.json()['token']}"}
        first = value.post(
            "/assignments/2/run",
            headers=headers,
            json={"code": "print('first')"},
        )
        second = value.post(
            "/assignments/2/run",
            headers=headers,
            json={"code": "print('second')"},
        )
        blocked = value.post(
            "/assignments/2/run",
            headers=headers,
            json={"code": "print('third')"},
        )

    assert first.status_code == 200
    assert second.status_code == 200
    assert blocked.status_code == 429
    assert blocked.headers["Retry-After"]
    assert blocked.json()["error"] == "Too many requests. Please wait and try again."


def test_execution_rate_limit_cannot_be_bypassed_with_forwarded_ip(tmp_path):
    settings = Settings(
        database_url="sqlite://",
        openai_api_key=None,
        study_accounts_file=tmp_path / "study_accounts.json",
        execution_requests_per_minute=1,
    )
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as value:
        login = value.post(
            "/auth/login",
            json={"login_id": "student", "password": "student"},
        )
        authorization = f"Bearer {login.json()['token']}"
        first = value.post(
            "/assignments/2/run",
            headers={
                "Authorization": authorization,
                "X-Forwarded-For": "198.51.100.1",
            },
            json={"code": "print('first')"},
        )
        blocked = value.post(
            "/assignments/2/run",
            headers={
                "Authorization": authorization,
                "X-Forwarded-For": "203.0.113.2",
            },
            json={"code": "print('second')"},
        )

    assert first.status_code == 200
    assert blocked.status_code == 429


def test_execution_concurrency_limit_fails_fast(client):
    assert client.app.state.execution_slots.acquire(blocking=False)
    assert client.app.state.execution_slots.acquire(blocking=False)
    try:
        blocked = client.post(
            "/assignments/2/run",
            json={"code": "print('busy')"},
        )
    finally:
        client.app.state.execution_slots.release()
        client.app.state.execution_slots.release()

    assert blocked.status_code == 503
    assert blocked.headers["Retry-After"] == "2"


def test_request_body_limit_rejects_oversized_payload_before_parsing(client):
    response = client.post(
        "/auth/login",
        headers={"content-length": "100001"},
        json={"login_id": "student", "password": "student"},
    )

    assert response.status_code == 413
    assert response.json()["error"] == "Request body is too large."


def test_lists_all_assignments_in_numeric_order_without_private_fields(client):
    response = client.get("/assignments")
    assert response.status_code == 200
    assignments = response.json()["assignments"]
    assert [assignment["id"] for assignment in assignments] == [1, 2, 3, 4, 5]
    assert [assignment["version"] for assignment in assignments] == [3, 2, 3, 2, 1]
    assert all(assignment["stable_id"] for assignment in assignments)
    assert all(assignment["solution_html"] == "" for assignment in assignments)
    assert all(assignment["vals"] == {} for assignment in assignments)
    assert all(assignment["has_solution"] for assignment in assignments)
    assert all(
        "<strong>solution" not in assignment["assignment_html"].lower()
        for assignment in assignments
    )


@pytest.mark.parametrize("assignment_id", [1, 2, 3, 4, 5])
def test_gets_each_assignment_without_hidden_grader_data(client, assignment_id):
    response = client.get(f"/assignments/{assignment_id}")
    assert response.status_code == 200
    assignment = response.json()
    assert assignment["id"] == assignment_id
    assert assignment["learning_objectives"]
    assert assignment["rubric"]
    assert "grader_config" not in assignment
    assert "common_misconceptions" not in assignment


def test_ros_assignment_exposes_one_editable_file_without_private_grader_data(client):
    response = client.get("/assignments/5")

    assert response.status_code == 200
    assignment = response.json()
    assert assignment["stable_id"] == "ros2-drive-forward"
    assert assignment["language"] == "python-ros2"
    assert assignment["editable_file_path"].endswith("controller.py")
    assert sum(item["editable"] for item in assignment["project_files"]) == 1
    assert any(item["path"].endswith("package.xml") for item in assignment["project_files"])
    assert "grader_config" not in assignment
    assert "reference_solution_path" not in assignment


def test_serves_assignment_image(client):
    response = client.get("/images/1")
    assert response.status_code == 200
    assert response.headers["content-type"] == "image/png"
    assert response.content.startswith(b"\x89PNG")


def test_missing_assignment_and_image_return_json_404(client):
    assignment_response = client.get("/assignments/999")
    image_response = client.get("/images/999")
    assert assignment_response.status_code == 404
    assert assignment_response.json()["error"] == "Assignment not found."
    assert image_response.status_code == 404
    assert image_response.json()["error"] == "Image not found."


def test_submit_rejects_unknown_oversized_and_missing_code(client):
    unknown = client.post("/assignments/999/submit", json={"code": "answer = 1"})
    oversized = client.post("/assignments/2/submit", json={"code": "x" * 50_001})
    missing = client.post("/assignments/2/submit", json={"code": ""})
    assert unknown.status_code == 404
    assert oversized.status_code == 413
    assert missing.status_code == 400


def test_public_run_executes_without_revealing_hidden_grading(client):
    response = client.post(
        "/assignments/2/run",
        json={"code": "print('hello')"},
    )
    body = response.json()
    assert response.status_code == 200
    assert body["pass"] is True
    assert body["tested_vals"] == []
    assert body["score"] == 100
    assert body["evidence"][0]["visibility"] == "public"


def test_correct_submission_passes_and_records_assignment_version(client):
    response = client.post(
        "/assignments/2/submit", json={"code": CORRECT_ASSIGNMENT_2}
    )
    body = response.json()
    assert response.status_code == 200
    assert body["pass"] is True
    assert body["ex_success"] is True
    assert body["assignment_version"] == 2
    assert body["submission_id"]
    assert body["unittest_pass_results"] == [True, True, True, True]
    assert body["hint"] == ""


@pytest.mark.parametrize("assignment_id", [1, 2, 3, 4])
def test_official_solution_passes_every_modular_grader(client, assignment_id):
    code = OFFICIAL_SOLUTIONS[assignment_id].read_text(encoding="utf-8")
    response = client.post(
        f"/assignments/{assignment_id}/submit", json={"code": code}
    )
    body = response.json()
    assert response.status_code == 200
    assert body["pass"] is True
    assert all(body["unittest_pass_results"])


def test_incorrect_submission_returns_structured_progressive_feedback(client):
    response = client.post(
        "/assignments/2/submit",
        json={"code": INCORRECT_ASSIGNMENT_2, "use_ai_tutor": True},
    )
    body = response.json()
    assert body["pass"] is False
    assert body["ex_success"] is True
    assert body["score"] == 0
    assert body["hint"]
    assert body["tutor_feedback"]["hint_level"] == 1
    assert body["tutor_feedback"]["solution_revealed"] is False
    assert all(
        "expected" not in item["message"].lower() for item in body["evidence"]
    )

    next_hint = client.post(
        "/assignments/2/hint",
        json={"submission_id": body["submission_id"], "hint_level": 2},
    )
    assert next_hint.status_code == 200
    assert next_hint.json()["hint_level"] == 2


@pytest.mark.parametrize("hint_level", [0, 5])
def test_progressive_hint_rejects_levels_outside_policy(client, hint_level):
    response = client.post(
        "/assignments/2/hint",
        json={"submission_id": "unused", "hint_level": hint_level},
    )
    assert response.status_code == 400


def test_progressive_hint_cannot_use_a_submission_from_another_assignment(client):
    submission = client.post(
        "/assignments/2/submit", json={"code": INCORRECT_ASSIGNMENT_2}
    ).json()
    response = client.post(
        "/assignments/1/hint",
        json={"submission_id": submission["submission_id"], "hint_level": 2},
    )
    assert response.status_code == 404


def test_ai_tutoring_is_opt_in_for_fast_default_grading(client):
    response = client.post(
        "/assignments/2/submit",
        json={"code": INCORRECT_ASSIGNMENT_2},
    )
    body = response.json()

    assert response.status_code == 200
    assert body["score"] == 0
    assert body["hint"] == ""
    assert body["tutor_feedback"] is None


def test_solution_requires_a_submission_for_current_assignment_version(client):
    blocked = client.post(
        "/assignments/2/solution", json={"submission_id": "not-a-submission"}
    )
    assert blocked.status_code == 403

    submission = client.post(
        "/assignments/2/submit", json={"code": INCORRECT_ASSIGNMENT_2}
    ).json()
    revealed = client.post(
        "/assignments/2/solution",
        json={"submission_id": submission["submission_id"]},
    )
    assert revealed.status_code == 200
    assert "14 units" in revealed.json()["solution_html"]


def test_solution_reveal_rejects_a_submission_from_an_old_assignment_version(
    client,
):
    submission = client.post(
        "/assignments/2/submit", json={"code": INCORRECT_ASSIGNMENT_2}
    ).json()
    headers = {"X-Admin-Token": "test-admin"}
    assignment = client.get("/admin/assignments", headers=headers).json()[
        "assignments"
    ][1]
    assignment["description"] = "A revised assignment description."

    updated = client.put(
        "/admin/assignments/2",
        headers=headers,
        json=assignment,
    )
    assert updated.status_code == 200
    assert updated.json()["version"] == 3
    validation = client.post(
        "/admin/assignments/2/validate",
        headers=headers,
    )
    assert validation.status_code == 200
    assert validation.json()["valid"] is True
    published = client.post(
        "/admin/assignments/2/publish",
        headers=headers,
    )
    assert published.status_code == 200

    revealed = client.post(
        "/assignments/2/solution",
        json={"submission_id": submission["submission_id"]},
    )
    assert revealed.status_code == 403


def test_legacy_grade_route_preserves_flutter_contract(client):
    response = client.post("/grade/2", json={"code": CORRECT_ASSIGNMENT_2})
    assert response.status_code == 200
    assert response.json()["pass"] is True


def test_admin_requires_token_and_validates_before_publish(client):
    authorization = client.headers.pop("Authorization")
    try:
        unauthorized = client.get("/admin/assignments")
    finally:
        client.headers["Authorization"] = authorization
    assert unauthorized.status_code == 401

    headers = {"X-Admin-Token": "test-admin"}
    assignments = client.get("/admin/assignments", headers=headers).json()[
        "assignments"
    ]
    assert assignments[0]["grader_config"]["expected_values"]
    validation = client.post(
        "/admin/assignments/1/validate", headers=headers
    )
    assert validation.status_code == 200
    assert validation.json() == {"valid": True, "errors": []}


def test_admin_content_update_increments_version_and_preserves_stable_id(client):
    headers = {"X-Admin-Token": "test-admin"}
    original = client.get("/admin/assignments", headers=headers).json()[
        "assignments"
    ][0]
    original["description"] = "Updated instructor-authored description"

    response = client.put(
        "/admin/assignments/1",
        headers=headers,
        json=original,
    )
    assert response.status_code == 200
    updated = response.json()
    assert updated["stable_id"] == original["stable_id"]
    assert updated["version"] == 4
    assert updated["status"] == "draft"

    assert client.get("/assignments/1").status_code == 404
    publish = client.post("/admin/assignments/1/publish", headers=headers)
    assert publish.status_code == 200
    student_copy = client.get("/assignments/1").json()
    assert student_copy["version"] == 4
    assert "grader_config" not in student_copy


def test_admin_update_cannot_bypass_publish_validation_or_force_version(client):
    headers = {"X-Admin-Token": "test-admin"}
    original = client.get("/admin/assignments", headers=headers).json()[
        "assignments"
    ][0]
    original["description"] = "A draft change"
    draft = client.put(
        "/admin/assignments/1",
        headers=headers,
        json=original,
    ).json()
    assert draft["status"] == "draft"
    assert draft["version"] == 4

    draft["status"] = "published"
    draft["version"] = 999
    attempted_bypass = client.put(
        "/admin/assignments/1",
        headers=headers,
        json=draft,
    )
    assert attempted_bypass.status_code == 200
    assert attempted_bypass.json()["status"] == "draft"
    assert attempted_bypass.json()["version"] == 4


def test_admin_rejects_duplicate_stable_assignment_id(client):
    headers = {"X-Admin-Token": "test-admin"}
    existing = client.get("/admin/assignments", headers=headers).json()[
        "assignments"
    ][0]
    existing["id"] = None

    response = client.post(
        "/admin/assignments",
        headers=headers,
        json=existing,
    )

    assert response.status_code == 409
    assert response.json()["error"] == "Assignment ID or stable ID already exists."
