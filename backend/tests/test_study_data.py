"""Instructor Study data tables: access, privacy, filters, CSV, and code view."""

import csv
import io
import json

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select

from app import create_app
from config import Settings
from models import AuditEvent
from study_data import TABLES

STUDENT_LOGIN = "study-data-student"
STUDENT_PASSWORD = "Study-Data-Student-4827"
QUESTION = "Why does my robot never stop near the wall?"


@pytest.fixture()
def client(tmp_path):
    accounts = tmp_path / "study_accounts.json"
    accounts.write_text(json.dumps({"version": 1, "accounts": [{
        "login_id": STUDENT_LOGIN,
        "temporary_password": STUDENT_PASSWORD,
        "role": "student",
        "participant_code": "P-001",
        "active": True,
        "demo": False,
    }]}), encoding="utf-8")
    settings = Settings(database_url="sqlite://", openai_api_key=None,
                        study_accounts_file=accounts)
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as test_client:
        yield test_client


def _login(client, login_id, password):
    response = client.post("/auth/login", json={"login_id": login_id, "password": password})
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['token']}"}, response.json()["user"]


def _instructor(client):
    return _login(client, "instructor", "instructor")[0]


def _activity(client):
    """One attempt, one hint, and one tutor question by a TDD + AI student."""
    headers, user = _login(client, STUDENT_LOGIN, STUDENT_PASSWORD)
    assert client.patch(f"/admin/students/{user['id']}", headers=_instructor(client),
                        json={"feedback_mode": "tdd_ai"}).status_code == 200
    session = client.post("/research/sessions", headers=headers,
                          json={"client_session_id": "browser-session-study"}).json()
    starter = client.get("/assignments/1", headers=headers).json()["starter_code"]
    submitted = client.post("/assignments/1/submit", headers=headers, json={
        "code": starter, "use_ai_tutor": False, "study_session_id": session["id"],
    })
    assert submitted.status_code == 200, submitted.text
    attempt_id = submitted.json()["submission_id"]
    assert client.post("/assignments/1/hint", headers=headers, json={
        "submission_id": attempt_id, "hint_level": 2}).status_code == 200
    assert client.post("/assignments/1/tutor", headers=headers, json={
        "submission_id": attempt_id, "question": QUESTION, "hint_level": 1,
    }).status_code == 200
    return headers, user, attempt_id, starter


def test_only_instructors_can_read_study_data(client):
    headers, _user, attempt_id, _code = _activity(client)
    assert client.get("/admin/study-data").status_code == 401
    assert client.get("/admin/study-data/attempts").status_code == 401
    assert client.get("/admin/study-data", headers=headers).status_code == 403
    assert client.get("/admin/study-data/ai_questions_and_hints",
                      headers=headers).status_code == 403
    assert client.get(f"/admin/study-data/attempts/{attempt_id}/code",
                      headers=headers).status_code == 403


def test_every_table_loads_without_login_ids_or_secrets(client):
    _activity(client)
    instructor = _instructor(client)
    catalog = client.get("/admin/study-data", headers=instructor).json()
    assert [table["name"] for table in catalog["tables"]] == [t.name for t in TABLES]
    assert [p["participant_code"] for p in catalog["participants"]] == ["P-001"]
    for table in TABLES:
        response = client.get(f"/admin/study-data/{table.name}", headers=instructor)
        assert response.status_code == 200, (table.name, response.text)
        body = json.dumps(response.json())
        assert STUDENT_LOGIN not in body, table.name
        for secret in ("password", "token_hash", "starter_code", '"code"'):
            assert secret not in body, (table.name, secret)
        exported = client.get(f"/admin/study-data/{table.name}",
                              params={"format": "csv"}, headers=instructor)
        assert exported.status_code == 200
        assert STUDENT_LOGIN not in exported.text


def test_ai_questions_and_hints_show_question_and_answer(client):
    _activity(client)
    instructor = _instructor(client)
    data = client.get("/admin/study-data/ai_questions_and_hints", headers=instructor).json()
    rows = {row["type"]: row for row in data["rows"]}
    assert set(rows) >= {"Hint button", "Question to the tutor"}
    question = rows["Question to the tutor"]
    assert question["participant_code"] == "P-001"
    assert question["student_question"] == QUESTION
    assert question["feedback_mode"] == "tdd_ai"
    assert question["source"] == "Built-in"
    assert question["answer_shown"]
    assert rows["Hint button"]["student_question"] == ""

    exported = client.get("/admin/study-data/ai_questions_and_hints",
                          params={"format": "csv"}, headers=instructor)
    assert exported.headers["content-type"].startswith("text/csv")
    parsed = list(csv.DictReader(io.StringIO(exported.content.decode("utf-8-sig"))))
    assert QUESTION in [row["student_question"] for row in parsed]
    with client.app.state.SessionLocal() as session:
        actions = session.scalars(select(AuditEvent.action)).all()
    assert "study_data.exported" in actions


