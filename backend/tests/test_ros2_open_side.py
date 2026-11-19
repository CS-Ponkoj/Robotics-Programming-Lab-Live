"""Assignment 8 (shown as Assignment 2): turn toward the open side using /flbr."""

import json
import math
import re
from pathlib import Path

import pytest

from assignment_repository import course_numbers, to_student_assignment
from data_contracts import SimulationConfig
from graders.ros2_topic import Ros2TopicGrader
from instructor_dataset import load_instructor_datasets
from models import Assignment
from ros2_executor import _safe_config
from ros2_feedback import HINT_LADDERS, classify
from ros2_sim_world import RANGE_MAX, SCAN_BEAMS, Simulation, flbr
from ros2_worker import ALLOWED_IMPORT_ROOTS, allowed_import_roots, select_harness, validate_controller


ROOT = Path(__file__).resolve().parents[2]
BACKEND = ROOT / "backend"
SOURCE = json.loads((BACKEND / "assignments" / "assignment_8.json").read_text(encoding="utf-8"))
CONFIG = SOURCE["grader_config"]
REFERENCE = (ROOT / SOURCE["reference_solution_path"]).read_text(encoding="utf-8")


def test_assignment_identity_and_scoring():
    assert SOURCE["id"] == 8
    assert SOURCE["stable_id"] == "ros2-turn-open-side"
    assert SOURCE["language"] == "python-ros2"
    assert SOURCE["grader_type"] == "ros2_topic"
    assert CONFIG["harness"] == "open_side"
    assert sum(CONFIG["test_weights"].values()) == 100
    assert sum(item["weight"] for item in SOURCE["rubric"]) == 100
    public_ids = [item["id"] for item in SOURCE["public_tests"]]
    assert set(CONFIG["test_weights"]) == set(public_ids)
    assert select_harness(CONFIG) == "/grader/ros2_open_side_harness.py"


def test_public_tests_match_the_harness_in_order():
    """The worker reports package-build first, then the harness results in order."""
    harness = (BACKEND / "ros2_open_side_harness.py").read_text(encoding="utf-8")
    harness_ids = re.findall(r'result\(\s*"([a-z0-9-]+)"', harness)
    assert ["package-build", *harness_ids] == [item["id"] for item in SOURCE["public_tests"]]


def test_simulation_world_is_valid_and_drives_flbr():
    config = SimulationConfig.model_validate(SOURCE["simulation_config"])
    assert config.provider == "ros2_2d" and config.world is not None
    assert CONFIG["flbr_topic"] == "/flbr"


def test_reference_rule_avoids_the_box_and_never_turning_collides():
    """Offline closed loop with the same 2D world the replay uses."""
    world = SOURCE["simulation_config"]["world"]

    def rule(sectors):
        front, left, right = (0.0 if math.isnan(sectors[key]) else sectors[key]
                              for key in ("front", "left", "right"))
        if front > 0.75:
            return 0.2, 0.0
        return (0.0, 0.5) if left > right else (0.0, -0.5)

    simulation = Simulation.from_scenario(world)
    next_message = 0.0
    while not simulation.finished:
        if simulation.time >= next_message:
            simulation.command(*rule(flbr(simulation.record())))
            next_message += 0.08
        simulation.advance(0.02)
    assert simulation.finished == "finished"

    straight = Simulation.from_scenario(world)
    straight.command(0.2, 0.0)
    while not straight.finished:
        straight.advance(0.02)
    assert straight.finished == "collided"


def test_flbr_matches_the_course_scan_parser():
    ranges = [math.inf] * SCAN_BEAMS
    middle = SCAN_BEAMS // 2
    ranges[middle] = 0.5            # straight ahead
    ranges[middle + 30] = 1.2       # +90 degrees: left
    ranges[middle - 30] = math.nan  # -90 degrees: unusable
    ranges[middle - 31] = 0.05      # below range_min: unusable
    sectors = flbr(ranges)
    assert sectors["front"] == 0.5
    assert sectors["left"] == 1.2
    # +inf counts as the maximum range, so a sector of open space is not NaN.
    assert sectors["right"] == RANGE_MAX
    # The 270-degree scan never covers the back sector.
    assert math.isnan(sectors["back"])


def test_flbr_sector_edges_are_exclusive():
    ranges = [math.inf] * SCAN_BEAMS
    middle = SCAN_BEAMS // 2
    ranges[middle + 15] = 0.3       # exactly +45 degrees: on the edge, in no sector
    sectors = flbr(ranges)
    assert sectors["front"] == RANGE_MAX
    assert sectors["left"] == RANGE_MAX


def test_course_messages_are_allowed_only_where_configured():
    code = "from rse_msgs.msg import Flbr\n"
    with pytest.raises(ImportError):
        validate_controller(code)
    validate_controller(code, allowed_import_roots(CONFIG))
    assert "rse_msgs" not in ALLOWED_IMPORT_ROOTS
    # Only course interfaces built into the image can be opted into.
    assert "os" not in allowed_import_roots({"extra_import_roots": ["os"]})
    with pytest.raises(ImportError):
        validate_controller("import os\n", allowed_import_roots(CONFIG))


def test_reference_imports_only_allowed_modules():
    validate_controller(REFERENCE, allowed_import_roots(CONFIG))
    validate_controller(SOURCE["starter_code"], allowed_import_roots(CONFIG))


def test_executor_passes_the_assignment_settings_to_the_grader():
    safe = _safe_config({**CONFIG, "unexpected": "dropped"})
    for key in ("flbr_topic", "turn_angular_z", "extra_import_roots", "harness"):
        assert safe[key] == CONFIG[key]
    assert "unexpected" not in safe


