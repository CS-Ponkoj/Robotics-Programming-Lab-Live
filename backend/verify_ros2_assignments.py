"""Run every maintained ROS 2 answer through the pinned Docker grader image."""

from __future__ import annotations

import json
import os
from pathlib import Path

from ros2_executor import DockerRos2Executor


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
ASSIGNMENTS_DIRECTORY = Path(__file__).resolve().parent / "assignments"
ROS_ASSIGNMENT_IDS = (5, 6)


def verify_assignment(assignment_id: int, image: str) -> None:
    source = json.loads(
        (ASSIGNMENTS_DIRECTORY / f"assignment_{assignment_id}.json").read_text(
            encoding="utf-8"
        )
    )
    reference = REPOSITORY_ROOT / source["reference_solution_path"]
    project_files = [
        item
        for item in source.get("asset_manifest", [])
        if isinstance(item, dict) and item.get("kind") == "project_file"
    ]
    timeout = float(source.get("execution_settings", {}).get("timeout_seconds", 20))
    result = DockerRos2Executor(image, timeout).execute(
        reference.read_text(encoding="utf-8"),
        project_files,
        source.get("grader_config", {}),
    )
    expected_ids = [str(item["id"]) for item in source.get("public_tests", [])]
    returned_ids = [str(item.get("id")) for item in result.get("tests", [])]
    failures = [
        str(item.get("id"))
        for item in result.get("tests", [])
        if item.get("passed") is not True
    ]
    if (
        result.get("success") is not True
        or returned_ids != expected_ids
        or failures
    ):
        raise RuntimeError(
            f"Assignment {assignment_id} ROS verification failed: "
            + json.dumps(result, sort_keys=True)
        )
    print(
        f"Assignment {assignment_id}: PASS "
        f"({len(returned_ids)}/{len(expected_ids)} checks) - "
        f"{result.get('output', '')}"
    )

    # Protect the exact-one-command contract with a real Docker regression, not
    # a mock that merely knows the expected score.
    duplicate = reference.read_text(encoding="utf-8").replace(
        "self.velocity_publisher.publish(command)",
        "self.velocity_publisher.publish(command)\n"
        "        self.velocity_publisher.publish(command)",
    )
    rejected = DockerRos2Executor(image, timeout).execute(
        duplicate, project_files, source.get("grader_config", {}),
    )
    criterion = "cmd-vel-topic" if assignment_id == 5 else "scan-response"
    evidence = {item["id"]: item for item in rejected.get("tests", [])}
    if (rejected.get("success") is not True or criterion not in evidence
            or evidence[criterion].get("passed") is not False):
        raise RuntimeError(f"Assignment {assignment_id}: duplicate commands were not rejected.")
    print(f"Assignment {assignment_id}: PASS duplicate-command rejection ({criterion}).")

    # A node that publishes but never moves must not earn motion or safety credit.
    stationary = never_moving_controller(source["starter_code"], assignment_id)
    stopped = DockerRos2Executor(image, timeout).execute(
        stationary, project_files, source.get("grader_config", {}),
    )
    stopped_evidence = {item["id"]: item for item in stopped.get("tests", [])}
    gated = (
        ("forward-motion", "straight-motion")
        if assignment_id == 5
        else ("obstacle-stop", "invalid-scan-stop", "straight-motion")
    )
    if stopped.get("success") is not True or any(
        stopped_evidence.get(test_id, {}).get("passed") is not False
        for test_id in gated
    ):
        raise RuntimeError(
            f"Assignment {assignment_id}: a never-moving node earned motion credit."
        )
    print(f"Assignment {assignment_id}: PASS never-moving node rejection ({', '.join(gated)}).")


def never_moving_controller(starter_code: str, assignment_id: int) -> str:
    """Complete only the ROS wiring so every published command is zero."""
    code = starter_code.replace(
        "self.velocity_publisher = None",
        "self.velocity_publisher = self.create_publisher(Twist, '/cmd_vel', 10)",
    )
    if assignment_id == 5:
        publish_todo = "        # TODO 4: Publish the command.\n        pass"
    else:
        code = code.replace(
            "self.scan_subscription = None",
            "self.scan_subscription = self.create_subscription("
            "LaserScan, '/scan', self.handle_scan, 10)",
        )
        publish_todo = "        # TODO 6: Publish the velocity command.\n        pass"
    if publish_todo not in code:
        raise RuntimeError(f"Assignment {assignment_id}: starter publish TODO changed.")
    return code.replace(publish_todo, "        self.velocity_publisher.publish(command)")


def main() -> None:
    image = os.environ.get(
        "ROS2_GRADER_IMAGE", "robotics-lab-ros2-grader:jazzy-v1"
    )
    for assignment_id in ROS_ASSIGNMENT_IDS:
        verify_assignment(assignment_id, image)


if __name__ == "__main__":
    main()
