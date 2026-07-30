import json
import re

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select

from app import create_app
from config import Settings
from models import Submission, User


@pytest.fixture()
def auth_client(tmp_path):
    settings = Settings(
        database_url="sqlite://",
        admin_api_token="legacy-admin",
        openai_api_key=None,
        study_accounts_file=tmp_path / "study_accounts.json",
        public_app_url="http://study.test",
    )
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as client:
        yield client


def login(client, login_id, password):
    response = client.post(
        "/auth/login",
        json={"login_id": login_id, "password": password},
    )
    assert response.status_code == 200
    return response.json()


def bearer(token):
    return {"Authorization": f"Bearer {token}"}


def test_default_demo_accounts_login_restore_and_logout(auth_client):
    student = login(auth_client, "student", "student")
    instructor = login(auth_client, "instructor", "instructor")

    assert student["user"]["role"] == "student"
    assert student["user"]["is_demo"] is True
    assert instructor["user"]["role"] == "instructor"

    restored = auth_client.get("/auth/me", headers=bearer(student["token"]))
    assert restored.status_code == 200
    assert restored.json()["login_id"] == "student"

    logged_out = auth_client.post(
        "/auth/logout", headers=bearer(student["token"])
    )
    assert logged_out.status_code == 200
    assert auth_client.get(
        "/auth/me", headers=bearer(student["token"])
    ).status_code == 401


def test_login_rejects_invalid_credentials_and_throttles(auth_client):
    for _ in range(5):
        response = auth_client.post(
            "/auth/login",
            json={"login_id": "student", "password": "wrong"},
        )
        assert response.status_code == 401
        assert response.json()["error"] == "Invalid login ID or password."
    blocked = auth_client.post(
        "/auth/login",
        json={"login_id": "student", "password": "student"},
    )
    assert blocked.status_code == 429


def test_instructor_session_replaces_admin_token_without_removing_compatibility(
    auth_client,
):
    instructor = login(auth_client, "instructor", "instructor")
    student = login(auth_client, "student", "student")

    bearer_access = auth_client.get(
        "/admin/assignments", headers=bearer(instructor["token"])
    )
    student_blocked = auth_client.get(
        "/admin/assignments", headers=bearer(student["token"])
    )
    legacy_access = auth_client.get(
        "/admin/assignments", headers={"X-Admin-Token": "legacy-admin"}
    )

    assert bearer_access.status_code == 200
    assert student_blocked.status_code == 403
    assert legacy_access.status_code == 200


def test_instructor_creates_resets_and_deactivates_student(auth_client):
    instructor = login(auth_client, "instructor", "instructor")
    headers = bearer(instructor["token"])
    created = auth_client.post(
        "/admin/students",
        headers=headers,
        json={
            "login_id": "STU-001",
            "participant_code": "P001",
            "email": "student1@example.com",
        },
    )
    assert created.status_code == 201
    body = created.json()
    assert body["user"]["login_id"] == "stu-001"
    assert body["user"]["participant_code"] == "P001"
    assert body["temporary_password"].startswith("Robot-")

    student_login = login(
        auth_client, "STU-001", body["temporary_password"]
    )
    student_id = body["user"]["id"]
    reset = auth_client.post(
        f"/admin/students/{student_id}/reset-password",
        headers=headers,
        json={},
    )
    assert reset.status_code == 200
    new_password = reset.json()["temporary_password"]
    assert new_password and new_password != body["temporary_password"]
    assert auth_client.get(
        "/auth/me", headers=bearer(student_login["token"])
    ).status_code == 401
    login(auth_client, "STU-001", new_password)

    deactivated = auth_client.patch(
        f"/admin/students/{student_id}",
        headers=headers,
        json={"active": False},
    )
    assert deactivated.status_code == 200
    assert deactivated.json()["is_active"] is False
    assert auth_client.post(
        "/auth/login",
        json={"login_id": "STU-001", "password": new_password},
    ).status_code == 401


def test_forgot_password_sends_single_use_link_and_revokes_sessions(auth_client):
    instructor = login(auth_client, "instructor", "instructor")
    created = auth_client.post(
        "/admin/students",
        headers=bearer(instructor["token"]),
        json={
            "login_id": "STU-EMAIL",
            "temporary_password": "Original-Password-4827",
            "email": "student-reset@example.com",
        },
    ).json()
    old_session = login(auth_client, "STU-EMAIL", "Original-Password-4827")

    requested = auth_client.post(
        "/auth/forgot-password",
        json={"identifier": "student-reset@example.com"},
    )
    assert requested.status_code == 202
    assert "If an account matches" in requested.json()["message"]
    outbox = auth_client.app.state.email_outbox
    assert len(outbox) == 1
    match = re.search(r"password_token=([^\s]+)", outbox[0]["body"])
    assert match

    reset = auth_client.post(
        "/auth/reset-password",
        json={"token": match.group(1), "new_password": "Changed-Password-5827"},
    )
    assert reset.status_code == 200
    assert auth_client.post(
        "/auth/reset-password",
        json={"token": match.group(1), "new_password": "Another-Password-5827"},
    ).status_code == 400
    assert auth_client.get(
        "/auth/me", headers=bearer(old_session["token"])
    ).status_code == 401
    login(auth_client, created["user"]["login_id"], "Changed-Password-5827")


