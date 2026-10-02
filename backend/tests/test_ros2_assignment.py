import json
from pathlib import Path
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app import create_app
from config import Settings
from models import Assignment
from graders.ros2_topic import Ros2TopicGrader
from ros2_executor import DockerRos2Executor
from ros2_worker import select_harness, validate_controller


TEST_IDS = [
    "package-build",
    "node-start",
    "cmd-vel-topic",
    "forward-motion",
    "straight-motion",
    "safe-stop",
    "hold-stop",
]

A6_TEST_IDS = [
    "package-build",
    "node-start",
    "scan-response",
    "cmd-vel-topic",
    "clear-path-forward",
    "obstacle-stop",
    "invalid-scan-stop",
    "straight-motion",
    "resume-motion",
]


@pytest.mark.parametrize(
    ("assignment_id", "rubric_groups"),
    [
        (5, [["package-build", "node-start"], ["cmd-vel-topic"],
             ["forward-motion", "straight-motion"], ["safe-stop", "hold-stop"]]),
        (6, [["package-build", "node-start"], ["scan-response", "cmd-vel-topic"],
             ["clear-path-forward", "straight-motion"],
             ["obstacle-stop", "invalid-scan-stop"], ["resume-motion"]]),
    ],
)
def test_ros2_rubric_weights_match_the_harness_weights(
    assignment_id, rubric_groups
):
    assignment_path = (
        Path(__file__).resolve().parents[1]
        / "assignments"
        / f"assignment_{assignment_id}.json"
    )
    source = json.loads(assignment_path.read_text(encoding="utf-8"))
    harness_weights = source["grader_config"]["test_weights"]
    grouped_weights = [
        sum(harness_weights[test_id] for test_id in group)
        for group in rubric_groups
    ]

    assert grouped_weights == [item["weight"] for item in source["rubric"]]
    assert sum(grouped_weights) == 100


class FakeRos2Executor:
    def execute(self, code, project_files, config):
        test_ids = list(config.get("test_weights", {})) or TEST_IDS
        is_obstacle_assignment = config.get("harness") == "obstacle_stop"
        correct = (
            (
                "LaserScan" in code
                and "create_subscription" in code
                and "math.isfinite" in code
                and "nearest_obstacle > self.stop_distance" in code
            )
            if is_obstacle_assignment
            else (
                "create_publisher" in code
                and ".publish(" in code
                and "linear.x = 0.20" in code
            )
        )
        tests = []
        for test_id in test_ids:
            passed = correct or test_id in {"package-build", "node-start"}
            tests.append(
                {
                    "id": test_id,
                    "passed": passed,
                    "message": "Requirement passed." if passed else "Complete this ROS behavior.",
                }
            )
        return {
            "success": True,
            "error": "",
            "output": "Observed ROS topic messages.",
            "tests": tests,
        }


def assignment() -> Assignment:
    return Assignment(
        id=5,
        stable_id="ros2-drive-forward",
        version=1,
        title="Drive Forward",
        public_tests=[{"id": value, "label": value} for value in TEST_IDS],
        asset_manifest=[
            {
                "kind": "project_file",
                "path": "src/robot_motion/robot_motion/controller.py",
                "editable": True,
                "content": "",
            }
        ],
        grader_type="ros2_topic",
        grader_config={
            "test_weights": {
                "package-build": 10,
                "node-start": 10,
                "cmd-vel-topic": 20,
                "forward-motion": 20,
                "straight-motion": 10,
                "safe-stop": 20,
                "hold-stop": 10,
            }
        },
    )


def test_ros2_topic_grader_accepts_correct_observable_behavior():
    grader = Ros2TopicGrader(FakeRos2Executor())
    result = grader.grade(
        assignment(),
        "self.create_publisher(Twist, '/cmd_vel', 10)\ncommand.linear.x = 0.20\nself.publisher.publish(command)",
    )

    assert result.execution_succeeded is True
    assert result.passed is True
    assert result.score == 100
    assert [item.test_id for item in result.evidence] == TEST_IDS


