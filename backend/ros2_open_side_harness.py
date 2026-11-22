"""Publish made-up rse_msgs/Flbr distances and observe the student's /cmd_vel.

The student fills in a given node: a /cmd_vel publisher, an /flbr
subscription, and a callback that drives forward when the front is clear and
otherwise stops and turns toward the side with more space. Every command is
judged against the Flbr message that triggered it, and each check judges only
its own rule: the speed is judged by clear-path-forward, the turn direction by
the turn checks, and stopping by the stop checks.
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
    output_tail,
    callback_contract_problem,
    launch_student,
    one_per_callback,
    read_audit,
    summarize_student_failure,
)
from ros2_obstacle_harness import attribute_commands, unused_axes_zero


STOP_TOLERANCE = 0.001
TURN_TOLERANCE = 0.05
PHASE_SECONDS = 0.8
MESSAGE_PERIOD = 0.08
# Checks that compare commands with the message that triggered them.
OUTSIDE_UNJUDGED = frozenset({
    "clear-path-forward", "stop-when-blocked", "turn-toward-open-side",
    "stop-at-threshold", "equal-sides-turn-right", "unknown-distance-safe",
    "resume-forward",
})
UNUSED_AXES_MESSAGE = "Keep linear.y, linear.z, angular.x and angular.y at 0.0."
# Readiness uses clear fronts only, so a node that latches its first decision
# always latches "drive" and scores the same on every run. Only a node that
# subscribed but has not answered a clear front for this long also gets
# blocked fronts, so a node that answers only those can still start.
CLEAR_ONLY_AFTER_SUBSCRIBED_SECONDS = 1.5
BLOCKED_PHASES = ("left-open", "right-open", "threshold", "sides-equal", "front-unknown", "side-unknown")
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


def result(test_id: str, passed: bool, message: str, status: str = "") -> dict:
    item = {"id": test_id, "passed": passed, "message": message}
    if status and not passed:
        item["status"] = status
    return item


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

    subscribed = [False]

    def wait_for_controller(timeout: float = 5.0) -> bool:
        """Wait for ROS discovery and one end-to-end reply.

        Readiness sends clear fronts only, so every node sees the same input
        before scoring. Only when the node has been subscribed for a while
        without answering do blocked fronts follow (alternating), so a node
        that answers only those still counts as started and the scored
        situations then show exactly what it skips.
        """
        deadline = time.monotonic() + timeout
        next_publish = time.monotonic()
        subscribed_at = None
        clear = True
        while time.monotonic() < deadline:
            if student.poll() is not None:
                return False
            now = time.monotonic()
            if now >= next_publish:
                values = (2.0, 1.0, 1.0, 1.0) if clear else (0.5, 2.0, 1.0, 1.0)
                flbr_publisher.publish(flbr_message(*values))
                if (
                    subscribed_at is not None
                    and now - subscribed_at >= CLEAR_ONLY_AFTER_SUBSCRIBED_SECONDS
                ):
                    clear = not clear
                next_publish = now + MESSAGE_PERIOD
            rclpy.spin_once(monitor, timeout_sec=0.03)
            if flbr_publisher.get_subscription_count() > 0:
                subscribed[0] = True
                if subscribed_at is None:
                    subscribed_at = time.monotonic()
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
    audit = read_audit(audit_fd)
    one_command = one_per_callback(audit)

    paired, _exact = attribute_commands(sent, messages)
    settled = [(phase, *command) for phase, command in paired]
    by_phase = {
        name: [item for item in settled if item[0] == name] for name, *_values in PHASES
    }
    publish_rate = len(messages) / (len(PHASES) * PHASE_SECONDS)

    def drives(phase: str) -> bool:
        """Straight ahead at the configured speed."""
        samples = by_phase[phase]
        return bool(samples) and all(
            math.isclose(item[2], forward_speed, abs_tol=linear_tolerance)
            and abs(item[3]) <= STOP_TOLERANCE
            and unused_axes_zero(item)
            for item in samples
        )

    def moves_forward(phase: str) -> bool:
        """Forward (any speed) without turning; the speed has its own check."""
        samples = by_phase[phase]
        return bool(samples) and all(
            item[2] > STOP_TOLERANCE and abs(item[3]) <= STOP_TOLERANCE for item in samples
        )

    def stopped_forward(phase: str) -> bool:
        samples = by_phase[phase]
        return bool(samples) and all(
            abs(item[2]) <= STOP_TOLERANCE and unused_axes_zero(item) for item in samples
        )

    def turns(phase: str, direction: float) -> bool:
        """The turn direction and speed only; stopping is judged separately."""
        samples = by_phase[phase]
        return bool(samples) and all(
            math.isclose(item[3], direction * turn_speed, abs_tol=TURN_TOLERANCE)
            and unused_axes_zero(item)
            for item in samples
        )

    node_started = controller_ready and (alive_at_end or bool(messages))
    callback_failed = not alive_at_end and audit["events"]["F"] > 0
    if callback_failed:
        reason = "Not checked: the node stopped with an error while handling a /flbr message."
    elif not alive_at_end:
        reason = "Not checked: the node stopped before this situation."
    elif audit["events"]["B"] > len(audit["counts"]):
        reason = "Not checked: the /flbr callback never finished (a loop or a wait blocks it), so the node stopped publishing."
    else:
        reason = None

    def unjudged(*phases: str) -> bool:
        return reason is not None and any(not by_phase[phase] for phase in phases)

    withheld = "Not credited yet: this counts only once the robot also drives forward when the front is clear."
    # Stopping and turning count only once the robot drives forward (at any
    # speed) when the front is clear; the exact speed is judged on its own.
    moves_when_clear = moves_forward("clear")
    responds = all(by_phase.values()) and one_command
    command_topic_ok = bool(settled) and publish_rate >= minimum_rate
    blocked_phases = ("left-open", "right-open", "sides-equal")
    clear_ok = drives("clear") and drives("clear-sides-differ")
    stop_rule = all(stopped_forward(phase) for phase in blocked_phases)
    turn_rule = turns("left-open", 1.0) and turns("right-open", -1.0)
    threshold_rule = stopped_forward("threshold")
    tie_rule = turns("sides-equal", -1.0)
    unknown_rule = (
        stopped_forward("front-unknown")
        and turns("front-unknown", 1.0)
        and turns("side-unknown", 1.0)
    )
    # Recovery needs an earlier stop of forward motion; a stray value on an
    # unused axis is judged by the other checks, not here.
    stopped_somewhere = any(
        bool(by_phase[phase]) and all(abs(item[2]) <= STOP_TOLERANCE for item in by_phase[phase])
        for phase in BLOCKED_PHASES
    )
    resume_ok = moves_forward("resume") and stopped_somewhere
    unused_ok = all(unused_axes_zero(item) for item in settled)
    unused_hint = "" if unused_ok else " " + UNUSED_AXES_MESSAGE
    drive_rule = f"linear.x = {forward_speed:.2f} and angular.z = 0.0"
    runtime_error = (
        "" if alive_at_end else summarize_student_failure(student_stderr, student.returncode)
    )

    def gated(test_id: str, rule_ok: bool, phases: tuple, ok_message: str, rule_message: str) -> dict:
        if moves_when_clear and rule_ok:
            return result(test_id, True, ok_message)
        if unjudged(*phases):
            return result(test_id, False, reason, "not_run")
        if rule_ok:
            return result(test_id, False, withheld)
        return result(test_id, False, rule_message)

    def clear_message() -> str:
        samples = by_phase["clear"] + by_phase["clear-sides-differ"]
        if samples and all(item[2] > STOP_TOLERANCE for item in samples) and not all(
            math.isclose(item[2], forward_speed, abs_tol=linear_tolerance) for item in samples
        ):
            fastest = max(item[2] for item in samples)
            slowest = min(item[2] for item in samples)
            shown = (
                f"{fastest:.2f}" if math.isclose(fastest, slowest, abs_tol=0.005)
                else f"{slowest:.2f} to {fastest:.2f}"
            )
            return (
                f"With the front clear, linear.x was {shown} m/s; drive at "
                f"{forward_speed:.2f} m/s with angular.z = 0.0." + unused_hint
            )
        return (
            f"When the front distance is more than 0.75 m, drive straight: {drive_rule}, "
            "even when one side has more space." + unused_hint
        )

    contract_unjudged = not responds and reason is not None and 1 not in audit["counts"]
    if responds:
        flbr_text = "Exactly one command is published for every /flbr message."
    elif contract_unjudged:
        flbr_text = reason
    else:
        problem = callback_contract_problem(audit, "/flbr")
        missing = [name for name, *_values in PHASES if not by_phase[name]]
        if not problem and missing:
            problem = (
                "Some /flbr messages got no command (" + ", ".join(missing) + "). "
                "Publish one Twist in every callback, whatever the distances."
            )
        flbr_text = (
            (problem + " " if problem else "")
            + "Each command is checked against the /flbr message that triggered it."
        )

    tests = [
        result(
            "node-start",
            node_started,
            "The open_side_controller node started."
            if node_started
            # The feedback classifier adds the observed cause (unfinished wiring
            # or a callback that never answers) from the observations below.
            else (
                "The node started, but it stopped with an error while handling its first "
                "/flbr message, so it never published on /cmd_vel."
                if callback_failed
                else "The node did not start publishing on /cmd_vel within 5 seconds."
            ),
        ),
        result("flbr-response", responds, flbr_text, "not_run" if contract_unjudged else ""),
        (
            result("cmd-vel-topic", True, "Twist commands were published consistently on /cmd_vel.")
            if command_topic_ok
            else result("cmd-vel-topic", False, reason, "not_run") if reason and not settled
            else result("cmd-vel-topic", False, "Publish a Twist on /cmd_vel for every /flbr message.")
        ),
        (
            result(
                "clear-path-forward", True,
                f"With the front clear the robot drives straight ({drive_rule}).",
            )
            if clear_ok
            else result("clear-path-forward", False, reason, "not_run")
            if unjudged("clear", "clear-sides-differ")
            else result("clear-path-forward", False, clear_message())
        ),
        gated(
            "stop-when-blocked", stop_rule, blocked_phases,
            "The robot stops driving forward when the front is 0.75 m or closer.",
            "When the front distance is 0.75 m or less, set linear.x to 0.0." + unused_hint,
        ),
        gated(
            "turn-toward-open-side", turn_rule, ("left-open", "right-open"),
            "The robot turns toward the side with more space.",
            f"When the front is blocked, turn toward the side with more space: "
            f"angular.z = +{turn_speed:.1f} (left) when left is greater than right, "
            f"-{turn_speed:.1f} (right) otherwise.",
        ),
        gated(
            "stop-at-threshold", threshold_rule, ("threshold",),
            "A front distance of exactly 0.75 m counts as blocked.",
            "A front distance of exactly 0.75 m is blocked: set linear.x to 0.0, and drive "
            "only when the front is greater than 0.75 m.",
        ),
        gated(
            "equal-sides-turn-right", tie_rule, ("sides-equal",),
            "With equal side distances the robot turns right.",
            f"When left and right are equal, left is not greater, so turn right "
            f"(angular.z = -{turn_speed:.1f}).",
        ),
        gated(
            "unknown-distance-safe", unknown_rule, ("front-unknown", "side-unknown"),
            "Unknown (NaN) distances are treated as no space.",
            "Treat a NaN distance as no space (0.0): an unknown front means stop and turn, "
            "and never turn toward an unknown side.",
        ),
        (
            result("resume-forward", True, "The robot drives straight again once the front clears.")
            if resume_ok
            else result("resume-forward", False, reason, "not_run") if unjudged("resume")
            else result(
                "resume-forward", False,
                "Recovery only counts after the robot stopped for a blocked front; then "
                "drive straight again when the front clears.",
            )
            if moves_forward("resume")
            else result(
                "resume-forward", False,
                f"Decide again for every message: when the front clears, publish {drive_rule} again.",
            )
        ),
    ]
    # Commands published outside the /flbr callback (for example from a timer)
    # cannot be tied to the message that triggered them, so the behaviour
    # checks are not judged: the result would depend on timing, not the code.
    if audit["events"]["O"]:
        mixed = (
            "Not checked: the node also published commands outside the /flbr callback, "
            "so its commands cannot be matched to the messages that triggered them."
        )
        tests = [
            result(item["id"], False, mixed, "not_run")
            if item["id"] in OUTSIDE_UNJUDGED
            else item
            for item in tests
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
                    # How the node behaved before the scored situations.
                    "started": node_started,
                    "subscribed": subscribed[0],
                    "alive": alive_at_end,
                    # True when the node stopped with an error inside its callback.
                    "callback_failed": callback_failed,
                    "callbacks": {
                        "count": len(audit["counts"]),
                        "max_commands": max(audit["counts"], default=0),
                        "skipped": sum(1 for count in audit["counts"] if count == 0),
                        "published_outside": bool(audit["events"]["O"]),
                        "queue_depth_wrong": bool(audit["events"]["Q"]),
                    },
                    # True when a command set linear.y, linear.z, angular.x or angular.y.
                    "unused_axes_used": not unused_ok,
                },
                "error": runtime_error
                or ("" if all(item["passed"] for item in tests) else "One or more ROS behavior requirements need attention."),
                "runtime_error": runtime_error,
                "output": (
                    f"Observed {len(messages)} Twist messages for {len(sent)} /flbr messages at about {publish_rate:.1f} Hz."
                    + (f"\nNode stdout: {output_tail(student_stdout)}" if student_stdout.strip() else "")
                ),
                "tests": tests,
            }
        )
    )


if __name__ == "__main__":
    main()
