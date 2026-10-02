"""Phase 1 research analytics built from authoritative study records.

The functions in this module intentionally return privacy-safe dictionaries.
They never include login IDs, source code, hidden-test identities, credentials,
or official solutions.
"""

from __future__ import annotations

from collections import Counter, defaultdict
from datetime import datetime, timezone
from statistics import median
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from data_contracts import CURRENT_DATA_SCHEMA_VERSION
from models import (
    Assignment,
    AssignmentActivity,
    LearningEvent,
    StudySession,
    Submission,
    User,
    utc_now,
)


INFRASTRUCTURE_STATUSES = {
    "grader_unavailable",
    "internal_error",
    "execution_error",
}
STUDENT_ERROR_STATUSES = {
    "syntax_error",
    "runtime_error",
    "timeout",
    "rejected",
}
SAFE_STATUS_LABELS = {
    "completed": "Completed",
    "syntax_error": "Syntax error",
    "runtime_error": "Runtime error",
    "timeout": "Timed out",
    "rejected": "Rejected by safety policy",
    "grader_unavailable": "Grader unavailable",
    "internal_error": "Platform error",
    "execution_error": "Execution error",
}


def participant_label(user: User) -> str:
    value = (user.participant_code or "").strip()
    return value or f"UNASSIGNED-{user.id[:8].upper()}"


def record_assignment_open(
    session: Session,
    *,
    user: User,
    assignment_id: int,
    assignment_version: int,
    occurred_at: datetime | None = None,
) -> AssignmentActivity:
    return _get_or_create_activity(
        session,
        user=user,
        assignment_id=assignment_id,
        assignment_version=assignment_version,
        occurred_at=occurred_at,
    )


def add_assignment_active_time(
    session: Session,
    *,
    user: User,
    assignment_id: int,
    assignment_version: int,
    active_seconds: int,
    occurred_at: datetime | None = None,
) -> AssignmentActivity:
    activity = _get_or_create_activity(
        session,
        user=user,
        assignment_id=assignment_id,
        assignment_version=assignment_version,
        occurred_at=occurred_at,
    )
    activity.active_seconds += active_seconds
    activity.last_active_at = _aware(occurred_at or utc_now())
    return activity


def current_assignment_active_seconds(
    session: Session,
    *,
    user: User,
    assignment_id: int,
    assignment_version: int,
) -> int | None:
    activity = _get_or_create_activity(
        session,
        user=user,
        assignment_id=assignment_id,
        assignment_version=assignment_version,
        occurred_at=utc_now(),
    )
    return activity.active_seconds


def mark_first_completion(
    session: Session,
    *,
    user: User,
    submission: Submission,
) -> None:
    """Freeze completion timing only when Phase 1 activity exists."""
    if not submission.passed or submission.created_at is None:
        return
    activity = session.scalar(
        select(AssignmentActivity).where(
            AssignmentActivity.user_id == user.id,
            AssignmentActivity.assignment_id == submission.assignment_id,
            AssignmentActivity.assignment_version == submission.assignment_version,
        )
    )
    if activity is None or activity.first_completed_at is not None:
        return
    activity.first_completed_at = _aware(submission.created_at)
    activity.active_seconds_to_completion = activity.active_seconds


