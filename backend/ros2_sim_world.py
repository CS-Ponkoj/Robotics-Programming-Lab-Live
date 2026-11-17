"""A small 2D world for replaying how a student's ROS 2 node drives a robot.

Pure Python with no ROS imports, so the physics, scans, and event rules can be
unit-tested anywhere. The grader container wraps it in ros2_sim_harness.py.
This is a visual teaching aid: a flat floor, straight walls, and a unicycle
robot. It is not a physics engine and it never affects grading.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field


SCAN_MIN_DEG = -135.0
SCAN_INCREMENT_DEG = 3.0
SCAN_BEAMS = 91
RANGE_MIN = 0.1
RANGE_MAX = 10.0
DISPLAY_BEAM_STEP = 3          # 91 beams -> 31 drawn rays
MOVING_SPEED = 0.001           # |linear.x| or |angular.z| above this counts as moving
MAX_FRAMES = 200
MAX_EVENTS = 50
MAX_WALLS = 20
MAX_DURATION_SECONDS = 8.0


@dataclass
class Pose:
    x: float
    y: float
    theta: float


def step(pose: Pose, linear: float, angular: float, dt: float) -> Pose:
    """Unicycle motion for one small time step."""
    theta = pose.theta + angular * dt
    heading = (pose.theta + theta) / 2.0
    return Pose(
        pose.x + linear * math.cos(heading) * dt,
        pose.y + linear * math.sin(heading) * dt,
        math.atan2(math.sin(theta), math.cos(theta)),
    )


def ray_hit(x: float, y: float, angle: float, wall: tuple[float, float, float, float]) -> float:
    """Distance along a ray to a wall segment, or inf when it misses."""
    x1, y1, x2, y2 = wall
    dx, dy = math.cos(angle), math.sin(angle)
    sx, sy = x2 - x1, y2 - y1
    denominator = dx * sy - dy * sx
    if abs(denominator) < 1e-12:
        return math.inf
    qx, qy = x1 - x, y1 - y
    distance = (qx * sy - qy * sx) / denominator
    along = (qx * dy - qy * dx) / denominator
    if distance < 0 or along < 0 or along > 1:
        return math.inf
    return distance


def scan(pose: Pose, walls: list[tuple]) -> list[float]:
    """The 270-degree scan the robot sees, using the wall-stop grader's layout."""
    ranges = []
    for index in range(SCAN_BEAMS):
        angle = pose.theta + math.radians(SCAN_MIN_DEG + index * SCAN_INCREMENT_DEG)
        distance = min((ray_hit(pose.x, pose.y, angle, wall) for wall in walls), default=math.inf)
        ranges.append(distance if RANGE_MIN <= distance <= RANGE_MAX else math.inf)
    return ranges


def distance_to_wall(x: float, y: float, wall: tuple) -> float:
    x1, y1, x2, y2 = wall
    sx, sy = x2 - x1, y2 - y1
    length = sx * sx + sy * sy
    t = 0.0 if length == 0 else max(0.0, min(1.0, ((x - x1) * sx + (y - y1) * sy) / length))
    return math.hypot(x - (x1 + t * sx), y - (y1 + t * sy))


def rounded(value: float) -> float | None:
    """JSON-safe reading: None for no return, three decimals otherwise."""
    return None if not math.isfinite(value) else round(value, 3)


