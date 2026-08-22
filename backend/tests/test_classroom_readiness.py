import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select

from app import create_app
from config import Settings
from models import Assignment, Submission


MANUAL_ANSWERS = Path(__file__).resolve().parents[2] / "manual_sqa_answers"
OFFICIAL_SOLUTIONS = {
    1: MANUAL_ANSWERS / "assignment_1_answer.py",
    2: MANUAL_ANSWERS / "assignment_2_answer.py",
    3: MANUAL_ANSWERS / "assignment_3_answer.py",
    4: MANUAL_ANSWERS / "assignment_4_answer.py",
}


def _settings(database_url: str, account_file: Path) -> Settings:
    return Settings(
        database_url=database_url,
        admin_api_token="classroom-sqa-admin",
        openai_api_key=None,
        study_accounts_file=account_file,
    )


def _login(client: TestClient, login_id: str, password: str) -> dict:
    response = client.post(
        "/auth/login",
        json={"login_id": login_id, "password": password},
    )
    assert response.status_code == 200
    return response.json()


def _bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@pytest.mark.parametrize("assignment_id", [1, 2, 3, 4])
def test_classroom_official_solution_passes(assignment_id, tmp_path):
    settings = _settings("sqlite://", tmp_path / "accounts.json")
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as client:
        student = _login(client, "student", "student")
        code = OFFICIAL_SOLUTIONS[assignment_id].read_text(encoding="utf-8")
        response = client.post(
            f"/assignments/{assignment_id}/submit",
            headers=_bearer(student["token"]),
            json={"code": code},
        )

    assert response.status_code == 200
    assert response.json()["pass"] is True
    assert all(response.json()["unittest_pass_results"])


def test_assignment_4_exposes_the_complete_deterministic_lidar_model(tmp_path):
    settings = _settings("sqlite://", tmp_path / "assignment-4-accounts.json")
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as client:
        student = _login(client, "student", "student")
        response = client.get(
            "/assignments/4", headers=_bearer(student["token"])
        )

    assert response.status_code == 200
    assignment = response.json()
    instructions = assignment["assignment_html"]
    assert "10 + 2 * np.sin(np.radians(angle))" in instructions
    assert "3 through 357" in instructions
    assert "80 through 100" in instructions
    assert "np.sin(np.radians(angle))" in assignment["starter_code"]


def test_assignment_2_uses_explicit_hit_and_leave_geometry(tmp_path):
    settings = _settings("sqlite://", tmp_path / "assignment-2-accounts.json")
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as client:
        student = _login(client, "student", "student")
        headers = _bearer(student["token"])
        assignment = client.get("/assignments/2", headers=headers).json()
        old_three_edge_model = client.post(
            "/assignments/2/submit",
            headers=headers,
            json={
                "code": (
                    "distance_to_obstacle = 4\n"
                    "distance_along_obstacle = 6\n"
                    "distance_from_obstacle_to_goal = 4\n"
                    "total_path_length = 14\n"
                )
            },
        )

    instructions = assignment["assignment_html"]
    assert "H(4,0)" in instructions
    assert "L(6,0)" in instructions
    assert "H -&gt; A -&gt; B -&gt; L" in instructions
    assert "Do not use the full rectangle perimeter" in instructions
    assert old_three_edge_model.status_code == 200
    assert old_three_edge_model.json()["pass"] is False


def test_assignment_3_includes_the_complete_floor_to_floor_route(tmp_path):
    settings = _settings("sqlite://", tmp_path / "assignment-3-accounts.json")
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as client:
        student = _login(client, "student", "student")
        response = client.get(
            "/assignments/3", headers=_bearer(student["token"])
        )

    assert response.status_code == 200
    assignment = response.json()
    instructions = assignment["assignment_html"]
    assert "S -&gt; M1 -&gt; M2 -&gt; E_m" in instructions
    assert "After exiting on floor 10" in instructions
    assert "path_from_E_m_to_goal" in assignment["starter_code"]
    assert "path_from_E_s_to_goal" in assignment["starter_code"]
    assert "total_time_via_E_m" in assignment["starter_code"]
    assert "total_time_via_E_s" in assignment["starter_code"]


def test_assignment_1_uses_valid_bug2_m_line_intersections(tmp_path):
    settings = _settings("sqlite://", tmp_path / "assignment-1-accounts.json")
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as client:
        student = _login(client, "student", "student")
        response = client.get(
            "/assignments/1", headers=_bearer(student["token"])
        )

    assert response.status_code == 200
    assignment = response.json()
    instructions = assignment["assignment_html"]
    assert "Bug2 <em>m-line</em>" in instructions
    assert "H(4, 11/3)" in instructions
    assert "L(23/4, 6)" in instructions
    assert "H and L both lie on the m-line" in instructions
    assert "hit_point = (4.0, 11.0 / 3.0)" in assignment["starter_code"]
    assert "leave_point = (23.0 / 4.0, 6.0)" in assignment["starter_code"]


