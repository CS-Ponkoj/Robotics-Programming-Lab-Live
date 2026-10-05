"""Observe /cmd_vel from one student node and return structured evidence."""

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
from ros2_callback_audit import (
    exactly_one_per_callback,
    launch_student,
    summarize_student_failure,
)


def result(test_id: str, passed: bool, message: str) -> dict:
    return {"id": test_id, "passed": passed, "message": message}


def motion_checks(messages, expected_linear, linear_tolerance,
                  angular_tolerance, move_seconds, stop_tolerance,
                  minimum_rate=5.0, observation_end=None):
    """Separate node-launch latency from the observed command timeline."""
    origin = messages[0][0] if messages else 0.0
    samples = [(stamp - origin, linear, angular)
               for stamp, linear, angular in messages]
    moving = [item for item in samples if item[0] < move_seconds - stop_tolerance]
    stopped = [item for item in samples
               if abs(item[1]) <= 0.001 and abs(item[2]) <= 0.001]
    first_stop = stopped[0][0] if stopped else None
    stop_ok = first_stop is not None and (
        move_seconds - stop_tolerance <= first_stop <= move_seconds + stop_tolerance
    )
    stopped_duration = stopped[-1][0] - first_stop if stopped else 0.0
    stopped_rate = (len(stopped) - 1) / stopped_duration if stopped_duration > 0 else 0.0
    observed_to_end = (
        bool(messages) and
        (observation_end is None or messages[-1][0] >= observation_end - 0.3)
    )
    forward_ok = bool(moving) and all(
        math.isclose(item[1], expected_linear, abs_tol=linear_tolerance)
        for item in moving
    )
    return {
        "forward-motion": forward_ok,
        # Straight driving is only evidence when the robot actually drives;
        # a node that never moves must not earn this credit.
        "straight-motion": forward_ok and all(
            abs(item[2]) <= angular_tolerance for item in samples
        ),
        "safe-stop": stop_ok,
        "hold-stop": stop_ok and len(stopped) >= 3
        and stopped_rate >= minimum_rate and observed_to_end and not any(
            item[0] > first_stop + 0.1
            and (abs(item[1]) > 0.001 or abs(item[2]) > 0.001)
            for item in samples
        ),
    }


def main() -> None:
    config = json.loads(os.environ.get("ROS_GRADER_CONFIG", "{}"))
    package = str(config.get("package_name", "robot_motion"))
    executable = str(config.get("executable", "controller"))
    topic = str(config.get("topic", "/cmd_vel"))
    expected_linear = float(config.get("expected_linear_x", 0.2))
    linear_tolerance = float(config.get("linear_tolerance", 0.02))
    angular_tolerance = float(config.get("angular_tolerance", 0.01))
    move_seconds = float(config.get("move_seconds", 5.0))
    stop_tolerance = float(config.get("stop_tolerance_seconds", 0.5))
    startup_grace = float(config.get("startup_grace_seconds", 2.0))
    minimum_rate = float(config.get("minimum_publish_rate_hz", 5.0))
    observation_seconds = move_seconds + startup_grace + stop_tolerance + 0.8

    messages: list[tuple[float, float, float]] = []
    student_started_at: float | None = None

    rclpy.init(args=None)
    monitor = Node(f"grader_cmd_vel_monitor_{os.getpid()}")

    def receive(message: Twist) -> None:
        now = time.monotonic()
        if student_started_at is None:
            return
        messages.append(
            (
                now - student_started_at,
                float(message.linear.x),
                float(message.angular.z),
            )
        )

    monitor.create_subscription(Twist, topic, receive, 10)
    # Give the monitoring participant time to advertise its subscription before
    # the student's five-second timer starts. This reduces DDS discovery loss on
    # cold or resource-constrained runners.
    monitor_ready_at = time.monotonic() + 0.5
    while time.monotonic() < monitor_ready_at:
        rclpy.spin_once(monitor, timeout_sec=0.05)

    student_started_at = time.monotonic()
    student, audit_fd = launch_student(package, executable, "timer", topic)
    started_at = time.monotonic()
    try:
        while time.monotonic() - started_at < observation_seconds:
            rclpy.spin_once(monitor, timeout_sec=0.05)
            if student.poll() is not None:
                break
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

    duration = messages[-1][0] - messages[0][0] if len(messages) > 1 else 0.0
    publish_rate = (len(messages) - 1) / duration if duration > 0 else 0.0
    checks = motion_checks(messages, expected_linear, linear_tolerance,
                           angular_tolerance, move_seconds, stop_tolerance,
                           minimum_rate, observation_seconds)
    forward_ok = checks["forward-motion"]
    straight_ok = checks["straight-motion"]
    stop_ok = checks["safe-stop"]
    held_stop = checks["hold-stop"]
    runtime_error = (
        ""
        if alive_at_end
        else summarize_student_failure(student_stderr, student.returncode)
    )
    publishing_ok = bool(messages) and publish_rate >= minimum_rate and one_command
    # A node that is alive but went quiet (for example, a cancelled timer)
    # needs that fact first, not a generic queue-depth reminder.
    last_message = messages[-1][0] if messages else 0.0
    went_quiet = alive_at_end and bool(messages) and last_message < observation_seconds - 1.0
    if publishing_ok:
        publishing_message = "Exactly one Twist command was published per timer callback on /cmd_vel."
    elif went_quiet:
        publishing_message = (
            f"Your node stopped publishing about {last_message:.1f} s after it started. "
            "Publish exactly one command in every 0.1-second callback, including after the stop."
        )
    else:
        publishing_message = (
            "Use queue depth 10 and a 0.1-second timer; publish exactly one Twist command "
            "on /cmd_vel in every callback, without duplicates or skipped callbacks."
        )

    tests = [
        result(
            "node-start",
            alive_at_end or bool(messages),
            "The robot_controller node started." if alive_at_end or messages else "The robot_controller node exited before it could be tested.",
        ),
        result("cmd-vel-topic", publishing_ok, publishing_message),
        result(
            "forward-motion",
            forward_ok,
            "Forward velocity is correct." if forward_ok else "Set linear.x to 0.20 m/s during the movement period.",
        ),
        result(
            "straight-motion",
            straight_ok,
            "Angular velocity remains zero while driving forward." if straight_ok else "Drive forward at 0.20 m/s and keep angular.z at zero.",
        ),
        result(
            "safe-stop",
            stop_ok,
            "The robot stops after approximately five seconds." if stop_ok else "Publish a zero-velocity command after approximately five seconds.",
        ),
        result(
            "hold-stop",
            held_stop,
            "The stopped state continues to be published." if held_stop else "Continue publishing zero velocity after stopping.",
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
                    f"Observed {len(messages)} Twist messages at approximately {publish_rate:.1f} Hz."
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
