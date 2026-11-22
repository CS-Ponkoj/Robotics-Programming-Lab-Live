"""Publish 270-degree scans of a wall ahead and observe the student's /cmd_vel.

The student designs the node in build_node(), so this harness checks
observable behavior, the ROS interfaces the running node creates, and the
one-command-per-scan contract (counted inside the student's process by
ros2_callback_audit). It never requires a particular callback structure or
stop distance.

Each check judges only its own rule. A check that could not be judged because
the node was not running is reported as not run, with the reason, and a check
whose credit is withheld says why.
"""

from __future__ import annotations

import json
import math
import os
import signal
import subprocess
import time

import rclpy
from geometry_msgs.msg import Twist
from rclpy.node import Node
from sensor_msgs.msg import LaserScan
from ros2_callback_audit import (
    output_tail,
    build_state,
    callback_contract_problem,
    created_interfaces,
    launch_student,
    one_per_callback,
    read_audit,
    summarize_student_failure,
)


FORWARD_MIN = 0.1
FORWARD_MAX = 0.3
STOP_TOLERANCE = 0.001
ANGULAR_TOLERANCE = 0.001
MINIMUM_RATE_HZ = 5.0
PHASE_SECONDS = 1.0
SETTLE_SECONDS = 0.3
SCAN_PERIOD = 0.08
SCAN_MIN_DEG = -135.0
SCAN_INCREMENT_DEG = 3.0
SCAN_BEAMS = 91
RANGE_MIN = 0.1
RANGE_MAX = 10.0
INTERFACE_SAMPLE_PERIOD = 0.25
TWIST_TYPE = "geometry_msgs/msg/Twist"
SCAN_TYPE = "sensor_msgs/msg/LaserScan"

# (phase, distance to a flat wall straight ahead in metres; None = nothing in range)
PHASES = [
    ("open", None),
    ("far", 1.2),
    ("near", 0.3),
    ("close", 0.2),
    ("hold", 0.2),
    ("resume", 1.2),
]

# Why behavior could not be observed, by node state. A check without
# evidence for one of these reasons is "not run", not failed on its rule.
NOT_CHECKED = {
    "build-returned-non-node": "Not checked: build_node() did not return a node, so nothing could run.",
    "build-error": "Not checked: build_node() stopped with an error before the node could run.",
    "build-never-returned": "Not checked: build_node() never returned, so main() could not start the node.",
    "callback-error": "Not checked: the node stopped with an error while handling a scan.",
    "callback-blocked": "Not checked: the scan callback never finished (a loop or a wait blocks it), so the node stopped publishing.",
    "stopped": "Not checked: the node stopped before this situation.",
}
NODE_START_FAILURE = {
    "build-returned-non-node": "The node did not start: build_node() returned None instead of a node.",
    "build-error": "The node did not start: build_node() stopped with an error.",
    "build-never-returned": "The node did not start: build_node() never returned.",
    "callback-error": "The node started, but it stopped with an error while handling its first scan, so it never published on /cmd_vel.",
    "callback-blocked": "The node started, but its scan callback never finished, so it never published on /cmd_vel.",
}
NO_COMMANDS = (
    "No command arrived in this situation, so this rule could not be checked."
)
ONE_COMMAND_RULE = "Exactly one command was published in the /scan callback for every scan."


def result(test_id: str, passed: bool, message: str, status: str = "") -> dict:
    item = {"id": test_id, "passed": passed, "message": message}
    if status and not passed:
        item["status"] = status
    return item


def wall_ranges(front: float | None) -> list[float]:
    """Readings of a flat wall perpendicular to the robot at ``front`` metres."""
    ranges = []
    for index in range(SCAN_BEAMS):
        angle = math.radians(SCAN_MIN_DEG + index * SCAN_INCREMENT_DEG)
        distance = math.inf
        if front is not None and math.cos(angle) > 0.17:
            distance = front / math.cos(angle)
            if distance > RANGE_MAX:
                distance = math.inf
        ranges.append(distance)
    return ranges


def in_phase(commands: list[tuple], start: float, end: float) -> list[tuple]:
    return [item for item in commands if start + SETTLE_SECONDS <= item[0] <= end]


def forward_ok(samples: list[tuple]) -> bool:
    return bool(samples) and all(
        FORWARD_MIN - 1e-9 <= item[1] <= FORWARD_MAX + 1e-9 for item in samples
    )


def moving(samples: list[tuple]) -> bool:
    """The robot drives forward, at any speed (the speed has its own checks)."""
    return bool(samples) and all(item[1] > STOP_TOLERANCE for item in samples)


