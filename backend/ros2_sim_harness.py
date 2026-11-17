"""Drive the student's node in a small 2D world and record a replay.

The robot moves with the latest /cmd_vel command and every /scan is computed
from where the robot is now, so the student's node controls the robot in a
closed loop. The replay is for students to watch; it never changes grading.
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
from ros2_sim_world import (
    RANGE_MAX, RANGE_MIN, SCAN_BEAMS, SCAN_INCREMENT_DEG, SCAN_MIN_DEG, Simulation, scan,
)


PHYSICS_PERIOD = 0.02
SCAN_PERIOD = 0.08
READY_TIMEOUT = 5.0


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
    scan_publisher = monitor.create_publisher(LaserScan, scan_topic, 10)
    student, audit_fd = launch_student(package, executable, "open", command_topic, scan_topic)

    def publish_scan(ranges: list[float]) -> None:
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
    spun_non_node = read_spin_report(audit_fd)
    runtime_error = "" if alive else summarize_student_failure(stderr, student.returncode)
    if spun_non_node:
        runtime_error = (
            "build_node() returned None or something that is not a ROS node, so there was "
            "no robot to drive. Create your node and return it at the end of build_node()."
        )
    if not ready and not runtime_error:
        runtime_error = (
            "The node did not publish on /cmd_vel within 5 seconds, so the robot never moved. "
            "Check that build_node() returns your node and that it publishes a Twist for each scan."
        )
    replay = simulation.replay(initial_walls) if ready else None
    output = f"Simulated {simulation.time:.1f} s: {replay['outcome'].replace('_', ' ')}." if replay else ""
    if stdout.strip():
        output += f"\nNode stdout: {stdout.strip()[-1000:]}"
    print(json.dumps({
        "error": runtime_error,
        "runtime_error": runtime_error,
        "output": output.strip(),
        "tests": [],
        "simulation": replay,
    }))


if __name__ == "__main__":
    main()
