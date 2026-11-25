"""One participant's study sessions, each as a timeline of what happened.

A study session starts when the student signs in (or the browser starts a
research session). Records that store their session (test runs and learning
events) are placed in it; records that do not (hints, quiz and pre-test
attempts, NASA-TLX responses) are placed in the latest session that started
at or before them. Anything earlier than every session is listed under
"Outside a recorded session". Submitted code is never included.
"""

from __future__ import annotations

from bisect import bisect_right
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from analytics_service import participant_label
from models import (
    Assignment,
    CourseQuizAttempt,
    HintInteraction,
    LearningEvent,
    StudySession,
    Submission,
    User,
    WorkloadSurvey,
)
from research_service import csv_bytes
from study_checks import behavior_summary
from workload_survey import KEYS as TLX_KEYS, raw_tlx

NO_SESSION = "outside"

# Events already shown with richer detail from their own records.
_SKIPPED_EVENTS = {"assignment_run", "assignment_submitted", "hint_requested"}

_EVENT_LABELS = {
    "assignment_opened": "Opened assignment",
    "ai_tutor_toggled": "AI switch",
    "workspace_tab_changed": "Changed tab",
    "workspace_file_selected": "Opened file",
    "solution_revealed": "Solution revealed",
    "simulation_run": "Simulation",
}

TIMELINE_COLUMNS = (
    ("time", "Time (UTC)"),
    ("activity", "Activity"),
    ("assignment", "Assignment"),
    ("result", "Result"),
    ("details", "Details"),
    ("attempt_id", "Attempt"),
)


