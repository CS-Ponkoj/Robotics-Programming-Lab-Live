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
    assert "Skip only the entries with no usable distance, not the whole mixed scan" in instructions
    assert "2.0 m" in instructions
    assert "Invalid sensor data must never cause forward motion" not in instructions


def test_ros_states_import_allowlist_shutdown_and_measured_numbers():
    for number in (5, 6):
        data = source(number)
        instructions = data["assignment_html"]
        assert ("may import only <code>rclpy</code>, <code>geometry_msgs</code>, "
                "<code>sensor_msgs</code>, and <code>math</code>") in instructions
        assert "TwistStamped" in instructions
        starter = data["starter_code"]
        assert "from rclpy.executors import ExternalShutdownException" in starter
        assert "except (KeyboardInterrupt, ExternalShutdownException):" in starter
        assert "rclpy.try_shutdown()" in starter
        assert "rclpy.shutdown()" not in starter
        package_xml = next(item["content"] for item in data["asset_manifest"]
                           if item["path"].endswith("package.xml"))
        assert "ament_pytest" not in package_xml
        for dependency in ("<exec_depend>launch</exec_depend>",
                           "<exec_depend>launch_ros</exec_depend>",
                           "<test_depend>python3-pytest</test_depend>"):
            assert dependency in package_xml
    drive = source(5)["assignment_html"]
    assert "do not import <code>time</code>" in drive
    for number_text in ("about 8 seconds", "at least 5 commands per second",
                        "0.20 &plusmn; 0.02 m/s", "&plusmn;0.01 rad/s", "&plusmn;0.001",
                        "between 4.5 and 5.5 seconds", "do not add extra timers",
                        "passing the integer 10"):
        assert number_text in drive
    obstacle = source(6)["assignment_html"]
    assert "and one Twist decision per scan" in obstacle
    assert "and timing" not in obstacle
    for number_text in ("about 0.8 seconds", "about 0.25 seconds",
                        "at least 3 commands per second", "do not filter beams by angle"):
        assert number_text in obstacle
    # Positive infinity is a conservative "no usable distance" rule, not "invalid".
    assert "no usable distance" in obstacle
    assert "nothing was detected within range" in obstacle


def test_tutor_review_versions_match_current_assignment_contracts():
    root = Path(__file__).parents[1]
    for number in range(1, 7):
        review = json.loads((root / "ai_evaluation_cases" /
                             f"assignment_{number}.json").read_text())
        assert review["assignment_version"] == source(number)["version"]


def test_python_assignments_describe_the_current_sandbox_allowlist():
    for number in (1, 2, 3, 4):
        instructions = source(number)["assignment_html"]
        assert "np.deg2rad" in instructions and "np.argmin" in instructions
        # These now run, so instructions must not call them unavailable.
        assert "<code>dict.update</code>" not in instructions
        assert "<code>math.pow</code>" not in instructions
        assert "a lone <code>_</code> is fine" in instructions


def test_vfh_states_that_a_zero_half_width_is_a_valid_input():
    instructions = source(4)["assignment_html"]
    assert "<code>search_half_width</code> may be 0" in instructions
    widths = [case["arguments"][4] for case in source(4)["grader_config"]["cases"]]
    assert 0 in widths


def test_obstacle_assignment_does_not_repeat_the_full_ros_terms_list():
    instructions = source(6)["assignment_html"]
    assert "<strong>ROS terms</strong>" not in instructions
    assert "Reminders from Assignment 5" in instructions


def test_misconception_tags_name_configured_misconceptions():
    for number in (1, 2, 3, 4):
        data = source(number)
        known = {item["tag"] for item in data["common_misconceptions"]}
        tags = [c["misconception"] for c in data["grader_config"]["criteria"] if "misconception" in c]
        assert tags and set(tags) <= known