def test_ros2_topic_grader_weights_partial_behavior_by_concept():
    grader = Ros2TopicGrader(FakeRos2Executor())
    result = grader.grade(assignment(), "pass")

    assert result.execution_succeeded is True
    assert result.passed is False
    assert result.score == 20


def test_ros2_obstacle_grader_rejects_starter_and_wrong_behavior():
    source = json.loads(
        (
            Path(__file__).resolve().parents[1]
            / "assignments"
            / "assignment_6.json"
        ).read_text(encoding="utf-8")
    )
    obstacle_assignment = Assignment(
        id=source["id"],
        stable_id=source["stable_id"],
        version=source["version"],
        title=source["title"],
        public_tests=source["public_tests"],
        asset_manifest=source["asset_manifest"],
        grader_type=source["grader_type"],
        grader_config=source["grader_config"],
    )
    result = Ros2TopicGrader(FakeRos2Executor()).grade(
        obstacle_assignment,
        source["starter_code"],
    )

    assert result.execution_succeeded is True
    assert result.passed is False
    assert result.score == 15
    assert [item.test_id for item in result.evidence] == A6_TEST_IDS


def test_ros2_controller_validation_allows_ros_imports_and_blocks_os():
    validate_controller(
        "import math\nimport rclpy\n"
        "from geometry_msgs.msg import Twist\n"
        "from sensor_msgs.msg import LaserScan"
    )
    with pytest.raises(ImportError, match="Import of 'os' is not allowed"):
        validate_controller("import os")


def test_ros2_worker_selects_only_known_behavior_harnesses():
    assert select_harness({}) == "/grader/ros2_topic_harness.py"
    assert select_harness({"harness": "obstacle_stop"}) == (
        "/grader/ros2_obstacle_harness.py"
    )
    with pytest.raises(ValueError, match="Unsupported ROS 2 harness"):
        select_harness({"harness": "student-selected-path"})


def test_obstacle_harness_waits_for_ros_discovery_before_scoring():
    source = (Path(__file__).parents[1] / "ros2_obstacle_harness.py").read_text(
        encoding="utf-8"
    )

    readiness = source.index("controller_ready = wait_for_controller()")
    clear_phase = source.index('run_phase(phase, ranges, phase_duration)')
    assert "scan_publisher.get_subscription_count() > 0" in source
    assert "monitor.count_publishers(command_topic) > 0" in source
    assert "messages.clear()" in source
    assert readiness < clear_phase
    scored_phase_loop = source[source.index('messages.clear()'):clear_phase]
    assert 'if controller_ready:' in scored_phase_loop


def test_drive_forward_harness_uses_process_relative_timing_with_startup_grace():
    source = (Path(__file__).parents[1] / "ros2_topic_harness.py").read_text(
        encoding="utf-8"
    )

    process_clock = source.index("student_started_at = time.monotonic()")
    student_launch = source.index("student, audit_fd = launch_student(")
    assert "startup_grace_seconds" in source
    assert "now - student_started_at" in source
    assert "monitor_ready_at = time.monotonic() + 0.5" in source
    assert process_clock < student_launch


def test_docker_executor_returns_actionable_error_when_docker_is_missing(monkeypatch):
    def missing(*_args, **_kwargs):
        raise FileNotFoundError

    monkeypatch.setattr("ros2_executor.subprocess.run", missing)
    result = DockerRos2Executor("grader:test").execute("pass", [], {})

    assert result["success"] is False
    assert "Docker Desktop" in result["error"]


def test_docker_executor_hides_daemon_pipe_details_when_desktop_is_stopped(monkeypatch):
    monkeypatch.setattr("ros2_executor.shutil.which", lambda _name: "docker")
    def unavailable(*_args, **_kwargs):
        return SimpleNamespace(
            returncode=1,
            stdout="",
            stderr=(
                "failed to connect to the docker API at "
                "npipe:////./pipe/dockerDesktopLinuxEngine"
            ),
        )

    monkeypatch.setattr("ros2_executor.subprocess.run", unavailable)
    result = DockerRos2Executor("grader:test").execute("pass", [], {})

    assert result["success"] is False
    assert result["tests"] == []
    assert "Start Docker Desktop" in result["error"]
    assert "npipe" not in result["error"]


