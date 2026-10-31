import os

import pytest

from ros2_callback_audit import (
    exactly_one_per_callback,
    instrument,
    summarize_student_failure,
)


@pytest.mark.parametrize("kind", ["timer", "scan"])
@pytest.mark.parametrize("count,depth,period", [
    (0, 10, .1), (1, 10, .1), (2, 10, .1), (1, 5, .1), (1, 10, .2),
])
def test_callback_counts_real_publications_not_source_calls(kind, count, depth, period):
    class Publisher:
        topic_name = "/cmd_vel"

        def publish(self, message):
            return message

    class Node:
        def create_timer(self, period, callback):
            return callback

        def create_subscription(self, message_type, topic, callback, qos):
            return callback

        def create_publisher(self, message_type, topic, qos):
            return Publisher()

    read_fd, write_fd = os.pipe()
    instrument(Node, Publisher, write_fd, kind, "/cmd_vel", "/scan")
    publisher = Node().create_publisher(object, "/cmd_vel", depth)

    def helper():
        for _ in range(count):
            publisher.publish(object())

    def callback(*args):
        helper()

    node = Node()
    audited = (node.create_timer(period, callback) if kind == "timer"
               else node.create_subscription(object, "/scan", callback, 10))
    try:
        audited()
        audited()
    finally:
        os.close(write_fd)
    assert exactly_one_per_callback(read_fd) is (
        count == 1 and depth == 10 and (kind == "scan" or period == .1)
    )


@pytest.mark.parametrize("kind", ["timer", "scan"])
@pytest.mark.parametrize("count", [0, 1, 2])
def test_async_callbacks_stay_coroutines_and_are_counted_after_await(kind, count):
    import asyncio
    import inspect

    class Publisher:
        topic_name = "/cmd_vel"

        def publish(self, message):
            return message

    class Node:
        def create_timer(self, period, callback):
            return callback

        def create_subscription(self, message_type, topic, callback, qos):
            return callback

        def create_publisher(self, message_type, topic, qos):
            return Publisher()

    read_fd, write_fd = os.pipe()
    instrument(Node, Publisher, write_fd, kind, "/cmd_vel", "/scan")
    publisher = Node().create_publisher(object, "/cmd_vel", 10)

    async def callback(*args):
        await asyncio.sleep(0)
        for _ in range(count):
            publisher.publish(object())

    node = Node()
    audited = (node.create_timer(0.1, callback) if kind == "timer"
               else node.create_subscription(object, "/scan", callback, 10))
    try:
        # rclpy's executor awaits a callback only when it is a coroutine function.
        assert inspect.iscoroutinefunction(audited)
        assert audited.__name__ == "callback"
        asyncio.run(audited())
        asyncio.run(audited())
    finally:
        os.close(write_fd)
    assert exactly_one_per_callback(read_fd) is (count == 1)


def test_no_callback_evidence_cannot_pass():
    read_fd, write_fd = os.pipe()
    os.close(write_fd)
    assert not exactly_one_per_callback(read_fd)


CRASHED_NODE_STDERR = """[WARN] [1791232022.128912342] [rcl]: ROS_LOCALHOST_ONLY is deprecated but still honored if it is enabled.
Traceback (most recent call last):
  File "/opt/ros/jazzy/lib/python3.12/site-packages/rclpy/executors.py", line 592, in handler
    await call_coroutine()
  File "/grader/ros2_callback_audit.py", line 40, in invoke
    return callback(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/workspace/install/robot_motion/lib/python3.12/site-packages/robot_motion/controller.py", line 28, in control_robot
    self.velocity_publisher.publish(command)
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
AttributeError: 'NoneType' object has no attribute 'publish'
"""


def test_failure_summary_keeps_only_the_students_frame_and_exception():
    summary = summarize_student_failure(CRASHED_NODE_STDERR, 1)

    assert summary == "\n".join([
        "Your node stopped with an error:",
        "controller.py, line 28, in control_robot",
        "    self.velocity_publisher.publish(command)",
        "AttributeError: 'NoneType' object has no attribute 'publish'",
    ])
    assert "grader" not in summary
    assert "rclpy" not in summary
    assert "WARN" not in summary


def test_failure_summary_explains_an_error_raised_inside_ros_code():
    stderr = "\n".join([
        "Traceback (most recent call last):",
        '  File "/opt/ros/jazzy/lib/python3.12/site-packages/rclpy/node.py", line 9, in create_publisher',
        "    raise TypeError(...)",
        "TypeError: Expected QoSProfile or int",
    ])

    assert summarize_student_failure(stderr, 1) == "\n".join([
        "The error was raised inside ROS code called by your node:",
        "TypeError: Expected QoSProfile or int",
    ])


def test_failure_summary_for_a_clean_exit_ignores_ros_warnings():
    stderr = "[WARN] [1.0] [rcl]: ROS_LOCALHOST_ONLY is deprecated\n"

    summary = summarize_student_failure(stderr, 0)

    assert summary.startswith("The node exited early (exit code 0).")
    assert "rclpy.spin()" in summary
    assert "deprecated" not in summary


def test_failure_summary_never_echoes_grader_paths():
    stderr = "something failed in /grader/ros2_topic_harness.py\nRuntimeError: boom\n"

    summary = summarize_student_failure(stderr, 2)

    assert "/grader/" not in summary
    assert "RuntimeError: boom" in summary


@pytest.mark.parametrize("counts,expected_polls", [([0, 0, 0, 1], 4), ([0] * 1000, None)])
def test_cmd_vel_publisher_waits_for_the_grader_listener(monkeypatch, counts, expected_polls):
    import ros2_callback_audit as audit

    clock = [0.0]
    monkeypatch.setattr(audit.time, "monotonic", lambda: clock[0])
    monkeypatch.setattr(audit.time, "sleep", lambda seconds: clock.__setitem__(0, clock[0] + seconds))
    polls = []

    class Publisher:
        topic_name = "/cmd_vel"

        def publish(self, message):
            return message

        def get_subscription_count(self):
            polls.append(clock[0])
            return counts[len(polls) - 1]

    class Node:
        def create_timer(self, period, callback):
            return callback

        def create_subscription(self, message_type, topic, callback, qos):
            return callback

        def create_publisher(self, message_type, topic, qos):
            return Publisher()

    read_fd, write_fd = os.pipe()
    try:
        instrument(Node, Publisher, write_fd, "timer", "/cmd_vel", "/scan")
        assert isinstance(Node().create_publisher(object, "/cmd_vel", 10), Publisher)
    finally:
        os.close(write_fd)
        os.close(read_fd)
    if expected_polls is None:
        # A listener that never appears must not hang the student's node.
        assert 5.0 <= clock[0] < 5.2
    else:
        assert len(polls) == expected_polls
