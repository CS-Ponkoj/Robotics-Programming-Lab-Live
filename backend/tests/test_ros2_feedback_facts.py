"""Check messages state facts in every mode; advice lives only in the hint ladders.

The observations below are the phase summaries the ROS 2 grader reported for
real QA submissions (Assignments 7 and 8), so each pattern is tested with what
the harness actually measures.
"""
import json
import re
from pathlib import Path
from types import SimpleNamespace

import pytest

from graders.ros2_topic import Ros2TopicGrader
from models import Assignment
from ros2_feedback import HINT_LADDERS, classify
from tutor import TutorService

BACKEND = Path(__file__).resolve().parents[1]
A7 = json.loads((BACKEND / "assignments" / "assignment_7.json").read_text(encoding="utf-8"))
A8 = json.loads((BACKEND / "assignments" / "assignment_8.json").read_text(encoding="utf-8"))
A7_IDS = [item["id"] for item in A7["public_tests"]]
A8_IDS = [item["id"] for item in A8["public_tests"]]
WALL = ("open", "far", "near", "close", "hold", "resume")
SIDES = ("clear", "clear-sides-differ", "left-open", "right-open", "threshold",
         "sides-equal", "front-unknown", "side-unknown", "resume")


def wall(*speeds, rate=11.0, turn=0.0, count=7):
    """Phase summaries for the six wall situations, one forward speed each."""
    phases = {
        name: {"count": count, "linear_min": speed, "linear_max": speed,
               "angular_max_abs": turn}
        for name, speed in zip(WALL, speeds)
    }
    return {"phases": phases, "rate_hz": rate}


def silent_wall(rate=0.0):
    return {"phases": {name: {"count": 0} for name in WALL}, "rate_hz": rate}


def sides(**commands):
    """Phase summaries for Assignment 8: name -> (linear.x, angular.z)."""
    good = {
        "clear": (0.2, 0.0), "clear-sides-differ": (0.2, 0.0),
        "left-open": (0.0, 0.5), "right-open": (0.0, -0.5), "threshold": (0.0, -0.5),
        "sides-equal": (0.0, -0.5), "front-unknown": (0.0, 0.5),
        "side-unknown": (0.0, 0.5), "resume": (0.2, 0.0),
    }
    good.update(commands)
    return {
        "phases": {
            name: {"count": 9, "linear_min": good[name][0], "linear_max": good[name][0],
                   "angular_min": good[name][1], "angular_max": good[name][1]}
            for name in SIDES
        },
        "rate_hz": 11.0, "started": True, "subscribed": True, "alive": True,
    }


def failing(ids, *names):
    return {test_id: test_id not in names for test_id in ids}


def keys(findings):
    return {test_id: finding.hint_key for test_id, finding in findings.items()}


# Real QA patterns: (harness, failed checks, observations).
NEVER_MOVING = ("wall_stop_open", failing(
    A7_IDS, "drive-open-floor", "drive-wall-far", "stop-wall-0-3", "stop-wall-0-2",
    "stay-stopped", "resume-motion", "straight-motion"), wall(0, 0, 0, 0, 0, 0))
STOP_DISTANCE_1_5 = ("wall_stop_open", failing(A7_IDS, "drive-wall-far", "resume-motion"),
                     wall(0.2, 0, 0, 0, 0, 0))
STOP_EXACTLY_0_3 = ("wall_stop_open", failing(A7_IDS, "stop-wall-0-3"),
                    wall(0.2, 0.2, 0.2, 0, 0, 0.2))
REVERSED = ("wall_stop_open", failing(
    A7_IDS, "drive-open-floor", "drive-wall-far", "stop-wall-0-3", "stop-wall-0-2",
    "stay-stopped", "resume-motion", "straight-motion"), wall(0, 0, 0.2, 0.2, 0.2, 0))
NEVER_STOPS = ("wall_stop_open", failing(
    A7_IDS, "stop-wall-0-3", "stop-wall-0-2", "stay-stopped"), wall(0.2, 0.2, 0.2, 0.2, 0.2, 0.2))
LATCHED = ("wall_stop_open", failing(A7_IDS, "resume-motion"), wall(0.2, 0.2, 0, 0, 0, 0))
TURNS = ("wall_stop_open", failing(A7_IDS, "straight-motion"),
         wall(0.2, 0.2, 0, 0, 0, 0.2, turn=0.3))
