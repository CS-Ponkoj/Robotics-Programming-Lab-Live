"""The AI tutor answers only when every gate holds, and says why when not."""
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest
from sqlalchemy.orm import sessionmaker

import ai_policy
from ai_policy import ai_access, ai_uses_today
from config import Settings
from course_settings import AiTutorSettings, get_setting, set_setting
from database import Base, build_engine
from models import Assignment, HintInteraction, Submission, User
from tutor import TutorService


@pytest.fixture
def session():
    engine = build_engine("sqlite://")
    Base.metadata.create_all(engine)
    with sessionmaker(bind=engine, expire_on_commit=False)() as value:
        value.add(Assignment(id=7, stable_id="ros2-wall-stop", version=3, title="A7"))
        value.add(User(id="u1", login_id="student", password_hash="x", role="student"))
        value.add(User(id="u2", login_id="other", password_hash="x", role="student"))
        value.commit()
        yield value


def settings(key="sk-test"):
    return Settings(database_url="sqlite://", openai_api_key=key)


def record_ai_answer(session, user_id, when, source="openai"):
    submission = Submission(
        assignment_id=7, assignment_version=3, student_id=user_id, user_id=user_id, code=""
    )
    session.add(submission)
    session.flush()
    session.add(
        HintInteraction(
            submission_id=submission.id, hint_level=1,
            feedback={"source": source}, created_at=when,
        )
    )
    session.commit()


@pytest.fixture
def approved(monkeypatch):
    monkeypatch.setattr(ai_policy, "approved_assignments", lambda: frozenset({(7, 3)}))


def test_gates_apply_in_order_with_student_words(session, monkeypatch):
    assignment, user = session.get(Assignment, 7), session.get(User, "u1")
    assert ai_access(settings(None), session, assignment, user).reason == "no_key"
    assert ai_access(settings(), session, assignment, user).message == ai_policy.NOT_ENABLED
    set_setting(session, AiTutorSettings(enabled=True, daily_limit=2), user=None)
    monkeypatch.setattr(ai_policy, "approved_assignments", lambda: frozenset())
    assert ai_access(settings(), session, assignment, user).reason == "not_reviewed"
    monkeypatch.setattr(ai_policy, "approved_assignments", lambda: frozenset({(7, 2)}))
    # Approval belongs to one assignment version; a new version needs review.
    assert ai_access(settings(), session, assignment, user).reason == "not_reviewed"
    monkeypatch.setattr(ai_policy, "approved_assignments", lambda: frozenset({(7, 3)}))
    assert ai_access(settings(), session, assignment, user, demo=True).reason == "demo"
    access = ai_access(settings(), session, assignment, user)
    assert access.allowed and access.remaining_today == 2


def test_daily_quota_counts_only_this_students_ai_answers_today(session, approved):
    assignment, user = session.get(Assignment, 7), session.get(User, "u1")
    set_setting(session, AiTutorSettings(enabled=True, daily_limit=2), user=None)
    now = datetime.now(timezone.utc)
    record_ai_answer(session, "u1", now)
    record_ai_answer(session, "u1", now, source="fallback")  # built-in hint: free
    record_ai_answer(session, "u1", now - timedelta(days=1))  # yesterday: free
    record_ai_answer(session, "u2", now)  # another student
    assert ai_uses_today(session, user) == 1
    assert ai_access(settings(), session, assignment, user).remaining_today == 1
    record_ai_answer(session, "u1", now)
    blocked = ai_access(settings(), session, assignment, user)
    assert (blocked.allowed, blocked.reason, blocked.message) == (False, "quota", ai_policy.QUOTA)


def test_course_setting_defaults_and_rejects_bad_values(session):
    assert get_setting(session, AiTutorSettings) == AiTutorSettings()
    assert AiTutorSettings().enabled is False
    with pytest.raises(ValueError):
        AiTutorSettings(enabled=True, daily_limit=0)
    with pytest.raises(ValueError):
        AiTutorSettings(enabled=True, daily_limit=5, extra=1)


def test_unavailable_ai_still_answers_with_built_in_hints_and_says_why():
    assignment = SimpleNamespace(language="python", grader_type="python_function")
    submission = SimpleNamespace(code="", evidence={"execution_succeeded": True, "tests": []})
    feedback = TutorService(settings()).feedback(
        assignment, submission, student_question="Why?",
        use_ai_tutor=False, ai_unavailable_message=ai_policy.QUOTA,
    )
    assert feedback.source == "fallback"
    assert feedback.answer == f"AI tutor: {ai_policy.QUOTA}"
    assert feedback.hint
