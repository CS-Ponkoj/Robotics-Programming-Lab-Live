import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select

from app import create_app
from config import Settings
from models import (
    AuditEvent,
    AuthSession,
    HintInteraction,
    StudySession,
    Submission,
    User,
)


CORRECT_ASSIGNMENT_2 = """
distance_to_obstacle = 4
perimeter_of_obstacle = 6
distance_from_obstacle_to_goal = 4
total_path_length = 14
"""


@pytest.fixture()
def demo_client(tmp_path):
    settings = Settings(
        database_url="sqlite://",
        admin_api_token="test-admin",
        openai_api_key=None,
        study_accounts_file=tmp_path / "study_accounts.json",
    )
    app = create_app(settings=settings, database_url="sqlite://")
    with TestClient(app) as client:
        yield client


def bearer(token):
    return {"Authorization": f"Bearer {token}"}


def persistent_counts(client):
    models = (AuthSession, Submission, HintInteraction, StudySession, AuditEvent)
    with client.app.state.SessionLocal() as session:
        return {
            model.__tablename__: session.scalar(
                select(func.count()).select_from(model)
            )
            for model in models
        }


def test_demo_session_supports_student_workflow_without_database_writes(
    demo_client,
):
    before = persistent_counts(demo_client)
    login = demo_client.post("/auth/demo")

    assert login.status_code == 200
    payload = login.json()
    assert payload["user"]["role"] == "student"
    assert payload["user"]["is_demo"] is True
    headers = bearer(payload["token"])

    assignments = demo_client.get("/assignments", headers=headers)
    assert assignments.status_code == 200

    run = demo_client.post(
        "/assignments/2/run",
        headers=headers,
        json={"code": CORRECT_ASSIGNMENT_2},
    )
    assert run.status_code == 200
    assert run.json()["pass"] is True
    submission_id = run.json()["submission_id"]

    hint = demo_client.post(
        "/assignments/2/hint",
        headers=headers,
        json={"submission_id": submission_id, "hint_level": 2},
    )
    assert hint.status_code == 200
    assert hint.json()["hint_level"] == 2

    solution = demo_client.post(
        "/assignments/2/solution",
        headers=headers,
        json={"submission_id": submission_id},
    )
    assert solution.status_code == 200
    assert solution.json()["solution_html"]

    tracked = demo_client.post(
        "/research/sessions",
        headers=headers,
        json={"client_session_id": "demo-browser-session"},
    )
    assert tracked.status_code == 409
    assert persistent_counts(demo_client) == before


def test_demo_sessions_are_isolated_and_logout_revokes_memory_token(demo_client):
    first = demo_client.post("/auth/demo").json()
    second = demo_client.post("/auth/demo").json()
    first_headers = bearer(first["token"])
    second_headers = bearer(second["token"])

    run = demo_client.post(
        "/assignments/2/run",
        headers=first_headers,
        json={"code": CORRECT_ASSIGNMENT_2},
    )
    submission_id = run.json()["submission_id"]

    assert demo_client.post(
        "/assignments/2/hint",
        headers=second_headers,
        json={"submission_id": submission_id, "hint_level": 1},
    ).status_code == 404
    assert demo_client.post(
        "/assignments/2/solution",
        headers=second_headers,
        json={"submission_id": submission_id},
    ).status_code == 403

    assert demo_client.post("/auth/logout", headers=first_headers).status_code == 200
    assert demo_client.get("/auth/me", headers=first_headers).status_code == 401


def test_demo_credentials_also_create_an_ephemeral_student_session(demo_client):
    before = persistent_counts(demo_client)
    with demo_client.app.state.SessionLocal() as session:
        last_login_before = session.scalar(
            select(User.last_login_at).where(User.login_id == "student")
        )
    login = demo_client.post(
        "/auth/login",
        json={"login_id": "student", "password": "student"},
    )
    assert login.status_code == 200
    assert login.json()["user"]["is_demo"] is True
    assert persistent_counts(demo_client) == before
    with demo_client.app.state.SessionLocal() as session:
        last_login_after = session.scalar(
            select(User.last_login_at).where(User.login_id == "student")
        )
    assert last_login_after == last_login_before


def test_demo_endpoint_is_hidden_when_demo_accounts_are_disabled(tmp_path):
    settings = Settings(
        database_url="sqlite://",
        enable_demo_accounts=False,
        study_accounts_file=tmp_path / "study_accounts.json",
    )
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as client:
        response = client.post("/auth/demo")
    assert response.status_code == 404
