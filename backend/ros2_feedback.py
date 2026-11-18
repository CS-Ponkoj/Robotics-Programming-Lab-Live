"""Evidence-based feedback for ROS 2 behavior checks.

The grader harness reports what the student's node published in each scenario
phase. This module turns those observations into a short, factual sentence
for each failed check and a hint key that selects a targeted hint ladder.

Only the student's own output is described. Nothing here reveals hidden tests,
expected values beyond the published rules, or a solution.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable

# The published Assignment 7 rules (instructions and test labels).
FORWARD_MIN = 0.1
FORWARD_MAX = 0.3
STOP_TOLERANCE = 0.001
ANGULAR_TOLERANCE = 0.001
MINIMUM_RATE_HZ = 5.0


@dataclass(frozen=True)
class Finding:
    """One observed cause for a failed check."""

    hint_key: str
    observation: str


@dataclass(frozen=True)
class HintLadder:
    diagnosis: str
    guiding_question: str
    levels: tuple[str, str, str, str]
    next_action: str


def _phase(observations: dict, name: str) -> dict:
    phases = observations.get("phases") if isinstance(observations, dict) else None
    value = phases.get(name) if isinstance(phases, dict) else None
    return value if isinstance(value, dict) else {}


def _number(phase: dict, key: str) -> float | None:
    value = phase.get(key)
    return float(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def _drives(phase: dict) -> bool:
    low, high = _number(phase, "linear_min"), _number(phase, "linear_max")
    return low is not None and high is not None and low > STOP_TOLERANCE


def _stopped(phase: dict) -> bool:
    low, high = _number(phase, "linear_min"), _number(phase, "linear_max")
    return (
        low is not None and high is not None
        and abs(low) <= STOP_TOLERANCE and abs(high) <= STOP_TOLERANCE
    )


def _speed_finding(phase: dict, where: str) -> Finding | None:
    high = _number(phase, "linear_max")
    low = _number(phase, "linear_min")
    if high is None or low is None:
        return None
    if high > FORWARD_MAX + 1e-9:
        return Finding(
            "speed-too-high",
            f"Your robot published linear.x up to {high:.2f} m/s {where}; "
            f"forward speed must stay between {FORWARD_MIN} and {FORWARD_MAX} m/s.",
        )
    if STOP_TOLERANCE < low < FORWARD_MIN - 1e-9:
        return Finding(
            "speed-too-low",
            f"Your robot published linear.x as low as {low:.2f} m/s {where}; "
            f"forward speed must be at least {FORWARD_MIN} m/s.",
        )
    return None


def wall_stop_findings(passed: dict[str, bool], observations: dict) -> dict[str, Finding]:
    """Findings for the open-structure wall-stop harness (Assignment 7)."""
    findings: dict[str, Finding] = {}
    open_, far = _phase(observations, "open"), _phase(observations, "far")
    near, close = _phase(observations, "near"), _phase(observations, "close")
    hold, resume = _phase(observations, "hold"), _phase(observations, "resume")
    clear_phases_stopped = _stopped(open_) and _stopped(far)
    close_phases_driving = _drives(near) or _drives(close)

    if clear_phases_stopped and close_phases_driving:
        reversed_rule = Finding(
            "wrong-threshold-direction",
            "Your robot stopped while the way was clear and drove while the wall "
            "was close: the drive and stop branches are swapped.",
        )
        for test_id in ("drive-open-floor", "drive-wall-far", "stop-wall-0-3", "stop-wall-0-2"):
            findings[test_id] = reversed_rule
    else:
        if not passed.get("drive-open-floor", True):
            findings_open = _speed_finding(open_, "with nothing in range")
            if findings_open is None and _stopped(open_) and _drives(far):
                findings_open = Finding(
                    "infinity-treated-as-obstacle",
                    "Your robot stayed stopped while every reading was +inf, but "
                    "drove with the wall 1.2 m away: +inf means nothing is in range.",
                )
            if findings_open:
                findings["drive-open-floor"] = findings_open
        if not passed.get("drive-wall-far", True):
            found = _speed_finding(far, "with the wall 1.2 m away")
            if found is None and _stopped(far):
                found = Finding(
                    "stops-too-early",
                    "Your robot stopped with the wall still 1.2 m away; keep driving "
                    "while the wall is more than 1.0 m away.",
                )
            if found:
                findings["drive-wall-far"] = found
        for test_id, phase, distance in (
            ("stop-wall-0-3", near, "0.3"),
            ("stop-wall-0-2", close, "0.2"),
            ("stay-stopped", hold, "0.2"),
        ):
            if passed.get(test_id, True):
                continue
            if not (_drives(open_) or _drives(far)):
                findings[test_id] = Finding(
                    "must-drive-first",
                    "Stopping only counts once your robot also drives when the way "
                    "is clear; first make it drive in the open.",
                )
            elif _drives(phase) or (_number(phase, "linear_max") or 0) > STOP_TOLERANCE:
                speed = _number(phase, "linear_max") or 0.0
                findings[test_id] = Finding(
                    "stops-too-late",
                    f"Your robot still published linear.x {speed:.2f} m/s with the "
                    f"wall {distance} m away.",
                )
    if not passed.get("resume-motion", True):
        found = _speed_finding(resume, "after the wall moved away")
        if found is None and _stopped(hold) and _stopped(resume):
            found = Finding(
                "does-not-resume",
                "Your robot stopped for the close wall but stayed stopped after the "
                "wall moved back to 1.2 m.",
            )
        if found:
            findings["resume-motion"] = found
    if not passed.get("straight-motion", True):
        turn = max(
            (_number(_phase(observations, name), "angular_max_abs") or 0.0)
            for name in ("open", "far", "near", "close", "hold", "resume")
        )
        if turn > ANGULAR_TOLERANCE:
            findings["straight-motion"] = Finding(
                "turns-while-driving",
                f"Your robot published angular.z up to {turn:.2f} rad/s; keep it at 0.0.",
            )
    if not passed.get("publish-rate", True):
        rate = observations.get("rate_hz") if isinstance(observations, dict) else None
        if isinstance(rate, (int, float)):
            findings["publish-rate"] = Finding(
                "publishes-too-rarely",
                f"Your robot published about {rate:.1f} commands per second; publish "
                f"one command for every scan (scans arrive about 12 times a second).",
            )
    return findings


_CLASSIFIERS: dict[str, Callable[[dict[str, bool], dict], dict[str, Finding]]] = {
    "wall_stop_open": wall_stop_findings,
}


def classify(harness: str, passed: dict[str, bool], observations: Any) -> dict[str, Finding]:
    """Findings for failed checks, or none for harnesses without a classifier."""
    classifier = _CLASSIFIERS.get(harness)
    if classifier is None or not isinstance(observations, dict):
        return {}
    return classifier(passed, observations)


HINT_LADDERS: dict[str, HintLadder] = {
    "build-node-returns-none": HintLadder(
        "build_node() does not hand a node back to main(), so there is nothing to run.",
        "What value does build_node() return on its last line?",
        (
            "Look at the last line of build_node(): what does it return?",
            "main() passes whatever build_node() returns to rclpy.spin(); it must be your node.",
            "Create the node, its publisher, and its subscription inside build_node(), then return that node.",
            "Return the node object you created; keep main() unchanged.",
        ),
        "Return your node from build_node() and run the tests again.",
    ),
    "speed-too-high": HintLadder(
        "Your robot drives faster than the rules allow.",
        "Where in your code is the forward speed set, and what value does it have?",
        (
            "Compare the speed your robot published with the allowed 0.1 to 0.3 m/s.",
            "Find every place that sets command.linear.x, including constants at the top of the file.",
            "Use one named forward-speed constant inside the allowed range for every drive command.",
            "Set the forward speed once, inside 0.1 to 0.3 m/s, and publish it whenever the way is clear.",
        ),
        "Change the forward speed, rerun the tests, and check the drive checks.",
    ),
    "speed-too-low": HintLadder(
        "Your robot drives, but slower than the minimum forward speed.",
        "Which value does your node publish as linear.x when the way is clear?",
        (
            "Compare the speed your robot published with the minimum of 0.1 m/s.",
            "Check the constant or expression that sets linear.x for driving.",
            "Make sure the drive branch publishes a constant speed, not one that shrinks with distance.",
            "Publish a fixed forward speed between 0.1 and 0.3 m/s whenever the way is clear.",
        ),
        "Raise the forward speed into the allowed range and rerun the tests.",
    ),
    "infinity-treated-as-obstacle": HintLadder(
        "Your robot treats +inf readings as an obstacle, so it never moves in open space.",
        "What does a reading of +inf mean in a ROS LaserScan?",
        (
            "With nothing in range every reading is +inf. Does your node drive in that case?",
            "In ROS (REP 117), +inf means nothing was detected within range: the way is clear.",
            "Check how your code handles math.inf; filtering it out may leave no readings, or a comparison may treat it as invalid.",
            "Treat +inf as a very large distance: greater than your stop distance, so the robot drives.",
        ),
        "Handle +inf as clear, rerun the tests, and watch the open-floor check.",
    ),
    "stops-too-early": HintLadder(
        "Your robot stops while the wall is still far away.",
        "Which distance makes your robot decide to stop?",
        (
            "With the wall 1.2 m away the robot should still drive. What does your stop distance compare against?",
            "Check your STOP_DISTANCE value: the rules allow 0.3 m to 1.0 m.",
            "Print the reading you compare and the stop distance for one scan to see which branch runs.",
            "Choose a stop distance between 0.3 and 1.0 m and drive whenever the reading is greater than it.",
        ),
        "Adjust the stop distance into the allowed range and rerun the tests.",
    ),
    "stops-too-late": HintLadder(
        "Your robot keeps driving when the wall is already close.",
        "Which reading does your node compare with the stop distance, and does it point straight ahead?",
        (
            "With the wall 0.3 m ahead the robot must be stopped. Which reading does your code use?",
            "The reading straight ahead is scan.ranges[len(scan.ranges) // 2]; check the index you use.",
            "Watch the LiDAR view in Simulate: the highlighted beams are the ones your node reacts to.",
            "Compare the reading straight ahead with a stop distance of at least 0.3 m and publish 0.0 when it is not greater.",
        ),
        "Check the index and the stop distance, then rerun the tests.",
    ),
    "wrong-threshold-direction": HintLadder(
        "The drive and stop branches are swapped: the robot stops when clear and drives when close.",
        "When the reading is larger than your stop distance, should the robot drive or stop?",
        (
            "Your robot did the opposite of the rule in both directions. Look at the comparison.",
            "A large reading means the wall is far away, so the robot should drive.",
            "Read your if-condition aloud with a reading of 1.2 m and a stop distance of 0.5 m.",
            "Drive when the reading is greater than the stop distance; otherwise publish 0.0.",
        ),
        "Fix the comparison direction and rerun the tests.",
    ),
    "must-drive-first": HintLadder(
        "Stopping cannot be confirmed yet because the robot never drives when the way is clear.",
        "What makes your robot move forward?",
        (
            "First make the robot drive with nothing in range; the stop checks depend on it.",
            "Check that the clear-path branch publishes a forward speed.",
            "Use Simulate to see whether the robot moves at all.",
            "Publish a forward speed between 0.1 and 0.3 m/s whenever the reading ahead is clear.",
        ),
        "Make the robot drive in the open, then rerun the tests.",
    ),
    "does-not-resume": HintLadder(
        "Your robot stops correctly but never drives again after the wall moves away.",
        "Does your node decide from each new scan, or does it remember that it stopped?",
        (
            "After the wall moves back to 1.2 m, the robot should drive again. Does anything keep it stopped?",
            "Look for a flag or saved state that is set when the robot stops and never cleared.",
            "Decide drive or stop from the current scan only, every time a scan arrives.",
            "Remove the stopped state; publish drive or stop from each scan's reading.",
        ),
        "Decide from every scan and rerun the tests.",
    ),
    "turns-while-driving": HintLadder(
        "Your robot turns although the task is to drive straight.",
        "Where does your node set angular.z?",
        (
            "Every command must keep angular.z at 0.0.",
            "Check every place a Twist is created or changed; a new Twist starts at 0.0.",
            "Remove any code that sets angular.z.",
            "Leave angular.z at 0.0 in every command you publish.",
        ),
        "Keep angular.z at 0.0 and rerun the tests.",
    ),
    "publishes-too-rarely": HintLadder(
        "Your robot does not publish a command often enough.",
        "When does your node publish: on every scan, on a timer, or only when something changes?",
        (
            "The rule is at least 5 commands per second; one per scan is enough.",
            "Publish from the scan callback so every scan gets a command.",
            "If you publish only when the decision changes, publish every time instead.",
            "Publish exactly one Twist at the end of every scan callback.",
        ),
        "Publish once per scan and rerun the tests.",
    ),
}
