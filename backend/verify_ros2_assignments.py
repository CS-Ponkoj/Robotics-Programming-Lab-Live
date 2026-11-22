"""Run every maintained ROS 2 answer through the pinned Docker grader image."""

from __future__ import annotations

import json
import os
from pathlib import Path

from ros2_executor import DockerRos2Executor
from ros2_feedback import classify


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
ASSIGNMENTS_DIRECTORY = Path(__file__).resolve().parent / "assignments"
ROS_ASSIGNMENT_IDS = (5, 6, 7, 8)
OPEN_ASSIGNMENT_IDS = (7,)
OPEN_SIDE_ASSIGNMENT_IDS = (8,)


def run_open(source: dict, image: str, code: str) -> dict:
    project_files = [
        item
        for item in source.get("asset_manifest", [])
        if isinstance(item, dict) and item.get("kind") == "project_file"
    ]
    timeout = float(source.get("execution_settings", {}).get("timeout_seconds", 20))
    return DockerRos2Executor(image, timeout).execute(
        code, project_files, source.get("grader_config", {})
    )


def verify_open_assignment(assignment_id: int, image: str) -> None:
    """Open-structure task: answer passes, and each common failure is caught."""
    source = json.loads(
        (ASSIGNMENTS_DIRECTORY / f"assignment_{assignment_id}.json").read_text(
            encoding="utf-8"
        )
    )
    reference = (REPOSITORY_ROOT / source["reference_solution_path"]).read_text(
        encoding="utf-8"
    )
    expected_ids = {str(item["id"]) for item in source.get("public_tests", [])}

    result = run_open(source, image, reference)
    outcome = {str(item.get("id")): item.get("passed") for item in result.get("tests", [])}
    failures = sorted(test_id for test_id, passed in outcome.items() if passed is not True)
    if result.get("success") is not True or set(outcome) != expected_ids or failures:
        raise RuntimeError(
            f"Assignment {assignment_id} ROS verification failed: "
            + json.dumps(result, sort_keys=True)
        )
    print(
        f"Assignment {assignment_id}: PASS ({len(outcome)}/{len(expected_ids)} checks) - "
        f"{result.get('output', '')}"
    )

    starter = run_open(source, image, source["starter_code"])
    starter_outcome = {str(item.get("id")): item.get("passed") for item in starter.get("tests", [])}
    if starter_outcome.get("returns-node") is not False:
        raise RuntimeError(f"Assignment {assignment_id}: the starter passed the returns-node gate.")
    print(f"Assignment {assignment_id}: PASS starter fails the returns-node gate.")

    stationary = reference.replace(
        "            command.linear.x = FORWARD_SPEED\n", "            pass\n"
    )
    if stationary == reference:
        raise RuntimeError(f"Assignment {assignment_id}: reference answer changed shape.")
    stopped = run_open(source, image, stationary)
    stopped_outcome = {str(item.get("id")): item.get("passed") for item in stopped.get("tests", [])}
    gated = ("stop-wall-0-3", "stop-wall-0-2", "stay-stopped", "straight-motion")
    if any(stopped_outcome.get(test_id) is not False for test_id in gated):
        raise RuntimeError(f"Assignment {assignment_id}: a never-moving node earned stop credit.")
    print(f"Assignment {assignment_id}: PASS never-moving node rejection ({', '.join(gated)}).")

    finite_only = reference.replace("if not math.isnan(distance)]", "if math.isfinite(distance)]")
    if finite_only == reference:
        raise RuntimeError(f"Assignment {assignment_id}: reference answer changed shape.")
    carried = run_open(source, image, finite_only)
    carried_outcome = {str(item.get("id")): item.get("passed") for item in carried.get("tests", [])}
    if carried_outcome.get("drive-open-floor") is not False:
        raise RuntimeError(
            f"Assignment {assignment_id}: treating +inf as unusable still drove on an open floor."
        )
    print(f"Assignment {assignment_id}: PASS +inf-as-obstacle rejection (drive-open-floor).")

    # A node that prints a lot must not freeze (its output pipes are drained).
    printing = reference.replace(
        "        command = Twist()\n", "        print(list(scan.ranges))\n        command = Twist()\n", 1
    )
    if printing == reference:
        raise RuntimeError(f"Assignment {assignment_id}: reference answer changed shape.")
    printed = run_open(source, image, printing)
    printed_failures = sorted(
        str(item.get("id")) for item in printed.get("tests", []) if item.get("passed") is not True
    )
    if printed.get("success") is not True or printed_failures:
        raise RuntimeError(f"Assignment {assignment_id}: a printing answer failed {printed_failures}.")
    print(f"Assignment {assignment_id}: PASS answer that prints every scan still passes every check.")

    # One command per scan callback: doubling or a timer fails the contract check.
    doubled = reference.replace(
        "        publisher.publish(command)\n",
        "        publisher.publish(command)\n        publisher.publish(command)\n",
    )
    timed = (
        reference.replace("    def handle_scan(scan):\n", "    latest = {'command': Twist()}\n\n    def handle_scan(scan):\n")
        .replace("        publisher.publish(command)\n", "        latest['command'] = command\n")
        .replace(
            "    node.create_subscription(LaserScan, '/scan', handle_scan, 10)\n",
            "    node.create_subscription(LaserScan, '/scan', handle_scan, 10)\n"
            "    node.create_timer(0.1, lambda: publisher.publish(latest['command']))\n",
        )
    )
    for name, code in (("double publish", doubled), ("timer publish", timed)):
        if code == reference or "create_timer" not in code and name == "timer publish":
            raise RuntimeError(f"Assignment {assignment_id}: reference answer changed shape.")
        contract = {
            str(item.get("id")): item.get("passed") for item in run_open(source, image, code).get("tests", [])
        }
        if contract.get("one-command-per-scan") is not False:
            raise RuntimeError(f"Assignment {assignment_id}: '{name}' passed one-command-per-scan.")
        print(f"Assignment {assignment_id}: PASS '{name}' fails one-command-per-scan.")

    # Feedback: real observations name the cause of the failed check.
    if not isinstance((result.get("observations") or {}).get("phases"), dict):
        raise RuntimeError(f"Assignment {assignment_id}: the harness reported no observations.")
    findings = classify(
        str(source["grader_config"].get("harness", "")), carried_outcome,
        carried.get("observations"),
    )
    found = findings.get("drive-open-floor")
    if found is None or found.hint_key != "infinity-treated-as-obstacle":
        raise RuntimeError(
            f"Assignment {assignment_id}: feedback missed +inf-as-obstacle: {findings}."
        )
    print(f"Assignment {assignment_id}: PASS feedback names infinity-treated-as-obstacle.")


