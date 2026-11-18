"""Who may use the AI tutor, for which assignment, and how often.

AI tutoring stays an optional enhancement. A student gets an AI answer only when
every gate holds; otherwise the built-in hints answer and the student is told
why in plain words. The order of the gates is also the order of the messages.

1. A key is configured on the server (never sent to the browser).
2. An instructor switched AI tutoring on for the course.
3. The assignment's instructor-authored evaluation cases are approved by a
   named instructor for this assignment version.
4. The student has not used today's quota (counted in UTC).
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, time, timezone
from functools import lru_cache

from sqlalchemy import select
from sqlalchemy.orm import Session

from config import Settings
from course_settings import AiTutorSettings, get_setting
from instructor_dataset import ReviewStatus, load_instructor_datasets
from models import Assignment, HintInteraction, Submission, User

NOT_ENABLED = "Not enabled for this course. Built-in hints still work."
NOT_REVIEWED = (
    "Not available for this assignment yet: an instructor is still reviewing "
    "its AI test cases. Built-in hints still work."
)
DEMO = "Not available in the demo. Built-in hints still work."
QUOTA = (
    "You have used today's AI tutor questions. Built-in hints still work, and "
    "the AI tutor is back tomorrow."
)


@dataclass(frozen=True)
class AiAccess:
    allowed: bool
    reason: str = ""
    message: str = ""
    remaining_today: int | None = None


@lru_cache(maxsize=1)
def approved_assignments() -> frozenset[tuple[int, int]]:
    """(assignment id, version) pairs whose evaluation cases are all approved."""
    try:
        datasets = load_instructor_datasets()
    except (OSError, ValueError):
        return frozenset()
    return frozenset(
        (dataset.assignment_id, dataset.assignment_version)
        for dataset in datasets
        if dataset.review_status == ReviewStatus.APPROVED
        and all(
            case.review_status == ReviewStatus.APPROVED and case.reviewer
            for case in dataset.cases
        )
    )


def ai_uses_today(session: Session, user: User, now: datetime | None = None) -> int:
    """AI answers this student received today, from stored hint interactions."""
    now = now or datetime.now(timezone.utc)
    start = datetime.combine(now.date(), time.min, tzinfo=timezone.utc)
    rows = session.scalars(
        select(HintInteraction.feedback)
        .join(Submission, Submission.id == HintInteraction.submission_id)
        .where(Submission.user_id == user.id, HintInteraction.created_at >= start)
    )
    return sum(1 for feedback in rows if isinstance(feedback, dict) and feedback.get("source") == "openai")


def ai_access(
    settings: Settings,
    session: Session,
    assignment: Assignment,
    user: User,
    *,
    demo: bool = False,
    count_quota: bool = True,
) -> AiAccess:
    if not settings.openai_api_key:
        return AiAccess(False, "no_key", NOT_ENABLED)
    course = get_setting(session, AiTutorSettings)
    if not course.enabled:
        return AiAccess(False, "course_off", NOT_ENABLED)
    if (assignment.id, assignment.version) not in approved_assignments():
        return AiAccess(False, "not_reviewed", NOT_REVIEWED)
    if demo:
        return AiAccess(False, "demo", DEMO)
    if not count_quota:
        return AiAccess(True)
    remaining = course.daily_limit - ai_uses_today(session, user)
    if remaining <= 0:
        return AiAccess(False, "quota", QUOTA, remaining_today=0)
    return AiAccess(True, remaining_today=remaining)
