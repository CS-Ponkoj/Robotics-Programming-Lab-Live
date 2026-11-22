"""Observe callback publication counts inside the isolated ROS container.

This is grading instrumentation, not a security boundary. Docker remains the
boundary for untrusted code; no student code is imported by the application API.
"""

from collections import Counter
from contextvars import ContextVar
from functools import wraps
import importlib.metadata
import inspect
import os
import re
import stat
import subprocess
import sys
import threading
import time


_ROS_LOG_LINE = re.compile(r"^\[(?:DEBUG|INFO|WARN|WARNING)\]")
_FRAME = re.compile(r'^\s*File "([^"]+)", line (\d+), in (.+)$')


RETURNED_NON_NODE_MESSAGE = (
    "build_node() returned None instead of a ROS node, so there was no node to run."
)
# Lines Python prints between chained tracebacks; the first block is the cause.
_CHAINED = (
    "During handling of the above exception, another exception occurred:",
    "The above exception was the direct cause of the following exception:",
)


def summarize_student_failure(stderr, returncode, returned_non_node=False):
    """Explain why the student's node stopped, using only the student's frames.

    Raw stderr mixes ROS log warnings, rclpy executor frames, and this file's
    instrumentation frame; students need their own line and the exception.
    The first traceback is the original failure: later ones (for example from
    main()'s ``finally:`` block) are consequences and would point at the wrong
    line. When build_node() returned something that is not a node, say that
    plainly instead of pointing into main().
    """
    if returned_non_node:
        return RETURNED_NON_NODE_MESSAGE
    lines = [
        line for line in (stderr or "").splitlines()
        if line.strip() and not _ROS_LOG_LINE.match(line.strip())
    ]
    starts = [
        index for index, line in enumerate(lines)
        if line.startswith("Traceback (most recent call last)")
    ]
    if starts:
        block = lines[starts[0] + 1:]
        for index, line in enumerate(block):
            if line.strip() in _CHAINED or line.startswith("Traceback (most recent call last)"):
                block = block[:index]
                break
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


# Audit channel protocol: one line per event, written by the student process.
#   a digit  commands published on the command topic by one audited callback (9 = 9 or more)
#   B        an audited callback started
#   F        an audited callback raised an exception
#   O        a command was published outside every audited callback (reported once)
#   Q        the command publisher does not use queue depth 10 (callback kinds only)
#   P        a timer period is not 0.1 s (timer kind only)
#   R / X / E  build_node() returned a node / returned something else / raised
#   U        the program has no build_node() to observe
#   S / N    main() passed a node / something that is not a node to rclpy.spin()
#   L        the student process cannot read the grader files (Landlock applied)
#   I:pub:<type> / I:sub:<type>  the node created a publisher on the command topic /
#            a subscription on the input topic (kept even if the node crashes later)
CONTRACT_FAILURES = frozenset("OQP")


def interface_type(msg_type):
    """'geometry_msgs/msg/Twist' for a generated ROS message class."""
    module = str(getattr(msg_type, "__module__", "") or "")
    name = str(getattr(msg_type, "__name__", "") or "")
    return f"{module.split('.', 1)[0]}/msg/{name}"


def created_interfaces(audit, direction):
    """Message types of the publishers ("pub") or subscriptions ("sub") the node created."""
    prefix = f"I:{direction}:"
    return {event[len(prefix):] for event in audit["events"] if event.startswith(prefix)}