def verify_simulation(assignment_id: int, image: str) -> None:
    """Visual replay: the answer stops and resumes; a node that never stops collides."""
    source = json.loads(
        (ASSIGNMENTS_DIRECTORY / f"assignment_{assignment_id}.json").read_text(
            encoding="utf-8"
        )
    )
    world = (source.get("simulation_config") or {}).get("world")
    if (source.get("simulation_config") or {}).get("provider") != "ros2_2d" or not world:
        return
    reference = (REPOSITORY_ROOT / source["reference_solution_path"]).read_text(
        encoding="utf-8"
    )
    config = {**source.get("grader_config", {}), "mode": "simulate", "simulation": world}

    def replay_of(code: str) -> dict:
        project_files = [
            item for item in source.get("asset_manifest", [])
            if isinstance(item, dict) and item.get("kind") == "project_file"
        ]
        timeout = float(source.get("execution_settings", {}).get("timeout_seconds", 20))
        result = DockerRos2Executor(image, timeout).execute(code, project_files, config)
        replay = result.get("simulation")
        return replay if isinstance(replay, dict) else {}

    def outcome(code: str) -> str | None:
        return replay_of(code).get("outcome")

    answer = replay_of(reference)
    if answer.get("outcome") != "stopped_and_resumed":
        raise RuntimeError(f"Assignment {assignment_id}: the answer did not stop and resume in the replay.")
    # Beam probe: the answer reacts to the beams straight ahead (drawn beam 15).
    probe = answer.get("sensitivity") or {}
    if probe.get("status") != "complete" or 15 not in probe.get("beams", []) or any(
        abs(beam - 15) > 2 for beam in probe.get("beams", [])
    ):
        raise RuntimeError(f"Assignment {assignment_id}: beam probe did not find the beams ahead: {probe}.")
    sideways = reference.replace("middle = len(scan.ranges) // 2", "middle = len(scan.ranges) // 4")
    if sideways == reference:
        raise RuntimeError(f"Assignment {assignment_id}: reference answer changed shape.")
    side_probe = replay_of(sideways).get("sensitivity") or {}
    if not side_probe.get("beams") or any(abs(beam - 7) > 2 for beam in side_probe["beams"]):
        raise RuntimeError(f"Assignment {assignment_id}: beam probe missed a sideways reading: {side_probe}.")
    print(
        f"Assignment {assignment_id}: PASS beam probe (answer {probe['beams']}, "
        f"len // 4 {side_probe['beams']})."
    )
    never_stops = reference.replace("if usable and min(usable) > STOP_DISTANCE:", "if True:")
    if never_stops == reference:
        raise RuntimeError(f"Assignment {assignment_id}: reference answer changed shape.")
    if outcome(never_stops) != "collided":
        raise RuntimeError(f"Assignment {assignment_id}: a node that never stops did not collide in the replay.")
    print(f"Assignment {assignment_id}: PASS simulation replay (answer stops and resumes; never-stop collides).")


