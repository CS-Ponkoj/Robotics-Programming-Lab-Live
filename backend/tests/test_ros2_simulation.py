"""2D robot replay: world physics, worker wiring, trace bounds, and the route."""

import json
import math
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlalchemy import func, select

from app import create_app
from config import Settings
from data_contracts import SimulationConfig, normalize_event_data
from models import LearningEvent, Submission
from ros2_executor import _safe_config, _valid_result
from ros2_sim_world import (
    MAX_FRAMES, Pose, Simulation, distance_to_wall, ray_hit, scan, step,
)
from ros2_worker import SIMULATION_HARNESS, select_harness, static_code_tests
from simulation_service import normalize_replay


ROOT = Path(__file__).resolve().parents[2]
SOURCE = json.loads((ROOT / "backend/assignments/assignment_7.json").read_text(encoding="utf-8"))
WORLD = SOURCE["simulation_config"]["world"]


def drive(controller, world=WORLD):
    """Run the pure world with a Python stand-in for the student's node."""
    simulation = Simulation.from_scenario(json.loads(json.dumps(world)))
    initial = list(simulation.walls)
    while not simulation.finished:
        ranges = simulation.record()
        simulation.command(*controller(ranges))
        for _ in range(4):
            simulation.advance(0.02)
    simulation.record()
    return simulation.replay(initial)


def reference(ranges):
    middle = len(ranges) // 2
    ahead = [value for value in ranges[middle - 5:middle + 6] if not math.isnan(value)]
    return (0.2 if ahead and min(ahead) > 0.5 else 0.0), 0.0


def test_unicycle_step_drives_straight_and_turns():
    assert step(Pose(0, 0, 0), 0.2, 0.0, 1.0).x == pytest.approx(0.2)
    turned = step(Pose(0, 0, 0), 0.0, math.pi / 2, 1.0)
    assert (turned.x, turned.y, turned.theta) == pytest.approx((0, 0, math.pi / 2))


def test_scan_matches_the_wall_stop_grader_layout():
    ranges = scan(Pose(0, 0, 0), [(1.0, -3.0, 1.0, 3.0)])
    assert len(ranges) == 91
    assert ranges[45] == pytest.approx(1.0)
    assert ranges[45 + 10] == pytest.approx(1.0 / math.cos(math.radians(30)))
    assert math.isinf(ranges[0]) and math.isinf(ranges[-1])  # behind and to the sides
    assert math.isinf(ray_hit(0, 0, math.pi, (1.0, -3.0, 1.0, 3.0)))
    assert distance_to_wall(0.9, 0.0, (1.0, -3.0, 1.0, 3.0)) == pytest.approx(0.1)


def test_reference_stops_before_the_wall_then_drives_again_after_it_moves():
    replay = drive(reference)
    kinds = [event["type"] for event in replay["events"]]
    assert replay["outcome"] == "stopped_and_resumed"
    assert kinds[:4] == ["started", "stopped", "wall_moved", "resumed"]
    stopped = next(event for event in replay["events"] if event["type"] == "stopped")
    assert 0.45 <= stopped["front"] <= 0.5
    moved = next(event for event in replay["events"] if event["type"] == "wall_moved")
    assert moved["walls"] == [[2.7, -3.0, 2.7, 3.0]]
    assert replay["walls"] == [[1.2, -3.0, 1.2, 3.0]]


@pytest.mark.parametrize(
    ("controller", "outcome"),
    [
        (lambda ranges: (0.2, 0.0), "collided"),
        (lambda ranges: (0.0, 0.0), "never_moved"),
        (lambda ranges: (0.1 if ranges[45] > 0.3 else 0.0, 0.0), "kept_driving"),
        (lambda ranges: (0.3 if ranges[45] > 0.5 else 0.0, 0.0), "stopped_and_resumed"),
    ],
)
def test_outcomes_describe_what_the_robot_did(controller, outcome):
    assert drive(controller)["outcome"] == outcome


def test_replay_is_bounded_and_json_safe():
    replay = drive(lambda ranges: (0.0, 0.0))
    assert len(replay["frames"]) <= MAX_FRAMES
    frame = replay["frames"][0]
    assert len(frame["ranges"]) == 31
    assert frame["ranges"][0] is None  # nothing behind the robot: inf becomes null
    json.dumps(replay, allow_nan=False)


def test_bad_commands_are_treated_as_stop():
    simulation = Simulation.from_scenario(WORLD)
    simulation.command(float("nan"), 0.0)
    assert simulation.linear == 0.0


