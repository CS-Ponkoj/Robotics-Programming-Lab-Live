"""Research check groups for the study assignments (analysis only)."""

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from sqlalchemy import select

from models import Assignment, AssignmentActivity, Submission, User
from study_checks import (
    BEHAVIOR,
    _GROUPS,
    behavior_checks,
    behavior_summary,
    check_group,
)
from tests.test_study_data import (  # noqa: F401  (fixture)
    STUDENT_LOGIN,
    STUDENT_PASSWORD,
    _instructor,
    _login,
    client,
)

ASSIGNMENTS = Path(__file__).resolve().parents[1] / "assignments"


@pytest.mark.parametrize("number", [7, 8])
def test_every_check_of_the_study_version_has_exactly_one_group(number):
    config = json.loads((ASSIGNMENTS / f"assignment_{number}.json").read_text("utf-8"))
    key = (config["stable_id"], config["version"])
    # A new assignment version needs its own reviewed grouping.
    assert key in _GROUPS, "map the check groups of the new assignment version"
    ids = [test_id for group in _GROUPS[key].values() for test_id in group]
    assert len(ids) == len(set(ids))
    assert set(ids) == set(config["grader_config"]["test_weights"])
    pass_tests = config["grader_config"].get("pass_tests")
    if pass_tests:
        assert set(_GROUPS[key][BEHAVIOR]) == set(pass_tests)


def test_unknown_versions_get_no_group_and_no_behavior_summary():
    assert check_group("ros2-wall-stop", 4, "drive-open-floor") == ""
    assert behavior_checks("ros2-wall-stop", 4) == frozenset()
    assert behavior_summary("ros2-wall-stop", 4, [], True) is None


def test_full_behavior_pass_needs_every_behavior_check_and_a_run():
    behavior = sorted(behavior_checks("ros2-turn-open-side", 3))
    tests = [{"test_id": test_id, "passed": True} for test_id in behavior]
    tests.append({"test_id": "main-unchanged", "passed": False})  # style only
    assert behavior_summary("ros2-turn-open-side", 3, tests, True) == (7, 7, True)
    assert behavior_summary("ros2-turn-open-side", 3, tests, False)[2] is False
    tests[0]["passed"] = False
    assert behavior_summary("ros2-turn-open-side", 3, tests, True) == (6, 7, False)


def _attempt(user_id, assignment, created_at, passed_ids, active):
    tests = [
        {"test_id": test_id, "label": test_id, "passed": test_id in passed_ids}
        for group in _GROUPS[(assignment.stable_id, assignment.version)].values()
        for test_id in group
    ]
    return Submission(
        user_id=user_id, student_id=STUDENT_LOGIN, assignment_id=assignment.id,
        assignment_version=assignment.version, mode="submit", code="x = 1",
        evidence={"tests": tests}, score=0, passed=False,
        execution_succeeded=True, execution_status="completed",
        feedback_mode="tdd_ai", created_at=created_at,
        active_seconds_at_attempt=active,
    )


def test_tables_show_groups_and_time_to_full_behavior_pass(client):  # noqa: F811
    _login(client, STUDENT_LOGIN, STUDENT_PASSWORD)
    start = datetime(2026, 11, 24, 9, 0, tzinfo=timezone.utc)
    with client.app.state.SessionLocal() as session:
        user = session.scalar(select(User).where(User.login_id == STUDENT_LOGIN))
        wall = session.scalar(select(Assignment).where(Assignment.stable_id == "ros2-wall-stop"))
        behavior = behavior_checks(wall.stable_id, wall.version)
        session.add(AssignmentActivity(
            user_id=user.id, assignment_id=wall.id, assignment_version=wall.version,
            first_active_at=start, last_active_at=start + timedelta(minutes=30),
            active_seconds=1500,
        ))
        session.add(_attempt(user.id, wall, start + timedelta(minutes=5),
                             set(list(behavior)[:3]), 240))
        session.add(_attempt(user.id, wall, start + timedelta(minutes=12),
                             set(behavior), 600))
        session.add(_attempt(user.id, wall, start + timedelta(minutes=20),
                             set(behavior), 900))
        session.commit()
        wall_id = wall.id
    headers = _instructor(client)
    query = f"?assignment_id={wall_id}&page_size=200"

    time_rows = client.get(f"/admin/study-data/assignment_time{query}",
                           headers=headers).json()["rows"]
    assert len(time_rows) == 1
    assert time_rows[0]["full_behavior_pass_at"] == "2026-11-24T09:12:00+00:00"
    assert time_rows[0]["seconds_to_full_behavior_pass"] == 720
    assert time_rows[0]["active_seconds_to_full_behavior_pass"] == 600
    assert time_rows[0]["behavior_checks_mapped"] is True

    attempts = client.get(f"/admin/study-data/attempts{query}&sort=created_at&order=asc",
                          headers=headers).json()["rows"]
    assert [row["full_behavior_pass"] for row in attempts] == [False, True, True]
    assert [row["behavior_checks_passed"] for row in attempts] == [3, 9, 9]
    assert {row["behavior_checks_total"] for row in attempts} == {9}

    checks = client.get(f"/admin/study-data/check_results{query}",
                        headers=headers).json()["rows"]
    groups = {row["check_id"]: row["check_group"] for row in checks}
    assert groups["node-start"] == "setup"
    assert groups["publish-rate"] == "behavior"
    assert groups["named-constants"] == "code_style"