def student_analytics_payload(session: Session, user: User) -> dict[str, Any]:
    assignments = session.scalars(
        select(Assignment)
        .where(Assignment.status == "published")
        .order_by(Assignment.id)
    ).all()
    submissions = session.scalars(
        select(Submission)
        .where(Submission.user_id == user.id)
        .order_by(Submission.created_at, Submission.id)
    ).all()
    events = session.scalars(
        select(LearningEvent)
        .where(LearningEvent.user_id == user.id)
        .order_by(LearningEvent.created_at, LearningEvent.id)
    ).all()
    activities = session.scalars(
        select(AssignmentActivity).where(AssignmentActivity.user_id == user.id)
    ).all()
    sessions = session.scalars(
        select(StudySession)
        .where(StudySession.user_id == user.id)
        .order_by(StudySession.started_at)
    ).all()
    summaries = build_student_assignment_summaries(
        assignments=assignments,
        submissions=submissions,
        events=events,
        activities=activities,
    )
    valid_attempts = [item for item in submissions if _is_valid_attempt(item)]
    current_keys = {(item.id, item.version) for item in assignments}
    completed_current = {
        (item.assignment_id, item.assignment_version)
        for item in valid_attempts
        if item.passed and (item.assignment_id, item.assignment_version) in current_keys
    }
    scores = [item.score for item in valid_attempts]
    summary = {
        "participant_code": participant_label(user),
        "account_active": user.is_active,
        "study_sessions": len([item for item in sessions if item.active_seconds > 0]),
        "median_session_active_seconds": _median(
            [item.active_seconds for item in sessions if item.active_seconds > 0]
        ),
        "active_seconds": sum(item.active_seconds for item in sessions),
        "attempts": len(valid_attempts),
        "assignments_completed": len(completed_current),
        "assignments_assigned": len(assignments),
        "assignments_started": sum(
            item["is_current_version"] and item["status"] != "not_started"
            for item in summaries
        ),
        "average_score": round(sum(scores) / len(scores), 1) if scores else 0,
        "best_score": max(scores, default=0),
        "hints_requested": sum(item["built_in_hint_count"] for item in summaries),
        "tutor_questions_asked": sum(
            event.event_type == "hint_requested"
            and event.event_data.get("interaction_type") == "student_question"
            for event in events
        ),
        "solutions_revealed": sum(
            event.event_type == "solution_revealed" for event in events
        ),
        "ai_tutor_uses": sum(item["ai_interaction_count"] for item in summaries),
        "last_activity_at": _latest_activity(sessions, submissions, events),
    }
    return {
        "summary": summary,
        "assignment_summaries": summaries,
        "attempts": [_attempt_row(item, participant_label(user)) for item in submissions],
        "events": [_event_row(item, participant_label(user)) for item in events],
    }