FAST = ("wall_stop_open", failing(A7_IDS, "drive-open-floor", "drive-wall-far", "resume-motion"),
        wall(0.5, 0.5, 0, 0, 0, 0.5))
INF_OBSTACLE = ("wall_stop_open", failing(A7_IDS, "drive-open-floor"), wall(0, 0.2, 0, 0, 0, 0.2))
CRASH = ("wall_stop_open", failing(
    A7_IDS, "node-start", "returns-node", "drive-open-floor", "drive-wall-far",
    "stop-wall-0-3", "stop-wall-0-2", "stay-stopped", "resume-motion", "straight-motion",
    "publish-rate", "cmd-vel-publisher", "scan-subscription"), silent_wall())
PUBLISH_ON_CHANGE = ("wall_stop_open", failing(
    A7_IDS, "drive-open-floor", "drive-wall-far", "stop-wall-0-3", "stop-wall-0-2",
    "stay-stopped", "resume-motion", "straight-motion", "publish-rate"), silent_wall(0.33))
SLEEPY = ("wall_stop_open", failing(A7_IDS, "stop-wall-0-3", "resume-motion", "publish-rate"),
          wall(0.2, 0.2, 0.2, 0, 0, 0, rate=2.0, count=2))
A8_REVERSED = ("open_side", failing(
    A8_IDS, "clear-path-forward", "stop-when-blocked", "turn-toward-open-side",
    "stop-at-threshold", "equal-sides-turn-right", "unknown-distance-safe", "resume-forward"),
    sides(**{"clear": (0.0, -0.5), "clear-sides-differ": (0.0, 0.5),
             "left-open": (0.2, 0.0), "right-open": (0.2, 0.0), "threshold": (0.2, 0.0),
             "sides-equal": (0.2, 0.0), "front-unknown": (0.2, 0.0),
             "side-unknown": (0.2, 0.0), "resume": (0.0, -0.5)}))
A8_NEVER_STOPS = ("open_side", failing(
    A8_IDS, "stop-when-blocked", "turn-toward-open-side", "stop-at-threshold",
    "equal-sides-turn-right", "unknown-distance-safe"),
    sides(**{name: (0.2, 0.0) for name in SIDES}))
A8_SILENT = ("open_side", failing(A8_IDS, "turn-toward-open-side", "clear-path-forward",
                                  "stop-when-blocked", "stop-at-threshold",
                                  "equal-sides-turn-right", "unknown-distance-safe",
                                  "resume-forward"),
             sides(**{name: (0.0, 0.0) for name in SIDES}))
A8_PATTERNS = [
    A8_REVERSED, A8_NEVER_STOPS, A8_SILENT,
    ("open_side", failing(A8_IDS, "turn-toward-open-side"),
     sides(**{"left-open": (0.0, -0.5), "right-open": (0.0, 0.5)})),
    ("open_side", failing(A8_IDS, "turn-toward-open-side"),
     sides(**{"left-open": (0.0, 0.0), "right-open": (0.0, 0.0)})),
    ("open_side", failing(A8_IDS, "turn-toward-open-side"),
     sides(**{"left-open": (0.0, -0.5), "right-open": (0.0, -0.5)})),
    ("open_side", failing(A8_IDS, "clear-path-forward"), sides(clear=(0.2, -0.5))),
    ("open_side", failing(A8_IDS, "stop-at-threshold"), sides(threshold=(0.2, 0.0))),
    ("open_side", failing(A8_IDS, "resume-forward"), sides(resume=(0.0, -0.5))),
    ("open_side", failing(A8_IDS, "equal-sides-turn-right"), sides(**{"sides-equal": (0.0, 0.5)})),
    ("open_side", failing(A8_IDS, "unknown-distance-safe"), sides(**{"side-unknown": (0.0, -0.5)})),
    ("open_side", failing(A8_IDS, "node-start", "flbr-response", "cmd-vel-topic"),
     {"phases": {name: {"count": 0} for name in SIDES}, "subscribed": False, "alive": True}),
    ("open_side", failing(A8_IDS, "node-start", "flbr-response", "cmd-vel-topic"),
     {"phases": {name: {"count": 0} for name in SIDES}, "subscribed": True, "alive": True}),
]
ALL_PATTERNS = [
    NEVER_MOVING, STOP_DISTANCE_1_5, STOP_EXACTLY_0_3, REVERSED, NEVER_STOPS, LATCHED,
    TURNS, FAST, INF_OBSTACLE, CRASH, PUBLISH_ON_CHANGE, SLEEPY, *A8_PATTERNS,
]
# Phrases of advice that the owner moved out of check messages into hints.
ADVICE = re.compile(
    r"\b(?:should|must|make it|so first|first make|keep (?:driving|it|angular)|"
    r"publish one|choose|complete TODO|decide from|return quickly|set angular|"
    r"drive only|treat|counts as|the rule|swapped|reversed|positive angular)\b",
    re.IGNORECASE,
)