def test_filters_paging_and_errors(client):
    _activity(client)
    instructor = _instructor(client)
    base = "/admin/study-data/check_results"
    everything = client.get(base, headers=instructor).json()
    assert everything["total"] > 1
    first = client.get(base, params={"page_size": 1}, headers=instructor).json()
    assert len(first["rows"]) == 1 and first["total"] == everything["total"]
    assert {row["result"] for row in everything["rows"]} <= {"passed", "failed", "not run"}
    assert client.get(base, params={"feedback_mode": "traditional"},
                      headers=instructor).json()["total"] == 0
    assert client.get(base, params={"assignment_id": 2},
                      headers=instructor).json()["total"] == 0
    assert client.get(base, params={"date_from": "2000-01-01", "date_to": "2000-01-02"},
                      headers=instructor).json()["total"] == 0
    assert client.get(base, params={"date_from": "2030-01-02", "date_to": "2030-01-01"},
                      headers=instructor).status_code == 400
    assert client.get("/admin/study-data/nope", headers=instructor).status_code == 404
    ascending = client.get(base, params={"sort": "check_id", "order": "asc"},
                           headers=instructor).json()["rows"]
    ids = [row["check_id"] for row in ascending]
    assert ids == sorted(ids, key=str.lower)


def test_test_accounts_are_hidden_unless_included(client):
    instructor = _instructor(client)
    created = client.post("/admin/students", headers=instructor, json={
        "login_id": "tdd", "temporary_password": "Test-Account-4827", "feedback_mode": "tdd",
    })
    assert created.status_code == 201, created.text
    hidden = client.get("/admin/study-data/participants", headers=instructor).json()
    shown = client.get("/admin/study-data/participants",
                       params={"include_test_accounts": "true"}, headers=instructor).json()
    # The new "tdd" login and the seeded demo student row are test accounts.
    assert not any(row["test_account"] for row in hidden["rows"])
    extra = [row for row in shown["rows"] if row["test_account"]]
    assert shown["total"] == hidden["total"] + len(extra) and len(extra) >= 1


def test_code_is_viewable_one_attempt_at_a_time_and_audited(client):
    _headers, _user, attempt_id, starter = _activity(client)
    instructor = _instructor(client)
    response = client.get(f"/admin/study-data/attempts/{attempt_id}/code", headers=instructor)
    assert response.status_code == 200
    assert response.json()["code"] == starter
    assert response.json()["participant_code"] == "P-001"
    assert client.get("/admin/study-data/attempts/missing/code",
                      headers=instructor).status_code == 404
    with client.app.state.SessionLocal() as session:
        actions = session.scalars(select(AuditEvent.action)).all()
    assert "study_data.code_viewed" in actions


def test_fixes_from_the_data_review(client):
    """Points, help counts, event modes, summary scope, and audit rows."""
    _headers, user, attempt_id, _code = _activity(client)
    instructor = _instructor(client)

    def rows(table, **params):
        response = client.get(f"/admin/study-data/{table}", params=params, headers=instructor)
        assert response.status_code == 200, response.text
        return response.json()["rows"]

    # Points: a passed check earns its weight even without earned_weight.
    for row in rows("check_results"):
        if row["points_possible"] is not None:
            expected = row["points_possible"] if row["result"] == "passed" else 0.0
            assert row["points_earned"] == expected, row

    # Help: requests and automatic hints are counted apart.
    participant = rows("participants")[0]
    assert participant["tutor_questions"] == 1 and participant["hint_button"] == 1
    assert "ai_questions" not in participant and "hints" not in participant
    assert participant["ai_answers"] == 0

    # Events: every row says where its mode came from.
    events = rows("learning_events")
    assert events and all(row["feedback_mode"] == "tdd_ai" for row in events)
    assert {row["mode_source"] for row in events} <= {
        "recorded with the event", "from its attempt", "account's current mode"}

    # Summary: only this course's assignments unless one is chosen.
    catalog = client.get("/admin/study-data", headers=instructor).json()
    course_tables = {t["name"]: t for t in catalog["tables"]}
    assert course_tables["assignment_summary"]["has_dates"] is False
    assert course_tables["attempts"]["has_dates"] is True
    summary_ids = {row["assignment_id"] for row in rows("assignment_summary")}
    assert 1 not in summary_ids  # assignment 1 is an old assignment
    assert {row["assignment_id"] for row in rows("assignment_summary", assignment_id=1)} == {1}

    # Audit rows name the table and attempt they concern.
    client.get("/admin/study-data/attempts", params={"format": "csv", "feedback_mode": "tdd_ai"},
               headers=instructor)
    client.get(f"/admin/study-data/attempts/{attempt_id}/code", headers=instructor)
    actions = rows("instructor_actions")
    export = next(row for row in actions if row["action"] == "study_data.exported")
    assert export["about"] == "attempts table"
    assert export["details"]["feedback_mode"] == "tdd_ai"
    viewed = next(row for row in actions if row["action"] == "study_data.code_viewed")
    assert viewed["about"].startswith("P-001 (attempt ")


