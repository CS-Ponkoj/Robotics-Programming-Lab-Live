"""Observe callback publication counts inside the isolated ROS container.

This is grading instrumentation, not a security boundary. Docker remains the
boundary for untrusted code; no student code is imported by the application API.
"""

from contextvars import ContextVar
from functools import wraps
import importlib.metadata
import inspect
import os
import re
import subprocess
import sys


_ROS_LOG_LINE = re.compile(r"^\[(?:DEBUG|INFO|WARN|WARNING)\]")
_FRAME = re.compile(r'^\s*File "([^"]+)", line (\d+), in (.+)$')


def summarize_student_failure(stderr, returncode):
    """Explain why the student's node stopped, using only the student's frames.

    Raw stderr mixes ROS log warnings, rclpy executor frames, and this file's
    instrumentation frame; students need their own line and the exception.
    """
    lines = [
        line for line in (stderr or "").splitlines()
        if line.strip() and not _ROS_LOG_LINE.match(line.strip())
    ]
    starts = [
        index for index, line in enumerate(lines)
        if line.startswith("Traceback (most recent call last)")
    ]
    if starts:
        block = lines[starts[-1] + 1:]
        kept = []
        in_student_frame = False
        exception = "Unknown error"
        for line in block:
            frame = _FRAME.match(line)
            if frame:
                in_student_frame = "/workspace/" in frame.group(1)
                if in_student_frame:
                    file_name = frame.group(1).rsplit("/", 1)[-1]
                    kept.append(f"{file_name}, line {frame.group(2)}, in {frame.group(3)}")
                continue
            if line.startswith(" "):
                # The code line under a student frame; skip caret markers.
                if in_student_frame and line.strip().strip("^~ "):
                    kept.append("    " + line.strip())
                    in_student_frame = False
                continue
            exception = line.strip()
        kept.append(exception)
        if len(kept) == 1:
            kept.insert(0, "The error was raised inside ROS code called by your node:")
        else:
            kept.insert(0, "Your node stopped with an error:")
        return "\n".join(kept).replace("/grader/", "")
    other = [line.strip() for line in lines if "/grader/" not in line][-3:]
    advice = (
        "Keep rclpy.spin() running so the node stays alive and keeps publishing."
    )
    summary = f"The node exited early (exit code {returncode}). {advice}"
    return "\n".join([summary, *other]) if other else summary


def absolute_topic(name):
    """Compare relative and absolute names alike; the student node has no namespace."""
    name = str(name)
    return name if name.startswith("/") else "/" + name


def instrument(node_class, publisher_class, report_fd, kind, topic, scan_topic):
    active = ContextVar("command_callback", default=None)
    topic = absolute_topic(topic)
    scan_topic = absolute_topic(scan_topic)
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
        if counter is not None and absolute_topic(publisher.topic_name) == topic:
            counter[0] += 1
        return original_publish(publisher, message)

    def audited(callback):
        if inspect.iscoroutinefunction(callback):
            # rclpy awaits coroutine callbacks only when it can see they are
            # coroutine functions, so the wrapper must stay async and count
            # publications after the awaited body completes.
            @wraps(callback)
            async def invoke_async(*args, **kwargs):
                count = [0]
                token = active.set(count)
                try:
                    return await callback(*args, **kwargs)
                finally:
                    active.reset(token)
                    report(count[0] == 1)
            return invoke_async

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
        if kind == "scan" and absolute_topic(topic_name) == scan_topic:
            callback = audited(callback)
        return original_subscription(node, msg_type, topic_name, callback, *args, **kwargs)

    def create_publisher(node, msg_type, topic_name, qos_profile, *args, **kwargs):
        if absolute_topic(topic_name) == topic:
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
