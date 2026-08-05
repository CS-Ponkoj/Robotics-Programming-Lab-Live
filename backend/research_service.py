import csv
import io
from collections import defaultdict
from datetime import datetime
from typing import Any, Iterable

from sqlalchemy import select
from sqlalchemy.orm import Session

from models import LearningEvent, StudySession, Submission, User, utc_now


AUTOMATIC_EVENT_TYPES = {
    "assignment_run",
    "assignment_submitted",
    "hint_requested",
    "solution_revealed",
}


def participant_label(user: User) -> str:
    """Return a research-safe identifier without exposing the login ID."""
    value = (user.participant_code or "").strip()
    return value or f"UNASSIGNED-{user.id[:8].upper()}"


def get_user_study_session(
    session: Session, study_session_id: str | None, user: User
) -> StudySession | None:
    if not study_session_id:
        return None
    return session.scalar(
        select(StudySession).where(
            StudySession.id == study_session_id,
            StudySession.user_id == user.id,
        )
    )


def record_learning_event(
    session: Session,
    *,
    study_session: StudySession,
    user: User,
    event_type: str,
    assignment_id: int | None = None,
    assignment_version: int | None = None,
    event_data: dict[str, Any] | None = None,
    client_occurred_at: datetime | None = None,
    commit: bool = True,
) -> LearningEvent:
    event = LearningEvent(
        study_session_id=study_session.id,
        user_id=user.id,
        assignment_id=assignment_id,
        assignment_version=assignment_version,
        event_type=event_type,
        event_data=event_data or {},
        client_occurred_at=client_occurred_at,
    )
    session.add(event)
    if commit:
        session.commit()
        session.refresh(event)
    return event


def _submission_rows(session: Session) -> list[tuple[Submission, User]]:
    submissions = session.scalars(
        select(Submission).order_by(Submission.created_at)
    ).all()
    users = {
        user.id: user
        for user in session.scalars(select(User).where(User.role == "student")).all()
    }
    users_by_login = {user.login_id: user for user in users.values()}
    result = []
    for submission in submissions:
        user = users.get(submission.user_id) or users_by_login.get(
            submission.student_id
        )
        if user is not None:
            result.append((submission, user))
    return result


def build_research_dataset(session: Session) -> dict[str, list[dict[str, Any]]]:
    students = session.scalars(
        select(User).where(User.role == "student").order_by(User.created_at)
    ).all()
    study_sessions = session.scalars(
        select(StudySession).order_by(StudySession.started_at)
    ).all()
    events = session.scalars(
        select(LearningEvent).order_by(LearningEvent.created_at)
    ).all()
    submission_rows = _submission_rows(session)

    sessions_by_user: dict[str, list[StudySession]] = defaultdict(list)
    events_by_user: dict[str, list[LearningEvent]] = defaultdict(list)
    submissions_by_user: dict[str, list[Submission]] = defaultdict(list)
    for item in study_sessions:
        sessions_by_user[item.user_id].append(item)
    for item in events:
        events_by_user[item.user_id].append(item)
    for submission, user in submission_rows:
        submissions_by_user[user.id].append(submission)

    summary_rows: list[dict[str, Any]] = []
    for user in students:
        user_submissions = submissions_by_user[user.id]
        user_events = events_by_user[user.id]
        scores = [item.score for item in user_submissions]
        completed = {item.assignment_id for item in user_submissions if item.passed}
        summary_rows.append(
            {
                "participant_code": participant_label(user),
                "account_active": user.is_active,
                "study_sessions": len(sessions_by_user[user.id]),
                "active_seconds": sum(
                    item.active_seconds for item in sessions_by_user[user.id]
                ),
                "attempts": len(user_submissions),
                "assignments_completed": len(completed),
                "average_score": round(sum(scores) / len(scores), 1) if scores else 0,
                "best_score": max(scores, default=0),
                "hints_requested": sum(
                    item.event_type == "hint_requested" for item in user_events
                ),
                "solutions_revealed": sum(
                    item.event_type == "solution_revealed" for item in user_events
                ),
                "ai_tutor_uses": sum(
                    item.event_type in {"assignment_run", "assignment_submitted"}
                    and bool(item.event_data.get("ai_tutor_requested"))
                    for item in user_events
                ),
                "last_activity_at": _latest_activity(
                    sessions_by_user[user.id], user_submissions, user_events
                ),
            }
        )

    attempt_rows = [
        {
            "participant_code": participant_label(user),
            "submission_id": submission.id,
            "study_session_id": submission.study_session_id or "",
            "assignment_id": submission.assignment_id,
            "assignment_version": submission.assignment_version,
            "mode": submission.mode,
            "execution_succeeded": submission.execution_succeeded,
            "passed": submission.passed,
            "score": submission.score,
            "created_at": submission.created_at,
        }
        for submission, user in submission_rows
    ]

    users_by_id = {user.id: user for user in students}
    event_rows = []
    for event in events:
        user = users_by_id.get(event.user_id)
        if user is None:
            continue
        event_rows.append(
            {
                "participant_code": participant_label(user),
                "event_id": event.id,
                "study_session_id": event.study_session_id,
                "assignment_id": event.assignment_id or "",
                "assignment_version": event.assignment_version or "",
                "event_type": event.event_type,
                "event_data": event.event_data,
                "client_occurred_at": event.client_occurred_at or "",
                "created_at": event.created_at,
            }
        )
    return {
        "student_summary": summary_rows,
        "assignment_attempts": attempt_rows,
        "learning_events": event_rows,
    }