def test_assignment_7_world_is_a_valid_ros2_2d_simulation():
    config = SimulationConfig.model_validate(SOURCE["simulation_config"])
    assert config.provider == "ros2_2d" and config.enabled
    assert SOURCE["version"] == 5
    assert "Press <strong>Simulate</strong>" in SOURCE["assignment_html"]
    with pytest.raises(ValidationError):
        SimulationConfig.model_validate({"enabled": True, "provider": "ros2_2d"})
    with pytest.raises(ValidationError):
        SimulationConfig.model_validate({
            "enabled": True, "provider": "ros2_2d",
            "world": {**WORLD, "wall_move": {**WORLD["wall_move"], "wall": 3}},
        })
    with pytest.raises(ValidationError):
        SimulationConfig.model_validate({
            "enabled": True, "provider": "ros2_2d", "world": {**WORLD, "duration_seconds": 30},
        })


def test_worker_selects_the_simulation_and_skips_code_checks():
    config = {**SOURCE["grader_config"], "mode": "simulate", "simulation": WORLD}
    assert select_harness(config) == SIMULATION_HARNESS
    assert static_code_tests({"code": "x = 1", "config": config}) == []
    with pytest.raises(ValueError):
        select_harness({**config, "simulation": None})
    assert select_harness(SOURCE["grader_config"]) == "/grader/ros2_wall_stop_harness.py"


def test_executor_sends_only_the_simulation_settings_it_needs():
    sent = _safe_config({**SOURCE["grader_config"], "mode": "simulate", "simulation": WORLD})
    assert sent["mode"] == "simulate" and sent["simulation"] == WORLD
    assert "gate_tests" not in sent and "pass_tests" not in sent
    assert _valid_result({"success": True, "error": "", "output": "", "tests": [], "simulation": None})
    assert not _valid_result({"success": True, "error": "", "output": "", "tests": [], "simulation": [1]})


def test_normalize_replay_drops_unexpected_or_unsafe_values():
    replay = drive(reference)
    replay["secret"] = "x"
    replay["frames"][0]["x"] = float("nan")
    replay["frames"][1]["extra"] = "y"
    replay["frames"][2]["ranges"] = [1.0] * 500
    replay["events"].append({"t": 1.0, "type": "teleported"})
    clean = normalize_replay(replay)
    assert "secret" not in clean
    assert len(clean["frames"]) == len(replay["frames"]) - 1
    assert "extra" not in clean["frames"][0]
    assert len(clean["frames"][1]["ranges"]) == 31
    assert all(event["type"] != "teleported" for event in clean["events"])
    assert normalize_replay({"walls": [], "frames": [], "outcome": "stopped"}) is None
    assert normalize_replay("nope") is None


def test_beam_probe_result_is_bounded_and_optional():
    replay = drive(reference)
    assert "sensitivity" not in normalize_replay(replay)
    replay["sensitivity"] = {"status": "complete", "beams": [16, 15, 15, 14, 99, -1, True, "7"]}
    assert normalize_replay(replay)["sensitivity"] == {
        "status": "complete", "beams": [14, 15, 16],
    }
    replay["sensitivity"] = {"status": "guessed", "beams": [15]}
    assert "sensitivity" not in normalize_replay(replay)
    assert _valid_result({
        "success": True, "error": "", "output": "", "tests": [],
        "observations": {"phases": {}, "rate_hz": 12.0},
    })
    assert not _valid_result({
        "success": True, "error": "", "output": "", "tests": [], "observations": [1],
    })


def test_simulation_run_event_stores_only_outcome_and_duration():
    assert normalize_event_data("simulation_run", {"outcome": "collided", "duration_seconds": 5.2}) == {
        "outcome": "collided", "duration_seconds": 5.2,
    }
    with pytest.raises(ValueError):
        normalize_event_data("simulation_run", {"outcome": "collided", "duration_seconds": 1, "code": "x"})


class FakeSimulationExecutor:
    def __init__(self):
        self.configs = []

    def execute(self, code, project_files, config):
        self.configs.append(config)
        return {
            "success": True, "error": "", "output": "Simulated 8.0 s.", "tests": [],
            "simulation": drive(reference, config["simulation"]),
        }


@pytest.fixture()
def sim_client(tmp_path):
    executor = FakeSimulationExecutor()
    settings = Settings(
        database_url="sqlite://", admin_api_token="test-admin", openai_api_key=None,
        study_accounts_file=tmp_path / "study_accounts.json", max_submission_chars=5000,
    )
    app = create_app(settings=settings, database_url="sqlite://",
                     ros2_executor_factory=lambda _timeout: executor)
    with TestClient(app) as client:
        client.executor = executor
        yield client


