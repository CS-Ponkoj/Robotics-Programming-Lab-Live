"""Publish 270-degree scans of a wall ahead and observe the student's /cmd_vel.

The student designs the node in build_node(), so this harness checks only
observable behavior and the ROS interfaces the running node creates. It never
requires a particular callback structure or stop distance.
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
from ros2_callback_audit import launch_student, summarize_student_failure


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


def result(test_id: str, passed: bool, message: str) -> dict:
    return {"id": test_id, "passed": passed, "message": message}


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


def stopped_ok(samples: list[tuple]) -> bool:
    return bool(samples) and all(abs(item[1]) <= STOP_TOLERANCE for item in samples)


def read_spin_report(read_fd: int) -> bool:
    """True when main() passed something other than a node to rclpy.spin()."""
    os.set_blocking(read_fd, False)
    try:
        try:
            evidence = os.read(read_fd, 65536)
        except BlockingIOError:
            evidence = b""
    finally:
        os.close(read_fd)
    return b"N" in evidence.splitlines()


def main() -> None:
    config = json.loads(os.environ.get("ROS_GRADER_CONFIG", "{}"))
    package = str(config.get("package_name", "wall_stop"))
    executable = str(config.get("executable", "controller"))
    command_topic = str(config.get("topic", "/cmd_vel"))
    scan_topic = str(config.get("scan_topic", "/scan"))

    commands: list[tuple[float, float, float]] = []
    windows: dict[str, tuple[float, float]] = {}

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
            if student.poll() is not None:
                return

    def interface_types(info_list) -> set[str]:
        return {
            info.topic_type for info in info_list if info.node_name != monitor_name
        }

    controller_ready = False
    publishers: set[str] = set()
    subscriptions: set[str] = set()
    try:
        controller_ready = wait_for_controller()
        if controller_ready:
            spin_for(1.0, publish=False)
            publishers = interface_types(monitor.get_publishers_info_by_topic(command_topic))
            subscriptions = interface_types(monitor.get_subscriptions_info_by_topic(scan_topic))
            commands.clear()
            for phase, front in PHASES:
                started = time.monotonic()
                spin_for(PHASE_SECONDS, front)
                windows[phase] = (started, time.monotonic())
            spin_for(0.2, publish=False)
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
    spun_non_node = read_spin_report(audit_fd)

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
    moves_when_clear = forward_ok(samples("open")) or forward_ok(samples("far"))
    node_started = controller_ready and (alive_at_end or bool(commands))
    returns_node = not spun_non_node and node_started
    runtime_error = "" if alive_at_end else summarize_student_failure(student_stderr, student.returncode)
    drive_hint = " Forward means linear.x between 0.1 and 0.3 m/s."
    stop_hint = " Stopped means linear.x is 0.0. Stopping only counts once the robot also drives when the way is clear."

    tests = [
        result(
            "node-start",
            node_started,
            "The node started and published on /cmd_vel."
            if node_started
            else "The node did not start publishing on /cmd_vel within 5 seconds.",
        ),
        result(
            "returns-node",
            returns_node,
            "build_node() returned a ROS node."
            if returns_node
            else (
                "build_node() returned None or something that is not a ROS node. "
                "Create your node and return it at the end of build_node()."
                if spun_non_node
                else "build_node() did not finish, so no node could start."
            ),
        ),
        result(
            "cmd-vel-publisher",
            TWIST_TYPE in publishers,
            "The node publishes Twist messages on /cmd_vel."
            if TWIST_TYPE in publishers
            else "Create a Twist publisher on /cmd_vel.",
        ),
        result(
            "scan-subscription",
            SCAN_TYPE in subscriptions,
            "The node subscribes to LaserScan messages on /scan."
            if SCAN_TYPE in subscriptions
            else "Subscribe to sensor_msgs/msg/LaserScan on /scan.",
        ),
        result(
            "drive-open-floor",
            forward_ok(samples("open")),
            "The robot drives when nothing is in range."
            if forward_ok(samples("open"))
            else "Drive forward when every reading is +inf: nothing is in range, so the way is clear." + drive_hint,
        ),
        result(
            "drive-wall-far",
            forward_ok(samples("far")),
            "The robot drives with the wall 1.2 m away."
            if forward_ok(samples("far"))
            else "Keep driving while the wall is more than 1.0 m away." + drive_hint,
        ),
        result(
            "stop-wall-0-3",
            moves_when_clear and stopped_ok(samples("near")),
            "The robot is stopped with the wall 0.3 m away."
            if moves_when_clear and stopped_ok(samples("near"))
            else "Be stopped when the wall is 0.3 m away." + stop_hint,
        ),
        result(
            "stop-wall-0-2",
            moves_when_clear and stopped_ok(samples("close")),
            "The robot is stopped with the wall 0.2 m away."
            if moves_when_clear and stopped_ok(samples("close"))
            else "Be stopped when the wall is 0.2 m away." + stop_hint,
        ),
        result(
            "stay-stopped",
            moves_when_clear and stopped_ok(samples("hold")),
            "The robot stays stopped while the wall is close."
            if moves_when_clear and stopped_ok(samples("hold"))
            else "Stay stopped for as long as the wall is close; do not creep forward." + stop_hint,
        ),
        result(
            "resume-motion",
            forward_ok(samples("resume")) and stopped_ok(samples("hold")),
            "The robot drives again when the wall moves away."
            if forward_ok(samples("resume")) and stopped_ok(samples("hold"))
            else "After stopping for the close wall, drive again as soon as it is 1.2 m away." + drive_hint,
        ),
        result(
            "straight-motion",
            moves_when_clear and bool(observed) and all(abs(item[2]) <= ANGULAR_TOLERANCE for item in observed),
            "angular.z stayed 0.0."
            if moves_when_clear and bool(observed) and all(abs(item[2]) <= ANGULAR_TOLERANCE for item in observed)
            else "Drive straight: keep angular.z at 0.0 in every command, and drive when the way is clear.",
        ),
        result(
            "publish-rate",
            rate >= MINIMUM_RATE_HZ,
            f"Published about {rate:.1f} commands per second."
            if rate >= MINIMUM_RATE_HZ
            else f"Published about {rate:.1f} commands per second; publish at least 5 per second (one per scan is enough).",
        ),
    ]
    print(
        json.dumps(
            {
                "error": runtime_error
                or ("" if all(item["passed"] for item in tests) else "One or more requirements need attention."),
                "runtime_error": runtime_error,
                "output": (
                    f"Observed {len(observed)} Twist messages over {observed_seconds:.0f} s of scans."
                    + (f"\nNode stdout: {student_stdout.strip()[-1000:]}" if student_stdout.strip() else "")
                ),
                "tests": tests,
            }
        )
    )


if __name__ == "__main__":
    main()
