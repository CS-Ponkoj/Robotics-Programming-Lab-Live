import json
import re

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select

import account_sync
from account_sync import seed_demo_accounts
from app import create_app
from config import Settings
from auth_service import aware_utc
from models import AuditEvent, PasswordResetToken, Submission, User, utc_now


@pytest.fixture()
def auth_client(tmp_path):
    settings = Settings(
        database_url="sqlite://",
        admin_api_token="legacy-admin",
        openai_api_key=None,
        enable_password_reset=True,
        enable_email_features=True,
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


def create_regular_student(client, login_id):
    password = "Study-Password-4827"
    instructor = login(client, "instructor", "instructor")
    response = client.post(
        "/admin/students",
        headers=bearer(instructor["token"]),
        json={"login_id": login_id, "temporary_password": password},
    )
    assert response.status_code == 201
    return login(client, login_id, password)


def test_default_accounts_login_restore_and_logout(auth_client):
    student = login(auth_client, "student", "student")
    instructor = login(auth_client, "instructor", "instructor")

    assert student["user"]["role"] == "student"
    assert student["user"]["is_demo"] is False
    assert instructor["user"]["role"] == "instructor"
    assert instructor["user"]["is_demo"] is False

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


def test_startup_removes_legacy_demo_flag_from_password_accounts(auth_client):
    with auth_client.app.state.SessionLocal() as session:
        accounts = session.scalars(
            select(User).where(User.login_id.in_(("student", "instructor")))
        ).all()
        for account in accounts:
            account.is_demo = True
        session.commit()

        seed_demo_accounts(
            session,
            True,
            student_password="student",
            instructor_password="instructor",
        )

        corrected = {
            account.login_id: account.is_demo
            for account in session.scalars(
                select(User).where(User.login_id.in_(("student", "instructor")))
            ).all()
        }
    assert corrected == {"instructor": False, "student": False}


def test_account_file_cannot_reapply_demo_flag_to_password_accounts(tmp_path):
    account_file = tmp_path / "study_accounts.json"
    account_file.write_text(
        json.dumps(
            {
                "version": 1,
                "accounts": [
                    {
                        "login_id": "student",
                        "role": "student",
                        "participant_code": "DEMO",
                        "active": True,
                        "demo": True,
                    },
                    {
                        "login_id": "instructor",
                        "role": "instructor",
                        "active": True,
                        "demo": True,
                    },
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
        student = login(client, "student", "student")
        instructor = login(client, "instructor", "instructor")

    assert student["user"]["is_demo"] is False
    assert instructor["user"]["is_demo"] is False
    sanitized = json.loads(account_file.read_text(encoding="utf-8"))
    assert {item["login_id"]: item["demo"] for item in sanitized["accounts"]} == {
        "student": False,
        "instructor": False,
    }


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


def test_instructor_manages_instructor_accounts_without_locking_out_last_admin(
    auth_client,
):
    primary = login(auth_client, "instructor", "instructor")
    headers = bearer(primary["token"])

    created = auth_client.post(
        "/admin/instructors",
        headers=headers,
        json={
            "login_id": "second-instructor",
            "temporary_password": "Instructor-Password-4827",
        },
    )
    assert created.status_code == 201
    instructor_id = created.json()["user"]["id"]
    login(auth_client, "second-instructor", "Instructor-Password-4827")

    listed = auth_client.get("/admin/instructors", headers=headers)
    assert listed.status_code == 200
    assert {item["login_id"] for item in listed.json()["instructors"]} >= {
        "instructor",
        "second-instructor",
    }

    reset = auth_client.post(
        f"/admin/instructors/{instructor_id}/reset-password",
        headers=headers,
        json={"temporary_password": "Replacement-Password-5938"},
    )
    assert reset.status_code == 200
    login(auth_client, "second-instructor", "Replacement-Password-5938")

    deactivated = auth_client.patch(
        f"/admin/instructors/{instructor_id}",
        headers=headers,
        json={"active": False},
    )
    assert deactivated.status_code == 200
    assert deactivated.json()["is_active"] is False

    primary_id = primary["user"]["id"]
    self_deactivation = auth_client.patch(
        f"/admin/instructors/{primary_id}",
        headers=headers,
        json={"active": False},
    )
    assert self_deactivation.status_code == 409


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


def test_deferred_email_and_self_service_reset_routes_are_disabled_by_default(
    tmp_path,
):
    settings = Settings(
        database_url="sqlite://",
        study_accounts_file=tmp_path / "study_accounts.json",
    )
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as client:
        instructor = login(client, "instructor", "instructor")
        headers = bearer(instructor["token"])

        assert client.post(
            "/auth/forgot-password", json={"identifier": "student"}
        ).status_code == 404
        assert client.post(
            "/auth/reset-password",
            json={"token": "x" * 20, "new_password": "Changed-Password-5827"},
        ).status_code == 404
        assert client.get("/admin/email/status", headers=headers).status_code == 404
        assert client.post(
            "/admin/email/test",
            headers=headers,
            json={"recipient": "student@example.test"},
        ).status_code == 404


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
        enable_email_features=True,
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
    student = create_regular_student(auth_client, "submission-owner")
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
        assert submission.student_id == "submission-owner"


def test_student_password_is_hashed_and_never_stored_as_plain_text(auth_client):
    instructor = login(auth_client, "instructor", "instructor")
    response = auth_client.post(
        "/admin/students",
        headers=bearer(instructor["token"]),
        json={
            "login_id": "HASHED-STUDENT",
            "temporary_password": "Study-Password-4827",
        },
    )

    assert response.status_code == 201
    with auth_client.app.state.SessionLocal() as session:
        user = session.scalar(
            select(User).where(User.login_id == "hashed-student")
        )
        assert user.password_hash != "Study-Password-4827"
        assert "Study-Password-4827" not in user.password_hash


def test_students_cannot_access_each_others_submission_feedback_or_solution(
    auth_client,
):
    instructor = login(auth_client, "instructor", "instructor")
    instructor_headers = bearer(instructor["token"])
    credentials = {}
    for login_id in ("ISOLATION-A", "ISOLATION-B"):
        created = auth_client.post(
            "/admin/students",
            headers=instructor_headers,
            json={
                "login_id": login_id,
                "temporary_password": "Study-Password-4827",
            },
        )
        assert created.status_code == 201
        credentials[login_id] = login(
            auth_client,
            login_id,
            "Study-Password-4827",
        )

    owner_headers = bearer(credentials["ISOLATION-A"]["token"])
    other_headers = bearer(credentials["ISOLATION-B"]["token"])
    submission = auth_client.post(
        "/assignments/2/submit",
        headers=owner_headers,
        json={"code": "total_path_length = 0"},
    ).json()

    owner_hint = auth_client.post(
        "/assignments/2/hint",
        headers=owner_headers,
        json={"submission_id": submission["submission_id"], "hint_level": 1},
    )
    other_hint = auth_client.post(
        "/assignments/2/hint",
        headers=other_headers,
        json={"submission_id": submission["submission_id"], "hint_level": 1},
    )
    owner_question = auth_client.post(
        "/assignments/2/tutor",
        headers=owner_headers,
        json={
            "submission_id": submission["submission_id"],
            "question": "Why is the total failing?",
        },
    )
    other_question = auth_client.post(
        "/assignments/2/tutor",
        headers=other_headers,
        json={
            "submission_id": submission["submission_id"],
            "question": "Show me this student's feedback.",
        },
    )
    other_solution = auth_client.post(
        "/assignments/2/solution",
        headers=other_headers,
        json={"submission_id": submission["submission_id"]},
    )

    assert owner_hint.status_code == 200
    assert owner_question.status_code == 200
    assert other_hint.status_code == 404
    assert other_question.status_code == 404
    assert other_solution.status_code == 403


def test_assignment_attempt_and_instructor_action_are_persisted_for_audit(
    auth_client,
):
    student = create_regular_student(auth_client, "audit-attempt-student")
    instructor = login(auth_client, "instructor", "instructor")
    submission_response = auth_client.post(
        "/assignments/2/submit",
        headers=bearer(student["token"]),
        json={"code": "total_path_length = 0"},
    )
    created = auth_client.post(
        "/admin/students",
        headers=bearer(instructor["token"]),
        json={
            "login_id": "AUDIT-STUDENT",
            "temporary_password": "Study-Password-4827",
        },
    )

    assert submission_response.status_code == 200
    assert created.status_code == 201
    with auth_client.app.state.SessionLocal() as session:
        submission = session.get(
            Submission,
            submission_response.json()["submission_id"],
        )
        audit_event = session.scalar(
            select(AuditEvent).where(AuditEvent.action == "student.created")
        )
        assert submission.student_id == "audit-attempt-student"
        assert submission.assignment_version == 9
        assert submission.evidence["tests"]
        assert audit_event.actor_user_id == instructor["user"]["id"]


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


def test_tracked_account_roster_rejects_plaintext_passwords(tmp_path, monkeypatch):
    account_file = tmp_path / "study_accounts.json"
    payload = {
        "version": 1,
        "accounts": [
            {
                "login_id": "tracked-student",
                "temporary_password": "must-not-enter-git",
                "role": "student",
                "email": "",
                "participant_code": "PTRACK",
                "active": True,
                "demo": False,
            }
        ],
    }
    account_file.write_text(json.dumps(payload), encoding="utf-8")
    monkeypatch.setattr(account_sync, "REPOSITORY_ACCOUNT_ROSTER", account_file.resolve())
    settings = Settings(
        database_url="sqlite://",
        admin_api_token="legacy-admin",
        study_accounts_file=account_file,
    )

    with TestClient(create_app(settings=settings, database_url="sqlite://")) as client:
        report = client.post(
            "/admin/accounts/import",
            headers={"X-Admin-Token": "legacy-admin"},
        )
        assert report.status_code == 200
        assert "tracked account roster cannot contain" in report.json()["errors"][0]
        assert client.post(
            "/auth/login",
            json={"login_id": "tracked-student", "password": "must-not-enter-git"},
        ).status_code == 401

    assert json.loads(account_file.read_text(encoding="utf-8")) == payload


@pytest.fixture()
def invitation_client(tmp_path, monkeypatch):
    """Email invitations on, public self-service reset off, fake SMTP."""
    sent = []

    class FakeSmtp:
        def __init__(self, host, port, timeout):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        def starttls(self):
            pass

        def login(self, username, password):
            pass

        def send_message(self, message):
            sent.append(message)

    monkeypatch.setattr("email_service.smtplib.SMTP", FakeSmtp)
    settings = Settings(
        database_url="sqlite://",
        study_accounts_file=tmp_path / "study_accounts.json",
        public_app_url="http://study.test",
        smtp_host="smtp.office365.test",
        smtp_username="mailer@unr.test",
        smtp_password="test-only-password",
        smtp_from="Robotics Programming Lab <mailer@unr.test>",
        enable_email_features=True,
        enable_password_reset=False,
    )
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as client:
        client.sent_messages = sent
        yield client


def test_invitation_email_lets_a_new_student_set_a_password(invitation_client):
    client = invitation_client
    instructor = login(client, "instructor", "instructor")
    created = client.post(
        "/admin/students",
        headers=bearer(instructor["token"]),
        json={
            "login_id": "new-student",
            "email": "new.student@unr.test",
            "participant_code": "P-101",
            "send_invitation_email": True,
        },
    )
    assert created.status_code == 201
    assert created.json()["email_sent"] is True
    # The password is never returned to the instructor or sent by email.
    assert created.json()["temporary_password"] is None

    assert len(client.sent_messages) == 1
    message = client.sent_messages[0]
    body = message.get_content()
    assert message["To"] == "new.student@unr.test"
    assert message["Subject"] == "Your Robotics Programming Lab account is ready"
    assert "Login ID: new-student" in body
    assert "expires in 72 hours" in body
    assert "temporary password" not in body.lower()
    token = re.search(r"password_token=([^\s]+)", body).group(1)

    with client.app.state.SessionLocal() as session:
        user = session.scalar(select(User).where(User.login_id == "new-student"))
        stored = session.scalar(
            select(PasswordResetToken).where(PasswordResetToken.user_id == user.id)
        )
        assert stored.purpose == "account_activation"
        lifetime = aware_utc(stored.expires_at) - utc_now()
        assert 71.9 <= lifetime.total_seconds() / 3600 <= 72.1

    activated = client.post(
        "/auth/reset-password",
        json={"token": token, "new_password": "Student-Chosen-5827"},
    )
    assert activated.status_code == 200
    login(client, "new-student", "Student-Chosen-5827")
    # The one-time link cannot be reused.
    assert client.post(
        "/auth/reset-password",
        json={"token": token, "new_password": "Second-Use-5827"},
    ).status_code == 400


def test_invitations_do_not_enable_public_password_reset(invitation_client):
    client = invitation_client
    assert client.post(
        "/auth/forgot-password", json={"identifier": "instructor"}
    ).status_code == 404

    from auth_service import create_password_reset_token

    with client.app.state.SessionLocal() as session:
        instructor = session.scalar(select(User).where(User.login_id == "instructor"))
        reset_token = create_password_reset_token(
            session, instructor, duration_minutes=30, purpose="password_reset"
        )
    # A self-service reset link stays unusable while that feature is off.
    assert client.post(
        "/auth/reset-password",
        json={"token": reset_token, "new_password": "Attacker-Chosen-5827"},
    ).status_code == 400
    login(client, "instructor", "instructor")


def _custom_client(tmp_path, client_address=("testclient", 50000), **overrides):
    settings = Settings(
        database_url="sqlite://",
        admin_api_token="legacy-admin",
        openai_api_key=None,
        enable_password_reset=True,
        enable_email_features=True,
        study_accounts_file=tmp_path / "study_accounts.json",
        public_app_url="http://study.test",
        **overrides,
    )
    return create_app(settings=settings, database_url="sqlite://")


def _email_student_reset_link(client, login_id, email):
    instructor = login(client, "instructor", "instructor")
    created = client.post(
        "/admin/students",
        headers=bearer(instructor["token"]),
        json={
            "login_id": login_id,
            "temporary_password": "Original-Password-4827",
            "email": email,
        },
    )
    assert created.status_code == 201

    def request_link():
        assert client.post(
            "/auth/forgot-password", json={"identifier": email}
        ).status_code == 202
        body = client.app.state.email_outbox[-1]["body"]
        return re.search(r"password_token=([^\s]+)", body).group(1)

    return request_link


def test_password_change_cancels_outstanding_reset_links(auth_client):
    request_link = _email_student_reset_link(
        auth_client, "stu-change", "stu-change@example.com"
    )
    old_link = request_link()
    session = login(auth_client, "stu-change", "Original-Password-4827")
    changed = auth_client.post(
        "/auth/change-password",
        headers=bearer(session["token"]),
        json={
            "current_password": "Original-Password-4827",
            "new_password": "Owner-Chosen-5827",
        },
    )
    assert changed.status_code == 200
    assert auth_client.post(
        "/auth/reset-password",
        json={"token": old_link, "new_password": "Attacker-Chosen-5827"},
    ).status_code == 400
    login(auth_client, "stu-change", "Owner-Chosen-5827")


def test_completed_reset_cancels_other_reset_links(auth_client):
    request_link = _email_student_reset_link(
        auth_client, "stu-two-links", "stu-two-links@example.com"
    )
    first, second = request_link(), request_link()
    assert auth_client.post(
        "/auth/reset-password",
        json={"token": second, "new_password": "Second-Link-5827"},
    ).status_code == 200
    assert auth_client.post(
        "/auth/reset-password",
        json={"token": first, "new_password": "First-Link-5827"},
    ).status_code == 400


def test_failed_logins_from_one_address_do_not_lock_out_the_owner(tmp_path):
    app = _custom_client(tmp_path)
    with TestClient(app, client=("203.0.113.9", 40000)) as attacker:
        for _ in range(5):
            assert attacker.post(
                "/auth/login",
                json={"login_id": "instructor", "password": "wrong"},
            ).status_code == 401
        assert attacker.post(
            "/auth/login",
            json={"login_id": "instructor", "password": "instructor"},
        ).status_code == 429
        with TestClient(app, client=("198.51.100.7", 40000)) as owner:
            assert owner.post(
                "/auth/login",
                json={"login_id": "instructor", "password": "instructor"},
            ).status_code == 200


def test_login_failure_tracking_is_bounded(tmp_path, monkeypatch):
    monkeypatch.setattr("app.MAX_TRACKED_LOGIN_KEYS", 10)
    with TestClient(_custom_client(tmp_path, auth_requests_per_minute=0)) as client:
        for index in range(25):
            client.post(
                "/auth/login",
                json={"login_id": f"missing-{index}", "password": "wrong"},
            )
        assert len(client.app.state.login_failures) <= 10


def test_unauthenticated_auth_endpoints_are_rate_limited(tmp_path):
    with TestClient(_custom_client(tmp_path, auth_requests_per_minute=3)) as client:
        statuses = [client.post("/auth/demo").status_code for _ in range(4)]
        assert statuses == [200, 200, 200, 429]
        assert client.post(
            "/auth/forgot-password", json={"identifier": "nobody@example.com"}
        ).status_code == 429
        assert client.post(
            "/auth/login", json={"login_id": "student", "password": "student"}
        ).status_code == 429


def test_demo_sessions_are_capped(tmp_path):
    with TestClient(
        _custom_client(tmp_path, max_demo_sessions=2, auth_requests_per_minute=0)
    ) as client:
        statuses = [client.post("/auth/demo").status_code for _ in range(3)]
        assert statuses == [200, 200, 503]


def test_admin_routes_are_rate_limited_for_sessions_and_token(tmp_path):
    with TestClient(_custom_client(tmp_path, admin_requests_per_minute=2)) as client:
        instructor = login(client, "instructor", "instructor")
        statuses = [
            client.get(
                "/admin/students", headers=bearer(instructor["token"])
            ).status_code
            for _ in range(3)
        ]
        assert statuses == [200, 200, 429]
        token_statuses = [
            client.get(
                "/admin/students", headers={"X-Admin-Token": "legacy-admin"}
            ).status_code
            for _ in range(3)
        ]
        assert token_statuses == [200, 200, 429]
        assert client.get(
            "/admin/students", headers={"X-Admin-Token": "wrong-token"}
        ).status_code == 401


def test_format_and_quiz_submission_are_rate_limited(tmp_path):
    with TestClient(_custom_client(tmp_path, general_requests_per_minute=1)) as client:
        headers = bearer(login(client, "student", "student")["token"])
        format_statuses = [
            client.post(
                "/assignments/1/format", headers=headers, json={"code": "x=1"}
            ).status_code
            for _ in range(2)
        ]
        assert format_statuses == [200, 429]
        quiz_statuses = [
            client.post(
                "/contents/unknown-topic/quiz/submit",
                headers=headers,
                json={"quiz_version": "1", "choices": {}},
            ).status_code
            for _ in range(2)
        ]
        assert quiz_statuses[1] == 429


def test_chunked_request_body_cannot_exceed_size_limit(tmp_path):
    with TestClient(_custom_client(tmp_path, max_request_bytes=1_000)) as client:
        def chunks():
            yield b'{"login_id": "student", "password": "'
            for _ in range(20):
                yield b"x" * 1_000
            yield b'"}'

        response = client.post(
            "/auth/login",
            content=chunks(),
            headers={"Content-Type": "application/json"},
        )
        assert response.status_code == 413
        assert response.json()["error"] == "Request body is too large."


def test_development_email_outbox_is_bounded(auth_client):
    from email_service import MAX_OUTBOX_MESSAGES, EmailService

    service = EmailService(
        auth_client.app.state.settings, auth_client.app.state.email_outbox
    )
    for index in range(MAX_OUTBOX_MESSAGES + 10):
        service.send_password_link(
            email=f"user{index}@example.com",
            login_id=f"user{index}",
            token=f"token-{index}",
            purpose="password_reset",
        )
    outbox = auth_client.app.state.email_outbox
    assert len(outbox) == MAX_OUTBOX_MESSAGES
    assert "token-59" in outbox[-1]["body"]


def test_failed_roster_account_keeps_its_temporary_password(tmp_path):
    account_file = tmp_path / "study_accounts.json"
    account_file.write_text(
        json.dumps(
            {
                "version": 1,
                "accounts": [
                    {
                        "login_id": "first-student",
                        "temporary_password": "First-Password-4827",
                        "role": "student",
                        "email": "shared@example.com",
                    },
                    {
                        "login_id": "second-student",
                        "temporary_password": "Second-Password-4827",
                        "role": "student",
                        "email": "shared@example.com",
                    },
                ],
            }
        ),
        encoding="utf-8",
    )
    settings = Settings(database_url="sqlite://", study_accounts_file=account_file)
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as client:
        report = client.app.state.account_import_report
        assert report["created"] == ["first-student"]
        assert any("second-student" in error for error in report["errors"])
    rewritten = json.loads(account_file.read_text(encoding="utf-8"))["accounts"]
    assert rewritten[0]["temporary_password"] is None
    assert rewritten[1]["temporary_password"] == "Second-Password-4827"


def test_admin_research_detail_hides_demo_students(auth_client):
    instructor = login(auth_client, "instructor", "instructor")
    created = auth_client.post(
        "/admin/students",
        headers=bearer(instructor["token"]),
        json={"login_id": "marked-demo", "temporary_password": "Demo-Marked-4827"},
    )
    assert created.status_code == 201
    with auth_client.app.state.SessionLocal() as session:
        user = session.scalar(select(User).where(User.login_id == "marked-demo"))
        user.is_demo = True
        session.commit()
        student_id = user.id
    assert auth_client.get(
        f"/admin/research/students/{student_id}",
        headers=bearer(instructor["token"]),
    ).status_code == 404