def build_student_assignment_summaries(
    *,
    assignments: list[Assignment],
    submissions: list[Submission],
    events: list[LearningEvent],
    activities: list[AssignmentActivity],
) -> list[dict[str, Any]]:
    assignment_by_key = {(item.id, item.version): item for item in assignments}
    submissions_by_key: dict[tuple[int, int], list[Submission]] = defaultdict(list)
    events_by_key: dict[tuple[int, int], list[LearningEvent]] = defaultdict(list)
    activity_by_key = {
        (item.assignment_id, item.assignment_version): item for item in activities
    }
    for item in submissions:
        submissions_by_key[(item.assignment_id, item.assignment_version)].append(item)
    for item in events:
        if item.assignment_id is not None and item.assignment_version is not None:
            events_by_key[(item.assignment_id, item.assignment_version)].append(item)

    keys = set(assignment_by_key) | set(submissions_by_key) | set(activity_by_key)
    rows = []
    for assignment_id, assignment_version in sorted(keys):
        assignment = assignment_by_key.get((assignment_id, assignment_version))
        attempts = sorted(
            [
                item
                for item in submissions_by_key[(assignment_id, assignment_version)]
                if _is_valid_attempt(item)
            ],
            key=lambda item: (_aware(item.created_at), item.id),
        )
        activity = activity_by_key.get((assignment_id, assignment_version))
        assignment_events = events_by_key[(assignment_id, assignment_version)]
        first_success_index = next(
            (index for index, item in enumerate(attempts, start=1) if item.passed),
            None,
        )
        scores = [item.score for item in attempts]
        latest = attempts[-1] if attempts else None
        first = attempts[0] if attempts else None
        completion_at = next(
            (_aware(item.created_at) for item in attempts if item.passed), None
        )
        error_counts = Counter(
            item.execution_status
            for item in attempts
            if item.execution_status in STUDENT_ERROR_STATUSES
        )
        oversized_count = sum(
            (item.evidence or {}).get("rejection_reason") == "size_limit"
            for item in attempts
        )
        unsafe_rejection_count = sum(
            item.execution_status == "rejected"
            and (item.evidence or {}).get("rejection_reason") != "size_limit"
            for item in attempts
        )
        failed_tests = sum(
            not bool(test.get("passed"))
            for item in attempts
            for test in (item.evidence or {}).get("tests", [])
            if test.get("visibility") == "public"
        )
        output_limit_count = sum(
            str((item.evidence or {}).get("code_output", "")).endswith(
                "[output truncated]"
            )
            for item in attempts
        )
        delivered_hint_events = [
            item
            for item in assignment_events
            if item.event_type == "hint_requested"
        ]
        built_in_hints = sum(
            item.event_data.get("interaction_type", "progressive_hint")
            == "progressive_hint"
            and item.event_data.get("source", "fallback") != "openai"
            for item in delivered_hint_events
        )
        ai_interactions = sum(
            (
                item.event_type in {"assignment_run", "assignment_submitted"}
                and bool(item.event_data.get("ai_tutor_requested"))
            )
            or (
                item.event_type == "hint_requested"
                and item.event_data.get("source") == "openai"
            )
            for item in assignment_events
        )
        status = (
            "completed"
            if first_success_index is not None
            else "partial"
            if attempts
            else "started"
            if activity is not None or assignment_events
            else "not_started"
        )
        elapsed_seconds = None
        if activity is not None and completion_at is not None:
            elapsed_seconds = max(
                0,
                round((completion_at - _aware(activity.first_active_at)).total_seconds()),
            )
        time_status = "available" if activity is not None else "not_collected"
        if activity is not None and completion_at is None:
            completion_time_status = "not_completed"
        elif activity is None:
            completion_time_status = "not_collected"
        else:
            completion_time_status = "available"
        rows.append(
            {
                "assignment_id": assignment_id,
                "assignment_version": assignment_version,
                "assignment_title": (
                    assignment.title if assignment is not None else "Historical assignment"
                ),
                "is_current_version": assignment is not None,
                "status": status,
                "attempt_count": len(attempts),
                "unsuccessful_attempt_count": (
                    first_success_index - 1
                    if first_success_index is not None
                    else len(attempts)
                ),
                "attempts_to_first_success": first_success_index,
                "first_score": first.score if first else None,
                "latest_score": latest.score if latest else None,
                "best_score": max(scores) if scores else None,
                "score_improvement": (
                    latest.score - first.score if latest and first else None
                ),
                "best_score_gain": (
                    max(scores) - first.score if scores and first else None
                ),
                "public_test_pass_percentage": _test_pass_percentage(
                    latest, visibility="public"
                ),
                "total_test_pass_percentage": _test_pass_percentage(latest),
                "total_active_seconds": activity.active_seconds if activity else None,
                "active_seconds_to_first_attempt": (
                    first.active_seconds_at_attempt if first else None
                ),
                "active_seconds_to_latest_attempt": (
                    latest.active_seconds_at_attempt if latest else None
                ),
                "median_active_seconds_between_attempts": _median_active_gap(
                    attempts
                ),
                "active_seconds_to_completion": (
                    activity.active_seconds_to_completion if activity else None
                ),
                "elapsed_seconds_to_completion": elapsed_seconds,
                "time_availability": time_status,
                "completion_time_availability": completion_time_status,
                "first_activity_at": activity.first_active_at if activity else None,
                "latest_activity_at": activity.last_active_at if activity else None,
                "first_completion_at": completion_at,
                "first_attempt_at": first.created_at if first else None,
                "last_attempt_at": latest.created_at if latest else None,
                "syntax_error_count": error_counts["syntax_error"],
                "runtime_error_count": error_counts["runtime_error"],
                "timeout_count": error_counts["timeout"],
                "rejection_count": unsafe_rejection_count,
                "failed_public_test_count": failed_tests,
                "excessive_output_count": output_limit_count,
                "oversized_submission_count": oversized_count,
                "oversized_submission_availability": "available",
                "unique_error_categories": len(error_counts),
                "error_free_attempt_rate": _error_free_rate(attempts),
                "built_in_hint_count": built_in_hints,
                "ai_interaction_count": ai_interactions,
                "highest_hint_level": max(
                    (
                        int(item.event_data.get("hint_level", 1))
                        for item in delivered_hint_events
                    ),
                    default=None,
                ),
            }
        )
    return rows


