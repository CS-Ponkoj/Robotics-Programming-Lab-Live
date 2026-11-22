"""Grader-side contracts for the open-structure ROS 2 tasks (Assignments 7 and 8).

Covers the callback audit's evidence channel, output draining, the first-failure
summary, per-assignment import rules, blocking-code checks, "not run" results,
and held-back credit. Behavior inside ROS itself is covered by
verify_ros2_assignments.py against the grader image.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

from graders.ros2_topic import Ros2TopicGrader
from models import Assignment
from ros2_callback_audit import (
    RETURNED_NON_NODE_MESSAGE,
    StudentProcess,
    build_state,
    callback_contract_problem,
    instrument,
    one_per_callback,
    read_audit,
    report_build_node,
    summarize_student_failure,
)
from ros2_code_checks import run_code_checks
from ros2_worker import allowed_import_roots, evaluate, validate_controller


ROOT = Path(__file__).resolve().parents[2]
A7 = json.loads((ROOT / "backend/assignments/assignment_7.json").read_text(encoding="utf-8"))
A8 = json.loads((ROOT / "backend/assignments/assignment_8.json").read_text(encoding="utf-8"))
REFERENCE_7 = (ROOT / A7["reference_solution_path"]).read_text(encoding="utf-8")
REFERENCE_8 = (ROOT / A8["reference_solution_path"]).read_text(encoding="utf-8")


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


def audit_of(kind, run):
    """Instrument fake classes, let ``run`` use them, and read the evidence."""
    publisher_class = type("AuditPublisher", (Publisher,), {})
    node_class = type(
        "AuditNode", (Node,),
        {"create_publisher": lambda self, message_type, topic, qos: publisher_class()},
    )
    read_fd, write_fd = os.pipe()
    try:
        instrument(node_class, publisher_class, write_fd, kind, "/cmd_vel", "/scan")
        run(node_class())
    finally:
        os.close(write_fd)
    return read_audit(read_fd)


@pytest.mark.parametrize("kind", ["open", "scan"])
def test_one_command_per_scan_callback_passes(kind):
    def run(node):
        publisher = node.create_publisher(object, "/cmd_vel", 10)
        callback = node.create_subscription(object, "/scan", lambda _scan: publisher.publish(1), 10)
        callback(None)
        callback(None)

    audit = audit_of(kind, run)
    assert audit["counts"] == [1, 1]
    assert one_per_callback(audit)


def test_publishing_from_a_timer_instead_of_the_scan_callback_fails():
    def run(node):
        publisher = node.create_publisher(object, "/cmd_vel", 10)
        callback = node.create_subscription(object, "/scan", lambda _scan: None, 10)
        tick = node.create_timer(0.1, lambda: publisher.publish(1))
        callback(None)
        tick()
        tick()

    audit = audit_of("open", run)
    assert not one_per_callback(audit)
    assert audit["events"]["O"] == 1  # reported once, not per command
    assert "outside the /scan callback (for example from a timer)" in callback_contract_problem(audit, "/scan")


@pytest.mark.parametrize("count,phrase", [(2, "One /scan callback published 2 commands"), (0, "published nothing")])
def test_doubled_or_skipped_commands_are_named(count, phrase):
    def run(node):
        publisher = node.create_publisher(object, "/cmd_vel", 10)

        def handle(_scan):
            for _ in range(count):
                publisher.publish(1)

        node.create_subscription(object, "/scan", handle, 10)(None)

    audit = audit_of("open", run)
    assert not one_per_callback(audit)
    assert phrase in callback_contract_problem(audit, "/scan")


def test_open_tasks_do_not_judge_queue_depth():
    def run(node):
        publisher = node.create_publisher(object, "/cmd_vel", 1)
        node.create_subscription(object, "/scan", lambda _scan: publisher.publish(1), 10)(None)

    assert one_per_callback(audit_of("open", run))


def test_a_raising_callback_is_recorded():
    def run(node):
        def handle(_scan):
            raise ValueError("boom")

        callback = node.create_subscription(object, "/scan", handle, 10)
        with pytest.raises(ValueError):
            callback(None)

    audit = audit_of("open", run)
    assert audit["events"]["B"] == 1 and audit["events"]["F"] == 1
    assert audit["counts"] == [0]


@pytest.mark.parametrize(
    "build,expected",
    [
        (lambda: Node(), "returned"),
        (lambda: None, "non-node"),
        (lambda: 1 / 0, "raised"),
    ],
)
def test_build_node_outcome_is_reported(build, expected):
    module = type("Module", (), {"build_node": staticmethod(build)})
    read_fd, write_fd = os.pipe()
    try:
        report_build_node(module, Node, write_fd)
        try:
            module.build_node()
        except ZeroDivisionError:
            pass
    finally:
        os.close(write_fd)
    assert build_state(read_audit(read_fd)) == expected


def test_a_build_node_that_never_returns_is_pending():
    read_fd, write_fd = os.pipe()
    os.close(write_fd)
    assert build_state(read_audit(read_fd)) == "pending"


def test_student_output_is_drained_while_the_node_runs():
    """A node printing far more than a pipe holds must finish, not block."""
    process = StudentProcess(
        [sys.executable, "-c", "import sys\nfor _ in range(40): print('x' * 50000)\nsys.stderr.write('done')"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    process.start_draining()
    assert process.wait(timeout=20) == 0
    stdout, stderr = process.communicate(timeout=5)
    assert stdout.rstrip().endswith("x" * 100)
    assert len(stdout) <= 16 * 1024 + 10
    assert stderr == "done"


CHAINED = """Traceback (most recent call last):
  File "/workspace/install/wall_stop/lib/python3.12/site-packages/wall_stop/controller.py", line 23, in main
    rclpy.spin(node)
  File "/opt/ros/jazzy/lib/python3.12/site-packages/rclpy/__init__.py", line 244, in spin
    executor.add_node(node)
