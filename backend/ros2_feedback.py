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


def _turn(phase: dict) -> float | None:
    """The single turn direction published in a phase: +1, -1, 0, or None if mixed."""
    low, high = _number(phase, "angular_min"), _number(phase, "angular_max")
    if low is None or high is None:
        return None
    if low > 0.25 and high > 0.25:
        return 1.0
    if low < -0.25 and high < -0.25:
        return -1.0
    if abs(low) <= STOP_TOLERANCE and abs(high) <= STOP_TOLERANCE:
        return 0.0
    return None


def open_side_findings(passed: dict[str, bool], observations: dict) -> dict[str, Finding]:
    """Findings for the turn-toward-the-open-side harness (Assignment 8)."""
    findings: dict[str, Finding] = {}
    clear = _phase(observations, "clear")
    differ = _phase(observations, "clear-sides-differ")
    left_open = _phase(observations, "left-open")
    right_open = _phase(observations, "right-open")
    threshold = _phase(observations, "threshold")
    sides_equal = _phase(observations, "sides-equal")
    side_unknown = _phase(observations, "side-unknown")
    resume = _phase(observations, "resume")

    if not passed.get("clear-path-forward", True):
        if _turn(clear) not in (None, 0.0) or _turn(differ) not in (None, 0.0):
            findings["clear-path-forward"] = Finding(
                "turns-while-clear",
                "Your robot turned while the front was clear; with the front clear, "
                "keep angular.z at 0.0 and drive straight.",
            )
        elif _drives(clear) and not (0.18 <= (_number(clear, "linear_max") or 0.0) <= 0.22):
            findings["clear-path-forward"] = Finding(
                "forward-speed-wrong",
                f"Your robot drove at linear.x = {_number(clear, 'linear_max'):.2f} m/s "
                "with the front clear; the rule is 0.20 m/s.",
            )
        elif _stopped(clear) and _drives(left_open):
            findings["clear-path-forward"] = Finding(
                "front-check-reversed",
                "Your robot stopped when the front was 2.0 m away and drove when it "
                "was 0.5 m away: the front comparison is reversed.",
            )
    if not passed.get("turn-toward-open-side", True):
        left_turn, right_turn = _turn(left_open), _turn(right_open)
        if left_turn == -1.0 and right_turn == 1.0:
            findings["turn-toward-open-side"] = Finding(
                "turn-direction-swapped",
                "Your robot turned right when the left had more space and left when the "
                "right had more space: positive angular.z turns left.",
            )
        elif left_turn == 0.0 and right_turn == 0.0:
            findings["turn-toward-open-side"] = Finding(
                "no-turn-when-blocked",
                "Your robot did not turn when the front was blocked; set angular.z to "
                "+0.5 or -0.5 toward the side with more space.",
            )
    if not passed.get("stop-at-threshold", True) and _drives(threshold):
        findings["stop-at-threshold"] = Finding(
            "threshold-boundary",
            "Your robot drove with the front exactly 0.75 m away; 0.75 m counts as "
            "blocked, so drive only when the front is greater than 0.75 m.",
        )
    if not passed.get("equal-sides-turn-right", True) and _turn(sides_equal) == 1.0:
        findings["equal-sides-turn-right"] = Finding(
            "tie-goes-left",
            "Your robot turned left when left and right were equal; left is not "
            "greater, so the rule turns right.",
        )
    if not passed.get("unknown-distance-safe", True) and _turn(side_unknown) == -1.0:
        findings["unknown-distance-safe"] = Finding(
            "nan-side-chosen",
            "Your robot turned right, toward a side whose distance was NaN (unknown); "
            "treat NaN as no space so the robot turns toward the known open side.",
        )
    if (
        not passed.get("resume-forward", True)
        and _stopped(resume)
        and _drives(clear)
    ):
        findings["resume-forward"] = Finding(
            "open-side-no-resume",
            "Your robot stayed stopped after the front cleared again; decide from "
            "every /flbr message instead of remembering that it stopped.",
        )
    return findings


