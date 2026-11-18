"""Per-assignment teaching insights for instructors.

Aggregates only: no names, login IDs, participant codes, or code. The
population matches the research dashboard: active, non-demo student accounts.
All numbers describe one assignment version so a changed assignment is never
mixed with its earlier version.
"""
from __future__ import annotations

from collections import Counter, defaultdict
from statistics import median
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from models import Assignment, LearningEvent, Submission, User


def _students(session: Session) -> set[str]:
    return set(
        session.scalars(
            select(User.id).where(
                User.role == "student", User.is_active.is_(True), User.is_demo.is_(False)
            )
        )
    )


def assignment_insights(
    session: Session, assignment: Assignment, version: int | None = None
) -> dict[str, Any]:
    version = assignment.version if version is None else version
    students = _students(session)
    submissions = [
        item
        for item in session.scalars(
            select(Submission)
            .where(
                Submission.assignment_id == assignment.id,
                Submission.assignment_version == version,
            )
            .order_by(Submission.created_at)
        )
        if item.user_id in students
    ]
    by_student: dict[str, list[Submission]] = defaultdict(list)
    for item in submissions:
        by_student[item.user_id].append(item)

    attempts_to_pass: list[int] = []
    minutes_to_pass: list[float] = []
    for attempts in by_student.values():
        for index, item in enumerate(attempts, start=1):
            if item.passed:
                attempts_to_pass.append(index)
                minutes = (item.created_at - attempts[0].created_at).total_seconds() / 60
                minutes_to_pass.append(round(minutes, 1))
                break

    # Each student counts once per check: their latest attempt decides.
    labels: dict[str, str] = {}
    failing: Counter[str] = Counter()
    hint_keys: Counter[str] = Counter()
    tags: Counter[str] = Counter()
    for attempts in by_student.values():
        latest = attempts[-1]
        for test in (latest.evidence or {}).get("tests", []):
            if not isinstance(test, dict):
                continue
            test_id = str(test.get("test_id", ""))
            labels.setdefault(test_id, str(test.get("label", test_id)))
            if test.get("passed"):
                continue
            failing[test_id] += 1
            if test.get("hint_key"):
                hint_keys[str(test["hint_key"])] += 1
            if test.get("misconception_tag"):
                tags[str(test["misconception_tag"])] += 1

    outcomes: Counter[str] = Counter()
    for event in session.scalars(
        select(LearningEvent).where(
            LearningEvent.event_type == "simulation_run",
            LearningEvent.assignment_id == assignment.id,
            LearningEvent.assignment_version == version,
        )
    ):
        if event.user_id in students:
            outcome = (event.event_data or {}).get("outcome")
            if isinstance(outcome, str):
                outcomes[outcome] += 1

    return {
        "assignment_id": assignment.id,
        "title": assignment.title,
        "version": version,
        "students_attempted": len(by_student),
        "students_passed": len(attempts_to_pass),
        "attempts": len(submissions),
        "median_attempts_to_pass": median(attempts_to_pass) if attempts_to_pass else None,
        "median_minutes_to_pass": median(minutes_to_pass) if minutes_to_pass else None,
        "checks": [
            {"test_id": test_id, "label": labels[test_id], "students_failing": count}
            for test_id, count in failing.most_common()
        ],
        "observed_patterns": [
            {"hint_key": key, "students": count} for key, count in hint_keys.most_common()
        ],
        "misconceptions": [
            {"tag": key, "students": count} for key, count in tags.most_common()
        ],
        "simulation_outcomes": [
            {"outcome": key, "runs": count} for key, count in outcomes.most_common()
        ],
    }
