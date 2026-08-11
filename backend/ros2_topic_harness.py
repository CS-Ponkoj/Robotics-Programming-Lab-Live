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


def result(test_id: str, passed: bool, message: str) -> dict:
    return {"id": test_id, "passed": passed, "message": message}


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
    minimum_rate = float(config.get("minimum_publish_rate_hz", 5.0))
    observation_seconds = move_seconds + stop_tolerance + 0.8

    messages: list[tuple[float, float, float]] = []
    first_message_at: float | None = None

    rclpy.init(args=None)
    monitor = Node(f"grader_cmd_vel_monitor_{os.getpid()}")

    def receive(message: Twist) -> None:
        nonlocal first_message_at
        now = time.monotonic()
        if first_message_at is None:
            first_message_at = now
        messages.append(
            (now - first_message_at, float(message.linear.x), float(message.angular.z))
        )

    monitor.create_subscription(Twist, topic, receive, 10)
    student = subprocess.Popen(
        ["ros2", "run", package, executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
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

    duration = messages[-1][0] - messages[0][0] if len(messages) > 1 else 0.0
    publish_rate = (len(messages) - 1) / duration if duration > 0 else 0.0
    moving = [item for item in messages if item[0] <= move_seconds - 0.3]
    stopped = [item for item in messages if abs(item[1]) <= 0.001 and abs(item[2]) <= 0.001]
    first_stop = stopped[0][0] if stopped else None
    forward_ok = bool(moving) and all(
        math.isclose(item[1], expected_linear, abs_tol=linear_tolerance)
        for item in moving
    )
    straight_ok = bool(messages) and all(
        abs(item[2]) <= angular_tolerance for item in messages
    )
    stop_ok = first_stop is not None and (
        move_seconds - stop_tolerance <= first_stop <= move_seconds + stop_tolerance
    )
    held_stop = stop_ok and sum(item[0] >= first_stop for item in stopped) >= 3 and not any(
        item[0] > first_stop + 0.1 and abs(item[1]) > 0.001 for item in messages
    )
    runtime_error = (
        ""
        if alive_at_end
        else (
            student_stderr.strip()[-1000:]
            or "The robot_controller node exited unexpectedly."
        )
    )

    tests = [
        result(
            "node-start",
            alive_at_end or bool(messages),
            "The robot_controller node started." if alive_at_end or messages else "The robot_controller node exited before it could be tested.",
        ),
        result(
            "cmd-vel-topic",
            bool(messages) and publish_rate >= minimum_rate,
            "Twist messages were published consistently on /cmd_vel." if messages and publish_rate >= minimum_rate else "Publish Twist messages consistently on /cmd_vel.",
        ),
        result(
            "forward-motion",
            forward_ok,
            "Forward velocity is correct." if forward_ok else "Set linear.x to 0.20 m/s during the movement period.",
        ),
        result(
            "straight-motion",
            straight_ok,
            "Angular velocity remains zero." if straight_ok else "Keep angular.z at zero while driving straight.",
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