def _aware(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    return value if value.tzinfo else value.replace(tzinfo=timezone.utc)


def _iso(value: datetime | None) -> str:
    moment = _aware(value)
    return moment.astimezone(timezone.utc).isoformat(timespec="seconds") if moment else ""


def _clip(text: Any, limit: int = 400) -> str:
    value = " ".join(str(text or "").split())
    return value if len(value) <= limit else value[: limit - 1] + "…"


def _assignment_labels(session: Session) -> tuple[dict[int, str], dict[int, str]]:
    from assignment_repository import course_numbers

    numbers = course_numbers()
    labels: dict[int, str] = {}
    stable: dict[int, str] = {}
    for assignment in session.scalars(select(Assignment)).all():
        number = numbers.get(assignment.stable_id)
        labels[assignment.id] = (
            f"Assignment {number}" if number else f"Old assignment (ID {assignment.id})"
        )
        stable[assignment.id] = assignment.stable_id
    return labels, stable


def _run_item(item: Submission, label: str, stable_id: str) -> dict[str, Any]:
    tests = (item.evidence or {}).get("tests") or []
    passed = sum(1 for test in tests if test.get("passed") is True)
    behavior = behavior_summary(stable_id, item.assignment_version, tests,
                                item.execution_succeeded)
    details = [f"Checks {passed}/{len(tests)}"]
    if behavior:
        details.append(f"behavior {behavior[0]}/{behavior[1]}"
                       + (" (full behavior pass)" if behavior[2] else ""))
    details.append(f"status {item.execution_status or ''}".strip())
    details.append(f"mode {item.feedback_mode or ''}".strip())
    return {
        "time": item.created_at,
        "activity": "Test run" if item.mode == "submit" else f"Run ({item.mode})",
        "assignment": label,
        "result": f"{item.score}%" + (" passed" if item.passed else ""),
        "details": ", ".join(details),
        "attempt_id": item.id,
    }


def _hint_item(hint: HintInteraction, submission: Submission, label: str) -> dict[str, Any]:
    feedback = hint.feedback or {}
    kind = feedback.get("interaction_type")
    source = "AI" if feedback.get("source") == "openai" else "Built-in"
    question = str(feedback.get("student_question") or "")
    shown = feedback.get("answer") if question else feedback.get("hint")
    if kind == "student_question":
        activity, details = "Tutor question", f'Q: "{_clip(question, 300)}" A: {_clip(shown)}'
    elif kind == "run_hint":
        activity, details = "Automatic hint", _clip(shown)
    else:
        activity, details = "Hint button", _clip(shown)
    return {
        "time": hint.created_at,
        "activity": activity,
        "assignment": label,
        "result": f"level {hint.hint_level}, {source}",
        "details": details,
        "attempt_id": submission.id,
    }


def _event_item(event: LearningEvent, label: str) -> dict[str, Any]:
    data = event.event_data or {}
    if event.event_type == "simulation_run":
        result = str(data.get("outcome") or "")
        details = f"{data.get('duration_seconds', '')} s replay"
    elif event.event_type == "ai_tutor_toggled":
        result = "on" if data.get("enabled") else "off"
        details = ""
    else:
        result = ""
        details = ", ".join(
            f"{key} {value}" for key, value in data.items()
            if key in {"tab", "path", "source", "submission_id"} and value not in (None, "")
        )
    return {
        "time": event.created_at,
        "activity": _EVENT_LABELS.get(event.event_type, event.event_type.replace("_", " ")),
        "assignment": label if event.assignment_id is not None else "",
        "result": result,
        "details": _clip(details),
        "attempt_id": str(data.get("submission_id") or ""),
    }


def _quiz_item(attempt: CourseQuizAttempt, number: int) -> dict[str, Any]:
    kind = "Pre-test" if attempt.assessment == "pretest" else "Quiz"
    scored = attempt.assessment == "pretest" or number == 1
    return {
        "time": attempt.submitted_at,
        "activity": kind if attempt.assessment == "pretest" else f"Quiz attempt {number}",
        "assignment": attempt.topic_id,
        "result": f"{attempt.score_percent}% ({attempt.correct_count}/{attempt.total_questions})",
        "details": "scored" if scored else "practice retake (not scored)",
        "attempt_id": attempt.id,
    }


def _tlx_item(survey: WorkloadSurvey, label: str) -> dict[str, Any]:
    ratings = {key: getattr(survey, key) for key in TLX_KEYS}
    raw = raw_tlx(ratings)
    shown = ", ".join(
        f"{key.replace('_demand', '').replace('_', ' ')} "
        f"{'-' if value is None else value}"
        for key, value in ratings.items()
    )
    return {
        "time": survey.submitted_at,
        "activity": "NASA-TLX",
        "assignment": label,
        "result": f"Raw TLX {raw}" if raw is not None else "Raw TLX not computed (unrated scales)",
        "details": f"{shown}; shown by {survey.trigger}",
        "attempt_id": survey.final_attempt_id or "",
    }


def participant_sessions(session: Session, user: User) -> dict[str, Any]:
    """Every study session of one student, each with its ordered timeline."""
    labels, stable = _assignment_labels(session)
    sessions = session.scalars(
        select(StudySession).where(StudySession.user_id == user.id)
        .order_by(StudySession.started_at, StudySession.id)
    ).all()
    starts = [_aware(item.started_at) for item in sessions]
    ids = {item.id for item in sessions}
    timelines: dict[str, list[dict[str, Any]]] = {item.id: [] for item in sessions}
    timelines[NO_SESSION] = []

    def place(item: dict[str, Any], session_id: str | None = None) -> None:
        if session_id in ids:
            timelines[session_id].append(item)
            return
        index = bisect_right(starts, _aware(item["time"])) - 1
        timelines[sessions[index].id if index >= 0 else NO_SESSION].append(item)

    submissions = session.scalars(
        select(Submission).where(Submission.user_id == user.id)
        .order_by(Submission.created_at)
    ).all()
    by_id = {item.id: item for item in submissions}
    for item in submissions:
        place(_run_item(item, labels.get(item.assignment_id, ""),
                        stable.get(item.assignment_id, "")), item.study_session_id)
    if by_id:
        for hint in session.scalars(
            select(HintInteraction).where(HintInteraction.submission_id.in_(list(by_id)))
        ).all():
            owner = by_id[hint.submission_id]
            place(_hint_item(hint, owner, labels.get(owner.assignment_id, "")))
    for event in session.scalars(
        select(LearningEvent).where(LearningEvent.user_id == user.id)
    ).all():
        if event.event_type in _SKIPPED_EVENTS:
            continue
        place(_event_item(event, labels.get(event.assignment_id, "")),
              event.study_session_id)
    numbers: dict[tuple[str, str, str], int] = {}
    for attempt in session.scalars(
        select(CourseQuizAttempt).where(CourseQuizAttempt.user_id == user.id)
        .order_by(CourseQuizAttempt.submitted_at, CourseQuizAttempt.id)
    ).all():
        key = (attempt.topic_id, attempt.assessment, attempt.quiz_version)
        numbers[key] = numbers.get(key, 0) + 1
        place(_quiz_item(attempt, numbers[key]))
    for survey in session.scalars(
        select(WorkloadSurvey).where(WorkloadSurvey.user_id == user.id)
    ).all():
        place(_tlx_item(survey, labels.get(survey.assignment_id, "")))

    def finish(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
        items.sort(key=lambda row: _aware(row["time"]))
        return [{**row, "time": _iso(row["time"])} for row in items]

    result = []
    for number, item in enumerate(sessions, start=1):
        rows = finish(timelines[item.id])
        result.append({
            "session_id": item.id,
            "number": number,
            "started_at": _iso(item.started_at),
            "last_active_at": _iso(item.last_active_at),
            "ended_at": _iso(item.ended_at),
            "active_seconds": item.active_seconds,
            "activity_count": len(rows),
            "rows": rows,
        })
    outside = finish(timelines[NO_SESSION])
    return {
        "participant": {
            "id": user.id,
            "participant_code": participant_label(user),
            "login_id": user.login_id,
            "feedback_mode": user.feedback_mode or "",
            "active": bool(user.is_active),
        },
        "columns": [{"key": key, "label": label} for key, label in TIMELINE_COLUMNS],
        "sessions": result,
        "outside_sessions": outside,
    }


def participant_sessions_csv(payload: dict[str, Any]) -> bytes:
    """One row per timeline item, with its session's details in front."""
    person = payload["participant"]
    header = ["participant_code", "login_id", "feedback_mode", "session_number",
              "session_started_at", "session_last_active_at", "session_ended_at",
              "session_active_seconds", *(key for key, _ in TIMELINE_COLUMNS)]
    records = []
    groups = [*payload["sessions"]]
    if payload["outside_sessions"]:
        groups.append({"number": "", "started_at": "", "last_active_at": "",
                       "ended_at": "", "active_seconds": "",
                       "rows": payload["outside_sessions"]})
    for group in groups:
        for row in group["rows"]:
            records.append({
                "participant_code": person["participant_code"],
                "login_id": person["login_id"],
                "feedback_mode": person["feedback_mode"],
                "session_number": group["number"],
                "session_started_at": group["started_at"],
                "session_last_active_at": group["last_active_at"],
                "session_ended_at": group["ended_at"],
                "session_active_seconds": group["active_seconds"],
                **{key: row.get(key, "") for key, _ in TIMELINE_COLUMNS},
            })
    if not records:
        return (",".join(header) + chr(13) + chr(10)).encode("utf-8-sig")
    return csv_bytes(records)
