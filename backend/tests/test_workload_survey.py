"""Raw NASA-TLX workload survey: access, validation, one response, export."""

from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import func, select

from models import Assignment, Submission, User, WorkloadSurvey
from workload_survey import KEYS, raw_tlx, validate_ratings
from tests.test_study_data import (  # noqa: F401  (fixture)
    STUDENT_LOGIN,
    STUDENT_PASSWORD,
    _instructor,
    _login,
    client,
)

FULL = {"mental_demand": 70, "physical_demand": 5, "temporal_demand": 40,
        "performance": 30, "effort": 65, "frustration": 45}


def _wall_id(client):
    with client.app.state.SessionLocal() as session:
        return session.scalar(select(Assignment.id).where(
            Assignment.stable_id == "ros2-wall-stop"))


def _add_attempt(client, login_id=STUDENT_LOGIN):
    with client.app.state.SessionLocal() as session:
        user = session.scalar(select(User).where(User.login_id == login_id))
        wall = session.scalar(select(Assignment).where(
            Assignment.stable_id == "ros2-wall-stop"))
        attempt = Submission(
            user_id=user.id, student_id=login_id, assignment_id=wall.id,
            assignment_version=wall.version, mode="submit", code="x = 1",
            evidence={"tests": []}, score=0, passed=False,
            execution_succeeded=True, execution_status="completed",
            feedback_mode="tdd",
        )
        session.add(attempt)
        session.commit()
        return attempt.id


def _count(client):
    with client.app.state.SessionLocal() as session:
        return session.scalar(select(func.count()).select_from(WorkloadSurvey))


def test_scoring_follows_the_protocol():
    assert raw_tlx(FULL) == 42.5  # worked example in the study-design doc
    partial = {**FULL, "physical_demand": None}
    assert raw_tlx(partial) is None  # never imputed
    assert validate_ratings({"effort": 50}) == {key: (50 if key == "effort" else None)
                                                for key in KEYS}
    for bad in ({"effort": 52}, {"effort": 105}, {"effort": -5}, {"effort": True},
                {"effort": 50.0}, {"effort": "50"}, {"mood": 50}, {}):
        with pytest.raises(ValueError):
            validate_ratings(bad)


def test_student_answers_once_after_an_attempt(client):
    headers, _user = _login(client, STUDENT_LOGIN, STUDENT_PASSWORD)
    wall = _wall_id(client)
    url = f"/assignments/{wall}/workload-survey"

    status = client.get(url, headers=headers).json()
    assert status["offered"] is True and status["completed"] is False
    assert status["has_attempt"] is False
    form = status["form"]
    assert [item["key"] for item in form["items"]] == list(KEYS)
    performance = next(i for i in form["items"] if i["key"] == "performance")
    assert (performance["low"], performance["high"]) == ("Good", "Poor")
    assert form["step"] == 5

    body = {"ratings": FULL, "trigger": "finished_button"}
    assert client.post(url, headers=headers, json=body).status_code == 409
    final_attempt = _add_attempt(client)

    for bad in ({"ratings": {"effort": 52}, "trigger": "finished_button"},
                {"ratings": FULL, "trigger": "instructor"},
                {"ratings": FULL, "trigger": "finished_button", "extra": 1}):
        assert client.post(url, headers=headers, json=bad).status_code in (400, 422)
    assert _count(client) == 0

    opened = (datetime.now(timezone.utc) - timedelta(minutes=2)).isoformat()
    saved = client.post(url, headers=headers, json={**body, "opened_at": opened})
    assert saved.status_code == 201, saved.text
    assert saved.json()["answered"] == 6
    again = client.post(url, headers=headers, json=body)
    assert again.status_code == 409
    assert client.get(url, headers=headers).json() == {
        "offered": True, "completed": True, "has_attempt": True, "form": None}

    with client.app.state.SessionLocal() as session:
        row = session.scalars(select(WorkloadSurvey)).one()
        assert row.final_attempt_id == final_attempt
        assert row.feedback_mode == "tdd" and row.trigger == "finished_button"
        assert row.opened_at is not None and row.form_version == "tlx-raw-1"

    instructor = _instructor(client)
    rows = client.get("/admin/study-data/workload_tlx", headers=instructor).json()["rows"]
    assert len(rows) == 1
    assert rows[0]["raw_tlx"] == 42.5 and rows[0]["performance"] == 30
    assert rows[0]["participant_code"] == "P-001"
    assert rows[0]["performance_direction"] == "0 = good, 100 = poor"
    csv_text = client.get("/admin/study-data/workload_tlx", params={"format": "csv"},
                          headers=instructor).text
    assert "42.5" in csv_text and STUDENT_LOGIN not in csv_text


def test_partial_answers_are_kept_without_a_raw_score(client):
    headers, _user = _login(client, STUDENT_LOGIN, STUDENT_PASSWORD)
    url = f"/assignments/{_wall_id(client)}/workload-survey"
    _add_attempt(client)
    long_ago = (datetime.now(timezone.utc) - timedelta(hours=5)).isoformat()
    saved = client.post(url, headers=headers, json={
        "ratings": {"mental_demand": 60, "frustration": 20},
        "trigger": "full_pass_prompt", "opened_at": long_ago})
    assert saved.status_code == 201 and saved.json()["answered"] == 2
    rows = client.get("/admin/study-data/workload_tlx",
                      headers=_instructor(client)).json()["rows"]
    assert rows[0]["raw_tlx"] is None and rows[0]["answered"] == 2
    # A browser time outside the hour before submitting is not kept.
    assert rows[0]["opened_at"] in ("", None)


def test_access_rules(client):
    url = f"/assignments/{_wall_id(client)}/workload-survey"
    body = {"ratings": FULL, "trigger": "finished_button"}
    assert client.get(url).status_code == 401
    assert client.post(url, json=body).status_code == 401

    instructor = _instructor(client)
    assert client.get(url, headers=instructor).json()["offered"] is False
    assert client.post(url, headers=instructor, json=body).status_code == 403

    demo = client.post("/auth/demo")
    assert demo.status_code == 200
    demo_headers = {"Authorization": f"Bearer {demo.json()['token']}"}
    assert client.get(url, headers=demo_headers).json()["offered"] is False
    assert client.post(url, headers=demo_headers, json=body).status_code == 403

    headers, _user = _login(client, STUDENT_LOGIN, STUDENT_PASSWORD)
    # Only the study assignments have a survey.
    assert client.get("/assignments/1/workload-survey", headers=headers).status_code == 404
    assert _count(client) == 0