def stopped_ok(samples: list[tuple]) -> bool:
    return bool(samples) and all(abs(item[1]) <= STOP_TOLERANCE for item in samples)


def node_state(build: str, alive: bool, audit: dict, commands: bool, resumed: bool) -> str:
    """One word for how the student's node ran; "running" when it worked as a node."""
    began = audit["events"]["B"]
    finished = len(audit["counts"])
    if build == "non-node":
        return "build-returned-non-node"
    if build == "raised":
        return "build-error"
    if not alive and audit["events"]["F"]:
        return "callback-error"
    if alive and began > finished and not resumed:
        return "callback-blocked"
    if build == "pending" and not commands:
        return "build-never-returned" if alive else "stopped"
    if not alive:
        return "stopped"
    return "running"


def main() -> None:
    config = json.loads(os.environ.get("ROS_GRADER_CONFIG", "{}"))
    package = str(config.get("package_name", "wall_stop"))
    executable = str(config.get("executable", "controller"))
    command_topic = str(config.get("topic", "/cmd_vel"))
    scan_topic = str(config.get("scan_topic", "/scan"))

    commands: list[tuple[float, float, float]] = []
    windows: dict[str, tuple[float, float]] = {}
    publishers: set[str] = set()
    subscriptions: set[str] = set()
    last_sample = [0.0]

    rclpy.init(args=None)
    monitor_name = f"grader_wall_monitor_{os.getpid()}"
    monitor = Node(monitor_name)

    def receive(message: Twist) -> None:
        commands.append((time.monotonic(), float(message.linear.x), float(message.angular.z)))

    monitor.create_subscription(Twist, command_topic, receive, 10)
    scan_publisher = monitor.create_publisher(LaserScan, scan_topic, 10)
    student, audit_fd = launch_student(package, executable, "open", command_topic, scan_topic)

    def scan_message(front: float | None) -> LaserScan:
        scan = LaserScan()
        scan.header.stamp = monitor.get_clock().now().to_msg()
        scan.header.frame_id = "laser"
        scan.angle_min = math.radians(SCAN_MIN_DEG)
        scan.angle_increment = math.radians(SCAN_INCREMENT_DEG)
        scan.angle_max = scan.angle_min + scan.angle_increment * (SCAN_BEAMS - 1)
        scan.scan_time = SCAN_PERIOD
        scan.range_min = RANGE_MIN
        scan.range_max = RANGE_MAX
        scan.ranges = wall_ranges(front)
        return scan

    def interface_types(info_list) -> set[str]:
        return {
            info.topic_type for info in info_list if info.node_name != monitor_name
        }

    def sample_interfaces(force: bool = False) -> None:
        """Remember the node's interfaces while it runs; a crash removes them."""
        now = time.monotonic()
        if not force and now - last_sample[0] < INTERFACE_SAMPLE_PERIOD:
            return
        last_sample[0] = now
        publishers.update(interface_types(monitor.get_publishers_info_by_topic(command_topic)))
        subscriptions.update(interface_types(monitor.get_subscriptions_info_by_topic(scan_topic)))

    def wait_for_controller(timeout: float = 5.0) -> bool:
        deadline = time.monotonic() + timeout
        next_publish = time.monotonic()
        while time.monotonic() < deadline:
            if student.poll() is not None:
                return False
            now = time.monotonic()
            if now >= next_publish:
                scan_publisher.publish(scan_message(None))
                next_publish = now + SCAN_PERIOD
            rclpy.spin_once(monitor, timeout_sec=0.03)
            sample_interfaces()
            if commands and monitor.count_publishers(command_topic) > 0:
                return True
        return False

    def spin_for(seconds: float, front: float | None = None, publish: bool = True) -> None:
        started = time.monotonic()
        next_publish = started
        while time.monotonic() - started < seconds:
            now = time.monotonic()
            if publish and now >= next_publish:
                scan_publisher.publish(scan_message(front))
                next_publish = now + SCAN_PERIOD
            rclpy.spin_once(monitor, timeout_sec=0.03)
            sample_interfaces()
            if student.poll() is not None:
                return

    controller_ready = False
    try:
        controller_ready = wait_for_controller()
        if controller_ready:
            spin_for(1.0, publish=False)
            sample_interfaces(force=True)
            commands.clear()
            for phase, front in PHASES:
                started = time.monotonic()
                spin_for(PHASE_SECONDS, front)
                windows[phase] = (started, time.monotonic())
            spin_for(0.2, publish=False)
        elif student.poll() is None:
            sample_interfaces(force=True)
    finally:
        alive_at_end = student.poll() is None
        if alive_at_end:
            os.killpg(student.pid, signal.SIGTERM)
            try:
                student.wait(timeout=1)
            except subprocess.TimeoutExpired:
                os.killpg(student.pid, signal.SIGKILL)
        monitor.destroy_node()
        rclpy.shutdown()
    student_stdout, student_stderr = student.communicate(timeout=1)
    audit = read_audit(audit_fd)

    def samples(phase: str) -> list[tuple]:
        if phase not in windows:
            return []
        start, end = windows[phase]
        return in_phase(commands, start, end)

    observed = (
        [item for item in commands if windows["open"][0] <= item[0] <= windows["resume"][1] + 0.1]
        if windows else []
    )
    observed_seconds = len(PHASES) * PHASE_SECONDS
    rate = len(observed) / observed_seconds
    build = build_state(audit)
    if build == "raised" and alive_at_end:
        # The grader's own shutdown interrupted a build_node() that never returned.
        build = "pending"
    publishers |= created_interfaces(audit, "pub")
    subscriptions |= created_interfaces(audit, "sub")
    state = node_state(build, alive_at_end, audit, bool(commands), bool(samples("resume")))
    reason = NOT_CHECKED.get(state)
    # Stopping, recovery and straight driving count only once the robot also
    # drives (at any speed) when the way is clear; speed has its own checks.
    moves_when_clear = moving(samples("open")) or moving(samples("far"))
    node_started = controller_ready and (alive_at_end or bool(commands))
    if build == "unknown":
        returns_node = node_started and not audit["events"]["N"]
    else:
        returns_node = build == "returned"
    runtime_error = (
        "" if alive_at_end
        else summarize_student_failure(
            student_stderr, student.returncode, returned_non_node=build == "non-node",
        )
    )
    withheld = "Not credited yet: this counts only once the robot also drives when the way is clear."

    def not_checked(phase_samples: list) -> bool:
        return reason is not None and not phase_samples

    def drive_check(test_id: str, phase: str, ok_message: str, rule: str) -> dict:
        items = samples(phase)
        if forward_ok(items):
            return result(test_id, True, ok_message)
        if not_checked(items):
            return result(test_id, False, reason, "not_run")
        if not items:
            return result(test_id, False, NO_COMMANDS)
        return result(test_id, False, rule + " Forward means linear.x between 0.1 and 0.3 m/s.")

    def stop_check(test_id: str, phase: str, ok_message: str, rule: str) -> dict:
        items = samples(phase)
        if moves_when_clear and stopped_ok(items):
            return result(test_id, True, ok_message)
        if not_checked(items):
            return result(test_id, False, reason, "not_run")
        if not items:
            return result(test_id, False, NO_COMMANDS)
        if stopped_ok(items):
            return result(test_id, False, "The robot was stopped here. " + withheld)
        return result(test_id, False, rule + " Stopped means linear.x is 0.0.")

    if returns_node:
        returns_message = "build_node() returned a ROS node."
    elif build == "non-node":
        returns_message = (
            "build_node() returned None or something that is not a ROS node. "
            "The rule: build_node() returns the node it created."
        )
    elif build == "raised":
        returns_message = "build_node() stopped with an error before it returned a node; the error shows the line."
    elif build == "pending" and alive_at_end:
        returns_message = (
            "build_node() never returned, so main() could not spin the node."
        )
    else:
        returns_message = "build_node() did not return a node before the program stopped."

    if node_started:
        start_message = "The node started and published on /cmd_vel."
    else:
        start_message = NODE_START_FAILURE.get(
            state, "The node did not start publishing on /cmd_vel within 5 seconds."
        )

    interface_reason = reason if state != "running" else None
    turning = [abs(item[2]) for item in observed if abs(item[2]) > ANGULAR_TOLERANCE]
    hold = samples("hold")
    resume = samples("resume")
    contract_ok = one_per_callback(audit)
    contract_problem = callback_contract_problem(audit, "/scan")
    contract_unjudged = reason is not None and 1 not in audit["counts"]

    tests = [
        result("node-start", node_started, start_message),
        result("returns-node", returns_node, returns_message),
        result(
            "cmd-vel-publisher",
            TWIST_TYPE in publishers,
            "The node publishes Twist messages on /cmd_vel.",
        ) if TWIST_TYPE in publishers else (
            result("cmd-vel-publisher", False, interface_reason, "not_run")
            if interface_reason else
            result("cmd-vel-publisher", False, "Create a Twist publisher on /cmd_vel.")
        ),
        result(
            "scan-subscription",
            True,
            "The node subscribes to LaserScan messages on /scan.",
        ) if SCAN_TYPE in subscriptions else (
            result("scan-subscription", False, interface_reason, "not_run")
            if interface_reason else
            result("scan-subscription", False, "Subscribe to sensor_msgs/msg/LaserScan on /scan.")
        ),
        drive_check(
            "drive-open-floor", "open",
            "The robot drives when nothing is in range.",
            "Drive forward when every reading is +inf: nothing is in range, so the way is clear.",
        ),
        drive_check(
            "drive-wall-far", "far",
            "The robot drives with the wall 1.2 m away.",
            "Keep driving while the wall is more than 1.0 m away.",
        ),
        stop_check(
            "stop-wall-0-3", "near",
            "The robot is stopped with the wall 0.3 m away.",
            "Be stopped when the wall is 0.3 m away.",
        ),
        stop_check(
            "stop-wall-0-2", "close",
            "The robot is stopped with the wall 0.2 m away.",
            "Be stopped when the wall is 0.2 m away.",
        ),
        stop_check(
            "stay-stopped", "hold",
            "The robot stays stopped while the wall is close.",
            "Stay stopped for as long as the wall is close; do not creep forward.",
        ),
        (
            result("resume-motion", True, "The robot drives again when the wall moves away.")
            if moving(resume) and stopped_ok(hold)
            else result("resume-motion", False, reason, "not_run") if not_checked(resume)
            else result("resume-motion", False, NO_COMMANDS) if not resume
            else result(
                "resume-motion", False,
                "The robot drove at 1.2 m, but it had not stayed stopped for the close wall, "
                "so there was no stop to recover from.",
            ) if moving(resume)
            else result(
                "resume-motion", False,
                "After stopping for the close wall, drive again as soon as it is 1.2 m away.",
            )
        ),
        (
            result("straight-motion", True, "angular.z stayed 0.0.")
            if moves_when_clear and observed and not turning
            else result("straight-motion", False, reason, "not_run") if not_checked(observed)
            else result("straight-motion", False, "Drive straight: keep angular.z at 0.0 in every command.")
            if turning or not observed
            else result("straight-motion", False, "angular.z stayed 0.0. " + withheld)
        ),
        (
            result("publish-rate", True, f"Published about {rate:.1f} commands per second.")
            if rate >= MINIMUM_RATE_HZ
            else result("publish-rate", False, reason, "not_run") if not_checked(observed)
            else result(
                "publish-rate", False,
                "The rule: at least 5 commands per second, one in the scan callback for every scan.",
            )
        ),
        (
            result("one-command-per-scan", True, ONE_COMMAND_RULE)
            if contract_ok
            else result("one-command-per-scan", False, reason, "not_run") if contract_unjudged
            else result(
                "one-command-per-scan", False,
                contract_problem or "Publish exactly one Twist inside the /scan callback for every scan.",
            )
        ),
    ]

    def phase_summary(phase: str) -> dict:
        """What the node published in one phase: the student's own output."""
        items = samples(phase)
        if not items:
            return {"count": 0}
        return {
            "count": len(items),
            "linear_min": round(min(item[1] for item in items), 3),
            "linear_max": round(max(item[1] for item in items), 3),
            "angular_max_abs": round(max(abs(item[2]) for item in items), 3),
        }

    counts = audit["counts"]
    print(
        json.dumps(
            {
                # Raw observations for the backend's feedback classifier.
                "observations": {
                    "phases": {phase: phase_summary(phase) for phase, _ in PHASES},
                    "rate_hz": round(rate, 2),
                    # How the node ran: "running" or why behavior was not observed.
                    "node_state": state,
                    "build_node": build,
                    "callbacks": {
                        "count": len(counts),
                        "max_commands": max(counts, default=0),
                        "skipped": sum(1 for count in counts if count == 0),
                        "published_outside": bool(audit["events"]["O"]),
                        "queue_depth_wrong": bool(audit["events"]["Q"]),
                    },
                },
                "error": runtime_error
                or ("" if all(item["passed"] for item in tests) else "One or more requirements need attention."),
                "runtime_error": runtime_error,
                "output": (
                    f"Observed {len(observed)} Twist messages over {observed_seconds:.0f} s of scans."
                    + (f"\nNode stdout: {output_tail(student_stdout)}" if student_stdout.strip() else "")
                ),
                "tests": tests,
            }
        )
    )


if __name__ == "__main__":
    main()
