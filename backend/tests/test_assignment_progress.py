"""Server-side assignment progress for signed-in students."""

from datetime import timedelta
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select

from app import create_app
from config import Settings
from models import AuthSession, Submission, utc_now


ANSWER_1 = (
    Path(__file__).resolve().parents[2] / "assignments_answers" / "assignment_1_answer.py"
).read_text(encoding="utf-8")


@pytest.fixture()
def client(tmp_path):
    settings = Settings(
        database_url="sqlite://",
        openai_api_key=None,
        study_accounts_file=tmp_path / "study_accounts.json",
        public_app_url="http://study.test",
    )
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as test_client:
        yield test_client


def login(client, login_id, password):
    response = client.post("/auth/login", json={"login_id": login_id, "password": password})
    assert response.status_code == 200
    return response.json()


def bearer(login_body):
    return {"Authorization": f"Bearer {login_body['token']}"}


def create_student(client, login_id):
    instructor = login(client, "instructor", "instructor")
    created = client.post(
        "/admin/students",
        headers=bearer(instructor),
        json={"login_id": login_id, "temporary_password": "Study-Password-4827"},
    )
    assert created.status_code == 201
    return login(client, login_id, "Study-Password-4827"), created.json()["user"]["id"]


def submit(client, student, assignment_id, code, study_session_id=None):
    body = {"code": code, "use_ai_tutor": False}
    if study_session_id:
        body["study_session_id"] = study_session_id
    response = client.post(f"/assignments/{assignment_id}/submit", headers=bearer(student), json=body)
    assert response.status_code == 200
    return response.json()


def progress(client, student):
    response = client.get("/me/assignment-progress", headers=bearer(student))
    assert response.status_code == 200
    return {item["assignment_id"]: item for item in response.json()["assignments"]}


def test_progress_summarizes_attempts_scores_and_reveals(client):
    student, _ = create_student(client, "progress-student")
    assert progress(client, student) == {}

    study = client.post(
        "/research/sessions", headers=bearer(student), json={"client_session_id": "browser-progress-01"}
    ).json()
    starter = client.get("/assignments/1", headers=bearer(student)).json()["starter_code"]
    submit(client, student, 1, starter, study["id"])
    best = submit(client, student, 1, ANSWER_1, study["id"])
    latest = submit(client, student, 1, starter, study["id"])
    revealed = client.post(
        "/assignments/1/solution", headers=bearer(student), json={"submission_id": latest["submission_id"]}
    )
    assert revealed.status_code == 200

    summary = progress(client, student)
    assert set(summary) == {1}
    assert summary[1] == {
        "assignment_id": 1,
        "attempt_count": 3,
        "best_score": 100,
        "latest_score": 0,
        "latest_submission_id": latest["submission_id"],
        "solution_revealed": True,
    }
    assert best["score"] == 100


def test_progress_hides_an_older_version_submission_but_keeps_its_scores(client):
    student, user_id = create_student(client, "version-student")
    current = client.get("/assignments/2", headers=bearer(student)).json()["version"]
    with client.app.state.SessionLocal() as session:
        session.add(
            Submission(
                id="older-version-submission",
                assignment_id=2,
                assignment_version=current - 1,
                data_schema_version=1,
                student_id="version-student",
                user_id=user_id,
                mode="submit",
                code="",
                execution_succeeded=True,
                execution_status="completed",
                passed=True,
                score=100,
                evidence={},
            )
        )
        session.commit()

    summary = progress(client, student)[2]
    assert summary["attempt_count"] == 1
    assert summary["best_score"] == 100
    # Hints and reveals are version-scoped, so an older submission is not offered.
    assert summary["latest_submission_id"] is None
    assert summary["solution_revealed"] is False


def test_progress_is_self_only(client):
    first, _ = create_student(client, "first-student")
    second, _ = create_student(client, "second-student")
    starter = client.get("/assignments/1", headers=bearer(first)).json()["starter_code"]
    submit(client, first, 1, starter)

    assert progress(client, first)[1]["attempt_count"] == 1
    assert progress(client, second) == {}
    # No query parameter can select another student.
    other = client.get("/me/assignment-progress?student_id=first-student", headers=bearer(second))
    assert other.json() == {"assignments": []}


def test_progress_rejects_unauthenticated_instructor_and_demo_sessions(client):
    assert client.get("/me/assignment-progress").status_code == 401
    instructor = login(client, "instructor", "instructor")
    assert client.get("/me/assignment-progress", headers=bearer(instructor)).status_code == 403
    demo = client.post("/auth/demo").json()
    response = client.get("/me/assignment-progress", headers=bearer(demo))
    assert response.status_code == 409


def test_progress_rejects_deactivated_and_expired_sessions(client):
    student, user_id = create_student(client, "lapsed-student")
    instructor = login(client, "instructor", "instructor")
    assert client.patch(
        f"/admin/students/{user_id}", headers=bearer(instructor), json={"active": False}
    ).status_code == 200
    assert client.get("/me/assignment-progress", headers=bearer(student)).status_code == 401

    expiring, expiring_id = create_student(client, "expiring-student")
    with client.app.state.SessionLocal() as session:
        for auth_session in session.scalars(
            select(AuthSession).where(AuthSession.user_id == expiring_id)
        ):
            auth_session.expires_at = utc_now() - timedelta(minutes=1)
        session.commit()
    assert client.get("/me/assignment-progress", headers=bearer(expiring)).status_code == 401