def instrument(node_class, publisher_class, report_fd, kind, topic, scan_topic):
    active = ContextVar("command_callback", default=None)
    topic = absolute_topic(topic)
    scan_topic = absolute_topic(scan_topic)
    original_publish = publisher_class.publish
    original_timer = node_class.create_timer
    original_subscription = node_class.create_subscription
    original_publisher = node_class.create_publisher
    reported_outside = [False]

    def write(event):
        try:
            os.write(report_fd, event + b"\n")
        except OSError:
            pass

    def report_count(count):
        write(str(min(count, 9)).encode())

    def publish(publisher, message):
        if absolute_topic(publisher.topic_name) == topic:
            counter = active.get()
            if counter is not None:
                counter[0] += 1
            elif not reported_outside[0]:
                reported_outside[0] = True
                write(b"O")
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
                write(b"B")
                try:
                    return await callback(*args, **kwargs)
                except BaseException:
                    write(b"F")
                    raise
                finally:
                    active.reset(token)
                    report_count(count[0])
            return invoke_async

        @wraps(callback)
        def invoke(*args, **kwargs):
            count = [0]
            token = active.set(count)
            write(b"B")
            try:
                return callback(*args, **kwargs)
            except BaseException:
                write(b"F")
                raise
            finally:
                active.reset(token)
                # A nonblocking, separate channel cannot pollute student output.
                # A saturated/missing channel fails closed in the harness.
                report_count(count[0])
        return invoke

    def timer(node, timer_period_sec, callback, *args, **kwargs):
        if kind == "timer":
            if abs(timer_period_sec - 0.1) > 1e-9:
                write(b"P")
            callback = audited(callback)
        return original_timer(node, timer_period_sec, callback, *args, **kwargs)

    def subscription(node, msg_type, topic_name, callback, *args, **kwargs):
        if absolute_topic(topic_name) == scan_topic:
            write(b"I:sub:" + interface_type(msg_type).encode())
            if kind in ("scan", "open"):
                callback = audited(callback)
        return original_subscription(node, msg_type, topic_name, callback, *args, **kwargs)

    def create_publisher(node, msg_type, topic_name, qos_profile, *args, **kwargs):
        if absolute_topic(topic_name) == topic:
            write(b"I:pub:" + interface_type(msg_type).encode())
        if absolute_topic(topic_name) == topic and kind in ("scan", "timer"):
            depth = qos_profile if isinstance(qos_profile, int) else qos_profile.depth
            if depth != 10:
                write(b"Q")
        publisher = original_publisher(node, msg_type, topic_name, qos_profile, *args, **kwargs)
        subscribers = getattr(publisher, "get_subscription_count", None)
        if absolute_topic(topic_name) == topic and subscribers is not None:
            # On slow hosts DDS discovery can take seconds; without this wait the
            # grader misses the first commands and a full drive looks short.
            deadline = time.monotonic() + 5.0
            while subscribers() == 0 and time.monotonic() < deadline:
                time.sleep(0.05)
        return publisher

    publisher_class.publish = publish
    node_class.create_timer = timer
    node_class.create_subscription = subscription
    node_class.create_publisher = create_publisher


STDOUT_HEAD_BYTES = 0
STDOUT_TAIL_BYTES = 16 * 1024
STDERR_HEAD_BYTES = 32 * 1024
STDERR_TAIL_BYTES = 32 * 1024


class _Drain:
    """Read one pipe continuously so a printing node never blocks on it.

    Keeps the first ``head`` and last ``tail`` bytes: the first traceback and
    the latest output are what the report needs.
    """

    def __init__(self, stream, head, tail):
        self.stream = stream
        self.head_limit = head
        self.tail_limit = tail
        self.head = bytearray()
        self.tail = bytearray()
        self.dropped = 0
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def _run(self):
        fd = self.stream.fileno()
        while True:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            room = self.head_limit - len(self.head)
            if room > 0:
                self.head += chunk[:room]
                chunk = chunk[room:]
            if chunk:
                self.tail += chunk
                excess = len(self.tail) - self.tail_limit
                if excess > 0:
                    del self.tail[:excess]
                    self.dropped += excess

    def text(self, timeout):
        self.thread.join(timeout)
        marker = b"\n...\n" if self.dropped and self.head else b""
        return (bytes(self.head) + marker + bytes(self.tail)).decode("utf-8", errors="replace")


class StudentProcess(subprocess.Popen):
    """The student's node, with its output drained while it runs.

    A node that prints fills a 64 KB pipe within seconds; an undrained pipe
    blocks print() and freezes a correct node. ``communicate()`` returns the
    retained output instead of reading the pipes itself, so every harness
    keeps its existing call.
    """

    def start_draining(self):
        self.stdout_drain = _Drain(self.stdout, STDOUT_HEAD_BYTES, STDOUT_TAIL_BYTES)
        self.stderr_drain = _Drain(self.stderr, STDERR_HEAD_BYTES, STDERR_TAIL_BYTES)

    def communicate(self, input=None, timeout=None):
        limit = 1.0 if timeout is None else timeout
        try:
            self.wait(timeout=limit)
        except subprocess.TimeoutExpired:
            pass
        return self.stdout_drain.text(limit), self.stderr_drain.text(limit)