@dataclass
class Simulation:
    """Advance the robot, apply the scenario script, and record a replay."""

    walls: list[tuple]
    pose: Pose
    radius: float
    duration: float
    wall_move: dict | None = None
    time: float = 0.0
    linear: float = 0.0
    angular: float = 0.0
    frames: list[dict] = field(default_factory=list)
    events: list[dict] = field(default_factory=list)
    finished: str = ""
    _moving: bool = False
    _ever_moved: bool = False
    _stopped_since: float | None = None
    _wall_moved: bool = False

    @classmethod
    def from_scenario(cls, scenario: dict) -> "Simulation":
        robot = scenario.get("robot", {})
        walls = [tuple(float(value) for value in wall) for wall in scenario["walls"]]
        return cls(
            walls=walls,
            pose=Pose(float(robot.get("x", 0.0)), float(robot.get("y", 0.0)), float(robot.get("theta", 0.0))),
            radius=float(robot.get("radius", 0.15)),
            duration=min(float(scenario.get("duration_seconds", MAX_DURATION_SECONDS)), MAX_DURATION_SECONDS),
            wall_move=scenario.get("wall_move"),
        )

    def event(self, kind: str, **details) -> None:
        if len(self.events) < MAX_EVENTS:
            self.events.append({"t": round(self.time, 2), "type": kind, **details})

    def front(self) -> float:
        return scan(self.pose, self.walls)[SCAN_BEAMS // 2]

    def command(self, linear: float, angular: float) -> None:
        """Latest /cmd_vel; the robot holds it until the next one arrives."""
        if not (math.isfinite(linear) and math.isfinite(angular)):
            linear, angular = 0.0, 0.0
        self.linear, self.angular = linear, angular
        moving = abs(linear) > MOVING_SPEED or abs(angular) > MOVING_SPEED
        if moving and not self._moving:
            kind = "resumed" if self._wall_moved and self._ever_moved else "started"
            self.event(kind)
            self._ever_moved = True
            self._stopped_since = None
        elif not moving and self._moving:
            self.event("stopped", front=rounded(self.front()))
        if not moving and self._stopped_since is None:
            self._stopped_since = self.time
        self._moving = moving

    def advance(self, dt: float) -> None:
        if self.finished:
            return
        self.pose = step(self.pose, self.linear, self.angular, dt)
        self.time += dt
        if any(distance_to_wall(self.pose.x, self.pose.y, wall) < self.radius for wall in self.walls):
            self.event("collided")
            self.finished = "collided"
            self.linear = self.angular = 0.0
            return
        move = self.wall_move
        if (
            move and not self._wall_moved and self._ever_moved and not self._moving
            and self._stopped_since is not None
            and self.time - self._stopped_since >= float(move.get("after_stopped_seconds", 1.0))
        ):
            index = int(move.get("wall", 0))
            dx, dy = float(move.get("dx", 0.0)), float(move.get("dy", 0.0))
            x1, y1, x2, y2 = self.walls[index]
            self.walls[index] = (x1 + dx, y1 + dy, x2 + dx, y2 + dy)
            self._wall_moved = True
            self.event("wall_moved", wall=index, walls=[list(wall) for wall in self.walls])
        if self.time >= self.duration:
            self.event("finished")
            self.finished = "finished"

    def record(self) -> list[float]:
        """Scan from the current pose and store one replay frame."""
        ranges = scan(self.pose, self.walls)
        if len(self.frames) < MAX_FRAMES:
            self.frames.append({
                "t": round(self.time, 3),
                "x": round(self.pose.x, 4),
                "y": round(self.pose.y, 4),
                "theta": round(self.pose.theta, 4),
                "linear": round(self.linear, 4),
                "angular": round(self.angular, 4),
                "front": rounded(ranges[SCAN_BEAMS // 2]),
                "ranges": [rounded(value) for value in ranges[::DISPLAY_BEAM_STEP]],
            })
        return ranges

    def outcome(self) -> str:
        if self.finished == "collided":
            return "collided"
        if not self._ever_moved:
            return "never_moved"
        if self.wall_move and self._wall_moved and any(item["type"] == "resumed" for item in self.events):
            return "stopped_and_resumed"
        if any(item["type"] == "stopped" for item in self.events):
            return "stopped"
        return "kept_driving"

    def replay(self, initial_walls: list[tuple]) -> dict:
        return {
            "scan": {
                "angle_min_deg": SCAN_MIN_DEG,
                "angle_increment_deg": SCAN_INCREMENT_DEG * DISPLAY_BEAM_STEP,
                "range_max": RANGE_MAX,
            },
            "robot_radius": self.radius,
            "walls": [list(wall) for wall in initial_walls],
            "frames": self.frames,
            "events": self.events,
            "outcome": self.outcome(),
            "duration_seconds": round(self.time, 2),
        }
