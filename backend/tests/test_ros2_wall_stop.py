"""Assignment 7: open-structure ROS 2 task with code checks and a gate."""

import json
from pathlib import Path

import pytest

from graders.ros2_topic import Ros2TopicGrader
from models import Assignment
from ros2_code_checks import run_code_checks
from ros2_executor import DockerRos2Executor
from ros2_worker import evaluate, select_harness, validate_controller


ROOT = Path(__file__).resolve().parents[2]
SOURCE = json.loads(
    (ROOT / "backend" / "assignments" / "assignment_7.json").read_text(encoding="utf-8")
)
CONFIG = SOURCE["grader_config"]
STARTER = SOURCE["starter_code"]
REFERENCE = (ROOT / SOURCE["reference_solution_path"]).read_text(encoding="utf-8")
GATE = CONFIG["gate_tests"]
BEHAVIOUR = CONFIG["pass_tests"]
CODE_TEST_IDS = {
    "imports-allowed", "build-node-defined", "reads-ranges", "no-blocking",
    "main-unchanged", "named-constants", "no-unused-imports",
}


def checks(code: str) -> dict[str, bool]:
    return {item["id"]: item["passed"] for item in run_code_checks(code, CONFIG)}


def test_reference_answer_passes_every_code_check():
    assert checks(REFERENCE) == {test_id: True for test_id in CODE_TEST_IDS}


def test_starter_keeps_main_but_has_no_robot_logic():
    result = checks(STARTER)
    assert result["build-node-defined"] is True
    assert result["main-unchanged"] is True
    assert result["no-unused-imports"] is True  # imports supplied by the skeleton never count
    assert result["reads-ranges"] is False
    assert result["named-constants"] is False


def test_main_check_ignores_comments_and_spacing_but_not_changes():
    reformatted = REFERENCE.replace(
        "def main(args=None):  # Do not change main().",
        "def main(args=None):\n    # a student comment",
    )
    assert checks(reformatted)["main-unchanged"] is True
    rewritten = REFERENCE.replace(
        "    node = build_node()\n    try:", "    node = build_node()\n    print('hi')\n    try:"
    )
    assert checks(rewritten)["main-unchanged"] is False


def test_class_based_answer_with_its_own_import_passes():
    code = STARTER.replace(
        "from sensor_msgs.msg import LaserScan\n",
        "from sensor_msgs.msg import LaserScan\nfrom rclpy.node import Node\n\n"
        "SPEED = 0.2\nSTOP_DISTANCE = 0.5\n\n\n"
        "class WallStop(Node):\n"
        "    def __init__(self):\n"
        "        super().__init__('wall_stop')\n"
        "        self.publisher = self.create_publisher(Twist, '/cmd_vel', 10)\n"
        "        self.create_subscription(LaserScan, '/scan', self.on_scan, 10)\n\n"
        "    def on_scan(self, scan):\n"
        "        command = Twist()\n"
        "        if scan.ranges[len(scan.ranges) // 2] > STOP_DISTANCE:\n"
        "            command.linear.x = SPEED\n"
        "        self.publisher.publish(command)\n",
    ).replace("    # Write your code here.\n    return None", "    return WallStop()")
    assert checks(code) == {test_id: True for test_id in CODE_TEST_IDS}


@pytest.mark.parametrize(
    ("edit", "failing"),
    [
        (("    return node\n", "    while True:\n        pass\n    return node\n"), "no-blocking"),
        (("FORWARD_SPEED = 0.20    # m/s\nSTOP_DISTANCE = 0.50    # m\nFRONT_READINGS = 5      # readings on each side of straight ahead\n", ""), "named-constants"),
        (("import math\n", "import math\nfrom rclpy.node import Node\n"), "no-unused-imports"),
        (("def build_node():", "def make_node():"), "build-node-defined"),
    ],
)
def test_code_checks_catch_each_problem(edit, failing):
    old, new = edit
    assert old in REFERENCE
    result = checks(REFERENCE.replace(old, new))
    assert result[failing] is False


def test_worker_reports_disallowed_import_as_a_failed_gate_check():
    response = evaluate({
        "code": "import numpy\n" + REFERENCE,
        "project_files": [],
        "config": CONFIG,
    })
    assert response["success"] is False
    assert response["tests"] == [
        {
            "id": "imports-allowed",
            "passed": False,
            "message": "Import of 'numpy' is not allowed. Use only rclpy, math, geometry_msgs and sensor_msgs.",
        }
    ]


def test_worker_keeps_plain_import_failure_for_older_assignments():
    response = evaluate({"code": "import numpy\n", "project_files": [], "config": {"harness": "obstacle_stop"}})
    assert response["tests"] == []


def test_harness_is_registered_and_shipped_in_the_grader_image():
    assert select_harness(CONFIG) == "/grader/ros2_wall_stop_harness.py"
    dockerfile = (ROOT / "backend" / "Dockerfile.ros2").read_text(encoding="utf-8")
    assert "COPY ros2_wall_stop_harness.py /grader/ros2_wall_stop_harness.py" in dockerfile
    assert "COPY ros2_code_checks.py /grader/ros2_code_checks.py" in dockerfile


