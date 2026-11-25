"""Instructor "Study data" tables: everything the app collects, row by row.

Each table is built from the stored records with the same filters, sorted,
paged for the screen, or written whole as CSV. Rows carry the participant
code and, by owner decision (2026-11-25), the student's login ID, and never
carry passwords, tokens, hidden tests, answers,
grader settings, or submitted code (code is viewable one attempt at a time
in the app, never in a table or a CSV).
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone
from typing import Any, Callable, Iterable

from sqlalchemy import select
from sqlalchemy.orm import Session

from analytics_service import participant_label, student_analytics_payload
from assignment_repository import course_numbers
from course_assessments import course_assessment_rows, course_learning_summary
from models import (
    Assignment,
    CourseQuizAttempt,
    AssignmentActivity,
    AuditEvent,
    AuthSession,
    HintInteraction,
    LearningEvent,
    PageFeedback,
    StudySession,
    Submission,
    User,
    WorkloadSurvey,
)
from research_service import csv_bytes
from study_checks import behavior_checks, behavior_summary, check_group
from workload_survey import KEYS as TLX_KEYS, PERFORMANCE_DIRECTION, raw_tlx

# The owner's shared test logins and the seeded demo row. They are hidden
# unless the instructor asks to include test accounts.
TEST_ACCOUNT_LOGIN_IDS = frozenset({"traditional", "tdd", "ai", "student"})
TEST_PARTICIPANT_CODES = frozenset({"DEMO"})

# A safety bound on any one table; a study is far below it.
MAX_TABLE_ROWS = 200_000


class TableTooLarge(Exception):
    """A CSV would exceed MAX_TABLE_ROWS; it is refused, never cut short."""

NOT_RUN_PREFIXES = ("Not run:", "Not checked:")

# Audit detail keys that are safe to show; login IDs and emails are dropped.
SAFE_AUDIT_DETAIL_KEYS = frozenset({
    "feedback_mode", "from", "to", "active", "enabled", "daily_limit",
    "created", "updated", "errors", "role", "participant_code",
    # Study data downloads: the filters used (no participant identity).
    "assignment_id", "date_from", "date_to", "one_participant",
    "include_test_accounts",
})

INTERACTION_LABELS = {
    "run_hint": "Automatic hint after a run",
    "progressive_hint": "Hint button",
    "student_question": "Question to the tutor",
}

SOURCE_LABELS = {"openai": "AI", "fallback": "Built-in"}


@dataclass(frozen=True)
class Column:
    key: str
    label: str
    help: str


@dataclass(frozen=True)
class Filters:
    student_id: str | None = None
    assignment_id: int | None = None
    feedback_mode: str | None = None
    date_from: date | None = None
    date_to: date | None = None
    include_test_accounts: bool = False


@dataclass(frozen=True)
class Table:
    name: str
    title: str
    description: str
    columns: tuple[Column, ...]
    time_key: str
    build: Callable[["_Context"], Iterable[dict[str, Any]]]
    has_assignment: bool = False
    # False for whole-study summaries: the date filter does not apply to them.
    has_dates: bool = True


def is_test_account(user: User) -> bool:
    return (
        user.login_id in TEST_ACCOUNT_LOGIN_IDS
        or (user.participant_code or "").strip() in TEST_PARTICIPANT_CODES
    )


class _Context:
    """Students in scope plus lookups shared by every table builder."""

    def __init__(self, session: Session, filters: Filters):
        self.session = session
        self.filters = filters
        query = select(User).where(User.role == "student", User.is_demo.is_(False))
        if filters.student_id:
            query = query.where(User.id == filters.student_id)
        users = session.scalars(query.order_by(User.created_at)).all()
        if not filters.include_test_accounts:
            users = [user for user in users if not is_test_account(user)]
        self.users = {user.id: user for user in users}
        self.user_ids = list(self.users)
        numbers = course_numbers()
        self.assignments: dict[int, str] = {}
        self.course_assignment_ids: set[int] = set()
        self.stable_ids: dict[int, str] = {}
        for assignment in session.scalars(select(Assignment)).all():
            self.stable_ids[assignment.id] = assignment.stable_id
            number = numbers.get(assignment.stable_id)
            if number:
                self.course_assignment_ids.add(assignment.id)
            self.assignments[assignment.id] = (
                f"Assignment {number}" if number else f"Old assignment (ID {assignment.id})"
            )
        self.start = (
            datetime.combine(filters.date_from, time.min, tzinfo=timezone.utc)
            if filters.date_from
            else None
        )
        self.end = (
            datetime.combine(filters.date_to + timedelta(days=1), time.min, tzinfo=timezone.utc)
            if filters.date_to
            else None
        )

    def code(self, user_id: str | None) -> str:
        user = self.users.get(user_id or "")
        return participant_label(user) if user else ""

    def account_mode(self, user_id: str | None) -> str:
        user = self.users.get(user_id or "")
        return (user.feedback_mode or "") if user else ""

    def assignment(self, assignment_id: int | None) -> str:
        if assignment_id is None:
            return ""
        return self.assignments.get(assignment_id, f"ID {assignment_id}")

    def in_range(self, value: datetime | None) -> bool:
        if value is None:
            return self.start is None and self.end is None
        moment = value if value.tzinfo else value.replace(tzinfo=timezone.utc)
        if self.start and moment < self.start:
            return False
        if self.end and moment >= self.end:
            return False
        return True

    def keep(self, *, mode: str | None, assignment_id: int | None = None,
             when: datetime | None = None, has_assignment: bool = False) -> bool:
        filters = self.filters
        if filters.feedback_mode and (mode or "") != filters.feedback_mode:
            return False
        if has_assignment and filters.assignment_id is not None:
            if assignment_id != filters.assignment_id:
                return False
        return self.in_range(when)


def _aware(value: datetime) -> datetime:
    """Stored times are UTC; SQLite returns them without a zone."""
    return value if value.tzinfo else value.replace(tzinfo=timezone.utc)


def iso_utc(value: datetime | None) -> str:
    if value is None:
        return ""
    return _aware(value).astimezone(timezone.utc).isoformat(timespec="seconds")


def _submissions(ctx: _Context) -> list[Submission]:
    if not ctx.user_ids:
        return []
    query = select(Submission).where(Submission.user_id.in_(ctx.user_ids))
    if ctx.filters.assignment_id is not None:
        query = query.where(Submission.assignment_id == ctx.filters.assignment_id)
    return ctx.session.scalars(query.order_by(Submission.created_at)).all()


def _points_earned(test: dict[str, Any]) -> float | None:
    """Credit the check actually gave.

    The grader stores earned_weight only when it differs from the plain rule
    (0 for setup checks held back until a driving check passes); otherwise a
    passed check earns its weight and any other check earns nothing.
    """
    weight = test.get("weight")
    if weight is None:
        return None
    if test.get("earned_weight") is not None:
        return float(test["earned_weight"])
    return float(weight) if test.get("passed") is True else 0.0


def _check_result(test: dict[str, Any]) -> str:
    if test.get("passed") is True:
        return "passed"
    if str(test.get("message") or "").startswith(NOT_RUN_PREFIXES):
        return "not run"
    return "failed"


# --- Table builders -------------------------------------------------------


def _participants(ctx: _Context):
    keys = ("attempts", "tutor_questions", "hint_button", "automatic_hints",
            "hints_type_not_recorded", "ai_answers")
    counts: dict[str, dict[str, int]] = {uid: dict.fromkeys(keys, 0) for uid in ctx.user_ids}
    for item in _submissions(ctx):
        counts[item.user_id]["attempts"] += 1
    # Requested help and automatic hints are counted apart: an automatic hint
    # after a run is exposure, not a request.
    kind_keys = {
        "student_question": "tutor_questions",
        "progressive_hint": "hint_button",
        "run_hint": "automatic_hints",
    }
    for interaction, user_id in _interactions(ctx):
        feedback = interaction.feedback or {}
        kind = kind_keys.get(feedback.get("interaction_type"), "hints_type_not_recorded")
        counts[user_id][kind] += 1
        if feedback.get("source") == "openai":
            counts[user_id]["ai_answers"] += 1
    for user in ctx.users.values():
        if ctx.filters.feedback_mode and user.feedback_mode != ctx.filters.feedback_mode:
            continue
        yield {
            "participant_code": participant_label(user),
            "feedback_mode": user.feedback_mode or "",
            "active": user.is_active,
            "test_account": is_test_account(user),
            "created_at": iso_utc(user.created_at),
            "last_sign_in": iso_utc(user.last_login_at),
            **counts[user.id],
        }


def _sign_ins(ctx: _Context):
    if not ctx.user_ids:
        return
    rows = ctx.session.scalars(
        select(AuthSession).where(AuthSession.user_id.in_(ctx.user_ids))
    ).all()
    for item in rows:
        mode = ctx.account_mode(item.user_id)
        if not ctx.keep(mode=mode, when=item.created_at):
            continue
        yield {
            "participant_code": ctx.code(item.user_id),
            "feedback_mode": mode,
            "signed_in_at": iso_utc(item.created_at),
            "last_used_at": iso_utc(item.last_used_at),
            "signed_out_at": iso_utc(item.revoked_at),
            "expires_at": iso_utc(item.expires_at),
            "device": item.device or "",
        }


def _study_sessions(ctx: _Context):
    if not ctx.user_ids:
        return
    rows = ctx.session.scalars(
        select(StudySession).where(StudySession.user_id.in_(ctx.user_ids))
    ).all()
    for item in rows:
        mode = ctx.account_mode(item.user_id)
        if not ctx.keep(mode=mode, when=item.started_at):
            continue
        yield {
            "participant_code": ctx.code(item.user_id),
            "feedback_mode": mode,
            "study_session_id": item.id,
            "started_at": iso_utc(item.started_at),
            "last_active_at": iso_utc(item.last_active_at),
            "ended_at": iso_utc(item.ended_at),
            "active_seconds": item.active_seconds,
        }


def _assignment_time(ctx: _Context):
    if not ctx.user_ids:
        return
    rows = ctx.session.scalars(
        select(AssignmentActivity).where(AssignmentActivity.user_id.in_(ctx.user_ids))
    ).all()
    # First attempt per student, assignment and version in which every
    # behavior check passed (study RQ4), oldest first.
    first_full: dict[tuple[str, int, int], Submission] = {}
    for submission in _submissions(ctx):
        key = (submission.user_id, submission.assignment_id, submission.assignment_version)
        if key in first_full:
            continue
        summary = behavior_summary(
            ctx.stable_ids.get(submission.assignment_id, ""),
            submission.assignment_version,
            (submission.evidence or {}).get("tests"),
            submission.execution_succeeded,
        )
        if summary is not None and summary[2]:
            first_full[key] = submission
    for item in rows:
        mode = ctx.account_mode(item.user_id)
        mapped = bool(behavior_checks(
            ctx.stable_ids.get(item.assignment_id, ""), item.assignment_version
        ))
        full = first_full.get((item.user_id, item.assignment_id, item.assignment_version))
        clock = None
        if full is not None and item.first_active_at is not None:
            # Rounded like the assignment summary's elapsed time.
            clock = max(0, round((_aware(full.created_at) - _aware(item.first_active_at))
                                 .total_seconds()))
        if not ctx.keep(mode=mode, assignment_id=item.assignment_id,
                        when=item.first_active_at, has_assignment=True):
            continue
        yield {
            "participant_code": ctx.code(item.user_id),
            "feedback_mode": mode,
            "assignment": ctx.assignment(item.assignment_id),
            "assignment_id": item.assignment_id,
            "assignment_version": item.assignment_version,
            "first_active_at": iso_utc(item.first_active_at),
            "last_active_at": iso_utc(item.last_active_at),
            "active_seconds": item.active_seconds,
            "first_completed_at": iso_utc(item.first_completed_at),
            "active_seconds_to_completion": item.active_seconds_to_completion,
            "full_behavior_pass_at": iso_utc(full.created_at if full else None),
            "seconds_to_full_behavior_pass": clock,
            "active_seconds_to_full_behavior_pass": (
                full.active_seconds_at_attempt if full else None
            ),
            "behavior_checks_mapped": mapped,
        }


def _attempts(ctx: _Context):
    numbers: dict[tuple[str, int], int] = {}
    for item in _submissions(ctx):
        key = (item.user_id, item.assignment_id)
        numbers[key] = numbers.get(key, 0) + 1
        if not ctx.keep(mode=item.feedback_mode, assignment_id=item.assignment_id,
                        when=item.created_at, has_assignment=True):
            continue
        tests = (item.evidence or {}).get("tests") or []
        behavior = behavior_summary(
            ctx.stable_ids.get(item.assignment_id, ""), item.assignment_version,
            tests, item.execution_succeeded,
        )
        yield {
            "participant_code": ctx.code(item.user_id),
            "feedback_mode": item.feedback_mode or "",
            "assignment": ctx.assignment(item.assignment_id),
            "assignment_id": item.assignment_id,
            "assignment_version": item.assignment_version,
            "attempt_number": numbers[key],
            "attempt_id": item.id,
            "run_type": item.mode,
            "score": item.score,
            "passed": item.passed,
            "execution_status": item.execution_status or "",
            "checks_passed": sum(1 for test in tests if test.get("passed") is True),
            "checks_total": len(tests),
            "behavior_checks_passed": behavior[0] if behavior else None,
            "behavior_checks_total": behavior[1] if behavior else None,
            "full_behavior_pass": behavior[2] if behavior else None,
            "active_seconds_at_attempt": item.active_seconds_at_attempt,
            "created_at": iso_utc(item.created_at),
        }


def _check_results(ctx: _Context):
    for item in _submissions(ctx):
        if not ctx.keep(mode=item.feedback_mode, assignment_id=item.assignment_id,
                        when=item.created_at, has_assignment=True):
            continue
        for test in (item.evidence or {}).get("tests") or []:
            yield {
                "participant_code": ctx.code(item.user_id),
                "feedback_mode": item.feedback_mode or "",
                "assignment": ctx.assignment(item.assignment_id),
                "assignment_id": item.assignment_id,
                "assignment_version": item.assignment_version,
                "attempt_id": item.id,
                "created_at": iso_utc(item.created_at),
                "check_id": str(test.get("test_id") or ""),
                "check": str(test.get("label") or ""),
                "check_group": check_group(
                    ctx.stable_ids.get(item.assignment_id, ""),
                    item.assignment_version,
                    str(test.get("test_id") or ""),
                ),
                "result": _check_result(test),
                "points_earned": _points_earned(test),
                "points_possible": test.get("weight"),
                "reason": str(test.get("reason") or ""),
                "mistake_label": str(test.get("misconception_tag") or ""),
                "hint_key": str(test.get("hint_key") or ""),
                "message": str(test.get("message") or ""),
            }


def _interactions(ctx: _Context) -> list[tuple[HintInteraction, str]]:
    if not ctx.user_ids:
        return []
    query = (
        select(HintInteraction, Submission.user_id)
        .join(Submission, Submission.id == HintInteraction.submission_id)
        .where(Submission.user_id.in_(ctx.user_ids))
    )
    if ctx.filters.assignment_id is not None:
        query = query.where(Submission.assignment_id == ctx.filters.assignment_id)
    return list(ctx.session.execute(query.order_by(HintInteraction.created_at)).all())


def _answer_text(feedback: dict[str, Any]) -> str:
    parts = []
    for key, label in (
        ("answer", "Answer"),
        ("diagnosis", "Diagnosis"),
        ("hint", "Hint"),
        ("guiding_question", "Question"),
        ("next_action", "Next step"),
    ):
        value = str(feedback.get(key) or "").strip()
        if value:
            parts.append(f"{label}: {value}")
    steps = [str(step).strip() for step in feedback.get("debugging_steps") or [] if str(step).strip()]
    if steps:
        parts.append("Steps: " + " / ".join(steps))
    return "\n".join(parts)


def _ai_questions_and_hints(ctx: _Context):
    if not ctx.user_ids:
        return
    query = (
        select(HintInteraction, Submission)
        .join(Submission, Submission.id == HintInteraction.submission_id)
        .where(Submission.user_id.in_(ctx.user_ids))
    )
    if ctx.filters.assignment_id is not None:
        query = query.where(Submission.assignment_id == ctx.filters.assignment_id)
    for interaction, submission in ctx.session.execute(
        query.order_by(HintInteraction.created_at)
    ).all():
        if not ctx.keep(mode=submission.feedback_mode,
                        assignment_id=submission.assignment_id,
                        when=interaction.created_at, has_assignment=True):
            continue
        feedback = interaction.feedback or {}
        kind = feedback.get("interaction_type")
        yield {
            "participant_code": ctx.code(submission.user_id),
            "feedback_mode": submission.feedback_mode or "",
            "assignment": ctx.assignment(submission.assignment_id),
            "assignment_id": submission.assignment_id,
            "assignment_version": submission.assignment_version,
            "attempt_id": submission.id,
            "attempt_score": submission.score,
            "asked_at": iso_utc(interaction.created_at),
            "type": INTERACTION_LABELS.get(kind, "Hint (type not recorded)"),
            "hint_level": interaction.hint_level,
            "source": SOURCE_LABELS.get(str(feedback.get("source") or ""), ""),
            "student_question": str(feedback.get("student_question") or ""),
            "answer_shown": _answer_text(feedback),
            "mistake_label": str(feedback.get("misconception") or ""),
            "ai_model": str(feedback.get("ai_model") or ""),
            "ai_model_snapshot": str(feedback.get("ai_model_snapshot") or ""),
            "prompt_version": str(feedback.get("prompt_version") or ""),
            "prompt_sha256": str(feedback.get("prompt_sha256") or ""),
            "fallback_reason": str(feedback.get("fallback_reason") or ""),
            "fallback_detail": str(feedback.get("fallback_detail") or ""),
        }


def _learning_events(ctx: _Context):
    if not ctx.user_ids:
        return
    query = select(LearningEvent).where(LearningEvent.user_id.in_(ctx.user_ids))
    if ctx.filters.assignment_id is not None:
        query = query.where(LearningEvent.assignment_id == ctx.filters.assignment_id)
    events = ctx.session.scalars(query.order_by(LearningEvent.created_at)).all()
    submission_ids = {
        str((event.event_data or {}).get("submission_id"))
        for event in events
        if (event.event_data or {}).get("submission_id")
    }
    modes = {}
    if submission_ids:
        modes = dict(ctx.session.execute(
            select(Submission.id, Submission.feedback_mode)
            .where(Submission.id.in_(submission_ids))
        ).all())
    for event in events:
        data = event.event_data or {}
        if data.get("feedback_mode"):
            mode, mode_source = data["feedback_mode"], "recorded with the event"
        elif modes.get(str(data.get("submission_id"))):
            mode, mode_source = modes[str(data["submission_id"])], "from its attempt"
        else:
            mode = ctx.account_mode(event.user_id)
            mode_source = "account's current mode" if mode else ""
        if not ctx.keep(mode=mode, assignment_id=event.assignment_id,
                        when=event.created_at, has_assignment=True):
            continue
        yield {
            "participant_code": ctx.code(event.user_id),
            "feedback_mode": mode,
            "mode_source": mode_source,
            "event_type": event.event_type,
            "assignment": ctx.assignment(event.assignment_id),
            "assignment_id": event.assignment_id or "",
            "assignment_version": event.assignment_version or "",
            "details": data,
            "study_session_id": event.study_session_id,
            "created_at": iso_utc(event.created_at),
            "client_occurred_at": iso_utc(event.client_occurred_at),
        }


def _quiz_rows(ctx: _Context):
    for user in ctx.users.values():
        for row in course_assessment_rows(ctx.session, user, participant_label(user)):
            yield user, row


def _quiz_attempts(ctx: _Context):
    for _user, row in _quiz_rows(ctx):
        when = datetime.fromisoformat(row["submitted_at"])
        if not ctx.keep(mode=row["feedback_mode"], when=when):
            continue
        yield {key: value for key, value in row.items()
               if key not in {"choices", "correct_pattern"}}


def _quiz_answers(ctx: _Context):
    if not ctx.user_ids:
        return
    attempts = ctx.session.scalars(
        select(CourseQuizAttempt)
        .where(CourseQuizAttempt.user_id.in_(ctx.user_ids))
        .order_by(CourseQuizAttempt.submitted_at, CourseQuizAttempt.id)
    ).all()
    numbers: dict[tuple[str, str, str, str], int] = {}
    for attempt in attempts:
        key = (attempt.user_id, attempt.topic_id, attempt.assessment, attempt.quiz_version)
        numbers[key] = numbers.get(key, 0) + 1
        if not ctx.keep(mode=attempt.feedback_mode, when=attempt.submitted_at):
            continue
        for index, answer in enumerate(attempt.answers or []):
            yield {
                "participant_code": ctx.code(attempt.user_id),
                "feedback_mode": attempt.feedback_mode or "",
                "topic_id": attempt.topic_id,
                "assessment": attempt.assessment,
                "quiz_version": attempt.quiz_version,
                "attempt_id": attempt.id,
                "attempt_number": numbers[key],
                # The pre-test has one attempt; a quiz counts only its first.
                "scored": numbers[key] == 1,
                "question_number": index + 1,
                "question_id": str(answer.get("question_id") or ""),
                "choice": str(answer.get("choice") or ""),
                "correct": answer.get("correct") is True,
                "submitted_at": iso_utc(attempt.submitted_at),
            }


def _course_learning(ctx: _Context):
    for user in ctx.users.values():
        if ctx.filters.feedback_mode and user.feedback_mode != ctx.filters.feedback_mode:
            continue
        for row in course_learning_summary(ctx.session, user, participant_label(user)):
            yield {"feedback_mode": user.feedback_mode or "", **row}


def _assignment_summary(ctx: _Context):
    for user in ctx.users.values():
        if ctx.filters.feedback_mode and user.feedback_mode != ctx.filters.feedback_mode:
            continue
        payload = student_analytics_payload(ctx.session, user)
        for row in payload["assignment_summaries"]:
            if ctx.filters.assignment_id is not None:
                if row.get("assignment_id") != ctx.filters.assignment_id:
                    continue
            elif row.get("assignment_id") not in ctx.course_assignment_ids:
                # Old assignments would inflate "not started" counts; pick one
                # in the Assignment filter to see it.
                continue
            yield {
                "participant_code": participant_label(user),
                "feedback_mode": user.feedback_mode or "",
                "assignment": ctx.assignment(row.get("assignment_id")),
                **row,
            }


def _instructor_actions(ctx: _Context):
    query = select(AuditEvent).where(~AuditEvent.action.startswith("auth."))
    events = ctx.session.scalars(query.order_by(AuditEvent.created_at)).all()
    actor_ids = {event.actor_user_id for event in events if event.actor_user_id}
    resource_ids = {event.resource_id for event in events
                    if event.resource_type == "user" and event.resource_id}
    attempt_ids = {event.resource_id for event in events
                   if event.resource_type == "submission" and event.resource_id}
    attempt_owners = {}
    if attempt_ids:
        attempt_owners = dict(ctx.session.execute(
            select(Submission.id, Submission.user_id).where(Submission.id.in_(attempt_ids))
        ).all())
        resource_ids |= set(attempt_owners.values())
    people = {}
    if actor_ids | resource_ids:
        people = {user.id: user for user in ctx.session.scalars(
            select(User).where(User.id.in_(actor_ids | resource_ids))
        ).all()}
    for event in events:
        if not ctx.in_range(event.created_at):
            continue
        if event.resource_type == "user":
            about = people.get(event.resource_id or "")
        elif event.resource_type == "submission":
            about = people.get(attempt_owners.get(event.resource_id or "", ""))
        else:
            about = None
        if about is not None and about.role == "student":
            if about.id not in ctx.users:
                continue
            about_label = participant_label(about)
            if event.resource_type == "submission":
                about_label += " (attempt " + (event.resource_id or "")[:8] + ")"
        elif about is not None:
            about_label = f"{about.role} account"
        elif event.resource_type == "study_data_table":
            about_label = f"{event.resource_id} table"
        else:
            about_label = event.resource_type
        if ctx.filters.student_id and (about is None or about.id != ctx.filters.student_id):
            continue
        actor = people.get(event.actor_user_id or "")
        if actor is None:
            actor_label = "system"
        elif actor.role == "instructor":
            actor_label = actor.login_id
        else:
            actor_label = participant_label(actor)
        details = {key: value for key, value in (event.details or {}).items()
                   if key in SAFE_AUDIT_DETAIL_KEYS}
        yield {
            "created_at": iso_utc(event.created_at),
            "action": event.action,
            "done_by": actor_label,
            "about": about_label,
            "details": details,
        }


def _workload_tlx(ctx: _Context):
    if not ctx.user_ids:
        return
    query = select(WorkloadSurvey).where(WorkloadSurvey.user_id.in_(ctx.user_ids))
    if ctx.filters.assignment_id is not None:
        query = query.where(WorkloadSurvey.assignment_id == ctx.filters.assignment_id)
    for item in ctx.session.scalars(query.order_by(WorkloadSurvey.submitted_at)).all():
        if not ctx.keep(mode=item.feedback_mode, assignment_id=item.assignment_id,
                        when=item.submitted_at, has_assignment=True):
            continue
        ratings = {key: getattr(item, key) for key in TLX_KEYS}
        yield {
            "participant_code": ctx.code(item.user_id),
            "feedback_mode": item.feedback_mode or "",
            "assignment": ctx.assignment(item.assignment_id),
            "assignment_id": item.assignment_id,
            "assignment_version": item.assignment_version,
            **ratings,
            "raw_tlx": raw_tlx(ratings),
            "answered": sum(value is not None for value in ratings.values()),
            "trigger": item.trigger,
            "opened_at": iso_utc(item.opened_at),
            "submitted_at": iso_utc(item.submitted_at),
            "final_attempt_id": item.final_attempt_id or "",
            "form_version": item.form_version,
            "performance_direction": PERFORMANCE_DIRECTION,
        }


def _page_feedback(ctx: _Context):
    rows = ctx.session.scalars(select(PageFeedback).order_by(PageFeedback.created_at)).all()
    for item in rows:
        if item.user_id and item.user_id not in ctx.users and item.sender_role == "student":
            continue
        if ctx.filters.student_id and item.user_id != ctx.filters.student_id:
            continue
        if not ctx.in_range(item.created_at):
            continue
        yield {
            "created_at": iso_utc(item.created_at),
            "participant_code": ctx.code(item.user_id),
            "sender_role": item.sender_role or "",
            "page": item.page or "",
            "category": item.category or "",
            "message": item.message or "",
            "status": item.status or "",
        }


# --- Table catalog --------------------------------------------------------

_P = Column("participant_code", "Participant", "Research code of the student.")
_LOGIN = Column("login_id", "Login ID", "The student's sign-in name (shown by owner decision, 2026-11-25).")
_M = Column("feedback_mode", "Mode", "Feedback mode: traditional, tdd, or tdd_ai.")
_A = Column("assignment", "Assignment", "The number students see; older assignments show their ID.")
_AID = Column("assignment_id", "Assignment ID", "Stable internal ID used in every record.")
_V = Column("assignment_version", "Version", "Assignment version the student worked on.")

TABLES: tuple[Table, ...] = (
    Table("participants", "Participants",
          "One row per student account with its mode and activity counts.",
          (_P, _M,
           Column("active", "Active", "Whether the account can sign in."),
           Column("test_account", "Test account", "Owner test or demo login."),
           Column("created_at", "Created", "When the account was created (UTC)."),
           Column("last_sign_in", "Last sign-in", "Most recent sign-in (UTC)."),
           Column("attempts", "Attempts", "Run Tests presses (scored attempts)."),
           Column("tutor_questions", "Tutor questions", "Questions typed to the tutor, whether AI or built-in answered."),
           Column("hint_button", "Hint button", "Hints the student asked for with the Hint button."),
           Column("automatic_hints", "Automatic hints", "Hints shown automatically after a run (exposure, not a request)."),
           Column("hints_type_not_recorded", "Older hints", "Hints from before 2026-11-24, when the type was not recorded."),
           Column("ai_answers", "AI answers", "Help answers that came from the AI (the rest were built-in).")),
          "created_at", _participants, has_dates=False),
    Table("ai_questions_and_hints", "AI questions and hints",
          "Every question a student asked the tutor and every hint they got, with the answer shown.",
          (_P, _M, _A,
           Column("asked_at", "When", "Time of the hint or question (UTC)."),
           Column("type", "Type", "Hint button or Question to the tutor (automatic hints after a run ended 2026-11-24)."),
           Column("source", "Source", "AI (OpenAI) or Built-in (fallback ladder)."),
           Column("student_question", "Student question", "Exactly what the student typed; recorded from 2026-11-24."),
           Column("answer_shown", "Answer shown", "The text the student saw."),
           Column("hint_level", "Level", "Hint level 1-4."),
           Column("mistake_label", "Mistake label", "Misconception named in the answer, if any."),
           Column("attempt_score", "Attempt score", "Score of that attempt (0-100)."),
           Column("ai_model", "AI model", "Configured model for AI answers; empty for built-in. Recorded from 2026-11-24."),
           Column("ai_model_snapshot", "Model snapshot", "Exact model version the provider reported."),
           Column("prompt_version", "Prompt version", "Tutor prompt version used for the AI answer."),
           Column("prompt_sha256", "Prompt fingerprint", "First 16 hex characters of the SHA-256 of the tutor instructions."),
           Column("fallback_reason", "Why built-in",
                  "For built-in answers: ai_switch_off, ai_policy, no_server_key, protected_request, "
                  "ai_answer_rejected (a safety check refused the AI answer) or provider_error. Recorded from 2026-11-25."),
           Column("fallback_detail", "Built-in detail", "The policy message or error type behind the fallback."),
           _V, _AID,
           Column("attempt_id", "Attempt", "The attempt the hint or question belongs to.")),
          "asked_at", _ai_questions_and_hints, has_assignment=True),
    Table("attempts", "Attempts",
          "Every Run Tests press: score, result, and time spent.",
          (_P, _M, _A, _AID, _V,
           Column("attempt_number", "Attempt no.", "Order of this attempt for the student on this assignment."),
           Column("attempt_id", "Attempt ID", "Open it to see the code in the app."),
           Column("run_type", "Run type", "submit (Run Tests) or run."),
           Column("score", "Score", "0-100."),
           Column("passed", "Passed", "Every required check passed."),
           Column("execution_status", "Status", "completed, syntax_error, runtime_error, timeout, ..."),
           Column("checks_passed", "Checks passed", "Checks that passed."),
           Column("checks_total", "Checks", "Checks in this attempt."),
           Column("behavior_checks_passed", "Behavior passed", "Behavior checks that passed (empty if the version has no check groups)."),
           Column("behavior_checks_total", "Behavior checks", "Behavior checks of this assignment version."),
           Column("full_behavior_pass", "Full behavior pass", "The run executed and every behavior check passed."),
           Column("active_seconds_at_attempt", "Active seconds", "Active time on the assignment before this attempt."),
           Column("created_at", "When", "Time of the attempt (UTC).")),
          "created_at", _attempts, has_assignment=True),
    Table("check_results", "Check results",
          "One row per check in every attempt: passed, failed, or not run.",
          (_P, _M, _A, _AID, _V,
           Column("attempt_id", "Attempt", "The attempt this check belongs to."),
           Column("created_at", "When", "Time of the attempt (UTC)."),
           Column("check_id", "Check ID", "Stable check identifier."),
           Column("check", "Check", "Check name students see."),
           Column("check_group", "Group",
                  "setup, behavior, or code_style (research grouping of the study "
                  "assignments; empty for other assignments)."),
           Column("result", "Result", "passed, failed, or not run."),
           Column("points_earned", "Points", "Points this check gave (0 while setup credit is held back)."),
           Column("points_possible", "Out of", "Points this check is worth."),
           Column("reason", "Reason", "Structured reason the grader gave, if any."),
           Column("mistake_label", "Mistake label", "Misconception tag from grader evidence."),
           Column("hint_key", "Hint key", "Observed pattern that picks the hint ladder."),
           Column("message", "Message", "The check message (what the student saw in TDD modes).")),
          "created_at", _check_results, has_assignment=True),
    Table("learning_events", "Learning events",
          "App actions: opening assignments, runs, Simulate, AI on/off, files, tabs.",
          (_P, _M,
           Column("mode_source", "Mode from", "recorded with the event, from its attempt, or the account's current mode."),
           Column("event_type", "Event", "What happened."),
           _A, _AID, _V,
           Column("details", "Details", "Stored event data."),
           Column("study_session_id", "Study session", "Session the event belongs to."),
           Column("created_at", "When", "Server time (UTC)."),
           Column("client_occurred_at", "Browser time", "Time reported by the browser (UTC).")),
          "created_at", _learning_events, has_assignment=True),
    Table("assignment_time", "Time per assignment",
          "Active time on each assignment and when it was first completed.",
          (_P, _M, _A, _AID, _V,
           Column("first_active_at", "First active", "First activity (UTC)."),
           Column("last_active_at", "Last active", "Latest activity (UTC)."),
           Column("active_seconds", "Active seconds", "Total active time."),
           Column("first_completed_at", "Completed", "First passing attempt (UTC)."),
           Column("active_seconds_to_completion", "Seconds to complete", "Active time until the first pass."),
           Column("full_behavior_pass_at", "Full behavior pass", "First attempt in which every behavior check passed (UTC)."),
           Column("seconds_to_full_behavior_pass", "Seconds to behavior pass",
                  "Clock time from first activity to that attempt; not capped (apply the study's task limit in analysis)."),
           Column("active_seconds_to_full_behavior_pass", "Active seconds to behavior pass",
                  "Active time on the assignment before that attempt."),
           Column("behavior_checks_mapped", "Behavior checks defined",
                  "False when this assignment version has no reviewed check groups, so the behavior columns are empty.")),
          "first_active_at", _assignment_time, has_assignment=True),
    Table("assignment_summary", "Assignment summary",
          "Per student and assignment of this course: attempts, scores, hints, and completion. "
          "Choose an old assignment in the filter to see it.",
          (_P, _M, _A,
           Column("built_in_hint_count", "Built-in hints",
                  "Hint button requests answered by built-in hints (from learning "
                  "events; automatic run hints and tutor questions are not counted)."),
           Column("ai_interaction_count", "AI interactions",
                  "Answers the AI gave: Hint button hints and tutor questions.")),
          "assignment_id", _assignment_summary, has_assignment=True,
          has_dates=False),
    Table("study_sessions", "Study sessions",
          "Each signed-in study session and its active time.",
          (_P, _M,
           Column("study_session_id", "Session", "Session identifier."),
           Column("started_at", "Started", "UTC."),
           Column("last_active_at", "Last active", "UTC."),
           Column("ended_at", "Ended", "UTC."),
           Column("active_seconds", "Active seconds", "Counted from heartbeats while the page is in use.")),
          "started_at", _study_sessions),
    Table("sign_ins", "Sign-ins",
          "Every sign-in with its times and device type.",
          (_P, _M,
           Column("signed_in_at", "Signed in", "UTC."),
           Column("last_used_at", "Last used", "UTC."),
           Column("signed_out_at", "Signed out", "UTC; empty if the session expired instead."),
           Column("expires_at", "Expires", "UTC."),
           Column("device", "Device", "Device type reported by the browser.")),
          "signed_in_at", _sign_ins),
    Table("quiz_attempts", "Quiz and pre-test attempts",
          "Server-graded whole quizzes and pre-tests.",
          (_P, _M,
           Column("topic_id", "Topic", "Course topic."),
           Column("assessment", "Type", "pretest or quiz."),
           Column("quiz_version", "Quiz version", "Exact quiz version."),
           Column("attempt_id", "Attempt ID", "Joins to quiz_answers.attempt_id."),
           Column("attempt_number", "Attempt no.", "Order of this attempt."),
           Column("scored", "Scored", "True for the pre-test and the first quiz attempt."),
           Column("correct_count", "Correct", "Correct answers."),
           Column("total_questions", "Questions", "Questions in the quiz."),
           Column("score_percent", "Score %", "0-100."),
           Column("submitted_at", "When", "UTC."),
           Column("data_schema_version", "Schema", "Record format version.")),
          "submitted_at", _quiz_attempts),
    Table("quiz_answers", "Quiz answers",
          "One row per question in every quiz and pre-test attempt.",
          (_P, _M,
           Column("topic_id", "Topic", "Course topic."),
           Column("assessment", "Type", "pretest or quiz."),
           Column("quiz_version", "Quiz version", "Exact quiz version."),
           Column("attempt_number", "Attempt no.", "Order of this attempt."),
           Column("scored", "Scored", "True for the scored attempt."),
           Column("question_number", "Question", "Question position in the quiz."),
           Column("question_id", "Question ID", "Stable question identifier in this quiz version."),
           Column("choice", "Choice", "The option the student chose."),
           Column("correct", "Correct", "Whether that choice was right."),
           Column("submitted_at", "When", "UTC.")),
          "submitted_at", _quiz_answers),
    Table("course_learning", "Course learning per topic",
          "Pre-test score, first quiz score, and the gain between them (from the correct counts).",
          (_P, _M,
           Column("topic_id", "Topic", "Course topic."),
           Column("pretest_score", "Pre-test %", "The single pre-test attempt."),
           Column("quiz_score", "Quiz % (first)", "The first submitted quiz attempt (the scored one)."),
           Column("learning_gain", "Gain (points)",
                  "Percentage points: first quiz % minus pre-test %, from the correct counts. "
                  "Not a normalized gain."),
           Column("quiz_version", "Quiz version", "Exact quiz version."),
           Column("quiz_attempts", "Quiz attempts", "First attempt plus practice retakes."),
           Column("best_quiz_score", "Best quiz %", "Highest attempt, including retakes (not the score).")),
          "topic_id", _course_learning, has_dates=False),
    Table("instructor_actions", "Instructor actions",
          "Account, mode, and setting changes from the audit log (sign-ins are in Sign-ins).",
          (Column("created_at", "When", "UTC."),
           Column("action", "Action", "What was changed."),
           Column("done_by", "By", "Instructor login, or system."),
           Column("about", "About", "Participant code or the setting changed."),
           Column("details", "Details", "Safe details; login IDs and emails are left out.")),
          "created_at", _instructor_actions),
    Table("workload_tlx", "NASA-TLX workload",
          "Raw NASA-TLX after each study assignment: six ratings and their mean. "
          "Higher is worse on every scale, including Performance (0 = good).",
          (_P, _M, _A,
           Column("mental_demand", "Mental", "0-100, steps of 5."),
           Column("physical_demand", "Physical", "0-100, steps of 5."),
           Column("temporal_demand", "Temporal", "0-100, steps of 5."),
           Column("performance", "Performance", "0 = good, 100 = poor (not reversed)."),
           Column("effort", "Effort", "0-100, steps of 5."),
           Column("frustration", "Frustration", "0-100, steps of 5."),
           Column("raw_tlx", "Raw TLX", "Mean of the six ratings; empty when any is unanswered (never imputed)."),
           Column("answered", "Answered", "How many of the six scales were rated."),
           Column("trigger", "Shown by", "finished_button (I'm finished) or full_pass_prompt (offered at the first full pass)."),
           Column("opened_at", "Opened", "When the form opened (browser time, kept only within the hour before submitting)."),
           Column("submitted_at", "Submitted", "UTC."),
           Column("final_attempt_id", "Final attempt", "The student's latest attempt on this version when they answered."),
           _V, _AID,
           Column("form_version", "Form version", "Survey form version."),
           Column("performance_direction", "Performance scale", "Direction of the Performance scale.")),
          "submitted_at", _workload_tlx, has_assignment=True),
    Table("page_feedback", "Page feedback",
          "Messages sent with the Feedback button.",
          (Column("created_at", "When", "UTC."), _P,
           Column("sender_role", "Sender", "student or instructor."),
           Column("page", "Page", "Where it was sent from."),
           Column("category", "Category", "Bug, suggestion, ..."),
           Column("message", "Message", "What was written."),
           Column("status", "Status", "new or resolved.")),
          "created_at", _page_feedback),
)

TABLES_BY_NAME = {table.name: table for table in TABLES}


def _uniform_time(value: Any) -> Any:
    """Every *_at value as UTC ISO 8601 to the second, like the detail tables."""
    if isinstance(value, datetime):
        return iso_utc(value)
    if isinstance(value, str):
        try:
            return iso_utc(datetime.fromisoformat(value))
        except ValueError:
            return value
    return value


def _sort_key(value: Any) -> tuple:
    if value is None or value == "":
        return (1, "")
    if isinstance(value, bool):
        return (0, int(value))
    if isinstance(value, (int, float)):
        return (0, value)
    return (0, str(value).lower())


def build_rows(session: Session, table: Table, filters: Filters,
               sort: str | None = None, descending: bool = True) -> list[dict[str, Any]]:
    """All rows of one table after filters, sorted (newest first by default)."""
    ctx = _Context(session, filters)
    # Owner decision (2026-11-25): instructors see each student's login ID
    # beside the participant code, on screen and in CSV.
    logins = {participant_label(user): user.login_id for user in ctx.users.values()}
    rows = []
    for row in table.build(ctx):
        if "participant_code" in row:
            row = _with_login(row, logins.get(row["participant_code"], ""))
        rows.append(row)
        if len(rows) >= MAX_TABLE_ROWS:
            break
    for row in rows:
        for name, value in row.items():
            if name.endswith("_at") and value not in (None, ""):
                row[name] = _uniform_time(value)
    key = sort if sort and rows and sort in rows[0] else table.time_key
    if rows and key in rows[0]:
        rows.sort(key=lambda row: _sort_key(row.get(key)), reverse=descending)
        if descending:
            # Keep empty values last in both directions.
            empty = [row for row in rows if row.get(key) in (None, "")]
            rows = [row for row in rows if row.get(key) not in (None, "")] + empty
    return rows


def _with_login(row: dict[str, Any], login_id: str) -> dict[str, Any]:
    """The row with login_id placed right after participant_code."""
    result: dict[str, Any] = {}
    for key, value in row.items():
        result[key] = value
        if key == "participant_code":
            result["login_id"] = login_id
    return result


def table_columns(table: Table, rows: list[dict[str, Any]]) -> list[dict[str, str]]:
    """Declared columns first, then any extra keys the rows carry."""
    declared = []
    for column in table.columns:
        declared.append(column)
        if column.key == "participant_code":
            declared.append(_LOGIN)
    known = {column.key for column in declared}
    extra = []
    if rows:
        for key in rows[0]:
            if key not in known:
                extra.append(Column(key, key.replace("_", " ").capitalize(), ""))
                known.add(key)
    present = set(rows[0]) if rows else known
    return [
        {"key": column.key, "label": column.label, "help": column.help}
        for column in declared + extra
        if column.key in present
    ]


def page_payload(session: Session, table: Table, filters: Filters, *, page: int,
                 page_size: int, sort: str | None, descending: bool) -> dict[str, Any]:
    rows = build_rows(session, table, filters, sort, descending)
    start = (page - 1) * page_size
    return {
        "table": table.name,
        "title": table.title,
        "description": table.description,
        "columns": table_columns(table, rows),
        "rows": rows[start:start + page_size],
        "total": len(rows),
        # True only if the safety bound cut the table short.
        "truncated": len(rows) >= MAX_TABLE_ROWS,
        "page": page,
        "page_size": page_size,
    }


def csv_payload(session: Session, table: Table, filters: Filters,
                sort: str | None, descending: bool) -> bytes:
    rows = build_rows(session, table, filters, sort, descending)
    if len(rows) >= MAX_TABLE_ROWS:
        raise TableTooLarge(table.name)
    columns = [column["key"] for column in table_columns(table, rows)]
    ordered = [{key: row.get(key) for key in columns} for row in rows]
    if not ordered:
        return ",".join(columns).encode("utf-8-sig") + b"\r\n"
    return csv_bytes(ordered)


def catalog_payload(session: Session, include_test_accounts: bool) -> dict[str, Any]:
    """The table list and the students for the participant filter."""
    users = session.scalars(
        select(User)
        .where(User.role == "student", User.is_demo.is_(False))
        .order_by(User.created_at)
    ).all()
    participants = [
        {
            "id": user.id,
            "participant_code": participant_label(user),
            "login_id": user.login_id,
            "feedback_mode": user.feedback_mode or "",
            "test_account": is_test_account(user),
        }
        for user in users
        if include_test_accounts or not is_test_account(user)
    ]
    ctx = _Context(session, Filters(include_test_accounts=True))
    assignments = [
        {"id": assignment_id, "label": label}
        for assignment_id, label in sorted(ctx.assignments.items())
    ]
    return {
        "tables": [
            {"name": table.name, "title": table.title, "description": table.description,
             "has_assignment": table.has_assignment, "has_dates": table.has_dates}
            for table in TABLES
        ],
        "participants": participants,
        "assignments": assignments,
    }
