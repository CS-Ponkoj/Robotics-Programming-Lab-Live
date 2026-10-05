"""Per-student assignment progress derived from the student's own records.

The browser keeps a local copy of progress per address; this summary lets a
signed-in student see the same history on any browser, device, or address.
"""

from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from models import Assignment, LearningEvent, Submission, User


def student_assignment_progress(session: Session, user: User) -> list[dict]:
    """Summarize every assignment the student has attempted.

    Counts and scores span all assignment versions, matching the browser's own
    progress record. A latest submission is reported only when it belongs to
    the current assignment version, because hints and solution reveals are
    version-scoped.
    """
    owned = Submission.student_id == user.login_id
    totals = session.execute(
        select(
            Submission.assignment_id,
            func.count(Submission.id),
            func.max(Submission.score),
        )
        .where(owned)
        .group_by(Submission.assignment_id)
    ).all()
    if not totals:
        return []

    ranked = (
        select(
            Submission.assignment_id,
            Submission.id,
            Submission.score,
            Submission.assignment_version,
            func.row_number()
            .over(
                partition_by=Submission.assignment_id,
                order_by=(Submission.created_at.desc(), Submission.id.desc()),
            )
            .label("position"),
        )
        .where(owned)
        .subquery()
    )
    latest = {
        row.assignment_id: row
        for row in session.execute(select(ranked).where(ranked.c.position == 1))
    }
    current_versions = dict(
        session.execute(select(Assignment.id, Assignment.version)).all()
    )
    revealed = set(
        session.scalars(
            select(LearningEvent.assignment_id)
            .where(
                LearningEvent.user_id == user.id,
                LearningEvent.event_type == "solution_revealed",
                LearningEvent.assignment_id.is_not(None),
            )
            .distinct()
        )
    )

    progress = []
    for assignment_id, attempt_count, best_score in sorted(totals):
        newest = latest.get(assignment_id)
        current = (
            newest is not None
            and newest.assignment_version == current_versions.get(assignment_id)
        )
        progress.append(
            {
                "assignment_id": assignment_id,
                "attempt_count": int(attempt_count),
                "best_score": int(best_score or 0),
                "latest_score": int(newest.score) if newest is not None else 0,
                "latest_submission_id": newest.id if current else None,
                "solution_revealed": assignment_id in revealed,
            }
        )
    return progress