def test_executor_passes_code_check_settings_but_not_scoring_rules(monkeypatch):
    captured = {}

    def complete(command, input_data, **kwargs):
        captured["request"] = json.loads(input_data)
        from types import SimpleNamespace
        return SimpleNamespace(
            returncode=0,
            stdout=json.dumps({"success": True, "error": "", "output": "", "tests": []}),
            stderr="", timed_out=False, overflowed=False,
        )

    monkeypatch.setattr("ros2_executor.shutil.which", lambda _name: "docker")
    monkeypatch.setattr("ros2_executor._run_bounded", complete)
    DockerRos2Executor("grader:test").execute(REFERENCE, [], CONFIG)
    sent = captured["request"]["config"]
    assert sent["code_checks"] is True
    assert sent["skeleton_main"] == CONFIG["skeleton_main"]
    assert sent["skeleton_imports"] == CONFIG["skeleton_imports"]
    assert "gate_tests" not in sent and "pass_tests" not in sent


class FixedExecutor:
    def __init__(self, failing: set[str]):
        self.failing = failing

    def execute(self, code, project_files, config):
        return {
            "success": True,
            "error": "",
            "output": "",
            "tests": [
                {"id": item["id"], "passed": item["id"] not in self.failing, "message": "m"}
                for item in SOURCE["public_tests"]
            ],
        }


def assignment_7() -> Assignment:
    return Assignment(
        id=7, stable_id=SOURCE["stable_id"], version=SOURCE["version"], title=SOURCE["title"],
        public_tests=SOURCE["public_tests"], asset_manifest=SOURCE["asset_manifest"],
        grader_type="ros2_topic", grader_config=CONFIG,
    )


def test_all_checks_passing_scores_100_and_passes():
    result = Ros2TopicGrader(FixedExecutor(set())).grade(assignment_7(), REFERENCE)
    assert result.score == 100
    assert result.passed is True


def test_a_failed_gate_check_scores_zero_even_with_good_behaviour():
    result = Ros2TopicGrader(FixedExecutor({"returns-node"})).grade(assignment_7(), REFERENCE)
    assert result.score == 0
    assert result.passed is False


def test_style_points_do_not_decide_passing():
    result = Ros2TopicGrader(FixedExecutor({"named-constants", "main-unchanged"})).grade(assignment_7(), REFERENCE)
    assert result.score == 91
    assert result.passed is True


def test_a_failed_behaviour_check_fails_the_task():
    result = Ros2TopicGrader(FixedExecutor({"drive-open-floor"})).grade(assignment_7(), REFERENCE)
    assert result.passed is False
    assert result.score == 91


def test_assignment_7_configuration_is_consistent():
    test_ids = [item["id"] for item in SOURCE["public_tests"]]
    weights = CONFIG["test_weights"]
    assert len(test_ids) == len(set(test_ids)) == 20
    assert set(weights) == set(test_ids)
    assert sum(weights.values()) == 100
    assert sum(item["weight"] for item in SOURCE["rubric"]) == 100
    assert set(GATE) <= set(test_ids) and set(BEHAVIOUR) <= set(test_ids)
    assert all(weights[test_id] == 0 for test_id in GATE)
    assert sum(weights[test_id] for test_id in BEHAVIOUR) == 70
    assert SOURCE["status"] == "published"
    assert 'src="/images/7"' in SOURCE["assignment_html"]
    assert (ROOT / "backend" / "static" / "image7.png").read_bytes().startswith(b"\x89PNG")
    editable = [item for item in SOURCE["asset_manifest"] if item["editable"]]
    assert [item["path"] for item in editable] == [SOURCE["execution_settings"]["editable_file"]]
    assert "reactive_navigation" not in json.dumps(SOURCE["asset_manifest"])


def test_assignment_7_starter_and_answer_pass_import_validation():
    validate_controller(STARTER)
    validate_controller(REFERENCE)
    assert CONFIG["skeleton_main"] in STARTER
    assert CONFIG["skeleton_main"] in REFERENCE


def test_assignment_7_explains_the_infinity_rule_and_measured_numbers():
    html = SOURCE["assignment_html"]
    for text in (
        "This is different from Assignment 6",
        "between 0.1 and 0.3 m/s",
        "Distances between 0.3 m and 1.0 m are not tested",
        "Each situation lasts 1 second",
        "the first 0.3 s is not checked",
        "at least 5 commands per second",
        "Code and quality points add to the score but do not decide passing",
    ):
        assert text in html


def test_wall_stop_harness_uses_the_documented_scan_and_timing():
    source = (ROOT / "backend" / "ros2_wall_stop_harness.py").read_text(encoding="utf-8")
    for text in (
        "FORWARD_MIN = 0.1", "FORWARD_MAX = 0.3", "STOP_TOLERANCE = 0.001",
        "ANGULAR_TOLERANCE = 0.001", "MINIMUM_RATE_HZ = 5.0", "PHASE_SECONDS = 1.0",
        "SETTLE_SECONDS = 0.3", "SCAN_MIN_DEG = -135.0", "SCAN_BEAMS = 91",
        '("open", None)', '("far", 1.2)', '("near", 0.3)', '("close", 0.2)',
        '("hold", 0.2)', '("resume", 1.2)',
    ):
        assert text in source
    harness_ids = {line.split('"')[1] for line in source.splitlines() if line.strip().startswith('"') and line.strip().endswith('",') and "-" in line}
    runtime_ids = set(SOURCE["grader_config"]["test_weights"]) - CODE_TEST_IDS - {"package-build"}
    assert runtime_ids <= harness_ids
