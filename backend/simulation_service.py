"""Run a student's ROS 2 node in the 2D replay world and return a safe trace.

The replay is a visual aid only: it creates no submission, earns no score,
and never changes pass rules. Grading stays in graders/ros2_topic.py.
"""

from __future__ import annotations

import math
from typing import Any

from data_contracts import SimulationConfig
from models import Assignment


PROVIDER = "ros2_2d"
MAX_FRAMES = 200
MAX_BEAMS = 31
MAX_EVENTS = 50
MAX_WALLS = 20
EVENT_TYPES = {"started", "stopped", "wall_moved", "resumed", "collided", "finished"}
OUTCOMES = {"collided", "never_moved", "stopped", "stopped_and_resumed", "kept_driving"}


def simulation_world(assignment: Assignment) -> dict | None:
    """The validated world for an assignment with an enabled robot replay."""
    raw = assignment.simulation_config or {}
    if not raw.get("enabled") or raw.get("provider") != PROVIDER:
        return None
    if assignment.grader_type != "ros2_topic":
        return None
    config = SimulationConfig.model_validate(raw)
    return config.world.model_dump(mode="json") if config.world else None


def run_simulation(assignment: Assignment, code: str, executor, world: dict) -> dict[str, Any]:
    project_files = [
        item for item in (assignment.asset_manifest or [])
        if isinstance(item, dict) and item.get("kind") == "project_file"
    ]
    config = dict(assignment.grader_config or {})
    config.update({"mode": "simulate", "simulation": world})
    result = executor.execute(code, project_files, config)
    replay = normalize_replay(result.get("simulation"))
    error = str(result.get("error") or "")
    return {
        "assignment_version": assignment.version,
        "success": bool(result.get("success")) and replay is not None,
        "error": error[-3000:],
        "output": str(result.get("output") or "")[-2000:],
        "simulation": replay,
    }


def _number(value: Any, limit: float = 100.0) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    value = float(value)
    return value if math.isfinite(value) and abs(value) <= limit else None


def _reading(value: Any) -> float | None:
    number = _number(value)
    return number if number is not None and number >= 0 else None


def _wall(value: Any) -> list[float] | None:
    if not isinstance(value, list) or len(value) != 4:
        return None
    numbers = [_number(item, 50.0) for item in value]
    return None if any(item is None for item in numbers) else numbers


def normalize_replay(replay: Any) -> dict | None:
    """Keep only bounded, finite, expected fields from the container's trace."""
    if not isinstance(replay, dict):
        return None
    walls = [wall for wall in (_wall(item) for item in replay.get("walls", [])[:MAX_WALLS]) if wall]
    frames = []
    for item in replay.get("frames", [])[:MAX_FRAMES]:
        if not isinstance(item, dict):
            continue
        values = {key: _number(item.get(key)) for key in ("t", "x", "y", "theta", "linear", "angular")}
        if any(value is None for value in values.values()):
            continue
        ranges = item.get("ranges", [])
        values["front"] = _reading(item.get("front"))
        values["ranges"] = [_reading(value) for value in ranges[:MAX_BEAMS]] if isinstance(ranges, list) else []
        frames.append(values)
    events = []
    for item in replay.get("events", [])[:MAX_EVENTS]:
        if not isinstance(item, dict) or item.get("type") not in EVENT_TYPES:
            continue
        time = _number(item.get("t"))
        if time is None:
            continue
        event = {"t": time, "type": item["type"]}
        if item["type"] == "stopped":
            event["front"] = _reading(item.get("front"))
        if item["type"] == "wall_moved":
            event["walls"] = [wall for wall in (_wall(w) for w in item.get("walls", [])[:MAX_WALLS]) if wall]
        events.append(event)
    scan = replay.get("scan") if isinstance(replay.get("scan"), dict) else {}
    outcome = replay.get("outcome")
    if not walls or not frames or outcome not in OUTCOMES:
        return None
    return {
        "scan": {
            "angle_min_deg": _number(scan.get("angle_min_deg"), 360.0) or -135.0,
            "angle_increment_deg": _number(scan.get("angle_increment_deg"), 360.0) or 9.0,
            "range_max": _number(scan.get("range_max")) or 10.0,
        },
        "robot_radius": _number(replay.get("robot_radius"), 1.0) or 0.15,
        "walls": walls,
        "frames": frames,
        "events": events,
        "outcome": outcome,
        "duration_seconds": _number(replay.get("duration_seconds"), 10.0) or 0.0,
    }
