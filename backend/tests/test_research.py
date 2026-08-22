import json

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select

from app import create_app
from config import Settings
from models import HintInteraction


@pytest.fixture()
def research_client(tmp_path):
    account_file = tmp_path / "study_accounts.json"
    account_file.write_text(
        json.dumps(
            {
                "version": 1,
                "accounts": [
                    {
                        "login_id": "research-student",
                        "temporary_password": "Research-Student-4827",
                        "role": "student",
                        "participant_code": "RESEARCH-001",
                        "active": True,
                        "demo": False,
                    }
                ],
            }
        ),
        encoding="utf-8",
    )
    settings = Settings(
        database_url="sqlite://",
        openai_api_key=None,
        study_accounts_file=account_file,
    )
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as client:
        yield client


def _login(client, login_id, password):
    response = client.post(
        "/auth/login", json={"login_id": login_id, "password": password}
    )
    assert response.status_code == 200
    return response.json()


def _bearer(login):
    return {"Authorization": f"Bearer {login['token']}"}


def _start(client, login, client_id="browser-session-0001"):
    return client.post(
        "/research/sessions",
        headers=_bearer(login),
        json={"client_session_id": client_id},
    )


def test_study_session_lifecycle_heartbeat_events_and_isolation(research_client):
    student = _login(
        research_client, "research-student", "Research-Student-4827"
    )
    instructor = _login(research_client, "instructor", "instructor")

    started = _start(research_client, student)
    assert started.status_code == 201
    session_id = started.json()["id"]
    duplicate = _start(research_client, student)
    assert duplicate.status_code == 201
    assert duplicate.json()["id"] == session_id

    opened = research_client.post(
        f"/research/sessions/{session_id}/events",
        headers=_bearer(student),
        json={
            "event_type": "assignment_opened",
            "assignment_id": 1,
            "assignment_version": research_client.get(
                "/assignments/1", headers=_bearer(student)
            ).json()["version"],
            "event_data": {"source": "assignment_catalog"},
        },
    )
    assert opened.status_code == 201
    heartbeat = research_client.post(
        f"/research/sessions/{session_id}/heartbeat",
        headers=_bearer(student),
        json={
            "active_seconds": 30,
            "assignment_id": 1,
            "assignment_version": research_client.get(
                "/assignments/1", headers=_bearer(student)
            ).json()["version"],
        },
    )
    assert heartbeat.status_code == 200
    assert heartbeat.json()["active_seconds"] == 30

    mine = research_client.get("/research/me", headers=_bearer(student))
    assert mine.status_code == 200
    assert mine.json()["summary"]["active_seconds"] == 30
    assert mine.json()["events"][0]["event_type"] == "assignment_opened"

    assert _start(research_client, instructor).status_code == 403
    assert research_client.post(
        f"/research/sessions/{session_id}/heartbeat",
        headers=_bearer(instructor),
        json={"active_seconds": 10},
    ).status_code == 404

    ended = research_client.post(
        f"/research/sessions/{session_id}/end", headers=_bearer(student)
    )
    assert ended.status_code == 200
    assert ended.json()["ended_at"] is not None
    assert research_client.post(
        f"/research/sessions/{session_id}/heartbeat",
        headers=_bearer(student),
        json={"active_seconds": 10},
    ).status_code == 409


def test_submission_hint_solution_and_ai_status_are_recorded(research_client):
    student = _login(
        research_client, "research-student", "Research-Student-4827"
    )
    study_session = _start(research_client, student, "browser-session-0002").json()
    assignment = research_client.get(
        "/assignments/1", headers=_bearer(student)
    ).json()
    submitted = research_client.post(
        "/assignments/1/submit",
        headers=_bearer(student),
        json={
            "code": assignment["starter_code"],
            "use_ai_tutor": False,
            "study_session_id": study_session["id"],
        },
    )
    assert submitted.status_code == 200
    submission_id = submitted.json()["submission_id"]

    hint = research_client.post(
        "/assignments/1/hint",
        headers=_bearer(student),
        json={"submission_id": submission_id, "hint_level": 2},
    )
    assert hint.status_code == 200
    question_text = "Why does the first calculation fail?"
    question = research_client.post(
        "/assignments/1/tutor",
        headers=_bearer(student),
        json={
            "submission_id": submission_id,
            "question": question_text,
            "hint_level": 1,
        },
    )
    assert question.status_code == 200
    solution = research_client.post(
        "/assignments/1/solution",
        headers=_bearer(student),
        json={"submission_id": submission_id},
    )
    assert solution.status_code == 200

    mine = research_client.get("/research/me", headers=_bearer(student)).json()
    types = [event["event_type"] for event in mine["events"]]
    assert types == [
        "assignment_submitted",
        "hint_requested",
        "hint_requested",
        "solution_revealed",
    ]
    assert mine["summary"]["attempts"] == 1
    assert mine["summary"]["hints_requested"] == 1
    assert mine["summary"]["tutor_questions_asked"] == 1
    assert mine["summary"]["solutions_revealed"] == 1
    assert all("code" not in attempt for attempt in mine["attempts"])
    assert all("code" not in event["event_data"] for event in mine["events"])
    assert all(
        question_text not in json.dumps(event["event_data"])
        for event in mine["events"]
    )
    question_event = mine["events"][2]
    assert question_event["event_data"]["interaction_type"] == "student_question"
    assert question_event["event_data"]["question_length"] == len(question_text)
    with research_client.app.state.SessionLocal() as session:
        interactions = session.scalars(select(HintInteraction)).all()
        assert len(interactions) == 2
        assert all(
            question_text not in json.dumps(item.feedback)
            for item in interactions
        )
    assert mine["attempts"][0]["data_schema_version"] == 1
    assert mine["attempts"][0]["execution_status"] in {
        "completed",
        "syntax_error",
        "runtime_error",
        "timeout",
        "rejected",
        "grader_unavailable",
        "internal_error",
        "execution_error",
    }

    invalid_session = research_client.post(
        "/assignments/1/submit",
        headers=_bearer(student),
        json={
            "code": assignment["starter_code"],
            "study_session_id": "00000000-0000-0000-0000-000000000000",
        },
    )
    assert invalid_session.status_code == 404