def verify_open_side_assignment(assignment_id: int, image: str) -> None:
    """Turn toward the open side: the answer passes and each mistake is caught."""
    source = json.loads(
        (ASSIGNMENTS_DIRECTORY / f"assignment_{assignment_id}.json").read_text(
            encoding="utf-8"
        )
    )
    reference = (REPOSITORY_ROOT / source["reference_solution_path"]).read_text(
        encoding="utf-8"
    )
    expected_ids = [str(item["id"]) for item in source.get("public_tests", [])]

    def outcome_of(code: str) -> tuple[dict, dict]:
        result = run_open(source, image, code)
        return result, {str(item.get("id")): item.get("passed") for item in result.get("tests", [])}

    result, outcome = outcome_of(reference)
    failures = sorted(test_id for test_id, passed in outcome.items() if passed is not True)
    if result.get("success") is not True or list(outcome) != expected_ids or failures:
        raise RuntimeError(
            f"Assignment {assignment_id} ROS verification failed: "
            + json.dumps(result, sort_keys=True)
        )
    print(f"Assignment {assignment_id}: PASS ({len(outcome)}/{len(expected_ids)} checks) - {result.get('output', '')}")

    def variant(old: str, new: str) -> str:
        code = reference.replace(old, new)
        if code == reference:
            raise RuntimeError(f"Assignment {assignment_id}: reference answer changed shape near {old!r}.")
        return code

    mistakes = {
        "starter": (source["starter_code"], ("clear-path-forward", "turn-toward-open-side")),
        "duplicate publish": (
            variant(
                "        self.velocity_publisher.publish(command)\n",
                "        self.velocity_publisher.publish(command)\n"
                "        self.velocity_publisher.publish(command)\n",
            ),
            ("flbr-response",),
        ),
        "class demo (always turns)": (
            variant(
                "        if front > self.stop_distance:\n            command.linear.x = self.forward_speed\n        elif left > right:",
                "        if front > self.stop_distance:\n            command.linear.x = self.forward_speed\n        if left > right:",
            ),
            ("clear-path-forward",),
        ),
        "swapped turn sign": (
            variant("command.angular.z = self.turn_speed\n", "command.angular.z = -self.turn_speed\n"),
            ("turn-toward-open-side",),
        ),
        "boundary uses >=": (
            variant("if front > self.stop_distance:", "if front >= self.stop_distance:"),
            ("stop-at-threshold",),
        ),
        "tie turns left": (variant("elif left > right:", "elif left >= right:"), ("equal-sides-turn-right",)),
        "imports sensor_msgs": ("from sensor_msgs.msg import LaserScan\n" + reference, ("package-build",)),
        "NaN compared directly": (
            variant(
                "        right = 0.0 if math.isnan(msg.right) else msg.right\n",
                "        right = msg.right\n",
            ),
            ("unknown-distance-safe",),
        ),
    }
    for name, (code, must_fail) in mistakes.items():
        _result, mistake = outcome_of(code)
        if any(mistake.get(test_id) is not False for test_id in must_fail):
            raise RuntimeError(f"Assignment {assignment_id}: '{name}' was not caught by {must_fail}: {mistake}")
        print(f"Assignment {assignment_id}: PASS '{name}' fails {', '.join(must_fail)}.")

    world = (source.get("simulation_config") or {}).get("world")
    config = {**source.get("grader_config", {}), "mode": "simulate", "simulation": world}

    def replay_of(code: str) -> dict:
        project_files = [
            item for item in source.get("asset_manifest", [])
            if isinstance(item, dict) and item.get("kind") == "project_file"
        ]
        timeout = float(source.get("execution_settings", {}).get("timeout_seconds", 20))
        replay = DockerRos2Executor(image, timeout).execute(code, project_files, config).get("simulation")
        return replay if isinstance(replay, dict) else {}

    answer = replay_of(reference)
    if answer.get("outcome") in (None, "collided", "never_moved"):
        raise RuntimeError(f"Assignment {assignment_id}: the answer did not drive safely in the replay: {answer.get('outcome')}.")
    straight = variant(
        "        elif left > right:\n            command.angular.z = self.turn_speed\n"
        "        else:\n            command.angular.z = -self.turn_speed\n",
        "        else:\n            command.linear.x = self.forward_speed\n",
    )
    if replay_of(straight).get("outcome") != "collided":
        raise RuntimeError(f"Assignment {assignment_id}: a node that never turns did not collide in the replay.")
    print(f"Assignment {assignment_id}: PASS simulation replay (answer {answer.get('outcome')}; never-turn collides).")


def verify_assignment(assignment_id: int, image: str) -> None:
    if assignment_id in OPEN_SIDE_ASSIGNMENT_IDS:
        verify_open_side_assignment(assignment_id, image)
        return
    if assignment_id in OPEN_ASSIGNMENT_IDS:
        verify_open_assignment(assignment_id, image)
        verify_simulation(assignment_id, image)
        return
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
