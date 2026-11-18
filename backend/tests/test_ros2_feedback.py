"""Evidence-based findings and hint ladders for Assignment 7 behavior checks."""
import json
from pathlib import Path
from types import SimpleNamespace

import pytest

from graders.ros2_topic import Ros2TopicGrader
from models import Assignment
from ros2_feedback import HINT_LADDERS, classify
from tutor import TutorService

ROOT = Path(__file__).resolve().parents[2]
SOURCE = json.loads(
    (ROOT / "backend" / "assignments" / "assignment_7.json").read_text(encoding="utf-8")
)
BEHAVIOR = SOURCE["grader_config"]["pass_tests"]


def phase(low, high, turn=0.0, count=8):
    return {"count": count, "linear_min": low, "linear_max": high, "angular_max_abs": turn}


def observations(**phases):
    names = ("open", "far", "near", "close", "hold", "resume")
    good = {
        "open": phase(0.2, 0.2), "far": phase(0.2, 0.2), "near": phase(0.0, 0.0),
        "close": phase(0.0, 0.0), "hold": phase(0.0, 0.0), "resume": phase(0.2, 0.2),
    }
    return {"phases": {name: phases.get(name, good[name]) for name in names}, "rate_hz": 12.0}


def passed_except(*failing):
    return {test_id: test_id not in failing for test_id in BEHAVIOR}


def keys(findings):
    return {test_id: finding.hint_key for test_id, finding in findings.items()}


def test_too_fast_and_wrong_beam_are_named_with_what_the_robot_did():
    # SPEED = 0.5 and a sideways beam: drives too fast and never stops in time.
    obs = observations(
        open=phase(0.5, 0.5), far=phase(0.5, 0.5), near=phase(0.5, 0.5),
        close=phase(0.0, 0.5), hold=phase(0.0, 0.0), resume=phase(0.5, 0.5),
    )
    findings = classify(
        "wall_stop_open",
        passed_except("drive-open-floor", "drive-wall-far", "stop-wall-0-3",
                      "stop-wall-0-2", "resume-motion"),
        obs,
    )
    assert keys(findings) == {
        "drive-open-floor": "speed-too-high",
        "drive-wall-far": "speed-too-high",
        "stop-wall-0-3": "stops-too-late",
        "stop-wall-0-2": "stops-too-late",
        "resume-motion": "speed-too-high",
    }
    assert "0.50 m/s" in findings["drive-open-floor"].observation
    assert "0.3 m away" in findings["stop-wall-0-3"].observation


@pytest.mark.parametrize(
    ("phases", "failing", "expected"),
    [
        ({"open": phase(0.0, 0.0)}, ["drive-open-floor"],
         {"drive-open-floor": "infinity-treated-as-obstacle"}),
        ({"far": phase(0.0, 0.0)}, ["drive-wall-far"],
         {"drive-wall-far": "stops-too-early"}),
        ({"open": phase(0.05, 0.05)}, ["drive-open-floor"],
         {"drive-open-floor": "speed-too-low"}),
        ({"resume": phase(0.0, 0.0)}, ["resume-motion"],
         {"resume-motion": "does-not-resume"}),
        ({"far": phase(0.2, 0.2, turn=0.4)}, ["straight-motion"],
         {"straight-motion": "turns-while-driving"}),
        ({"open": phase(0.0, 0.0), "far": phase(0.0, 0.0),
          "near": phase(0.2, 0.2), "close": phase(0.2, 0.2)},
         ["drive-open-floor", "drive-wall-far", "stop-wall-0-3", "stop-wall-0-2"],
         dict.fromkeys(["drive-open-floor", "drive-wall-far", "stop-wall-0-3",
                        "stop-wall-0-2"], "wrong-threshold-direction")),
        ({"open": phase(0.0, 0.0), "far": phase(0.0, 0.0)},
         ["drive-open-floor", "drive-wall-far", "stop-wall-0-3"],
         {"stop-wall-0-3": "must-drive-first"}),
    ],
)
def test_each_pattern_is_recognised(phases, failing, expected):
    findings = classify("wall_stop_open", passed_except(*failing), observations(**phases))
    assert {key: value for key, value in keys(findings).items() if key in expected} == expected