def test_instructor_dashboard_and_exports_use_participant_codes(research_client):
    instructor = _login(research_client, "instructor", "instructor")
    created = research_client.post(
        "/admin/students",
        headers=_bearer(instructor),
        json={
            "login_id": "private-login-name",
            "temporary_password": "Research-Password-4827",
            "participant_code": "P-042",
        },
    )
    assert created.status_code == 201
    student_id = created.json()["user"]["id"]
    duplicate_code = research_client.post(
        "/admin/students",
        headers=_bearer(instructor),
        json={
            "login_id": "second-private-login",
            "temporary_password": "Research-Password-5927",
            "participant_code": "P-042",
        },
    )
    assert duplicate_code.status_code == 409
    student = _login(
        research_client, "private-login-name", "Research-Password-4827"
    )
    study_session = _start(
        research_client, student, "browser-session-private"
    ).json()
    assert research_client.post(
        f"/research/sessions/{study_session['id']}/heartbeat",
        headers=_bearer(student),
        json={"active_seconds": 25},
    ).status_code == 200

    summary = research_client.get(
        "/admin/research/summary", headers=_bearer(instructor)
    )
    assert summary.status_code == 200
    participant = next(
        row for row in summary.json()["participants"] if row["participant_code"] == "P-042"
    )
    assert participant["active_seconds"] == 25
    assert "login_id" not in participant
    assert "private-login-name" not in summary.text

    detail = research_client.get(
        f"/admin/research/students/{student_id}", headers=_bearer(instructor)
    )
    assert detail.status_code == 200
    assert detail.json()["summary"]["participant_code"] == "P-042"
    assert research_client.get(
        "/admin/research/summary", headers=_bearer(student)
    ).status_code == 403

    csv_export = research_client.get(
        "/admin/research/export?dataset_name=student_summary&format=csv",
        headers=_bearer(instructor),
    )
    assert csv_export.status_code == 200
    assert "P-042" in csv_export.text
    assert "private-login-name" not in csv_export.text
    assert "password" not in csv_export.text.lower()

    xlsx_export = research_client.get(
        "/admin/research/export?format=xlsx", headers=_bearer(instructor)
    )
    assert xlsx_export.status_code == 200
    assert xlsx_export.content.startswith(b"PK")
    assert len(xlsx_export.content) > 5_000


def test_learning_event_validation_limits_untrusted_data(research_client):
    student = _login(
        research_client, "research-student", "Research-Student-4827"
    )
    session_id = _start(
        research_client, student, "browser-session-validation"
    ).json()["id"]

    invalid_type = research_client.post(
        f"/research/sessions/{session_id}/events",
        headers=_bearer(student),
        json={"event_type": "password_captured"},
    )
    assert invalid_type.status_code == 400
    oversized = research_client.post(
        f"/research/sessions/{session_id}/events",
        headers=_bearer(student),
        json={
            "event_type": "assignment_opened",
            "event_data": {"value": "x" * 4_100},
        },
    )
    assert oversized.status_code == 413
    mismatched_assignment_version = research_client.post(
        f"/research/sessions/{session_id}/events",
        headers=_bearer(student),
        json={
            "event_type": "assignment_opened",
            "assignment_id": 1,
            "event_data": {"source": "assignment_catalog"},
        },
    )
    assert mismatched_assignment_version.status_code == 400
    invalid_shape = research_client.post(
        f"/research/sessions/{session_id}/events",
        headers=_bearer(student),
        json={
            "event_type": "ai_tutor_toggled",
            "event_data": {"enabled": False, "unexpected": "not stored"},
        },
    )
    assert invalid_shape.status_code == 400
    too_much_time = research_client.post(
        f"/research/sessions/{session_id}/heartbeat",
        headers=_bearer(student),
        json={"active_seconds": 61},
    )
    assert too_much_time.status_code == 400