def launch_student(package, executable, kind, topic, scan_topic="/scan"):
    read_fd, write_fd = os.pipe()
    os.set_blocking(write_fd, False)
    try:
        process = StudentProcess(
            [sys.executable, "/grader/ros2_callback_audit.py", package,
             executable, kind, topic, scan_topic, str(write_fd)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            start_new_session=True, pass_fds=(write_fd,),
        )
    except BaseException:
        os.close(read_fd)
        raise
    finally:
        os.close(write_fd)
    process.start_draining()
    return process, read_fd


def read_audit(read_fd):
    """Read every audit event after the student has exited, then close the channel."""
    os.set_blocking(read_fd, False)
    data = bytearray()
    try:
        while len(data) < 1_000_000:
            try:
                chunk = os.read(read_fd, 65536)
            except BlockingIOError:
                break
            if not chunk:
                break
            data += chunk
    finally:
        os.close(read_fd)
    lines = bytes(data).decode("ascii", errors="replace").split()
    return {
        "counts": [int(line) for line in lines if line.isdigit()],
        "events": Counter(line for line in lines if not line.isdigit()),
    }


def one_per_callback(audit):
    """Every audited callback published exactly one command, and nothing broke the contract."""
    counts = audit["counts"]
    return (
        bool(counts)
        and all(count == 1 for count in counts)
        and not any(audit["events"][event] for event in CONTRACT_FAILURES)
    )


def exactly_one_per_callback(read_fd):
    """Read bounded evidence after the student has exited; reject empty evidence."""
    return one_per_callback(read_audit(read_fd))


def output_tail(text: str, limit: int = 1000) -> str:
    """The end of a node's printed output, cut at a line start so no number
    or word is shown half."""
    text = text.strip()
    if len(text) <= limit:
        return text
    tail = text[-limit:]
    newline = tail.find("\n")
    if 0 <= newline < len(tail) - 1:
        tail = tail[newline + 1:]
    else:
        tail = "…" + tail.split(" ", 1)[-1]
    return "(earlier output not shown)\n" + tail


def callback_contract_problem(audit, source):
    """One sentence naming why the one-command-per-callback contract failed."""
    counts = audit["counts"]
    events = audit["events"]
    if events["Q"]:
        return "The /cmd_vel publisher does not use queue depth 10, which the rules require."
    if events["P"]:
        return "The timer does not use a period of 0.1 s, which the rules require."
    if events["O"]:
        return (
            f"The node also published commands outside the {source} callback "
            "(for example from a timer). The rule: publish only inside that callback."
        )
    most = max(counts, default=0)
    if most >= 2:
        return (
            f"One {source} callback published {most if most < 9 else 'many'} commands. "
            "The rule: exactly one Twist in each callback."
        )
    if not counts:
        return f"No {source} callback ran, so no command could be checked."
    if any(count == 0 for count in counts):
        return (
            f"Some {source} callbacks published nothing. The rule: one Twist in "
            "every callback, also when the command has not changed."
        )
    return ""


def build_state(audit):
    """What build_node() did: returned, non-node, raised, pending, or unknown."""
    events = audit["events"]
    if events["X"] or events["N"]:
        return "non-node"
    if events["R"]:
        return "returned"
    if events["E"]:
        return "raised"
    if events["U"]:
        return "unknown"
    return "pending"


def report_spin(rclpy_module, node_class, report_fd):
    """Record what main() passes to rclpy.spin() (open tasks)."""
    original_spin = rclpy_module.spin

    def spin(node, *args, **kwargs):
        try:
            os.write(report_fd, b"S\n" if isinstance(node, node_class) else b"N\n")
        except OSError:
            pass
        return original_spin(node, *args, **kwargs)

    rclpy_module.spin = spin


# Older name, kept for callers that only need the non-node report.
report_non_node_spin = report_spin


def report_build_node(module, node_class, report_fd):
    """Wrap build_node() so the harness knows whether it returned a node."""

    def write(event):
        try:
            os.write(report_fd, event + b"\n")
        except OSError:
            pass

    original = getattr(module, "build_node", None) if module is not None else None
    if not callable(original):
        write(b"U")
        return

    @wraps(original)
    def build_node(*args, **kwargs):
        try:
            node = original(*args, **kwargs)
        except BaseException:
            write(b"E")
            raise
        write(b"R" if isinstance(node, node_class) else b"X")
        return node

    module.build_node = build_node


# Landlock (Linux 5.13+) lets an unprivileged process drop its own file access.
_LANDLOCK_CREATE_RULESET = 444
_LANDLOCK_ADD_RULE = 445
_LANDLOCK_RESTRICT_SELF = 446
_LANDLOCK_RULE_PATH_BENEATH = 1
_ACCESS_EXECUTE = 1 << 0
_ACCESS_READ_FILE = 1 << 2
_ACCESS_READ_DIR = 1 << 3
_PR_SET_NO_NEW_PRIVS = 38


def hide_directory(hidden="/grader"):
    """Make ``hidden`` unreadable to this process and every child it starts.

    The container runs everything as one unprivileged user without
    capabilities, so the student's node cannot be given a different user.
    Instead the node removes its own right to read the grader files before
    any student code is imported. Every other top-level directory stays
    readable and executable, and writes are not affected. Returns False when
    the kernel offers no Landlock.
    """
    import ctypes

    libc = ctypes.CDLL(None, use_errno=True)
    libc.syscall.restype = ctypes.c_long
    abi = libc.syscall(_LANDLOCK_CREATE_RULESET, None, ctypes.c_size_t(0), ctypes.c_uint32(1))
    if abi < 1:
        return False

    class RulesetAttr(ctypes.Structure):
        _fields_ = [("handled_access_fs", ctypes.c_uint64)]

    class PathBeneath(ctypes.Structure):
        _pack_ = 1
        _fields_ = [("allowed_access", ctypes.c_uint64), ("parent_fd", ctypes.c_int32)]

    handled = _ACCESS_EXECUTE | _ACCESS_READ_FILE | _ACCESS_READ_DIR
    attr = RulesetAttr(handled)
    ruleset = libc.syscall(
        _LANDLOCK_CREATE_RULESET, ctypes.byref(attr), ctypes.c_size_t(ctypes.sizeof(attr)),
        ctypes.c_uint32(0),
    )
    if ruleset < 0:
        return False
    hidden_name = hidden.strip("/")
    try:
        for entry in os.listdir("/"):
            if entry == hidden_name:
                continue
            try:
                parent = os.open("/" + entry, os.O_PATH | os.O_CLOEXEC)
            except OSError:
                continue
            try:
                directory = stat.S_ISDIR(os.fstat(parent).st_mode)
                rule = PathBeneath(handled if directory else handled & ~_ACCESS_READ_DIR, parent)
                libc.syscall(
                    _LANDLOCK_ADD_RULE, ctypes.c_int(ruleset),
                    ctypes.c_int(_LANDLOCK_RULE_PATH_BENEATH), ctypes.byref(rule),
                    ctypes.c_uint32(0),
                )
            finally:
                os.close(parent)
        libc.prctl(_PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0)
        restricted = libc.syscall(_LANDLOCK_RESTRICT_SELF, ctypes.c_int(ruleset), ctypes.c_uint32(0))
    finally:
        os.close(ruleset)
    return restricted == 0


def main():
    import rclpy
    from rclpy.node import Node
    from rclpy.publisher import Publisher

    package, executable, kind, topic, scan_topic, fd = sys.argv[1:]
    report_fd = int(fd)
    instrument(Node, Publisher, report_fd, kind, topic, scan_topic)
    if kind == "open":
        report_spin(rclpy, Node, report_fd)
    entries = [entry for entry in importlib.metadata.distribution(package).entry_points
               if entry.group == "console_scripts" and entry.name == executable]
    if len(entries) != 1:
        raise RuntimeError("The controller executable is not defined exactly once.")
    # Student code is imported only after the process lost access to /grader.
    sys.path[:] = [path for path in sys.path if not path.startswith("/grader")]
    try:
        if hide_directory("/grader"):
            os.write(report_fd, b"L\n")
    except (OSError, AttributeError):
        pass
    entry_main = entries[0].load()
    if kind == "open":
        report_build_node(sys.modules.get(entry_main.__module__), Node, report_fd)
    entry_main()


if __name__ == "__main__":
    main()