def bearer(token):
    return {"Authorization": f"Bearer {token}"}


def student_token(client):
    return client.post("/auth/login", json={"login_id": "student", "password": "student"}).json()["token"]


def counts(client):
    with client.app.state.SessionLocal() as session:
        return (
            session.scalar(select(func.count()).select_from(Submission)),
            session.scalar(select(func.count()).select_from(LearningEvent)),
        )


def test_simulate_requires_authentication(sim_client):
    assert sim_client.post("/assignments/7/simulate", json={"code": "x"}).status_code == 401


def test_student_simulation_returns_a_replay_and_records_only_one_event(sim_client):
    token = student_token(sim_client)
    study = sim_client.post(
        "/research/sessions", headers=bearer(token), json={"client_session_id": "browser-sim-01"}
    ).json()
    before = counts(sim_client)
    response = sim_client.post(
        "/assignments/7/simulate", headers=bearer(token),
        json={"code": SOURCE["starter_code"], "study_session_id": study["id"]},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["success"] is True and body["assignment_version"] == 5
    assert body["simulation"]["outcome"] == "stopped_and_resumed"
    assert set(body) == {"assignment_version", "success", "error", "output", "simulation"}
    text = json.dumps(body)
    for private in ("gate_tests", "test_weights", "skeleton_main", "assignments_answers", "FORWARD_SPEED"):
        assert private not in text
    after = counts(sim_client)
    assert after == (before[0], before[1] + 1)  # no submission row, one learning event
    with sim_client.app.state.SessionLocal() as session:
        event = session.scalars(select(LearningEvent).order_by(LearningEvent.id.desc())).first()
        assert event.event_type == "simulation_run"
        assert event.event_data == {"outcome": "stopped_and_resumed", "duration_seconds": body["simulation"]["duration_seconds"]}
        assert event.assignment_version == 5
    assert sim_client.executor.configs[-1]["mode"] == "simulate"


def test_demo_simulation_writes_nothing(sim_client):
    before = counts(sim_client)
    token = sim_client.post("/auth/demo").json()["token"]
    response = sim_client.post("/assignments/7/simulate", headers=bearer(token),
                               json={"code": SOURCE["starter_code"]})
    assert response.status_code == 200
    assert counts(sim_client) == before


def test_simulate_rejects_assignments_without_a_replay_and_oversized_code(sim_client):
    token = student_token(sim_client)
    assert sim_client.post("/assignments/6/simulate", headers=bearer(token),
                           json={"code": "x = 1"}).status_code == 409
    assert sim_client.post("/assignments/2/simulate", headers=bearer(token),
                           json={"code": "x = 1"}).status_code == 409
    assert sim_client.post("/assignments/7/simulate", headers=bearer(token),
                           json={"code": "x" * 6000}).status_code == 413
    assert sim_client.post("/assignments/7/simulate", headers=bearer(token),
                           json={"code": "  "}).status_code == 400
    assert sim_client.post("/assignments/99/simulate", headers=bearer(token),
                           json={"code": "x = 1"}).status_code == 404
    assert sim_client.executor.configs == []


def test_failed_node_reports_its_error_without_a_replay(tmp_path):
    class Failing:
        def execute(self, code, project_files, config):
            return {"success": False, "error": "Your node stopped with an error:\nNameError", "output": "",
                    "tests": [], "simulation": None}

    settings = Settings(database_url="sqlite://", admin_api_token="t", openai_api_key=None,
                        study_accounts_file=tmp_path / "s.json")
    with TestClient(create_app(settings=settings, database_url="sqlite://",
                               ros2_executor_factory=lambda _timeout: Failing())) as client:
        response = client.post("/assignments/7/simulate", headers=bearer(student_token(client)),
                               json={"code": "x = 1"})
    assert response.status_code == 200
    assert response.json()["success"] is False
    assert response.json()["simulation"] is None
    assert "NameError" in response.json()["error"]


def test_simulation_shares_the_execution_rate_limit(tmp_path):
    settings = Settings(database_url="sqlite://", admin_api_token="t", openai_api_key=None,
                        study_accounts_file=tmp_path / "s.json", execution_requests_per_minute=1)
    with TestClient(create_app(settings=settings, database_url="sqlite://",
                               ros2_executor_factory=lambda _timeout: FakeSimulationExecutor())) as client:
        headers = bearer(student_token(client))
        assert client.post("/assignments/7/simulate", headers=headers, json={"code": "x = 1"}).status_code == 200
        assert client.post("/assignments/7/simulate", headers=headers, json={"code": "x = 1"}).status_code == 429
