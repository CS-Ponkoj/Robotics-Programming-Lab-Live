"""Instructor validation accepts every shipped grader harness."""
import json
from pathlib import Path
from types import SimpleNamespace

import pytest

from validation import validate_assignment

ASSIGNMENTS = Path(__file__).resolve().parent.parent / "assignments"


class PassingGrader:
    def grade(self, assignment, code):
        return SimpleNamespace(passed=True)


def assignment_from_seed(path: Path) -> SimpleNamespace:
    data = json.loads(path.read_text(encoding="utf-8"))
    return SimpleNamespace(
        stable_id=data["stable_id"],
        version=data["version"],
        title=data["title"],
        assignment_html=data["assignment_html"],
        learning_objectives=data["learning_objectives"],
        rubric=data["rubric"],
        grader_type=data["grader_type"],
        grader_config=data["grader_config"],
        asset_manifest=data.get("asset_manifest", []),
        reference_solution_path=data["reference_solution_path"],
    )


ROS_SEEDS = sorted(
    path
    for path in ASSIGNMENTS.glob("assignment_*.json")
    if json.loads(path.read_text(encoding="utf-8"))["grader_type"] == "ros2_topic"
)


@pytest.mark.parametrize("path", ROS_SEEDS, ids=lambda path: path.stem)
def test_every_shipped_ros2_assignment_validates(path):
    assert validate_assignment(assignment_from_seed(path), PassingGrader()) == []


def test_unknown_ros2_harness_is_rejected():
    assignment = assignment_from_seed(ROS_SEEDS[-1])
    assignment.grader_config = {**assignment.grader_config, "harness": "made_up"}
    errors = validate_assignment(assignment, PassingGrader())
    assert errors == ["Unsupported ROS 2 harness: made_up."]
