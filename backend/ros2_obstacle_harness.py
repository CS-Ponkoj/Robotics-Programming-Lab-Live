"""Publish synthetic LaserScan data and observe student /cmd_vel behavior."""

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
from ros2_callback_audit import launch_student, exactly_one_per_callback


def result(test_id: str, passed: bool, message: str) -> dict:
    return {"id": test_id, "passed": passed, "message": message}


def main() -> None:
    config = json.loads(os.environ.get("ROS_GRADER_CONFIG", "{}"))
    package = str(config.get("package_name", "reactive_navigation"))
    executable = str(config.get("executable", "controller"))
    command_topic = str(config.get("topic", "/cmd_vel"))
    scan_topic = str(config.get("scan_topic", "/scan"))
    expected_linear = float(config.get("expected_linear_x", 0.20))
    linear_tolerance = float(config.get("linear_tolerance", 0.02))
    angular_tolerance = float(config.get("angular_tolerance", 0.01))
    stop_distance = float(config.get("stop_distance", 0.75))
    minimum_rate = float(config.get("minimum_publish_rate_hz", 3.0))

    messages: list[tuple[str, float, float, float]] = []
    current_phase = "startup"
    phase_started_at = time.monotonic()

    rclpy.init(args=None)
    monitor = Node(f"grader_obstacle_monitor_{os.getpid()}")

    def receive(message: Twist) -> None:
        messages.append(
            (
                current_phase,
                time.monotonic() - phase_started_at,
                float(message.linear.x),
                float(message.angular.z),
            )
        )

    monitor.create_subscription(Twist, command_topic, receive, 10)
    scan_publisher = monitor.create_publisher(LaserScan, scan_topic, 10)
    student, audit_fd = launch_student(
        package, executable, "scan", command_topic, scan_topic,
    )

    def scan_message(ranges: list[float]) -> LaserScan:
        scan = LaserScan()
        scan.header.stamp = monitor.get_clock().now().to_msg()
        scan.header.frame_id = "laser"
        scan.angle_min = -0.5
        scan.angle_max = 0.5
        scan.angle_increment = 1.0 / max(len(ranges) - 1, 1)
        scan.range_min = 0.05
        scan.range_max = 10.0
        scan.ranges = ranges
        return scan

    def wait_for_controller(timeout: float = 5.0) -> bool:
        """Wait for ROS discovery and one end-to-end scan response."""
        nonlocal current_phase, phase_started_at
        current_phase = "readiness"
        phase_started_at = time.monotonic()
        deadline = phase_started_at + timeout
        next_publish = phase_started_at
        while time.monotonic() < deadline:
            if student.poll() is not None:
                return False
            now = time.monotonic()
            if now >= next_publish:
                scan_publisher.publish(scan_message([2.0] * 9))
                next_publish = now + 0.08
            rclpy.spin_once(monitor, timeout_sec=0.03)
            if (
                scan_publisher.get_subscription_count() > 0
                and monitor.count_publishers(command_topic) > 0
                and messages
            ):
                return True
        return False

    def run_phase(name: str, ranges: list[float], duration: float) -> None:
        nonlocal current_phase, phase_started_at
        current_phase = name
        phase_started_at = time.monotonic()
        next_publish = phase_started_at
        while time.monotonic() - phase_started_at < duration:
            now = time.monotonic()
            if now >= next_publish:
                scan_publisher.publish(scan_message(ranges))
                next_publish = now + 0.08
            rclpy.spin_once(monitor, timeout_sec=0.03)
            if student.poll() is not None:
                break

    controller_ready = False
    # Float32 LaserScan readings cannot represent every decimal exactly.
    # Use an exactly representable boundary and neighboring values here.
    phases = [
        ("clear", [2.0] * 9),
        ("threshold", [stop_distance]),
        ("obstacle", [2.0, stop_distance - 0.05, 2.0]),
        ("above-threshold", [stop_distance + 0.05, 2.0]),
        ("mixed", [math.nan, math.inf, -1.0, 0.0, 2.0]),
        ("invalid", [math.inf, math.nan, 0.0, -1.0]),
        ("empty", []),
        ("resume", [2.0] * 9),
    ]
    phase_duration = 0.8
    try:
        controller_ready = wait_for_controller()
        # Readiness traffic must never count as scored student evidence.
        messages.clear()
        if controller_ready:
            for phase, ranges in phases:
                run_phase(phase, ranges, phase_duration)
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
    one_command = exactly_one_per_callback(audit_fd)

    settled = [item for item in messages if item[1] >= 0.25]
    by_phase = {
        phase: [item for item in settled if item[0] == phase]
        for phase, _ranges in phases
    }
    observed_duration = len(phases) * phase_duration
    publish_rate = len(settled) / observed_duration

    def forward_ok(phase: str) -> bool:
        samples = by_phase[phase]
        return bool(samples) and all(
            math.isclose(item[2], expected_linear, abs_tol=linear_tolerance)
            for item in samples
        )

    def stopped_ok(phase: str) -> bool:
        samples = by_phase[phase]
        return bool(samples) and all(abs(item[2]) <= 0.001 for item in samples)

    responds_to_each_scan_state = all(by_phase.values()) and one_command
    command_topic_ok = bool(settled) and publish_rate >= minimum_rate
    clear_ok = all(forward_ok(phase) for phase in
                   ("clear", "above-threshold", "mixed"))
    # Stopping is only evidence of obstacle handling when the same controller
    # also drives on a plainly clear scan; an always-stopped node earns none.
    moves_when_clear = forward_ok("clear")
    obstacle_ok = moves_when_clear and all(
        stopped_ok(phase) for phase in ("obstacle", "threshold")
    )
    invalid_ok = moves_when_clear and all(
        stopped_ok(phase) for phase in ("invalid", "empty")
    )
    straight_ok = moves_when_clear and all(
        abs(item[3]) <= angular_tolerance for item in settled
    )
    resume_ok = forward_ok("resume")
    node_started = controller_ready and (alive_at_end or bool(messages))
    runtime_error = (
        ""
        if alive_at_end
        else (
            student_stderr.strip()[-1000:]
            or "The obstacle_stop_controller node exited unexpectedly."
        )
    )

    tests = [
        result(
            "node-start",
            node_started,
            "The obstacle_stop_controller node started."
            if node_started
            else "The node did not become ready before the test phases began.",
        ),
        result(
            "scan-response",
            responds_to_each_scan_state,
            "Exactly one command is published per callback for clear, blocked, invalid, and restored scans."
            if responds_to_each_scan_state
            else "Use publisher queue depth 10, subscribe to /scan, and publish exactly one command per scan callback, without duplicates or skipped callbacks.",
        ),
        result(
            "cmd-vel-topic",
            command_topic_ok,
            "Twist commands were published consistently on /cmd_vel."
            if command_topic_ok
            else "Publish Twist commands consistently on /cmd_vel.",
        ),
        result(
            "clear-path-forward",
            clear_ok,
            "Clear-path forward velocity is correct."
            if clear_ok
            else "Set linear.x to 0.20 m/s when every valid obstacle distance is greater than the stop threshold.",
        ),
        result(
            "obstacle-stop",
            obstacle_ok,
            f"The robot stops when an obstacle is within {stop_distance:.2f} m."
            if obstacle_ok
            else f"Move forward on a clear scan, and publish zero linear velocity when an obstacle is at or within {stop_distance:.2f} m.",
        ),
        result(
            "invalid-scan-stop",
            invalid_ok,
            "The robot stops when the scan has no valid positive distance."
            if invalid_ok
            else "Move forward on a clear scan, and treat a scan with no finite positive distance as unsafe by publishing zero velocity.",
        ),
        result(
            "straight-motion",
            straight_ok,
            "Angular velocity remains zero."
            if straight_ok
            else "Move forward on a clear scan and keep angular.z at zero for this straight-line controller.",
        ),
        result(
            "resume-motion",
            resume_ok,
            "Forward motion resumes after the path clears."
            if resume_ok
            else "Reevaluate every scan and resume 0.20 m/s motion after the path clears.",
        ),
    ]
    print(
        json.dumps(
            {
                "error": runtime_error
                or (
                    ""
                    if all(item["passed"] for item in tests)
                    else "One or more ROS behavior requirements need attention."
                ),
                "runtime_error": runtime_error,
                "output": (
                    f"Observed {len(settled)} settled Twist messages at approximately {publish_rate:.1f} Hz."
                    + (
                        f"\nNode stderr: {student_stderr.strip()[-1000:]}"
                        if runtime_error
                        else ""
                    )
                    + (
                        f"\nNode stdout: {student_stdout.strip()[-1000:]}"
                        if student_stdout.strip()
                        else ""
                    )
                ),
                "tests": tests,
            }
        )
    )


if __name__ == "__main__":
    main()