def test_package_depends_on_the_course_messages():
    package = next(
        item for item in SOURCE["asset_manifest"] if item["path"].endswith("package.xml")
    )
    assert "<exec_depend>rse_msgs</exec_depend>" in package["content"]
    assert "sensor_msgs" not in package["content"]


def phase(linear: float, angular: float) -> dict:
    return {"count": 10, "linear_min": linear, "linear_max": linear,
            "angular_min": angular, "angular_max": angular}


def observations(**overrides) -> dict:
    phases = {
        "clear": phase(0.2, 0.0), "clear-sides-differ": phase(0.2, 0.0),
        "left-open": phase(0.0, 0.5), "right-open": phase(0.0, -0.5),
        "threshold": phase(0.0, -0.5), "sides-equal": phase(0.0, -0.5),
        "front-unknown": phase(0.0, 0.5), "side-unknown": phase(0.0, 0.5),
        "resume": phase(0.2, 0.0),
    }
    phases.update(overrides)
    return {"phases": phases, "rate_hz": 11.0}


@pytest.mark.parametrize(
    ("failed", "overrides", "hint_key"),
    [
        ("clear-path-forward", {"clear-sides-differ": phase(0.2, 0.5)}, "turns-while-clear"),
        ("clear-path-forward", {"clear": phase(1.0, 0.0), "clear-sides-differ": phase(1.0, 0.0)}, "forward-speed-wrong"),
        ("turn-toward-open-side", {"left-open": phase(0.0, -0.5), "right-open": phase(0.0, 0.5)}, "turn-direction-swapped"),
        ("turn-toward-open-side", {"left-open": phase(0.0, 0.0), "right-open": phase(0.0, 0.0)}, "no-turn-when-blocked"),
        ("stop-at-threshold", {"threshold": phase(0.2, 0.0)}, "threshold-boundary"),
        ("equal-sides-turn-right", {"sides-equal": phase(0.0, 0.5)}, "tie-goes-left"),
        ("unknown-distance-safe", {"side-unknown": phase(0.0, -0.5)}, "nan-side-chosen"),
        ("resume-forward", {"resume": phase(0.0, -0.5)}, "open-side-no-resume"),
    ],
)
def test_feedback_names_the_observed_cause(failed, overrides, hint_key):
    findings = classify("open_side", {failed: False}, observations(**overrides))
    assert findings[failed].hint_key == hint_key
    assert hint_key in HINT_LADDERS


def test_every_configured_misconception_has_a_hint_ladder():
    for item in SOURCE["common_misconceptions"]:
        assert item["tag"] in HINT_LADDERS


def test_grader_turns_findings_into_hints():
    class FakeExecutor:
        def execute(self, code, project_files, config):
            tests = [{"id": item["id"], "passed": True, "message": "ok"} for item in SOURCE["public_tests"]]
            for item in tests:
                if item["id"] == "turn-toward-open-side":
                    item.update(passed=False, message="Turn toward the side with more space.")
            return {
                "success": True, "error": "", "output": "", "tests": tests,
                "observations": observations(
                    **{"left-open": phase(0.0, -0.5), "right-open": phase(0.0, 0.5)}
                ),
            }

    assignment = Assignment(
        id=8, title=SOURCE["title"], grader_type="ros2_topic", grader_config=CONFIG,
        public_tests=SOURCE["public_tests"], asset_manifest=SOURCE["asset_manifest"],
        misconceptions=SOURCE["common_misconceptions"],
    )
    result = Ros2TopicGrader(FakeExecutor()).grade(assignment, REFERENCE)
    failed = next(item for item in result.evidence if item.test_id == "turn-toward-open-side")
    assert failed.passed is False
    assert result.passed is False
    assert 0 < result.score < 100


def test_ai_cases_are_drafts_so_the_tutor_stays_off():
    datasets = {dataset.assignment_id: dataset for dataset in load_instructor_datasets()}
    dataset = datasets[8]
    assert dataset.assignment_stable_id == SOURCE["stable_id"]
    assert all(case.review_status == "draft" for case in dataset.cases)
    used = {tag for case in dataset.cases for tag in case.misconception_tags}
    assert used == {item["tag"] for item in SOURCE["common_misconceptions"]}


def test_course_numbers_show_the_current_course_as_1_and_2():
    numbers = course_numbers()
    assert numbers["ros2-wall-stop"] == 1
    assert numbers["ros2-turn-open-side"] == 2
    current = Assignment(id=8, stable_id="ros2-turn-open-side", version=1, data_schema_version=1,
                         title=SOURCE["title"], description="", assignment_html="",
                         starter_code="", language="python-ros2")
    old = Assignment(id=6, stable_id="ros2-obstacle-stop", version=12, data_schema_version=1,
                     title="Assignment 6", description="", assignment_html="",
                     starter_code="", language="python-ros2")
    assert to_student_assignment(current).display_number == 2
    # Assignments without a course number keep showing their ID.
    assert to_student_assignment(old).display_number is None


def test_course_numbers_reject_invalid_values(tmp_path):
    catalog = tmp_path / "catalog.json"
    catalog.write_text(json.dumps({"course_numbers": {"x": 0}}), encoding="utf-8")
    with pytest.raises(ValueError):
        course_numbers(catalog)
    catalog.write_text(json.dumps({"old_assignments": []}), encoding="utf-8")
    assert course_numbers(catalog) == {}