def test_unconfigured_email_is_reported_and_invitation_is_blocked(auth_client):
    instructor = login(auth_client, "instructor", "instructor")
    headers = bearer(instructor["token"])

    status = auth_client.get("/admin/email/status", headers=headers)
    assert status.status_code == 200
    assert status.json()["configured"] is False
    assert status.json()["password_configured"] is False

    invitation = auth_client.post(
        "/admin/students",
        headers=headers,
        json={
            "login_id": "STU-NO-SMTP",
            "email": "student@example.com",
            "send_invitation_email": True,
        },
    )
    assert invitation.status_code == 503
    assert "Real email delivery is not configured" in invitation.json()["error"]
    student_ids = {
        value["login_id"]
        for value in auth_client.get(
            "/admin/students", headers=headers
        ).json()["students"]
    }
    assert "stu-no-smtp" not in student_ids


def test_configured_smtp_sends_real_test_message(tmp_path, monkeypatch):
    sent_messages = []
    smtp_actions = []

    class FakeSmtp:
        def __init__(self, host, port, timeout):
            smtp_actions.append(("connect", host, port, timeout))

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        def starttls(self):
            smtp_actions.append(("starttls",))

        def login(self, username, password):
            smtp_actions.append(("login", username, password))

        def send_message(self, message):
            sent_messages.append(message)

    monkeypatch.setattr("email_service.smtplib.SMTP", FakeSmtp)
    settings = Settings(
        database_url="sqlite://",
        study_accounts_file=tmp_path / "study_accounts.json",
        public_app_url="http://study.test",
        smtp_host="smtp.example.test",
        smtp_port=587,
        smtp_username="mailer@example.test",
        smtp_password="test-only-password",
        smtp_from="Robotics Lab <mailer@example.test>",
        smtp_use_tls=True,
    )
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as client:
        instructor = login(client, "instructor", "instructor")
        headers = bearer(instructor["token"])
        status = client.get("/admin/email/status", headers=headers)
        assert status.status_code == 200
        assert status.json()["configured"] is True
        assert "smtp_password" not in status.json()

        result = client.post(
            "/admin/email/test",
            headers=headers,
            json={"recipient": "recipient@example.test"},
        )
        assert result.status_code == 200
        assert result.json()["sent"] is True

    assert ("connect", "smtp.example.test", 587, 15) in smtp_actions
    assert ("starttls",) in smtp_actions
    assert ("login", "mailer@example.test", "test-only-password") in smtp_actions
    assert len(sent_messages) == 1
    assert sent_messages[0]["To"] == "recipient@example.test"


def test_authenticated_submission_uses_logged_in_student_id(auth_client):
    student = login(auth_client, "student", "student")
    response = auth_client.post(
        "/assignments/2/run",
        headers=bearer(student["token"]),
        json={"code": "print('hello')", "student_id": "spoofed"},
    )
    assert response.status_code == 200
    with auth_client.app.state.SessionLocal() as session:
        submission = session.scalar(
            select(Submission).where(
                Submission.id == response.json()["submission_id"]
            )
        )
        assert submission.student_id == "student"


def test_json_file_creates_updates_and_sanitizes_accounts(tmp_path):
    account_file = tmp_path / "study_accounts.json"
    account_file.write_text(
        json.dumps(
            {
                "version": 1,
                "accounts": [
                    {
                        "login_id": "JSON-STUDENT",
                        "temporary_password": "Json-Password-4827",
                        "role": "student",
                        "email": "json@example.com",
                        "participant_code": "PJSON",
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
        admin_api_token="legacy-admin",
        study_accounts_file=account_file,
    )
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as client:
        login(client, "JSON-STUDENT", "Json-Password-4827")
        sanitized = json.loads(account_file.read_text(encoding="utf-8"))
        assert sanitized["accounts"][0]["temporary_password"] is None

        sanitized["accounts"][0]["active"] = False
        account_file.write_text(json.dumps(sanitized), encoding="utf-8")
        report = client.post(
            "/admin/accounts/import",
            headers={"X-Admin-Token": "legacy-admin"},
        )
        assert report.status_code == 200
        assert "json-student" in report.json()["deactivated"]
        with client.app.state.SessionLocal() as session:
            user = session.scalar(
                select(User).where(User.login_id == "json-student")
            )
            assert user.is_active is False
