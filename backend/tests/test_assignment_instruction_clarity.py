"""Keep student instructions consistent with the assessed mathematical contract."""
import json
from pathlib import Path


def source(number):
    root = Path(__file__).parents[1]
    return json.loads((root / "assignments" / f"assignment_{number}.json").read_text())


def test_bug_routes_explain_the_euclidean_helper_and_python_exponent():
    for number in (1, 2):
        instructions = source(number)["assignment_html"]
        assert "Euclidean" in instructions
        assert "math.sqrt((x2 - x1)**2 + (y2 - y1)**2)" in instructions
        assert "math.hypot(dx, dy)" in instructions
        assert "<code>^</code>" in instructions
    assert "H = (4, 11/3)" in source(1)["assignment_html"]
    assert "-1 &lt;= y &lt;= 1" in source(2)["assignment_html"]
    assert "C, D" not in source(2)["assignment_html"]


def test_elevator_example_names_every_parameter_and_explains_the_allowance():
    instructions = source(3)["assignment_html"]
    assert "<table>" not in instructions  # Long parameter names must wrap on mobile.
    for name in ("robot_speed", "service_detour_radius", "main_elevator_wait",
                 "service_elevator_wait", "main_seconds_per_floor",
                 "service_seconds_per_floor", "floors_to_travel", "start",
                 "goal", "main_elevator", "service_elevator", "main_waypoints"):
        assert name in instructions
    assert "do not subtract a diameter" in instructions
    assert "route_length(points)" in instructions
    assert "ties to even" in instructions


def test_vfh_is_a_parameterized_sector_selection_not_a_safety_guarantee():
    data = source(4)
    instructions = data["assignment_html"]
    assert "Safe Trajectory" not in data["title"]
    assert "goal_direction - search_half_width" in instructions
    assert "goal_direction + search_half_width" in instructions
    assert "five equally weighted checks is worth 20%" in instructions
    assert "does not calculate a robot trajectory" in instructions
    assert "fewer than 360" in instructions


def test_ros_explains_exact_one_and_mixed_scan_behavior():
    for number in (5, 6):
        instructions = source(number)["assignment_html"]
        assert "exactly one" in instructions
        assert "Queue depth 10" in instructions
        assert "callback" in instructions
    instructions = source(6)["assignment_html"]
    assert "Ignore invalid entries, not the whole mixed scan" in instructions
    assert "2.0 m" in instructions
    assert "Invalid sensor data must never cause forward motion" not in instructions


def test_tutor_review_versions_match_current_assignment_contracts():
    root = Path(__file__).parents[1]
    for number in range(1, 7):
        review = json.loads((root / "ai_evaluation_cases" /
                             f"assignment_{number}.json").read_text())
        assert review["assignment_version"] == source(number)["version"]
