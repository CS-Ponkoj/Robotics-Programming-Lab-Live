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


STOP_TOLERANCE = 0.001
UNUSED_AXES_MESSAGE = "Keep linear.y, linear.z, angular.x and angular.y at 0.0."


def result(test_id: str, passed: bool, message: str) -> dict:
    return {"id": test_id, "passed": passed, "message": message}


def unused_axes_zero(item) -> bool:
    """linear.y, linear.z, angular.x and angular.y (item[3:]) must stay 0.0."""
    return all(math.isfinite(value) and abs(value) <= STOP_TOLERANCE
               for value in item[3:])


def is_stop(item) -> bool:
    """A stop command has all six Twist fields at zero."""
    return (abs(item[1]) <= STOP_TOLERANCE and abs(item[2]) <= STOP_TOLERANCE
            and unused_axes_zero(item))


def motion_checks(messages, expected_linear, linear_tolerance,
                  angular_tolerance, move_seconds, stop_tolerance,
                  minimum_rate=5.0, observation_end=None):
    """Separate node-launch latency from the observed command timeline."""
    return motion_evidence(messages, expected_linear, linear_tolerance,
                           angular_tolerance, move_seconds, stop_tolerance,
                           minimum_rate, observation_end)["checks"]


def motion_evidence(messages, expected_linear, linear_tolerance,
                    angular_tolerance, move_seconds, stop_tolerance,
                    minimum_rate=5.0, observation_end=None):
    """Return the motion checks plus the reason forward motion failed."""
    origin = messages[0][0] if messages else 0.0
    samples = [(item[0] - origin, *item[1:]) for item in messages]
    stopped = [item for item in samples if is_stop(item)]
    unused_ok = all(unused_axes_zero(item) for item in samples)
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
    # Every command before the first stop is part of the drive, including
    # the commands just before the switch, so none may use another speed.
    driving = [item for item in samples
               if first_stop is None or item[0] < first_stop]
    wrong_speed = next(
        (item for item in driving
         if not math.isclose(item[1], expected_linear, abs_tol=linear_tolerance)),
        None,
    )
    # Driving forward is only credited for a drive that ends in a stop:
    # a robot that never stops has not completed the motion it was given.
    if not driving:
        forward_problem = "no-drive"
    elif wrong_speed is not None:
        forward_problem = "wrong-speed"
    elif first_stop is None:
        forward_problem = "never-stopped"
    elif first_stop < move_seconds - stop_tolerance:
        forward_problem = "stopped-early"
    else:
        forward_problem = ""
    forward_ok = not forward_problem
    checks = {
        "forward-motion": forward_ok,
        # Straight driving is only evidence when the robot actually drives
        # and then stops; a node that never moves or never stops earns none.
        # The unused components must stay zero in every command, moving or stopped.
        "straight-motion": forward_ok and unused_ok and all(
            abs(item[2]) <= angular_tolerance for item in samples
        ),
        "safe-stop": stop_ok,
        "hold-stop": stop_ok and len(stopped) >= 3
        and stopped_rate >= minimum_rate and observed_to_end and not any(
            item[0] > first_stop + 0.1 and not is_stop(item)
            for item in samples
        ),
        "unused-axes-zero": unused_ok,
    }
    return {
        "checks": checks,
        "forward_problem": forward_problem,
        "wrong_speed": wrong_speed,
        "first_stop": first_stop,
    }


def forward_message(evidence, expected_linear: float) -> str:
    problem = evidence["forward_problem"]
    if not problem:
        return "Forward velocity is correct, and the drive ends with a stop."
    if problem == "wrong-speed":
        item = evidence["wrong_speed"]
        return (
            f"At {item[0]:.1f} s after the first command, linear.x was {item[1]:.2f} m/s. "
            f"Every command before the stop must use linear.x = {expected_linear:.2f} m/s; "
            "then switch directly to a full stop."
        )
    if problem == "never-stopped":
        return (
            "The robot never stopped. Forward-motion credit requires driving at "
            f"{expected_linear:.2f} m/s and then publishing zero velocity after about five seconds."
        )
    if problem == "stopped-early":
        return (
            f"The robot stopped {evidence['first_stop']:.1f} s after the first command. "
            f"Keep linear.x at {expected_linear:.2f} m/s for about five seconds before stopping."
        )
    return f"Set linear.x to {expected_linear:.2f} m/s during the movement period."


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

    messages: list[tuple[float, ...]] = []
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
                float(message.linear.y),
                float(message.linear.z),
                float(message.angular.x),
                float(message.angular.y),
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
    evidence = motion_evidence(messages, expected_linear, linear_tolerance,
                               angular_tolerance, move_seconds, stop_tolerance,
                               minimum_rate, observation_seconds)
    checks = evidence["checks"]
    forward_ok = checks["forward-motion"]
    straight_ok = checks["straight-motion"]
    stop_ok = checks["safe-stop"]
    held_stop = checks["hold-stop"]
    unused_ok = checks["unused-axes-zero"]
    unused_hint = "" if unused_ok else " " + UNUSED_AXES_MESSAGE
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
            forward_message(evidence, expected_linear),
        ),
        result(
            "straight-motion",
            straight_ok,
            "Angular velocity remains zero while driving forward." if straight_ok else "Drive forward at 0.20 m/s, keep angular.z at zero, and then stop." + unused_hint,
        ),
        result(
            "safe-stop",
            stop_ok,
            "The robot stops after approximately five seconds." if stop_ok else "Publish a zero-velocity command after approximately five seconds." + unused_hint,
        ),
        result(
            "hold-stop",
            held_stop,
            "The stopped state continues to be published." if held_stop else "Continue publishing zero velocity after stopping." + unused_hint,
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