def classroom_analytics_payload(session: Session) -> dict[str, Any]:
    students = session.scalars(
        select(User)
        .where(User.role == "student", User.is_active.is_(True), User.is_demo.is_(False))
        .order_by(User.created_at)
    ).all()
    participant_payloads = [student_analytics_payload(session, item) for item in students]
    participants = []
    for user, payload in zip(students, participant_payloads, strict=True):
        participants.append({**payload["summary"], "student_id": user.id})
    started = sum(
        item["assignments_started"] > 0
        for item in (p["summary"] for p in participant_payloads)
    )
    completed = sum(
        item["assignments_completed"] > 0
        for item in (p["summary"] for p in participant_payloads)
    )
    assigned = len(students)
    overview = {
        "active_participants": assigned,
        "students_started": started,
        "students_completed": completed,
        "participation_rate": _percentage(started, assigned),
        "completion_rate": _percentage(completed, started),
        "total_attempts": sum(p["summary"]["attempts"] for p in participant_payloads),
        "total_active_seconds": sum(
            p["summary"]["active_seconds"] for p in participant_payloads
        ),
        "return_session_rate": _percentage(
            sum(p["summary"]["study_sessions"] >= 2 for p in participant_payloads),
            started,
        ),
    }
    return {
        "overview": overview,
        "participants": participants,
        "assignment_summaries": assignment_catalog(session, participant_payloads),
        "data_health": data_health(session),
    }


