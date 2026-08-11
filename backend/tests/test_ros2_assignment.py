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
from ros2_worker import validate_controller


TEST_IDS = [
    "package-build",
    "node-start",
    "cmd-vel-topic",
    "forward-motion",
    "straight-motion",
    "safe-stop",
    "hold-stop",
]


class FakeRos2Executor:
    def execute(self, code, project_files, config):
        correct = (
            "create_publisher" in code
            and ".publish(" in code
            and "linear.x = 0.20" in code
        )
        tests = []
        for test_id in TEST_IDS:
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


def test_ros2_controller_validation_allows_ros_imports_and_blocks_os():
    validate_controller("import rclpy\nfrom geometry_msgs.msg import Twist")
    with pytest.raises(ImportError, match="Import of 'os' is not allowed"):
        validate_controller("import os")


def test_docker_executor_returns_actionable_error_when_docker_is_missing(monkeypatch):
    def missing(*_args, **_kwargs):
        raise FileNotFoundError

    monkeypatch.setattr("ros2_executor.subprocess.run", missing)
    result = DockerRos2Executor("grader:test").execute("pass", [], {})

    assert result["success"] is False
    assert "Docker Desktop" in result["error"]


def test_ros2_controller_validation_rejects_syntax_errors():
    with pytest.raises(SyntaxError):
        validate_controller('if True print(1)')


def test_docker_executor_isolated_flags_and_config_allowlist(monkeypatch):
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
        {'topic': '/cmd_vel', 'secret': 'must-not-leave-api'},
    )

    command = captured['command']
    assert result['success'] is True
    assert command[command.index('--network') + 1] == 'none'
    assert '--read-only' in command
    assert '--memory' in command
    assert '--cpus' in command
    assert '--pids-limit' in command
    assert '--cap-drop' in command
    assert 'no-new-privileges' in command
    assert captured['request']['config'] == {'topic': '/cmd_vel'}


def test_ros2_assignment_submission_uses_injected_executor(tmp_path):
    settings = Settings(
        database_url="sqlite://",
        admin_api_token="test-admin",
        openai_api_key=None,
        study_accounts_file=tmp_path / "study_accounts.json",
    )
    solution = (
        Path(__file__).resolve().parents[2]
        / "manual_sqa_answers"
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
        response = client.post("/assignments/5/submit", json={"code": solution})

    assert response.status_code == 200
    body = response.json()
    assert body["pass"] is True
    assert body["ex_success"] is True
    assert body["score"] == 100
    assert [item["test_id"] for item in body["evidence"]] == TEST_IDS