AttributeError: 'NoneType' object has no attribute 'handle'

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/workspace/install/wall_stop/lib/python3.12/site-packages/wall_stop/controller.py", line 27, in main
    node.destroy_node()
AttributeError: 'NoneType' object has no attribute 'destroy_node'
"""


def test_failure_summary_reports_the_first_failure_not_the_finally_block():
    summary = summarize_student_failure(CHAINED, 1)
    assert "line 23" in summary and "'handle'" in summary
    assert "line 27" not in summary and "destroy_node" not in summary


def test_failure_summary_says_plainly_when_build_node_returned_none():
    summary = summarize_student_failure(CHAINED, 1, returned_non_node=True)
    assert summary == RETURNED_NON_NODE_MESSAGE
    assert "returned None" in summary and "main()" not in summary


@pytest.mark.parametrize(
    "code",
    [
        "__import__('time')",
        "import importlib",
        "exec('x = 1')",
        "eval('1')",
        "open('/grader/ros2_worker.py').read()",
        "x = ().__class__",
    ],
)
def test_validation_rejects_ways_around_the_import_rules(code):
    for config in (A7["grader_config"], A8["grader_config"]):
        with pytest.raises(ImportError):
            validate_controller(code, allowed_import_roots(config))


def test_each_assignment_has_its_own_import_roots():
    a7, a8 = allowed_import_roots(A7["grader_config"]), allowed_import_roots(A8["grader_config"])
    assert a7 == {"rclpy", "math", "geometry_msgs", "sensor_msgs"}
    assert a8 == {"rclpy", "math", "geometry_msgs", "rse_msgs"}
    for code in ("from sensor_msgs.msg import LaserScan\n", "import time\n"):
        with pytest.raises(ImportError):
            validate_controller(code, a8)
    validate_controller(REFERENCE_7, a7)
    validate_controller(REFERENCE_8, a8)
    validate_controller(A8["starter_code"], a8)


@pytest.mark.parametrize(
    "edit,phrase",
    [
        (("        publisher.publish(command)\n",
          "        node.get_clock().sleep_for(rclpy.duration.Duration(seconds=0.5))\n"
          "        publisher.publish(command)\n"), "sleep_for()"),
        (("    return node\n", "    while rclpy.ok():\n        rclpy.spin_once(node)\n    return node\n"),
         "while rclpy.ok() loop"),
        (("    return node\n", "    rclpy.spin_once(node)\n    return node\n"), "spin_once()"),
    ],
)
def test_no_blocking_catches_waits_and_spinning_outside_main(edit, phrase):
    old, new = edit
    assert old in REFERENCE_7
    results = {item["id"]: item for item in run_code_checks(REFERENCE_7.replace(old, new), A7["grader_config"])}
    assert results["no-blocking"]["passed"] is False
    assert phrase in results["no-blocking"]["message"]


def test_spinning_in_main_is_not_blocking():
    results = {item["id"]: item["passed"] for item in run_code_checks(REFERENCE_7, A7["grader_config"])}
    assert results["no-blocking"] is True


def test_code_checks_can_be_limited_to_a_list():
    config = {"code_checks": ["imports-allowed", "no-blocking"]}
    ids = [item["id"] for item in run_code_checks(REFERENCE_8, config, ["rclpy", "math", "geometry_msgs", "rse_msgs"])]
    assert ids == ["imports-allowed", "no-blocking"]


def public_ids(source):
    return {item["id"] for item in source["public_tests"]}


def test_a_syntax_error_reports_one_cause_and_marks_the_rest_not_run():
    response = evaluate({"code": "def build_node(:\n", "project_files": [], "config": A7["grader_config"]})
    tests = {item["id"]: item for item in response["tests"]}
    assert set(tests) == public_ids(A7)
    assert tests["package-build"]["passed"] is False
    assert "SyntaxError on line 1" in tests["package-build"]["message"]
    others = [item for test_id, item in tests.items() if test_id != "package-build"]
    assert all(item["status"] == "not_run" and not item["passed"] for item in others)
    assert response["error"].startswith("SyntaxError")


def test_a_forbidden_import_in_assignment_8_fails_its_imports_check_with_the_rule():
    response = evaluate({
        "code": "from sensor_msgs.msg import LaserScan\n" + REFERENCE_8,
        "project_files": [], "config": A8["grader_config"],
    })
    tests = {item["id"]: item for item in response["tests"]}
    assert public_ids(A8) <= set(tests)
    # Assignment 2 has its own imports check, so the rule is reported there
    # once and every other check is marked not run.
    assert tests["imports-allowed"]["passed"] is False
    assert "Import of 'sensor_msgs.msg' is not allowed" in tests["imports-allowed"]["message"]
    assert "rclpy, math, geometry_msgs and rse_msgs" in tests["imports-allowed"]["message"]
    assert tests["package-build"]["passed"] is False
    assert all(
        tests[test_id]["status"] == "not_run" for test_id in public_ids(A8) - {"imports-allowed"}
    )
    assert "not allowed" in response["error"]


class FixedExecutor:
    def __init__(self, passing):
        self.passing = passing

    def execute(self, code, project_files, config):
        return {
            "success": True, "error": "", "output": "",
            "tests": [
                {"id": item["id"], "passed": item["id"] in self.passing, "message": "m"}
                for item in A7["public_tests"]
            ],
        }


def assignment_7():
    return Assignment(
        id=7, stable_id=A7["stable_id"], version=A7["version"], title=A7["title"],
        public_tests=A7["public_tests"], asset_manifest=A7["asset_manifest"],
        grader_type="ros2_topic", grader_config=A7["grader_config"],
    )


def test_a_node_that_never_drives_scores_zero():
    """Rate, contract and code checks pass, but the robot never moves."""
    behaviour = {
        "drive-open-floor", "drive-wall-far", "stop-wall-0-3", "stop-wall-0-2",
        "stay-stopped", "resume-motion", "straight-motion",
    }
    passing = public_ids(A7) - behaviour
    result = Ros2TopicGrader(FixedExecutor(passing)).grade(assignment_7(), REFERENCE_7)
    assert result.score == 0
    assert result.passed is False


def test_credit_counts_once_the_robot_drives():
    passing = public_ids(A7) - {"stop-wall-0-3", "stop-wall-0-2", "stay-stopped", "resume-motion"}
    result = Ros2TopicGrader(FixedExecutor(passing)).grade(assignment_7(), REFERENCE_7)
    assert result.score == 65


def test_publishing_from_a_timer_fails_assignment_7():
    passing = public_ids(A7) - {"one-command-per-scan"}
    result = Ros2TopicGrader(FixedExecutor(passing)).grade(assignment_7(), REFERENCE_7)
    assert result.passed is False
    assert result.score == 95


def test_a_shadowed_builtin_name_counts_only_in_its_own_scope():
    """A parameter named like a built-in elsewhere does not unlock the
    built-in in another function (a crafted import-rule bypass)."""
    from ros2_worker import ForbiddenCodeError, validate_controller

    allowed = frozenset({"rclpy", "math", "geometry_msgs", "sensor_msgs"})
    bypass = (
        "def _unused(getattr, open):\n    return None\n\n"
        "def build_node():\n    return getattr(print, 'x')\n"
    )
    with pytest.raises(ForbiddenCodeError):
        validate_controller(bypass, allowed)
    for fine in (
        "input = 1\nprint(input)\n",
        "def f(input):\n    return input * 2\n",
    ):
        validate_controller(fine, allowed)
    # Names that reach outside the node may not be bound either: a binding
    # that runs only sometimes cannot be told apart from the built-in.
    for bad in (
        "x = input()\n", "open('x')\n", "vars()\n",
        "def open(path):\n    return path\n",
        "x = [open for open in [1]]\nopen('a')\n",
        "if False:\n    open = 1\nopen('a')\n",
        "for open in []:\n    pass\nopen('a')\n",
    ):
        with pytest.raises(ForbiddenCodeError):
            validate_controller(bad, allowed)


def test_queue_depth_and_extra_axes_get_their_own_hint_keys():
    from ros2_feedback import HINT_LADDERS, classify

    queue = classify(
        "open_side",
        {"flbr-response": False},
        {"callbacks": {"queue_depth_wrong": True}},
    )
    assert queue["flbr-response"].hint_key == "publisher-queue-depth"
    axes = classify(
        "open_side",
        {"clear-path-forward": False},
        {"unused_axes_used": True, "callbacks": {}},
    )
    assert axes["clear-path-forward"].hint_key in {"extra-axes", "never-moves", "forward-speed-wrong"}
    assert {"publisher-queue-depth", "extra-axes"} <= set(HINT_LADDERS)


def test_a_failed_rate_check_states_the_measured_rate():
    from ros2_feedback import classify

    findings = classify(
        "wall_stop_open",
        {"publish-rate": False},
        {"rate_hz": 2.0, "phases": {"open": {"count": 2, "linear_max": 0.2, "linear_min": 0.2}}},
    )
    finding = findings.get("publish-rate")
    assert finding is not None and "2.0 commands per second" in finding.observation
    assert finding.unless_message_has == "published about"
