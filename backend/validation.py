from pathlib import Path

from graders.base import AssignmentGrader
from models import Assignment


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent


def validate_assignment(
    assignment: Assignment, grader: AssignmentGrader
) -> list[str]:
    errors: list[str] = []
    if not assignment.stable_id.strip():
        errors.append("A stable ID is required.")
    if assignment.version < 1:
        errors.append("Assignment version must be at least 1.")
    if not assignment.title.strip():
        errors.append("A title is required.")
    if not assignment.assignment_html.strip():
        errors.append("Instructions are required.")
    if not assignment.learning_objectives:
        errors.append("At least one learning objective is required.")
    if not assignment.rubric:
        errors.append("At least one rubric criterion is required.")
    if assignment.grader_type == "python_variables":
        expected = (assignment.grader_config or {}).get("expected_values", {})
        if not expected:
            errors.append("Hidden expected values are required for this grader.")
    elif assignment.grader_type == "ros2_topic":
        config = assignment.grader_config or {}
        for name in ("package_name", "executable", "topic", "message_type"):
            if not str(config.get(name, "")).strip():
                errors.append(f"ROS 2 grader setting '{name}' is required.")
        harness = str(config.get("harness", "drive_forward"))
        if harness not in {"drive_forward", "obstacle_stop"}:
            errors.append(f"Unsupported ROS 2 harness: {harness}.")
        project_files = [
            item
            for item in (assignment.asset_manifest or [])
            if isinstance(item, dict) and item.get("kind") == "project_file"
        ]
        editable_files = [item for item in project_files if item.get("editable") is True]
        if len(editable_files) != 1:
            errors.append("A ROS 2 assignment must have exactly one editable project file.")
    else:
        errors.append(f"Unsupported grader type: {assignment.grader_type}.")
    if not assignment.reference_solution_path:
        errors.append("A server-side reference solution path is required.")
        return errors

    reference = (REPOSITORY_ROOT / assignment.reference_solution_path).resolve()
    if REPOSITORY_ROOT not in reference.parents:
        errors.append("Reference solution must stay inside the repository.")
        return errors
    if not reference.is_file():
        errors.append("Reference solution file does not exist.")
        return errors
    result = grader.grade(assignment, reference.read_text(encoding="utf-8"))
    if not result.passed:
        errors.append(
            "Reference solution did not pass the hidden grader; assignment cannot publish."
        )
    return errors
