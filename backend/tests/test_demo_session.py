import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select

from app import create_app
from config import Settings
from models import (
    AssignmentActivity,
    AuditEvent,
    AuthSession,
    HintInteraction,
    LearningEvent,
    StudySession,
    Submission,
    User,
)


CORRECT_ASSIGNMENT_2 = """
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

    restored = demo_client.get("/auth/me", headers=headers)
    assert restored.status_code == 200
    assert restored.json()["is_demo"] is True
    research = demo_client.get("/research/me", headers=headers)
    assert research.status_code == 409
    assert "no saved research data" in research.json()["error"]

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


def test_student_credentials_create_a_persistent_student_session(demo_client):
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
    payload = login.json()
    assert payload["user"]["is_demo"] is False
    headers = bearer(payload["token"])

    restored = demo_client.get("/auth/me", headers=headers)
    assert restored.status_code == 200
    assert restored.json()["is_demo"] is False
    tracked = demo_client.post(
        "/research/sessions",
        headers=headers,
        json={"client_session_id": "persistent-student-session"},
    )
    assert tracked.status_code == 201
    assert demo_client.get("/research/me", headers=headers).status_code == 200

    after = persistent_counts(demo_client)
    assert after["auth_sessions"] == before["auth_sessions"] + 1
    assert after["study_sessions"] == before["study_sessions"] + 1
    with demo_client.app.state.SessionLocal() as session:
        last_login_after = session.scalar(
            select(User.last_login_at).where(User.login_id == "student")
        )
    assert last_login_after is not None
    assert last_login_after != last_login_before


def test_demo_endpoint_is_hidden_when_demo_accounts_are_disabled(tmp_path):
    settings = Settings(
        database_url="sqlite://",
        enable_demo_accounts=False,
        study_accounts_file=tmp_path / "study_accounts.json",
    )
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as client:
        response = client.post("/auth/demo")
    assert response.status_code == 404


def test_demo_token_cannot_write_to_a_real_student_study_session(demo_client):
    login = demo_client.post(
        "/auth/login",
        json={"login_id": "student", "password": "student"},
    )
    assert login.status_code == 200
    student_headers = bearer(login.json()["token"])
    started = demo_client.post(
        "/research/sessions",
        headers=student_headers,
        json={"client_session_id": "real-classroom-session"},
    )
    assert started.status_code == 201
    session_id = started.json()["id"]

    demo_headers = bearer(demo_client.post("/auth/demo").json()["token"])
    version = demo_client.get("/assignments/1", headers=demo_headers).json()[
        "version"
    ]
    before = persistent_counts(demo_client)
    with demo_client.app.state.SessionLocal() as session:
        events_before = session.scalar(select(func.count()).select_from(LearningEvent))
        activities_before = session.scalar(
            select(func.count()).select_from(AssignmentActivity)
        )

    attempts = [
        demo_client.post(
            f"/research/sessions/{session_id}/heartbeat",
            headers=demo_headers,
            json={
                "active_seconds": 30,
                "assignment_id": 1,
                "assignment_version": version,
            },
        ),
        demo_client.post(
            f"/research/sessions/{session_id}/events",
            headers=demo_headers,
            json={
                "event_type": "assignment_opened",
                "assignment_id": 1,
                "assignment_version": version,
                "event_data": {"source": "assignment_catalog"},
            },
        ),
        demo_client.post(
            f"/research/sessions/{session_id}/end", headers=demo_headers
        ),
    ]
    assert [response.status_code for response in attempts] == [409, 409, 409]

    assert persistent_counts(demo_client) == before
    with demo_client.app.state.SessionLocal() as session:
        assert (
            session.scalar(select(func.count()).select_from(LearningEvent))
            == events_before
        )
        assert (
            session.scalar(select(func.count()).select_from(AssignmentActivity))
            == activities_before
        )
        study_session = session.get(StudySession, session_id)
        assert study_session.ended_at is None
        assert study_session.active_seconds == 0


def test_demo_payload_hides_the_shared_student_account_identity(demo_client):
    with demo_client.app.state.SessionLocal() as session:
        real_id = session.scalar(select(User.id).where(User.login_id == "student"))
    login = demo_client.post("/auth/demo")
    assert login.status_code == 200
    restored = demo_client.get(
        "/auth/me", headers=bearer(login.json()["token"])
    )
    assert restored.status_code == 200
    for user in (login.json()["user"], restored.json()):
        assert user["is_demo"] is True
        assert user["id"] != real_id
        assert user["participant_code"] is None
        assert user["email"] is None


def test_demo_list_never_shows_the_shared_student_accounts_saved_drafts(demo_client):
    student = demo_client.post(
        "/auth/login", json={"login_id": "student", "password": "student"}
    ).json()
    headers = {"Authorization": f"Bearer {student['token']}"}
    version = demo_client.get("/assignments/1", headers=headers).json()["version"]
    saved = demo_client.put(
        "/assignments/1/draft",
        headers=headers,
        json={"assignment_version": version, "code": "# the real student's work\n"},
    )
    assert saved.status_code == 200
    real_list = demo_client.get("/assignments", headers=headers).json()["assignments"]
    assert next(a for a in real_list if a["id"] == 1)["has_saved_draft"] is True

    demo = demo_client.post("/auth/demo").json()
    demo_headers = {"Authorization": f"Bearer {demo['token']}"}
    demo_list = demo_client.get("/assignments", headers=demo_headers).json()["assignments"]
    # The demo runs as the seeded student row but must not see its work.
    assert all(item["has_saved_draft"] is False for item in demo_list)
    assert demo_client.get("/assignments/1/draft", headers=demo_headers).json()["code"] is None