@pytest.mark.parametrize(
    ("label", "code", "expected_error"),
    [
        ("incorrect", "total_path_length = 0", None),
        ("syntax", "total_path_length =", "SyntaxError"),
        ("runtime", "total_path_length = 1 / 0", "ZeroDivisionError"),
    ],
)
def test_classroom_rejects_incorrect_and_broken_submissions(
    label, code, expected_error, tmp_path
):
    settings = _settings("sqlite://", tmp_path / f"{label}-accounts.json")
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as client:
        student = _login(client, "student", "student")
        response = client.post(
            "/assignments/2/submit",
            headers=_bearer(student["token"]),
            json={"code": code},
        )

    assert response.status_code == 200
    result = response.json()
    assert result["pass"] is False
    if expected_error is None:
        assert result["ex_success"] is True
        assert any(not passed for passed in result["unittest_pass_results"])
    else:
        assert result["ex_success"] is False
        assert expected_error in result["code_exec_result"]


def test_attempt_and_instructor_edit_survive_application_restart(tmp_path):
    database_path = tmp_path / "classroom-restart.sqlite"
    database_url = f"sqlite:///{database_path.as_posix()}"
    account_file = tmp_path / "accounts.json"
    marker = "Classroom restart persistence marker."

    first_settings = _settings(database_url, account_file)
    with TestClient(
        create_app(settings=first_settings, database_url=database_url)
    ) as first_client:
        instructor = _login(first_client, "instructor", "instructor")
        student_password = "Classroom-Student-4827"
        created = first_client.post(
            "/admin/students",
            headers=_bearer(instructor["token"]),
            json={
                "login_id": "classroom-persistent-student",
                "temporary_password": student_password,
            },
        )
        assert created.status_code == 201
        student = _login(
            first_client,
            "classroom-persistent-student",
            student_password,
        )

        submission_response = first_client.post(
            "/assignments/2/submit",
            headers=_bearer(student["token"]),
            json={"code": "total_path_length = 0"},
        )
        assert submission_response.status_code == 200
        submission_id = submission_response.json()["submission_id"]

        admin_headers = _bearer(instructor["token"])
        assignment = first_client.get(
            "/admin/assignments", headers=admin_headers
        ).json()["assignments"][1]
        original_version = assignment["version"]
        assignment["description"] = marker
        updated = first_client.put(
            "/admin/assignments/2",
            headers=admin_headers,
            json=assignment,
        )
        assert updated.status_code == 200
        assert updated.json()["version"] == original_version + 1

    second_settings = _settings(database_url, account_file)
    with TestClient(
        create_app(settings=second_settings, database_url=database_url)
    ) as second_client:
        instructor = _login(second_client, "instructor", "instructor")
        assignments = second_client.get(
            "/admin/assignments", headers=_bearer(instructor["token"])
        ).json()["assignments"]
        persisted_assignment = next(item for item in assignments if item["id"] == 2)

        with second_client.app.state.SessionLocal() as session:
            persisted_submission = session.scalar(
                select(Submission).where(Submission.id == submission_id)
            )
            database_assignment = session.get(Assignment, 2)

            assert persisted_submission is not None
            assert persisted_submission.student_id == "classroom-persistent-student"
            assert persisted_submission.assignment_version == original_version
            assert database_assignment is not None
            assert database_assignment.description == marker

        assert persisted_assignment["description"] == marker
        assert persisted_assignment["version"] == original_version + 1


def test_manual_account_dataset_creates_changes_and_deactivates_login(tmp_path):
    account_file = tmp_path / "study_accounts.json"
    account_file.write_text(
        json.dumps(
            {
                "version": 1,
                "accounts": [
                    {
                        "login_id": "CLASS-001",
                        "temporary_password": "First-Classroom-4827",
                        "role": "student",
                        "email": "",
                        "participant_code": "P001",
                        "active": True,
                        "demo": False,
                    }
                ],
            }
        ),
        encoding="utf-8",
    )
    settings = _settings("sqlite://", account_file)

    with TestClient(create_app(settings=settings, database_url="sqlite://")) as client:
        created = client.post(
            "/auth/login",
            json={"login_id": "CLASS-001", "password": "First-Classroom-4827"},
        )
        assert created.status_code == 200
        sanitized = json.loads(account_file.read_text(encoding="utf-8"))
        assert sanitized["accounts"][0]["temporary_password"] is None

        sanitized["accounts"][0]["temporary_password"] = "Changed-Classroom-5938"
        account_file.write_text(json.dumps(sanitized), encoding="utf-8")
        changed = client.post(
            "/admin/accounts/import",
            headers={"X-Admin-Token": "classroom-sqa-admin"},
        )
        assert changed.status_code == 200
        assert "class-001" in changed.json()["updated"]
        assert client.post(
            "/auth/login",
            json={"login_id": "CLASS-001", "password": "First-Classroom-4827"},
        ).status_code == 401
        assert client.post(
            "/auth/login",
            json={"login_id": "CLASS-001", "password": "Changed-Classroom-5938"},
        ).status_code == 200

        sanitized = json.loads(account_file.read_text(encoding="utf-8"))
        sanitized["accounts"][0]["active"] = False
        account_file.write_text(json.dumps(sanitized), encoding="utf-8")
        deactivated = client.post(
            "/admin/accounts/import",
            headers={"X-Admin-Token": "classroom-sqa-admin"},
        )
        assert deactivated.status_code == 200
        assert "class-001" in deactivated.json()["deactivated"]
        assert client.post(
            "/auth/login",
            json={"login_id": "CLASS-001", "password": "Changed-Classroom-5938"},
        ).status_code == 401
