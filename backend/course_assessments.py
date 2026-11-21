"""Course pre-test and quiz results for instructors and research exports.

The learning measure for a topic is its quiz's FIRST submitted attempt (taken
before the student has seen any correct answers) compared with the topic's
one-attempt pre-test. Later quiz attempts are practice and are reported, but
never replace the first score.
"""

from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from models import CourseQuizAttempt, User


def _attempts(session: Session, user: User) -> list[CourseQuizAttempt]:
    return list(session.scalars(
        select(CourseQuizAttempt)
        .where(CourseQuizAttempt.user_id == user.id)
        .order_by(CourseQuizAttempt.submitted_at, CourseQuizAttempt.id)
    ).all())


def course_assessment_rows(
    session: Session, user: User, participant_code: str
) -> list[dict[str, Any]]:
    """One row per pre-test or quiz attempt, oldest first, with each answer."""
    rows = []
    numbers: dict[tuple[str, str, str], int] = {}
    for attempt in _attempts(session, user):
        key = (attempt.topic_id, attempt.assessment, attempt.quiz_version)
        numbers[key] = numbers.get(key, 0) + 1
        answers = attempt.answers or []
        rows.append({
            "participant_code": participant_code,
            "topic_id": attempt.topic_id,
            "assessment": attempt.assessment,
            "quiz_version": attempt.quiz_version,
            "attempt_number": numbers[key],
            # The pre-test has one attempt; a quiz counts only its first.
            "scored": numbers[key] == 1,
            "feedback_mode": attempt.feedback_mode,
            "correct_count": attempt.correct_count,
            "total_questions": attempt.total_questions,
            "score_percent": attempt.score_percent,
            "choices": ",".join(item["choice"] for item in answers) or None,
            "correct_pattern": "".join("1" if item["correct"] else "0" for item in answers) or None,
            "submitted_at": attempt.submitted_at.isoformat(),
            "data_schema_version": attempt.data_schema_version,
        })
    return rows


def course_learning_summary(
    session: Session, user: User, participant_code: str
) -> list[dict[str, Any]]:
    """Per topic: pre-test score, first-attempt quiz score, and the difference."""
    topics: dict[str, dict[str, Any]] = {}
    for attempt in _attempts(session, user):
        entry = topics.setdefault(attempt.topic_id, {
            "participant_code": participant_code,
            "topic_id": attempt.topic_id,
            "pretest_score": None,
            "quiz_score": None,
            "quiz_version": None,
            "learning_gain": None,
            "quiz_attempts": 0,
            "best_quiz_score": None,
            "feedback_mode": None,
        })
        if attempt.assessment == "pretest":
            if entry["pretest_score"] is None:
                entry["pretest_score"] = attempt.score_percent
            continue
        entry["quiz_attempts"] += 1
        entry["best_quiz_score"] = max(entry["best_quiz_score"] or 0, attempt.score_percent)
        if entry["quiz_score"] is None:
            entry["quiz_score"] = attempt.score_percent
            entry["quiz_version"] = attempt.quiz_version
            entry["feedback_mode"] = attempt.feedback_mode
    for entry in topics.values():
        if entry["pretest_score"] is not None and entry["quiz_score"] is not None:
            entry["learning_gain"] = entry["quiz_score"] - entry["pretest_score"]
    return sorted(topics.values(), key=lambda entry: entry["topic_id"])