@pytest.mark.parametrize("pattern", ALL_PATTERNS)
def test_observations_say_only_what_the_robot_did(pattern):
    harness, passed, observations = pattern
    for finding in classify(harness, passed, observations).values():
        assert not ADVICE.search(finding.observation), finding.observation
        assert finding.hint_key in HINT_LADDERS


def test_never_moving_node_is_not_diagnosed_as_stopping_early_or_not_resuming():
    findings = classify(*NEVER_MOVING)
    assert set(keys(findings).values()) == {"never-drives"}
    assert "never drove" in findings["drive-open-floor"].observation


def test_stop_distance_above_one_metre_is_not_called_does_not_resume():
    assert keys(classify(*STOP_DISTANCE_1_5)) == {
        "drive-wall-far": "stops-too-early", "resume-motion": "stops-too-early",
    }


def test_latched_stop_is_does_not_resume():
    assert keys(classify(*LATCHED)) == {"resume-motion": "does-not-resume"}


def test_stopping_at_0_2_but_not_0_3_names_the_boundary():
    findings = classify(*STOP_EXACTLY_0_3)
    assert keys(findings) == {"stop-wall-0-3": "stop-distance-at-boundary"}
    assert "stopped with the wall 0.2 m away" in findings["stop-wall-0-3"].observation
    ladder = " ".join(HINT_LADDERS["stop-distance-at-boundary"].levels)
    assert "float32" in ladder and "above 0.3 m" in ladder


@pytest.mark.parametrize("pattern", [CRASH, PUBLISH_ON_CHANGE])
def test_no_behaviour_is_described_when_no_command_was_seen(pattern):
    found = keys(classify(*pattern))
    assert "must-drive-first" not in found.values()
    assert "never-drives" not in found.values()
    if pattern is CRASH:
        # Nothing at all was published: the error and gate checks explain it.
        assert found == {}
    else:
        assert set(found.values()) == {"publishes-too-rarely"}


def test_a_slow_node_is_explained_by_its_rate_not_by_its_stop_rule():
    found = keys(classify(*SLEEPY))
    assert found == dict.fromkeys(
        ["stop-wall-0-3", "resume-motion", "publish-rate"], "publishes-too-rarely"
    )


def test_ignoring_the_scan_is_named_and_starters_are_not_tagged():
    passed = failing(A7_IDS, "reads-ranges", "stop-wall-0-3", "stop-wall-0-2", "stay-stopped")
    findings = classify("wall_stop_open", passed, wall(0.2, 0.2, 0.2, 0.2, 0.2, 0.2))
    assert keys(findings) == dict.fromkeys(
        ["reads-ranges", "stop-wall-0-3", "stop-wall-0-2", "stay-stopped"], "sensor-ignored"
    )
    starter = classify("wall_stop_open", failing(A7_IDS, "reads-ranges"), silent_wall())
    assert starter == {}


def test_reversed_front_check_gets_its_configured_tag_first():
    found = keys(classify(*A8_REVERSED))
    assert set(found.values()) == {"front-check-reversed"}
    assert set(found) == {test_id for test_id, ok in A8_REVERSED[1].items() if not ok}


def test_driving_into_a_blocked_front_is_not_called_no_turn():
    found = keys(classify(*A8_NEVER_STOPS))
    assert "no-turn-when-blocked" not in found.values()
    assert found["turn-toward-open-side"] == "drives-when-blocked"


def test_a_node_that_publishes_only_zeros_never_moves():
    assert set(keys(classify(*A8_SILENT)).values()) == {"never-moves"}


# Ladders -----------------------------------------------------------------

def test_wall_stop_hints_follow_the_published_stop_distance_rule():
    text = " ".join(
        " ".join((ladder.diagnosis, ladder.guiding_question, *ladder.levels, ladder.next_action))
        for ladder in HINT_LADDERS.values()
    )
    for wrong in ("at least 0.3 m", "0.3 m to 1.0 m", "between 0.3 and 1.0", "0.3 to 1.0 m"):
        assert wrong not in text
    assert "above 0.3 m" in " ".join(HINT_LADDERS["stops-too-early"].levels)


