"""Instructor insights count real students once each and never identify them."""
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy.orm import sessionmaker

from assignment_insights import assignment_insights
from database import Base, build_engine
from models import Assignment, LearningEvent, StudySession, Submission, User

START = datetime(2026, 11, 18, 9, 0, tzinfo=timezone.utc)


def check(test_id, passed, hint_key=None, tag=None):
    return {"test_id": test_id, "label": test_id.title(), "passed": passed,
            "hint_key": hint_key, "misconception_tag": tag}


@pytest.fixture
def session():
    engine = build_engine("sqlite://")
    Base.metadata.create_all(engine)
    with sessionmaker(bind=engine, expire_on_commit=False)() as value:
        value.add(Assignment(id=7, stable_id="ros2-wall-stop", version=3, title="A7"))
        for user_id, role, demo in (("s1", "student", False), ("s2", "student", False),
                                    ("demo", "student", True), ("teach", "instructor", False)):
            value.add(User(id=user_id, login_id=user_id, password_hash="x", role=role, is_demo=demo))
        value.commit()
        yield value


def attempt(session, user_id, minutes, passed, tests, version=3):
    session.add(Submission(
        assignment_id=7, assignment_version=version, student_id=user_id, user_id=user_id,
        code="", passed=passed, created_at=START + timedelta(minutes=minutes),
        evidence={"tests": tests},
    ))


def test_insights_summarise_students_not_demo_or_instructor(session):
    late = check("stop", False, "stops-too-late")
    early = check("drive", False, "stops-too-early", "stops-too-early")
    attempt(session, "s1", 0, False, [late, check("drive", True)])
    attempt(session, "s1", 12, True, [check("stop", True), check("drive", True)])
    attempt(session, "s2", 5, False, [late, early])
    attempt(session, "s2", 9, False, [late, check("drive", True)])  # latest counts
    attempt(session, "demo", 1, False, [late, early])
    attempt(session, "teach", 1, False, [late, early])
    attempt(session, "s2", 1, True, [check("stop", True)], version=2)  # old version
    session.add(StudySession(id="study", user_id="s2", client_session_id="client"))
    session.flush()
    for user_id, outcome in (("s2", "collided"), ("s2", "collided"), ("demo", "stopped")):
        session.add(LearningEvent(
            study_session_id="study", user_id=user_id, assignment_id=7,
            assignment_version=3, event_type="simulation_run",
            event_data={"outcome": outcome, "duration_seconds": 8.0},
        ))
    session.commit()

    result = assignment_insights(session, session.get(Assignment, 7))
    assert result["students_attempted"] == 2
    assert result["students_passed"] == 1
    assert result["attempts"] == 4
    assert result["median_attempts_to_pass"] == 2
    assert result["median_minutes_to_pass"] == 12.0
    assert result["checks"] == [{"test_id": "stop", "label": "Stop", "students_failing": 1}]
    assert result["observed_patterns"] == [{"hint_key": "stops-too-late", "students": 1}]
    assert result["misconceptions"] == []
    assert result["simulation_outcomes"] == [{"outcome": "collided", "runs": 2}]
    text = str(result)
    for private in ("s1", "s2", "demo", "teach"):
        assert f"'{private}'" not in text

    previous = assignment_insights(session, session.get(Assignment, 7), version=2)
    assert previous["students_attempted"] == 1 and previous["students_passed"] == 1