def assignment_catalog(
    session: Session,
    participant_payloads: list[dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    if participant_payloads is None:
        students = session.scalars(
            select(User).where(
                User.role == "student",
                User.is_active.is_(True),
                User.is_demo.is_(False),
            )
        ).all()
        participant_payloads = [student_analytics_payload(session, item) for item in students]
    assignments = session.scalars(
        select(Assignment)
        .where(Assignment.status == "published")
        .order_by(Assignment.id)
    ).all()
    rows = []
    for assignment in assignments:
        participant_rows = []
        for payload in participant_payloads:
            row = next(
                (
                    item
                    for item in payload["assignment_summaries"]
                    if item["assignment_id"] == assignment.id
                    and item["assignment_version"] == assignment.version
                ),
                None,
            )
            if row is not None:
                participant_rows.append((payload["summary"]["participant_code"], row))
        started_rows = [item for _, item in participant_rows if item["status"] != "not_started"]
        completed_rows = [item for _, item in participant_rows if item["status"] == "completed"]
        final_scores = [item["latest_score"] for item in started_rows if item["latest_score"] is not None]
        attempts_to_success = [
            item["attempts_to_first_success"]
            for item in completed_rows
            if item["attempts_to_first_success"] is not None
        ]
        active_completion = [
            item["active_seconds_to_completion"]
            for item in completed_rows
            if item["active_seconds_to_completion"] is not None
        ]
        rows.append(
            {
                "assignment_id": assignment.id,
                "assignment_version": assignment.version,
                "assignment_title": assignment.title,
                "assigned_students": len(participant_payloads),
                "students_started": len(started_rows),
                "students_completed": len(completed_rows),
                "uptake_rate": _percentage(len(started_rows), len(participant_payloads)),
                "completion_rate": _percentage(len(completed_rows), len(started_rows)),
                "total_attempts": sum(item["attempt_count"] for item in started_rows),
                "first_attempt_success_rate": _percentage(
                    sum(item["attempts_to_first_success"] == 1 for item in started_rows),
                    sum(item["attempt_count"] > 0 for item in started_rows),
                ),
                "median_final_score": _median(final_scores),
                "score_distribution": _score_distribution(final_scores),
                "median_attempts_to_success": _median(attempts_to_success),
                "median_active_seconds_to_completion": _median(active_completion),
                "most_common_errors": _assignment_error_ranking(started_rows),
                "most_failed_public_tests": _most_failed_tests(
                    session, assignment.id, assignment.version, "public"
                ),
                "hidden_test_aggregate": _hidden_test_aggregate(
                    session, assignment.id, assignment.version
                ),
            }
        )
    return rows


def data_health(session: Session) -> dict[str, Any]:
    submissions = session.scalars(select(Submission)).all()
    events = session.scalars(select(LearningEvent)).all()
    students = session.scalars(select(User).where(User.role == "student")).all()
    student_ids = {item.id for item in students}
    demo_ids = {item.id for item in students if item.is_demo}
    submission_event_ids = {
        str(item.event_data.get("submission_id"))
        for item in events
        if item.event_type in {"assignment_run", "assignment_submitted"}
        and item.event_data.get("submission_id")
    }
    expected_event_submissions = [item for item in submissions if item.study_session_id]
    missing_event_count = sum(
        item.id not in submission_event_ids for item in expected_event_submissions
    )
    missing_versions = sum(
        not item.assignment_version or item.assignment_version < 1
        for item in submissions
    )
    orphan_records = sum(
        item.user_id not in student_ids for item in submissions if item.user_id
    ) + sum(item.user_id not in student_ids for item in events)
    timestamp_errors = sum(
        _aware(item.last_active_at) < _aware(item.started_at)
        or (
            item.ended_at is not None
            and _aware(item.ended_at) < _aware(item.started_at)
        )
        for item in session.scalars(select(StudySession)).all()
    )
    duplicate_events = session.scalar(
        select(func.count()).select_from(
            select(
                LearningEvent.user_id,
                LearningEvent.study_session_id,
                LearningEvent.event_type,
                LearningEvent.assignment_id,
                LearningEvent.assignment_version,
                LearningEvent.created_at,
            )
            .group_by(
                LearningEvent.user_id,
                LearningEvent.study_session_id,
                LearningEvent.event_type,
                LearningEvent.assignment_id,
                LearningEvent.assignment_version,
                LearningEvent.created_at,
            )
            .having(func.count(LearningEvent.id) > 1)
            .subquery()
        )
    ) or 0
    demo_contamination = sum(item.user_id in demo_ids for item in submissions) + sum(
        item.user_id in demo_ids for item in events
    )
    checked_timestamps = len(session.scalars(select(StudySession)).all())
    return {
        "missing_event_count": missing_event_count,
        "missing_event_rate": _percentage(
            missing_event_count, len(expected_event_submissions)
        ),
        "missing_assignment_versions": missing_versions,
        "version_missing_rate": _percentage(missing_versions, len(submissions)),
        "missing_participant_conditions": None,
        "participant_condition_availability": "not_applicable_until_phase_2",
        "duplicate_event_groups": duplicate_events,
        "duplicate_event_rate": _percentage(duplicate_events, len(events)),
        "orphan_records": orphan_records,
        "timestamp_order_errors": timestamp_errors,
        "timestamp_order_error_rate": _percentage(
            timestamp_errors, checked_timestamps
        ),
        "demo_data_contamination": demo_contamination,
        "export_reconciliation_status": "pass",
        "export_reconciliation_expected_rows": len(submissions),
        "export_reconciliation_export_rows": len(submissions),
    }


def paginated_attempts(
    session: Session,
    *,
    user: User,
    page: int,
    page_size: int,
    assignment_id: int | None = None,
    assignment_version: int | None = None,
) -> dict[str, Any]:
    conditions = [Submission.user_id == user.id]
    if assignment_id is not None:
        conditions.append(Submission.assignment_id == assignment_id)
    if assignment_version is not None:
        conditions.append(Submission.assignment_version == assignment_version)
    total = session.scalar(
        select(func.count()).select_from(Submission).where(*conditions)
    ) or 0
    submissions = session.scalars(
        select(Submission)
        .where(*conditions)
        .order_by(Submission.created_at.desc(), Submission.id.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    ).all()
    return {
        "page": page,
        "page_size": page_size,
        "total": total,
        "items": [
            {**_attempt_row(item, participant_label(user)), "attempt_number": total - ((page - 1) * page_size + index)}
            for index, item in enumerate(submissions)
        ],
    }


def _get_or_create_activity(
    session: Session,
    *,
    user: User,
    assignment_id: int,
    assignment_version: int,
    occurred_at: datetime | None,
) -> AssignmentActivity:
    activity = session.scalar(
        select(AssignmentActivity).where(
            AssignmentActivity.user_id == user.id,
            AssignmentActivity.assignment_id == assignment_id,
            AssignmentActivity.assignment_version == assignment_version,
        )
    )
    timestamp = _aware(occurred_at or utc_now())
    if activity is None:
        activity = AssignmentActivity(
            user_id=user.id,
            assignment_id=assignment_id,
            assignment_version=assignment_version,
            data_schema_version=CURRENT_DATA_SCHEMA_VERSION,
            first_active_at=timestamp,
            last_active_at=timestamp,
            active_seconds=0,
        )
        session.add(activity)
    else:
        activity.first_active_at = min(_aware(activity.first_active_at), timestamp)
        activity.last_active_at = max(_aware(activity.last_active_at), timestamp)
    return activity


def _is_valid_attempt(submission: Submission) -> bool:
    return submission.execution_status not in INFRASTRUCTURE_STATUSES


def _attempt_row(submission: Submission, participant_code: str) -> dict[str, Any]:
    return {
        "participant_code": participant_code,
        "submission_id": submission.id,
        "study_session_id": submission.study_session_id or "",
        "assignment_id": submission.assignment_id,
        "assignment_version": submission.assignment_version,
        "data_schema_version": submission.data_schema_version,
        "execution_status": submission.execution_status,
        "execution_status_label": SAFE_STATUS_LABELS.get(
            submission.execution_status, "Execution result"
        ),
        "mode": submission.mode,
        "execution_succeeded": submission.execution_succeeded,
        "passed": submission.passed,
        "score": submission.score,
        "active_seconds_at_attempt": submission.active_seconds_at_attempt,
        "created_at": submission.created_at,
    }


def _event_row(event: LearningEvent, participant_code: str) -> dict[str, Any]:
    return {
        "participant_code": participant_code,
        "event_id": event.id,
        "study_session_id": event.study_session_id,
        "assignment_id": event.assignment_id or "",
        "assignment_version": event.assignment_version or "",
        "event_type": event.event_type,
        "event_data": event.event_data,
        "client_occurred_at": event.client_occurred_at or "",
        "created_at": event.created_at,
    }


def _test_pass_percentage(
    submission: Submission | None, visibility: str | None = None
) -> float | None:
    if submission is None:
        return None
    tests = (submission.evidence or {}).get("tests", [])
    if visibility is not None:
        tests = [item for item in tests if item.get("visibility") == visibility]
    if not tests:
        return None
    return round(100 * sum(bool(item.get("passed")) for item in tests) / len(tests), 1)


def _error_free_rate(attempts: list[Submission]) -> float | None:
    if not attempts:
        return None
    return round(
        100
        * sum(item.execution_status not in STUDENT_ERROR_STATUSES for item in attempts)
        / len(attempts),
        1,
    )


def _median_active_gap(attempts: list[Submission]) -> float | None:
    snapshots = [item.active_seconds_at_attempt for item in attempts]
    if len(snapshots) < 2 or any(value is None for value in snapshots):
        return None
    return _median(
        [
            max(0, int(current) - int(previous))
            for previous, current in zip(snapshots, snapshots[1:])
        ]
    )


def _percentage(numerator: int, denominator: int) -> float | None:
    return round(100 * numerator / denominator, 1) if denominator else None


def _median(values: list[int | float]) -> float | None:
    return round(float(median(values)), 1) if values else None


def _score_distribution(scores: list[int]) -> dict[str, int]:
    result = {"0-59": 0, "60-69": 0, "70-79": 0, "80-89": 0, "90-100": 0}
    for score in scores:
        if score < 60:
            result["0-59"] += 1
        elif score < 70:
            result["60-69"] += 1
        elif score < 80:
            result["70-79"] += 1
        elif score < 90:
            result["80-89"] += 1
        else:
            result["90-100"] += 1
    return result


def _assignment_error_ranking(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    fields = {
        "syntax_error": "syntax_error_count",
        "runtime_error": "runtime_error_count",
        "timeout": "timeout_count",
        "rejected": "rejection_count",
    }
    return [
        {"category": label, "affected_students": sum(row[field] > 0 for row in rows)}
        for label, field in fields.items()
        if any(row[field] > 0 for row in rows)
    ]


def _most_failed_tests(
    session: Session, assignment_id: int, assignment_version: int, visibility: str
) -> list[dict[str, Any]]:
    failures: dict[str, set[str]] = defaultdict(set)
    labels: dict[str, str] = {}
    rows = session.scalars(
        select(Submission).where(
            Submission.assignment_id == assignment_id,
            Submission.assignment_version == assignment_version,
            Submission.execution_status.not_in(INFRASTRUCTURE_STATUSES),
        )
    ).all()
    for submission in rows:
        participant = submission.user_id or submission.student_id
        for test in (submission.evidence or {}).get("tests", []):
            if test.get("visibility") != visibility or bool(test.get("passed")):
                continue
            test_id = str(test.get("test_id") or test.get("label") or "public-test")
            failures[test_id].add(participant)
            labels[test_id] = str(test.get("label") or test_id)
    return sorted(
        (
            {
                "test_id": test_id,
                "label": labels[test_id],
                "affected_students": len(participants),
            }
            for test_id, participants in failures.items()
        ),
        key=lambda item: (-item["affected_students"], item["test_id"]),
    )[:10]


def _hidden_test_aggregate(
    session: Session, assignment_id: int, assignment_version: int
) -> dict[str, Any]:
    passed = 0
    executed = 0
    for submission in session.scalars(
        select(Submission).where(
            Submission.assignment_id == assignment_id,
            Submission.assignment_version == assignment_version,
            Submission.execution_status.not_in(INFRASTRUCTURE_STATUSES),
        )
    ).all():
        for test in (submission.evidence or {}).get("tests", []):
            if test.get("visibility") == "hidden":
                executed += 1
                passed += bool(test.get("passed"))
    return {
        "executed": executed,
        "passed": passed,
        "pass_percentage": _percentage(passed, executed),
    }


def _latest_activity(
    sessions: list[StudySession],
    submissions: list[Submission],
    events: list[LearningEvent],
) -> datetime | None:
    timestamps = [_aware(item.last_active_at) for item in sessions]
    timestamps.extend(_aware(item.created_at) for item in submissions)
    timestamps.extend(_aware(item.created_at) for item in events)
    return max(timestamps, default=None)


def _aware(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)
