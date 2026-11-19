"""Publish made-up rse_msgs/Flbr distances and observe the student's /cmd_vel.

The student fills in a given node: a /cmd_vel publisher, an /flbr
subscription, and a callback that drives forward when the front is clear and
otherwise stops and turns toward the side with more space. Every command is
judged against the Flbr message that triggered it.
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
from rse_msgs.msg import Flbr
from ros2_callback_audit import (
    exactly_one_per_callback,
    launch_student,
    summarize_student_failure,
)
from ros2_obstacle_harness import attribute_commands, unused_axes_zero


STOP_TOLERANCE = 0.001
TURN_TOLERANCE = 0.05
PHASE_SECONDS = 0.8
MESSAGE_PERIOD = 0.08
UNUSED_AXES_MESSAGE = "Keep linear.y, linear.z, angular.x and angular.y at 0.0."
NAN = math.nan

# (phase, front, left, back, right). Float32 fields: use values that are
# exactly representable so the 0.75 m boundary is tested exactly.
PHASES = [
    ("clear", 2.0, 1.0, 1.0, 1.0),
    ("clear-sides-differ", 2.0, 3.0, 1.0, 0.5),
    ("left-open", 0.5, 2.5, 1.0, 1.0),
    ("right-open", 0.5, 1.0, 1.0, 2.5),
    ("threshold", 0.75, 1.0, 1.0, 2.0),
    ("sides-equal", 0.5, 1.5, 1.0, 1.5),
    ("front-unknown", NAN, 2.0, 1.0, 1.0),
    # Right unknown: "left > right" is False against NaN, so a NaN-naive rule
    # wrongly turns right, toward the unknown side.
    ("side-unknown", 0.5, 1.0, 1.0, NAN),
    ("resume", 2.0, 1.0, 1.0, 1.0),
]


def result(test_id: str, passed: bool, message: str) -> dict:
    return {"id": test_id, "passed": passed, "message": message}


def main() -> None:
    config = json.loads(os.environ.get("ROS_GRADER_CONFIG", "{}"))
    package = str(config.get("package_name", "open_side"))
    executable = str(config.get("executable", "controller"))
    command_topic = str(config.get("topic", "/cmd_vel"))
    flbr_topic = str(config.get("flbr_topic", "/flbr"))
    forward_speed = float(config.get("expected_linear_x", 0.20))
    turn_speed = float(config.get("turn_angular_z", 0.5))
    linear_tolerance = float(config.get("linear_tolerance", 0.02))
    minimum_rate = float(config.get("minimum_publish_rate_hz", 3.0))

    messages: list[tuple] = []
    sent: list[tuple[float, str]] = []

    rclpy.init(args=None)
    monitor = Node(f"grader_open_side_monitor_{os.getpid()}")

    def receive(message: Twist) -> None:
        messages.append(
            (
                time.monotonic(),
                float(message.linear.x),
                float(message.angular.z),
                float(message.linear.y),
                float(message.linear.z),
                float(message.angular.x),
                float(message.angular.y),
            )
        )

    monitor.create_subscription(Twist, command_topic, receive, 10)
    flbr_publisher = monitor.create_publisher(Flbr, flbr_topic, 10)
    student, audit_fd = launch_student(
        package, executable, "scan", command_topic, flbr_topic,
    )

    def flbr_message(front: float, left: float, back: float, right: float) -> Flbr:
        message = Flbr()
        message.header.stamp = monitor.get_clock().now().to_msg()
        message.header.frame_id = "base_link"
        message.front = front
        message.left = left
        message.back = back
        message.right = right
        return message

    def wait_for_controller(timeout: float = 5.0) -> bool:
        """Wait for ROS discovery and one end-to-end reply."""
        deadline = time.monotonic() + timeout
        next_publish = time.monotonic()
        while time.monotonic() < deadline:
            if student.poll() is not None:
                return False
            now = time.monotonic()
            if now >= next_publish:
                flbr_publisher.publish(flbr_message(2.0, 1.0, 1.0, 1.0))
                next_publish = now + MESSAGE_PERIOD
            rclpy.spin_once(monitor, timeout_sec=0.03)
            if (
                flbr_publisher.get_subscription_count() > 0
                and monitor.count_publishers(command_topic) > 0
                and messages
            ):
                return True
        return False

    def drain(expected: int, limit: float, quiet: float) -> None:
        """Spin without publishing until replies stop or all are counted."""
        started = time.monotonic()
        last_count, last_change = len(messages), started
        while time.monotonic() - started < limit:
            rclpy.spin_once(monitor, timeout_sec=0.02)
            now = time.monotonic()
            if len(messages) != last_count:
                last_count, last_change = len(messages), now
            if expected and len(messages) >= expected:
                return
            if now - last_change >= quiet:
                return
            if student.poll() is not None:
                return

    def run_phase(name: str, values: tuple[float, float, float, float]) -> None:
        started = time.monotonic()
        next_publish = started
        while time.monotonic() - started < PHASE_SECONDS:
            now = time.monotonic()
            if now >= next_publish:
                sent.append((time.monotonic(), name))
                flbr_publisher.publish(flbr_message(*values))
                next_publish = now + MESSAGE_PERIOD
            rclpy.spin_once(monitor, timeout_sec=0.03)
            if student.poll() is not None:
                break

    controller_ready = False
    try:
        controller_ready = wait_for_controller()
        if controller_ready:
            # Replies to readiness messages must not count as scored evidence.
            drain(0, 2.0, 0.3)
        messages.clear()
        if controller_ready:
            for name, *values in PHASES:
                run_phase(name, tuple(values))
            drain(len(sent), 1.0, 0.5)
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

    paired, _exact = attribute_commands(sent, messages)
    settled = [(phase, *command) for phase, command in paired]
    by_phase = {
        name: [item for item in settled if item[0] == name] for name, *_values in PHASES
    }
    publish_rate = len(messages) / (len(PHASES) * PHASE_SECONDS)

    def matches(phase: str, linear: float, angular: float) -> bool:
        samples = by_phase[phase]
        return bool(samples) and all(
            math.isclose(item[2], linear, abs_tol=linear_tolerance if linear else STOP_TOLERANCE)
            and math.isclose(item[3], angular, abs_tol=TURN_TOLERANCE if angular else STOP_TOLERANCE)
            and unused_axes_zero(item)
            for item in samples
        )

    def drives(phase: str) -> bool:
        return matches(phase, forward_speed, 0.0)

    def stopped_forward(phase: str) -> bool:
        samples = by_phase[phase]
        return bool(samples) and all(
            abs(item[2]) <= STOP_TOLERANCE and unused_axes_zero(item) for item in samples
        )

    def turns(phase: str, direction: float) -> bool:
        return matches(phase, 0.0, direction * turn_speed)

    moves_when_clear = drives("clear")
    responds = all(by_phase.values()) and one_command
    command_topic_ok = bool(settled) and publish_rate >= minimum_rate
    clear_ok = moves_when_clear and drives("clear-sides-differ")
    stop_ok = moves_when_clear and all(
        stopped_forward(phase) for phase in ("left-open", "right-open", "threshold", "sides-equal")
    )
    turn_ok = moves_when_clear and turns("left-open", 1.0) and turns("right-open", -1.0)
    threshold_ok = moves_when_clear and turns("threshold", -1.0)
    tie_ok = moves_when_clear and turns("sides-equal", -1.0)
    unknown_ok = moves_when_clear and turns("front-unknown", 1.0) and turns("side-unknown", 1.0)
    resume_ok = drives("resume") and stop_ok
    unused_ok = all(unused_axes_zero(item) for item in settled)
    unused_hint = "" if unused_ok else " " + UNUSED_AXES_MESSAGE
    each_hint = " Each command is checked against the /flbr message that triggered it."
    drive_rule = f"linear.x = {forward_speed:.2f} and angular.z = 0.0"
    node_started = controller_ready and (alive_at_end or bool(messages))
    runtime_error = (
        "" if alive_at_end else summarize_student_failure(student_stderr, student.returncode)
    )

    tests = [
        result(
            "node-start",
            node_started,
            "The open_side_controller node started."
            if node_started
            else "The node did not start publishing on /cmd_vel within 5 seconds.",
        ),
        result(
            "flbr-response",
            responds,
            "Exactly one command is published for every /flbr message."
            if responds
            else "Use publisher queue depth 10, subscribe to Flbr on /flbr, and publish exactly one Twist in each callback, without skipping or doubling.",
        ),
        result(
            "cmd-vel-topic",
            command_topic_ok,
            "Twist commands were published consistently on /cmd_vel."
            if command_topic_ok
            else "Publish a Twist on /cmd_vel for every /flbr message.",
        ),
        result(
            "clear-path-forward",
            clear_ok,
            f"With the front clear the robot drives straight ({drive_rule})."
            if clear_ok
            else f"When the front distance is more than 0.75 m, drive straight: {drive_rule}, even when one side has more space." + each_hint + unused_hint,
        ),
        result(
            "stop-when-blocked",
            stop_ok,
            "The robot stops driving forward when the front is 0.75 m or closer."
            if stop_ok
            else "When the front distance is 0.75 m or less, set linear.x to 0.0. Stopping only counts once the robot also drives when the front is clear." + each_hint + unused_hint,
        ),
        result(
            "turn-toward-open-side",
            turn_ok,
            "The robot turns toward the side with more space."
            if turn_ok
            else f"When the front is blocked, turn toward the side with more space: angular.z = +{turn_speed:.1f} (left) when left is greater than right, -{turn_speed:.1f} (right) otherwise." + each_hint,
        ),
        result(
            "stop-at-threshold",
            threshold_ok,
            "A front distance of exactly 0.75 m counts as blocked."
            if threshold_ok
            else "A front distance of exactly 0.75 m is blocked: drive only when the front is greater than 0.75 m." + each_hint,
        ),
        result(
            "equal-sides-turn-right",
            tie_ok,
            "With equal side distances the robot turns right."
            if tie_ok
            else f"When left and right are equal, left is not greater, so turn right (angular.z = -{turn_speed:.1f})." + each_hint,
        ),
        result(
            "unknown-distance-safe",
            unknown_ok,
            "Unknown (NaN) distances are treated as no space."
            if unknown_ok
            else "Treat a NaN distance as no space (0.0): an unknown front means stop and turn, and never turn toward an unknown side." + each_hint,
        ),
        result(
            "resume-forward",
            resume_ok,
            "The robot drives straight again once the front clears."
            if resume_ok
            else (
                "Recovery only counts after the robot stopped for a blocked front; then drive straight again when the front clears."
                if drives("resume")
                else f"Decide again for every message: when the front clears, publish {drive_rule} again."
            ),
        ),
    ]

    def phase_summary(phase: str) -> dict:
        items = by_phase[phase]
        if not items:
            return {"count": 0}
        return {
            "count": len(items),
            "linear_min": round(min(item[2] for item in items), 3),
            "linear_max": round(max(item[2] for item in items), 3),
            "angular_min": round(min(item[3] for item in items), 3),
            "angular_max": round(max(item[3] for item in items), 3),
        }

    print(
        json.dumps(
            {
                "observations": {
                    "phases": {name: phase_summary(name) for name, *_values in PHASES},
                    "rate_hz": round(publish_rate, 2),
                },
                "error": runtime_error
                or ("" if all(item["passed"] for item in tests) else "One or more ROS behavior requirements need attention."),
                "runtime_error": runtime_error,
                "output": (
                    f"Observed {len(messages)} Twist messages for {len(sent)} /flbr messages at about {publish_rate:.1f} Hz."
                    + (f"\nNode stdout: {student_stdout.strip()[-1000:]}" if student_stdout.strip() else "")
                ),
                "tests": tests,
            }
        )
    )


if __name__ == "__main__":
    main()