def test_ros2_controller_validation_rejects_syntax_errors():
    with pytest.raises(SyntaxError):
        validate_controller('if True print(1)')


def test_docker_executor_isolated_flags_and_config_allowlist(monkeypatch):
    monkeypatch.setattr('ros2_executor.shutil.which', lambda _name: 'docker')
    captured = {}

    def complete(command, **kwargs):
        captured['command'] = command
        captured['request'] = json.loads(kwargs['input'])
        return SimpleNamespace(
            returncode=0,
            stdout=json.dumps(
                {'success': True, 'error': '', 'output': '', 'tests': []}
            ),
            stderr='',
        )

    monkeypatch.setattr('ros2_executor.subprocess.run', complete)
    result = DockerRos2Executor('grader:test').execute(
        'pass',
        [],
        {
            'harness': 'obstacle_stop',
            'topic': '/cmd_vel',
            'scan_topic': '/scan',
            'stop_distance': 0.75,
            'secret': 'must-not-leave-api',
        },
    )

    command = captured['command']
    assert result['success'] is True
    assert command[command.index('--network') + 1] == 'none'
    tmpfs_values = [
        command[index + 1]
        for index, value in enumerate(command)
        if value == '--tmpfs'
    ]
    assert any(
        value.startswith('/workspace:') and 'exec' in value
        for value in tmpfs_values
    )
    assert any(
        value.startswith('/tmp:') and 'noexec' in value
        for value in tmpfs_values
    )
    assert '--read-only' in command
    assert '--memory' in command
    assert '--cpus' in command
    assert '--pids-limit' in command
    assert '--cap-drop' in command
    assert 'no-new-privileges' in command
    assert captured['request']['config'] == {
        'harness': 'obstacle_stop',
        'topic': '/cmd_vel',
        'scan_topic': '/scan',
        'stop_distance': 0.75,
    }


def test_ros2_assignment_submission_uses_injected_executor(tmp_path):
    settings = Settings(
        database_url="sqlite://",
        admin_api_token="test-admin",
        openai_api_key=None,
        study_accounts_file=tmp_path / "study_accounts.json",
    )
    solution = (
        Path(__file__).resolve().parents[2]
        / "assignments_answers"
        / "assignment_5_ros2_drive_forward"
        / "controller.py"
    ).read_text(encoding="utf-8")

    with TestClient(
        create_app(
            settings=settings,
            database_url="sqlite://",
            ros2_executor_factory=lambda _timeout: FakeRos2Executor(),
        )
    ) as client:
        login = client.post(
            "/auth/login",
            json={"login_id": "student", "password": "student"},
        )
        client.headers.update(
            {"Authorization": f"Bearer {login.json()['token']}"}
        )
        assignment_response = client.get("/assignments/5")
        response = client.post("/assignments/5/submit", json={"code": solution})

    assert assignment_response.status_code == 200
    assignment_body = assignment_response.json()
    assert assignment_body["version"] == 5
    assert 'src="/images/5"' in assignment_body["assignment_html"]
    assert "src/robot_motion/robot_motion/controller.py" in assignment_body["assignment_html"]
    assert response.status_code == 200
    body = response.json()
    assert body["pass"] is True
    assert body["ex_success"] is True
    assert body["score"] == 100
    assert [item["test_id"] for item in body["evidence"]] == TEST_IDS


