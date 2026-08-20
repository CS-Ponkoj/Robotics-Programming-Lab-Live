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


def main() -> None:
    image = os.environ.get(
        "ROS2_GRADER_IMAGE", "robotics-lab-ros2-grader:jazzy-v1"
    )
    for assignment_id in ROS_ASSIGNMENT_IDS:
        verify_assignment(assignment_id, image)


if __name__ == "__main__":
    main()