def test_low_publish_rate_reports_the_measured_rate():
    obs = {**observations(), "rate_hz": 2.0}
    findings = classify("wall_stop_open", passed_except("publish-rate"), obs)
    assert findings["publish-rate"].hint_key == "publishes-too-rarely"
    assert "2.0 commands per second" in findings["publish-rate"].observation


def test_other_harnesses_and_missing_observations_give_nothing():
    assert classify("drive_forward", passed_except("drive-open-floor"), observations()) == {}
    assert classify("wall_stop_open", passed_except("drive-open-floor"), None) == {}


def test_every_hint_key_has_a_four_step_ladder():
    produced = {
        "speed-too-high", "speed-too-low", "infinity-treated-as-obstacle",
        "stops-too-early", "stops-too-late", "wrong-threshold-direction",
        "must-drive-first", "does-not-resume", "turns-while-driving",
        "publishes-too-rarely", "build-node-returns-none",
    }
    assert produced <= set(HINT_LADDERS)
    for ladder in HINT_LADDERS.values():
        assert len(ladder.levels) == 4
        assert all("```" not in text and "def " not in text for text in ladder.levels)


class ObservingExecutor:
    def __init__(self, failing, obs):
        self.failing, self.obs = failing, obs

    def execute(self, code, project_files, config):
        return {
            "success": True,
            "error": "",
            "output": "",
            "tests": [
                {"id": item["id"], "passed": item["id"] not in self.failing,
                 "message": f"Check {item['id']}."}
                for item in SOURCE["public_tests"]
            ],
            "observations": self.obs,
        }


def assignment_7() -> Assignment:
    return Assignment(
        id=7, stable_id=SOURCE["stable_id"], version=SOURCE["version"], title=SOURCE["title"],
        public_tests=SOURCE["public_tests"], asset_manifest=SOURCE["asset_manifest"],
        misconceptions=SOURCE["common_misconceptions"], language="python-ros2",
        grader_type="ros2_topic", grader_config=SOURCE["grader_config"],
    )


def test_grader_adds_observations_and_only_configured_tags_become_labels():
    obs = observations(open=phase(0.5, 0.5), far=phase(0.0, 0.0))
    grader = Ros2TopicGrader(
        ObservingExecutor({"drive-open-floor", "drive-wall-far"}, obs)
    )
    result = grader.grade(assignment_7(), "code")
    by_id = {item.test_id: item for item in result.evidence}
    fast, early = by_id["drive-open-floor"], by_id["drive-wall-far"]
    assert fast.hint_key == "speed-too-high"
    assert fast.misconception_tag is None  # a hint pattern, not a configured tag
    assert "0.50 m/s" in fast.message
    assert early.hint_key == "stops-too-early"
    assert early.misconception_tag == "stops-too-early"  # configured in Assignment 7
    assert by_id["stop-wall-0-3"].hint_key is None  # passed checks stay unchanged


def test_built_in_hints_follow_the_ladder_for_the_first_failed_check():
    obs = observations(open=phase(0.5, 0.5), far=phase(0.5, 0.5))
    result = Ros2TopicGrader(
        ObservingExecutor({"drive-open-floor", "drive-wall-far"}, obs)
    ).grade(assignment_7(), "code")
    submission = SimpleNamespace(
        code="",
        evidence={
            "execution_succeeded": True,
            "score": result.score,
            "tests": [item.model_dump() for item in result.evidence],
        },
    )
    ladder = HINT_LADDERS["speed-too-high"]
    for level in range(1, 5):
        feedback = TutorService._fallback(assignment_7(), submission, level)
        assert feedback.hint == ladder.levels[level - 1]
        assert feedback.diagnosis == ladder.diagnosis
        assert "0.50 m/s" in feedback.debugging_steps[0]
        assert feedback.misconception == ""