def test_reading_index_is_not_the_first_cause_for_late_stops():
    early = " ".join(HINT_LADDERS["stops-too-late"].levels[:2])
    assert "index" not in early and "ranges[" not in early


@pytest.mark.parametrize("key", sorted(HINT_LADDERS))
def test_level_four_names_the_change_without_a_code_expression(key):
    level_four = HINT_LADDERS[key].levels[3]
    assert not re.search(r"[<>]=?|==|\bself\.\w|\w\.\w+\s*=|=\s*[+-]?\d", level_four), level_four


def test_every_configured_misconception_has_a_ladder():
    for source in (A7, A8):
        for item in source["common_misconceptions"]:
            assert item["tag"] in HINT_LADDERS


# Grader integration ------------------------------------------------------

class RecordedExecutor:
    def __init__(self, source, passed, observations, messages=None, not_run=()):
        self.source, self.passed, self.obs = source, passed, observations
        self.messages, self.not_run = messages or {}, set(not_run)

    def execute(self, code, project_files, config):
        tests = []
        for item in self.source["public_tests"]:
            entry = {
                "id": item["id"], "passed": self.passed.get(item["id"], True),
                "message": self.messages.get(item["id"], f"Rule for {item['id']}."),
            }
            if item["id"] in self.not_run:
                entry["status"] = "not_run"
            tests.append(entry)
        return {"success": True, "error": "", "output": "", "tests": tests,
                "observations": self.obs}


def assignment(source) -> Assignment:
    return Assignment(
        id=source["id"], stable_id=source["stable_id"], version=source["version"],
        title=source["title"], public_tests=source["public_tests"],
        asset_manifest=source["asset_manifest"],
        misconceptions=source["common_misconceptions"], language="python-ros2",
        grader_type="ros2_topic", grader_config=source["grader_config"],
    )


def grade(source, passed, observations, **kwargs):
    executor = RecordedExecutor(source, passed, observations, **kwargs)
    result = Ros2TopicGrader(executor).grade(assignment(source), "code")
    return {item.test_id: item for item in result.evidence}


def test_configured_code_check_tags_reach_the_evidence():
    passed = failing(A7_IDS, "reads-ranges", "main-unchanged", "stop-wall-0-3")
    evidence = grade(A7, passed, wall(0.2, 0.2, 0.2, 0, 0, 0.2))
    assert evidence["reads-ranges"].misconception_tag == "sensor-ignored"
    assert evidence["main-unchanged"].misconception_tag == "main-modified"
    assert evidence["stop-wall-0-3"].misconception_tag == "sensor-ignored"


def test_never_moving_node_gets_no_research_tag():
    _, passed, observations = NEVER_MOVING
    evidence = grade(A7, passed, observations)
    assert {item.misconception_tag for item in evidence.values()} == {None}
    assert evidence["drive-wall-far"].hint_key == "never-drives"


def test_checks_marked_not_run_get_no_finding():
    _, passed, observations = NEVER_MOVING
    evidence = grade(A7, passed, observations, not_run={"drive-open-floor"})
    assert evidence["drive-open-floor"].hint_key is None
    assert evidence["drive-open-floor"].message == "Rule for drive-open-floor."


def test_findings_never_repeat_the_harness_message():
    harness = {
        "drive-wall-far": "Keep driving while the wall is more than 1.0 m away. "
                          "Your robot published linear.x 0.00 m/s with the wall 1.2 m away.",
        "publish-rate": "Published about 2.0 commands per second; publish at least 5 per second.",
    }
    passed = failing(A7_IDS, "drive-wall-far", "resume-motion", "publish-rate")
    evidence = grade(A7, passed, wall(0.2, 0, 0, 0, 0, 0, rate=2.0), messages=harness)
    for test_id, message in harness.items():
        assert evidence[test_id].message == message


def test_messages_are_the_same_for_every_mode():
    """Findings are added by the grader once, before any mode shapes a response."""
    from feedback_modes import shape_submission_response

    _, passed, observations = STOP_DISTANCE_1_5
    evidence = [item.model_dump() for item in grade(A7, passed, observations).values()]
    payload = {"evidence": evidence, "unittest_results": [item["message"] for item in evidence],
               "unittest_pass_results": [item["passed"] for item in evidence], "hint": "h"}
    tdd = shape_submission_response(payload, "tdd")
    ai = shape_submission_response(payload, "tdd_ai")
    assert tdd["unittest_results"] == ai["unittest_results"]
    assert tdd["evidence"] == ai["evidence"]
    assert tdd["hint"] == "" and ai["hint"] == "h"