_CLASSIFIERS: dict[str, Callable[[dict[str, bool], dict], dict[str, Finding]]] = {
    "wall_stop_open": wall_stop_findings,
    "open_side": open_side_findings,
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
    "turns-while-clear": HintLadder(
        "Your robot turns even though the front is clear.",
        "When the front distance is greater than 0.75 m, which value should angular.z have?",
        (
            "With the front clear the robot drives straight. Which branch sets angular.z?",
            "Turning belongs only to the blocked case; the clear case keeps angular.z at 0.0.",
            "Use one if/else on the front distance: the drive branch sets only linear.x.",
            "When the front is greater than 0.75 m, publish linear.x = 0.20 and leave angular.z at 0.0.",
        ),
        "Make the clear branch drive straight and rerun the tests.",
    ),
    "forward-speed-wrong": HintLadder(
        "Your robot drives with the front clear, but not at the required speed.",
        "Which value does your node publish as linear.x when the front is clear?",
        (
            "Compare the speed you published with the rule: 0.20 m/s.",
            "Check the forward-speed attribute set in __init__ and where you use it.",
            "Use self.forward_speed for linear.x instead of a different number.",
            "Publish linear.x = self.forward_speed (0.20 m/s) whenever the front is clear.",
        ),
        "Use the given forward speed and rerun the tests.",
    ),
    "front-check-reversed": HintLadder(
        "The front comparison is reversed: the robot stops when clear and drives when blocked.",
        "If the front distance is larger than 0.75 m, is the way ahead clear or blocked?",
        (
            "Your robot did the opposite of the rule. Look at the comparison with the stop distance.",
            "A large front distance means the obstacle is far away, so the robot should drive.",
            "Read your if-condition aloud with a front of 2.0 m and a stop distance of 0.75 m.",
            "Drive when front > self.stop_distance; otherwise stop and turn.",
        ),
        "Fix the comparison direction and rerun the tests.",
    ),
    "turn-direction-swapped": HintLadder(
        "Your robot turns toward the side with less space.",
        "Which sign of angular.z turns a ROS robot to the left?",
        (
            "Compare the turn you published with the side that had more space.",
            "In ROS, positive angular.z turns left (counter-clockwise) and negative turns right.",
            "Check which side your comparison picks and which sign you then publish.",
            "When left is greater than right, publish angular.z = +0.5; otherwise publish -0.5.",
        ),
        "Fix the turn sign and rerun the tests.",
    ),
    "no-turn-when-blocked": HintLadder(
        "Your robot stops for a blocked front but does not turn, so it stays stuck.",
        "After stopping, how does the robot find a new way forward?",
        (
            "With the front blocked, the robot must turn on the spot toward more space.",
            "Set angular.z in the blocked branch, as well as linear.x = 0.0.",
            "Compare msg.left with msg.right to choose the direction.",
            "In the blocked branch publish linear.x = 0.0 and angular.z = +0.5 or -0.5 toward the larger side.",
        ),
        "Add the turn to the blocked branch and rerun the tests.",
    ),
    "threshold-boundary": HintLadder(
        "Your robot treats a front distance of exactly 0.75 m as clear.",
        "Is 0.75 greater than 0.75?",
        (
            "The rule drives only when the front is greater than 0.75 m.",
            "Check whether your comparison is > or >=.",
            "At exactly 0.75 m the robot must stop and turn.",
            "Use front > self.stop_distance for the drive branch.",
        ),
        "Fix the boundary comparison and rerun the tests.",
    ),
    "tie-goes-left": HintLadder(
        "With equal space on both sides your robot turns left; the rule turns right.",
        "When left equals right, is left greater than right?",
        (
            "The rule turns left only when left is greater than right; otherwise it turns right.",
            "Check whether your side comparison is > or >=.",
            "Equal sides are not 'left greater', so they fall into the right-turn branch.",
            "Use left > right for the left turn and turn right in every other case.",
        ),
        "Fix the side comparison and rerun the tests.",
    ),
    "nan-side-chosen": HintLadder(
        "Your robot turned toward a side whose distance is unknown (NaN).",
        "What does any comparison with NaN return in Python?",
        (
            "A NaN distance means that direction has no usable reading.",
            "Any comparison with NaN is False, so left > right can fail even when left is the known open side.",
            "Replace a NaN distance with 0.0 (no space) before comparing; math.isnan() tells you when.",
            "Set left and right to 0.0 when they are NaN, then turn left when left > right, otherwise right.",
        ),
        "Handle NaN before comparing and rerun the tests.",
    ),
    "open-side-no-resume": HintLadder(
        "Your robot stays stopped after the front clears again.",
        "Does your node decide from each new message, or does it remember that it stopped?",
        (
            "When the front is clear again, the robot should drive straight again.",
            "Look for a flag or saved state that is set when the robot stops and never cleared.",
            "Decide drive or turn from the current message only, every time one arrives.",
            "Remove the stopped state; choose the command from each /flbr message.",
        ),
        "Decide from every message and rerun the tests.",
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