def student_research_payload(session: Session, user: User) -> dict[str, Any]:
    dataset = build_research_dataset(session)
    label = participant_label(user)
    summary = next(
        (
            row
            for row in dataset["student_summary"]
            if row["participant_code"] == label
        ),
        {
            "participant_code": label,
            "account_active": user.is_active,
            "study_sessions": 0,
            "active_seconds": 0,
            "attempts": 0,
            "assignments_completed": 0,
            "average_score": 0,
            "best_score": 0,
            "hints_requested": 0,
            "solutions_revealed": 0,
            "ai_tutor_uses": 0,
            "last_activity_at": None,
        },
    )
    return {
        "summary": summary,
        "attempts": [
            row
            for row in dataset["assignment_attempts"]
            if row["participant_code"] == label
        ],
        "events": [
            row
            for row in dataset["learning_events"]
            if row["participant_code"] == label
        ],
    }


def csv_bytes(rows: Iterable[dict[str, Any]]) -> bytes:
    values = list(rows)
    if not values:
        return b""
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=list(values[0].keys()))
    writer.writeheader()
    for row in values:
        writer.writerow({key: _export_value(value) for key, value in row.items()})
    return output.getvalue().encode("utf-8-sig")


def xlsx_bytes(dataset: dict[str, list[dict[str, Any]]]) -> bytes:
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Font, PatternFill

    workbook = Workbook()
    workbook.remove(workbook.active)
    for sheet_name, rows in dataset.items():
        sheet = workbook.create_sheet(_sheet_title(sheet_name))
        if not rows:
            sheet.append(["No records"])
            continue
        headers = list(rows[0].keys())
        sheet.append(headers)
        for cell in sheet[1]:
            cell.font = Font(bold=True, color="FFFFFF")
            cell.fill = PatternFill("solid", fgColor="1C6B52")
            cell.alignment = Alignment(horizontal="center")
        for row in rows:
            sheet.append([_export_value(row.get(header)) for header in headers])
        sheet.freeze_panes = "A2"
        sheet.auto_filter.ref = sheet.dimensions
        for column in sheet.columns:
            width = min(36, max(12, max(len(str(cell.value or "")) for cell in column) + 2))
            sheet.column_dimensions[column[0].column_letter].width = width
    output = io.BytesIO()
    workbook.save(output)
    return output.getvalue()


def _latest_activity(
    sessions: list[StudySession],
    submissions: list[Submission],
    events: list[LearningEvent],
) -> datetime | None:
    timestamps = [item.last_active_at for item in sessions]
    timestamps.extend(item.created_at for item in submissions)
    timestamps.extend(item.created_at for item in events)
    return max(timestamps, default=None)


def _export_value(value: Any) -> Any:
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, (dict, list)):
        import json

        return json.dumps(value, sort_keys=True, separators=(",", ":"))
    if isinstance(value, str) and value[:1] in {"=", "+", "-", "@"}:
        return "'" + value
    return value


def _sheet_title(value: str) -> str:
    return " ".join(word.capitalize() for word in value.split("_"))[:31]