def test_quiz_answers_keep_question_ids_and_gain_uses_counts(client):
    from datetime import timedelta

    from models import CourseQuizAttempt, User, utc_now

    instructor = _instructor(client)
    with client.app.state.SessionLocal() as session:
        user = session.scalars(select(User).where(User.login_id == STUDENT_LOGIN)).one()
        start = utc_now()
        for offset, (assessment, correct) in enumerate((("pretest", 5), ("quiz", 10))):
            session.add(CourseQuizAttempt(
                user_id=user.id, topic_id="ros2-mobile-robots", quiz_version="v1",
                correct_count=correct, total_questions=15,
                score_percent=round(100 * correct / 15), assessment=assessment,
                feedback_mode="tdd", submitted_at=start + timedelta(seconds=offset),
                answers=[{"question_id": f"q{i}", "choice": "A", "correct": i <= correct}
                         for i in range(1, 16)],
            ))
        session.commit()
    answers = client.get("/admin/study-data/quiz_answers", params={"page_size": 200},
                         headers=instructor).json()["rows"]
    assert len(answers) == 30
    assert {row["question_id"] for row in answers} == {f"q{i}" for i in range(1, 16)}
    learning = client.get("/admin/study-data/course_learning", headers=instructor).json()["rows"]
    # 66.7% - 33.3% from the counts; the rounded percentages would give 34.
    assert learning[0]["learning_gain"] == 33.3


def test_followups_ids_times_definitions_and_large_csv(client, monkeypatch):
    import re
    from datetime import timedelta

    import study_data
    from models import CourseQuizAttempt, User, utc_now

    _activity(client)
    instructor = _instructor(client)
    with client.app.state.SessionLocal() as session:
        user = session.scalars(select(User).where(User.login_id == STUDENT_LOGIN)).one()
        session.add(CourseQuizAttempt(
            user_id=user.id, topic_id="ros2-mobile-robots", quiz_version="v1",
            correct_count=10, total_questions=15, score_percent=67, assessment="quiz",
            feedback_mode="tdd_ai", submitted_at=utc_now() - timedelta(minutes=1),
            answers=[{"question_id": f"q{i}", "choice": "A", "correct": i <= 10}
                     for i in range(1, 16)],
        ))
        session.commit()

    def table(name):
        return client.get(f"/admin/study-data/{name}", headers=instructor).json()

    # Quiz attempts join to quiz answers by attempt_id.
    attempt = table("quiz_attempts")["rows"][0]
    answers = table("quiz_answers")["rows"]
    assert attempt["attempt_id"] and {row["attempt_id"] for row in answers} == {attempt["attempt_id"]}

    # Every *_at value is UTC to the second with an offset.
    stamp = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\+00:00$")
    for name in ("quiz_attempts", "assignment_summary", "attempts", "participants"):
        for row in table(name)["rows"]:
            for key, value in row.items():
                if key.endswith("_at") and value not in (None, ""):
                    assert stamp.match(value), (name, key, value)

    # The summary's help counts are defined.
    summary = table("assignment_summary")
    helps = {column["key"]: column["help"] for column in summary["columns"]}
    assert "Hint button" in helps["built_in_hint_count"]
    assert "AI switch" in helps["ai_interaction_count"]

    # A CSV past the safety bound is refused, never cut short.
    monkeypatch.setattr(study_data, "MAX_TABLE_ROWS", 2)
    refused = client.get("/admin/study-data/check_results", params={"format": "csv"},
                         headers=instructor)
    assert refused.status_code == 413
    assert "Narrow the filters" in refused.json()["error"]