def test_ros2_obstacle_assignment_submission_uses_behavior_harness(tmp_path):
    settings = Settings(
        database_url="sqlite://",
        admin_api_token="test-admin",
        openai_api_key=None,
        study_accounts_file=tmp_path / "study_accounts.json",
    )
    solution = (
        Path(__file__).resolve().parents[2]
        / "assignments_answers"
        / "assignment_6_ros2_obstacle_stop"
        / "controller.py"
    ).read_text(encoding="utf-8")

    with TestClient(
        create_app(
            settings=settings,
            database_url="sqlite://",
            ros2_executor_factory=lambda _timeout: FakeRos2Executor(),
        )
    ) as client:
        login = client.post(
            "/auth/login",
            json={"login_id": "student", "password": "student"},
        )
        client.headers.update(
            {"Authorization": f"Bearer {login.json()['token']}"}
        )
        assignment_response = client.get("/assignments/6")
        response = client.post("/assignments/6/submit", json={"code": solution})

    assert assignment_response.status_code == 200
    assignment_body = assignment_response.json()
    assert assignment_body["stable_id"] == "ros2-obstacle-stop"
    assert assignment_body["version"] == 5
    assert 'src="/images/6"' in assignment_body["assignment_html"]
    assert "src/reactive_navigation/reactive_navigation/controller.py" in assignment_body["assignment_html"]
    assert assignment_body["editable_file_path"].endswith("controller.py")
    assert sum(item["editable"] for item in assignment_body["project_files"]) == 1
    assert "grader_config" not in assignment_body
    assert "reference_solution_path" not in assignment_body

    assert response.status_code == 200
    body = response.json()
    assert body["pass"] is True
    assert body["ex_success"] is True
    assert body["score"] == 100
    assert [item["test_id"] for item in body["evidence"]] == A6_TEST_IDS


def test_ros2_obstacle_assignment_rejects_oversized_submission(tmp_path):
    settings = Settings(
        database_url="sqlite://",
        admin_api_token="test-admin",
        openai_api_key=None,
        max_submission_chars=100,
        study_accounts_file=tmp_path / "study_accounts.json",
    )
    with TestClient(
        create_app(
            settings=settings,
            database_url="sqlite://",
            ros2_executor_factory=lambda _timeout: FakeRos2Executor(),
        )
    ) as client:
        login = client.post(
            "/auth/login",
            json={"login_id": "student", "password": "student"},
        )
        response = client.post(
            "/assignments/6/submit",
            headers={"Authorization": f"Bearer {login.json()['token']}"},
            json={"code": "x" * 101},
        )

    assert response.status_code == 413
    assert response.json()["error"] == "Submitted code is too large."


def test_docker_executor_hides_raw_container_failure_output(monkeypatch):
    monkeypatch.setattr("ros2_executor.shutil.which", lambda _name: "docker")

    def crashed(*_args, **_kwargs):
        return SimpleNamespace(
            returncode=1,
            stdout="",
            stderr=(
                'Traceback (most recent call last):\n'
                '  File "/grader/ros2_obstacle_harness.py", line 42, in <module>\n'
                '    assert stop_time < HIDDEN_LIMIT\n'
                'AssertionError'
            ),
        )

    monkeypatch.setattr("ros2_executor.subprocess.run", crashed)
    result = DockerRos2Executor("grader:test").execute("pass", [], {})

    assert result["success"] is False
    assert "/grader/" not in result["error"]
    assert "HIDDEN_LIMIT" not in result["error"]
    assert "stopped unexpectedly" in result["error"]


def test_ros2_worker_redacts_hidden_harness_frames_but_keeps_student_frames():
    from ros2_worker import redact_grader_frames

    stderr = (
        "Traceback (most recent call last):\n"
        '  File "/grader/ros2_topic_harness.py", line 88, in run\n'
        "    expected = SECRET_EXPECTED_SPEED\n"
        "               ^^^^^^^^^^^^^^^^^^^^^\n"
        '  File "/workspace/src/robot_motion/robot_motion/controller.py", line 7, in tick\n'
        "    self.publisher.publish(mesage)\n"
        "NameError: name 'mesage' is not defined"
    )

    redacted = redact_grader_frames(stderr)

    assert "/grader/" not in redacted
    assert "SECRET_EXPECTED_SPEED" not in redacted
    assert "controller.py" in redacted
    assert "self.publisher.publish(mesage)" in redacted
    assert redacted.endswith("NameError: name 'mesage' is not defined")
