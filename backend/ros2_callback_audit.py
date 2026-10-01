"""Observe callback publication counts inside the isolated ROS container.

This is grading instrumentation, not a security boundary. Docker remains the
boundary for untrusted code; no student code is imported by the application API.
"""

from contextvars import ContextVar
from functools import wraps
import importlib.metadata
import os
import subprocess
import sys


def instrument(node_class, publisher_class, report_fd, kind, topic, scan_topic):
    active = ContextVar("command_callback", default=None)
    original_publish = publisher_class.publish
    original_timer = node_class.create_timer
    original_subscription = node_class.create_subscription
    original_publisher = node_class.create_publisher

    def report(valid):
        try:
            os.write(report_fd, b"1\n" if valid else b"0\n")
        except (BlockingIOError, BrokenPipeError):
            pass

    def publish(publisher, message):
        counter = active.get()
        if counter is not None and publisher.topic_name == topic:
            counter[0] += 1
        return original_publish(publisher, message)

    def audited(callback):
        @wraps(callback)
        def invoke(*args, **kwargs):
            count = [0]
            token = active.set(count)
            try:
                return callback(*args, **kwargs)
            finally:
                active.reset(token)
                # A nonblocking, separate channel cannot pollute student output.
                # A saturated/missing channel fails closed in the harness.
                report(count[0] == 1)
        return invoke

    def timer(node, timer_period_sec, callback, *args, **kwargs):
        if kind == "timer":
            if abs(timer_period_sec - 0.1) > 1e-9:
                report(False)
            callback = audited(callback)
        return original_timer(node, timer_period_sec, callback, *args, **kwargs)

    def subscription(node, msg_type, topic_name, callback, *args, **kwargs):
        if kind == "scan" and topic_name == scan_topic:
            callback = audited(callback)
        return original_subscription(node, msg_type, topic_name, callback, *args, **kwargs)

    def create_publisher(node, msg_type, topic_name, qos_profile, *args, **kwargs):
        if topic_name == topic:
            depth = qos_profile if isinstance(qos_profile, int) else qos_profile.depth
            if depth != 10:
                report(False)
        return original_publisher(node, msg_type, topic_name, qos_profile, *args, **kwargs)

    publisher_class.publish = publish
    node_class.create_timer = timer
    node_class.create_subscription = subscription
    node_class.create_publisher = create_publisher


def launch_student(package, executable, kind, topic, scan_topic="/scan"):
    read_fd, write_fd = os.pipe()
    os.set_blocking(write_fd, False)
    try:
        process = subprocess.Popen(
            [sys.executable, "/grader/ros2_callback_audit.py", package,
             executable, kind, topic, scan_topic, str(write_fd)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            start_new_session=True, pass_fds=(write_fd,),
        )
    except BaseException:
        os.close(read_fd)
        raise
    finally:
        os.close(write_fd)
    return process, read_fd


def exactly_one_per_callback(read_fd):
    """Read bounded evidence after the student has exited; reject empty evidence."""
    os.set_blocking(read_fd, False)
    try:
        evidence = os.read(read_fd, 65536)
    finally:
        os.close(read_fd)
    lines = evidence.splitlines()
    return bool(lines) and all(line == b"1" for line in lines)


def main():
    from rclpy.node import Node
    from rclpy.publisher import Publisher

    package, executable, kind, topic, scan_topic, fd = sys.argv[1:]
    instrument(Node, Publisher, int(fd), kind, topic, scan_topic)
    entries = [entry for entry in importlib.metadata.distribution(package).entry_points
               if entry.group == "console_scripts" and entry.name == executable]
    if len(entries) != 1:
        raise RuntimeError("The controller executable is not defined exactly once.")
    entries[0].load()()


if __name__ == "__main__":
    main()