# Built-in tutor fallback -------------------------------------------------

def submission(tests, *, succeeded=True, status="completed"):
    return SimpleNamespace(code="", evidence={
        "execution_succeeded": succeeded, "execution_status": status, "tests": tests,
    })


def check(test_id, hint_key=None, label=None, message="Rule."):
    return {"test_id": test_id, "label": label or test_id, "passed": False,
            "message": message, "hint_key": hint_key,
            "misconception_tag": hint_key if hint_key == "stops-too-early" else None}


@pytest.mark.parametrize(("status", "phrase"), [
    ("runtime_error", "stopped with an error"),
    ("syntax_error", "syntax error"),
    ("rejected", "rules do not allow"),
    ("timeout", "did not finish in time"),
])
def test_failed_execution_leads_with_the_error_not_a_behaviour_ladder(status, phrase):
    tests = [check("node-start"), check("stop-wall-0-3", "must-drive-first"),
             check("drive-wall-far", "stops-too-early")]
    for level in (1, 2, 3, 4):
        feedback = TutorService._fallback(
            assignment(A7), submission(tests, succeeded=False, status=status), level
        )
        assert phrase in feedback.diagnosis.lower()
        assert feedback.hint not in {
            text for ladder in HINT_LADDERS.values() for text in ladder.levels
        }
        assert feedback.misconception == ""
        assert "calculations" not in feedback.diagnosis


def test_build_node_returning_none_keeps_its_ladder_after_a_failed_run():
    tests = [check("returns-node", "build-node-returns-none")]
    feedback = TutorService._fallback(
        assignment(A7), submission(tests, succeeded=False, status="runtime_error"), 2
    )
    assert feedback.hint == HINT_LADDERS["build-node-returns-none"].levels[1]


def test_blocking_code_and_a_silent_start_lead_the_hints():
    blocking = TutorService._fallback(
        assignment(A7), submission([check("no-blocking"), check("drive-wall-far", "stops-too-early")]), 1
    )
    assert "blocking loop or sleep()" in blocking.diagnosis
    not_started = TutorService._fallback(
        assignment(A7), submission([check("node-start"), check("drive-wall-far", "stops-too-early")]), 1
    )
    assert "did not start publishing" in not_started.diagnosis
    wired = TutorService._fallback(
        assignment(A8), submission([check("node-start", "not-wired")]), 1
    )
    assert wired.hint == HINT_LADDERS["not-wired"].levels[0]


def test_behaviour_diagnosis_without_a_ladder_reads_naturally():
    feedback = TutorService._fallback(
        assignment(A7),
        submission([check("resume-motion", label="Drives again when the wall moves away")]),
        1,
    )
    assert feedback.diagnosis == (
        'Your node ran, but the check "Drives again when the wall moves away" did not pass.'
    )


def test_the_ai_sees_the_student_facing_assignment_number():
    from config import Settings

    captured = {}

    class FakeResponses:
        @staticmethod
        def create(**kwargs):
            captured.update(kwargs)
            raise RuntimeError("no provider in tests")

    client = SimpleNamespace(responses=FakeResponses())
    item = assignment(A7)
    item.description, item.assignment_html = A7["description"], A7["assignment_html"]
    TutorService(Settings(openai_api_key="test-key"), client=client).feedback(
        item, submission([check("drive-wall-far", "stops-too-early")]), hint_level=1,
    )
    payload = json.loads(captured["input"])
    assert payload["assignment"]["display_name"] == "Assignment 1"
    assert payload["assignment"]["title"].startswith("Assignment 1:")
    assert "Assignment 7" not in captured["input"]
    assert "assignment.display_name" in captured["instructions"]


def test_fixed_open_side_threshold_is_enforced_for_assignment_8():
    from schemas import TutorGeneratedContent

    content = TutorGeneratedContent(
        diagnosis="The robot stops late.", misconception="", answer="",
        debugging_steps=["Look at the comparison."],
        guiding_question="Which distance stops it?", next_action="Rerun the tests.",
        hint="Adjust the stop distance to 0.75 m or higher.",
    )
    item = assignment(A8)
    item.assignment_html = A8["assignment_html"]
    with pytest.raises(ValueError):
        TutorService._enforce_assignment_scope(content, item)
