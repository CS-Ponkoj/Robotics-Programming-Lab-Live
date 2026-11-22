"""Drive the student's node in a small 2D world and record a replay.

The robot moves with the latest /cmd_vel command and every /scan is computed
from where the robot is now, so the student's node controls the robot in a
closed loop. The replay is for students to watch; it never changes grading.

Assignments whose node reads the course's four-sector summary instead of the
raw scan set ``flbr_topic`` in their grader config; the harness then publishes
rse_msgs/Flbr computed from the same simulated scan.
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
    RETURNED_NON_NODE_MESSAGE,
    build_state,
    launch_student,
    read_audit,
    summarize_student_failure,
)
from ros2_sim_world import (
    RANGE_MAX, RANGE_MIN, SCAN_BEAMS, SCAN_INCREMENT_DEG, SCAN_MIN_DEG, Simulation, flbr,
    scan,
)


PHYSICS_PERIOD = 0.02
SCAN_PERIOD = 0.08
READY_TIMEOUT = 5.0

# Beam probe: which readings does the node react to?
PROBE_BEAM_STEP = 3          # one probe group per drawn beam (91 beams -> 31)
PROBE_CLEAR = 3.0            # beyond any allowed stop distance
PROBE_NEAR = 0.15            # closer than any allowed stop distance
PROBE_REPLY_TIMEOUT = 0.25
PROBE_BUDGET_SECONDS = 2.5
PROBE_LATEST_START = 11.0    # seconds after start; the harness limit is 16 s
STOPPED = 0.001


def probe_groups() -> list[list[int]]:
    """Raw beam indices for each drawn beam: the beam and its neighbours."""
    groups = []
    for center in range(0, SCAN_BEAMS, PROBE_BEAM_STEP):
        groups.append([
            index for index in (center - 1, center, center + 1) if 0 <= index < SCAN_BEAMS
        ])
    return groups


def main() -> None:
    config = json.loads(os.environ.get("ROS_GRADER_CONFIG", "{}"))
    package = str(config.get("package_name", "wall_stop"))
    executable = str(config.get("executable", "controller"))
    command_topic = str(config.get("topic", "/cmd_vel"))
    scan_topic = str(config.get("scan_topic", "/scan"))
    flbr_topic = str(config.get("flbr_topic") or "")
    scenario = config["simulation"]
    simulation = Simulation.from_scenario(scenario)
    initial_walls = list(simulation.walls)
    received: list[tuple[float, float]] = []

    rclpy.init(args=None)
    monitor = Node(f"grader_sim_{os.getpid()}")
    monitor.create_subscription(
        Twist, command_topic,
        lambda message: received.append((float(message.linear.x), float(message.angular.z))),
        10,
    )
    if flbr_topic:
        from rse_msgs.msg import Flbr

        flbr_publisher = monitor.create_publisher(Flbr, flbr_topic, 10)
        student, audit_fd = launch_student(package, executable, "scan", command_topic, flbr_topic)
    else:
        scan_publisher = monitor.create_publisher(LaserScan, scan_topic, 10)
        student, audit_fd = launch_student(package, executable, "open", command_topic, scan_topic)

    def publish_scan(ranges: list[float]) -> None:
        if flbr_topic:
            sectors = flbr(ranges)
            summary = Flbr()
            summary.header.stamp = monitor.get_clock().now().to_msg()
            summary.header.frame_id = "laser"
            summary.front = sectors["front"]
            summary.left = sectors["left"]
            summary.back = sectors["back"]
            summary.right = sectors["right"]
            flbr_publisher.publish(summary)
            return
        message = LaserScan()
        message.header.stamp = monitor.get_clock().now().to_msg()
        message.header.frame_id = "laser"
        message.angle_min = math.radians(SCAN_MIN_DEG)
        message.angle_increment = math.radians(SCAN_INCREMENT_DEG)
        message.angle_max = message.angle_min + message.angle_increment * (SCAN_BEAMS - 1)
        message.scan_time = SCAN_PERIOD
        message.range_min = RANGE_MIN
        message.range_max = RANGE_MAX
        message.ranges = ranges
        scan_publisher.publish(message)

    def reply_to(ranges: list[float]) -> float | None:
        """linear.x of the first command answering this scan, if any."""
        received.clear()
        publish_scan(ranges)
        deadline = time.monotonic() + PROBE_REPLY_TIMEOUT
        while time.monotonic() < deadline and student.poll() is None:
            rclpy.spin_once(monitor, timeout_sec=0.01)
            if received:
                return received[0][0]
        return None

    def drives(ranges: list[float]) -> bool | None:
        linear = reply_to(ranges)
        return None if linear is None else linear > STOPPED

    def probe_beams() -> dict:
        """Close one beam group at a time and see whether the node stops.

        Stops when the node does not answer, does not drive on a clear scan, or
        does not drive again after a probe (a latched stop), so it never reports
        beams it could not confirm.
        """
        clear = [PROBE_CLEAR] * SCAN_BEAMS
        if drives(clear) is not True:
            return {"status": "not_driving", "beams": []}
        beams = []
        deadline = time.monotonic() + PROBE_BUDGET_SECONDS
        for display_index, group in enumerate(probe_groups()):
            if time.monotonic() > deadline:
                return {"status": "incomplete", "beams": beams}
            ranges = list(clear)
            for index in group:
                ranges[index] = PROBE_NEAR
            result = drives(ranges)
            if result is None:
                return {"status": "no_reply", "beams": beams}
            if result is False:
                beams.append(display_index)
                if drives(clear) is not True:
                    return {"status": "latched", "beams": beams}
        return {"status": "complete", "beams": beams}

    harness_started = time.monotonic()
    sensitivity = None
    ready = False
    try:
        # The robot stays still and sees its start position until the node answers.
        deadline = time.monotonic() + READY_TIMEOUT
        next_scan = time.monotonic()
        while time.monotonic() < deadline and student.poll() is None:
            if time.monotonic() >= next_scan:
                publish_scan(scan(simulation.pose, simulation.walls))
                next_scan = time.monotonic() + SCAN_PERIOD
            rclpy.spin_once(monitor, timeout_sec=0.02)
            if received:
                ready = True
                break
        if ready:
            simulation.command(*received[-1])
            received.clear()
            started = time.monotonic()
            next_scan = started
            next_physics = started
            while not simulation.finished and student.poll() is None:
                now = time.monotonic()
                if now >= next_scan:
                    publish_scan(simulation.record())
                    next_scan += SCAN_PERIOD
                rclpy.spin_once(monitor, timeout_sec=0.005)
                while received:
                    simulation.command(*received.pop(0))
                while time.monotonic() >= next_physics + PHYSICS_PERIOD and not simulation.finished:
                    simulation.advance(PHYSICS_PERIOD)
                    next_physics += PHYSICS_PERIOD
            simulation.record()
            if (
                not flbr_topic
                and student.poll() is None
                and time.monotonic() - harness_started < PROBE_LATEST_START
            ):
                sensitivity = probe_beams()
    finally:
        alive = student.poll() is None
        if alive:
            os.killpg(student.pid, signal.SIGTERM)
            try:
                student.wait(timeout=1)
            except subprocess.TimeoutExpired:
                os.killpg(student.pid, signal.SIGKILL)
        monitor.destroy_node()
        rclpy.shutdown()
    stdout, stderr = student.communicate(timeout=1)
    spun_non_node = build_state(read_audit(audit_fd)) == "non-node"
    runtime_error = "" if alive else summarize_student_failure(
        stderr, student.returncode, returned_non_node=spun_non_node,
    )
    if spun_non_node:
        runtime_error = RETURNED_NON_NODE_MESSAGE
    if not ready and not runtime_error and flbr_topic:
        runtime_error = (
            "The node did not publish on /cmd_vel within 5 seconds, so the robot never moved. "
            "Check that it creates the /cmd_vel publisher and the /flbr subscription and "
            "publishes one Twist for each message."
        )
    if not ready and not runtime_error:
        runtime_error = (
            "The node did not publish on /cmd_vel within 5 seconds, so the robot never moved. "
            "Check that build_node() returns your node and that it publishes a Twist for each scan."
        )
    replay = simulation.replay(initial_walls) if ready else None
    if replay is not None and sensitivity is not None:
        replay["sensitivity"] = sensitivity
    output = f"Simulated {simulation.time:.1f} s: {replay['outcome'].replace('_', ' ')}." if replay else ""
    if stdout.strip():
        output += f"\nNode stdout: {output_tail(stdout)}"
    print(json.dumps({
        "error": runtime_error,
        "runtime_error": runtime_error,
        "output": output.strip(),
        "tests": [],
        "simulation": replay,
    }))


if __name__ == "__main__":
    main()
