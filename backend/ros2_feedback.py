"""Evidence-based feedback for ROS 2 behavior checks.

The grader harness reports what the student's node published in each scenario
phase. This module turns those observations into a short, factual sentence
for each failed check and a hint key that selects a targeted hint ladder.

Observations state only what the robot or node did; they never say how to
fix it, because every feedback mode with check messages sees them. Advice
belongs in HINT_LADDERS, which only modes with hints receive.

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

WALL_STOP_BEHAVIOR = (
    "drive-open-floor", "drive-wall-far", "stop-wall-0-3", "stop-wall-0-2",
    "stay-stopped", "resume-motion", "straight-motion",
)
OPEN_SIDE_BEHAVIOR = (
    "clear-path-forward", "stop-when-blocked", "turn-toward-open-side",
    "stop-at-threshold", "equal-sides-turn-right", "unknown-distance-safe",
    "resume-forward",
)

# Failed source checks that are themselves explicit evidence of a pattern.
# The tag counts as a misconception label only where an assignment
# configures it (Assignment 7: sensor-ignored, main-modified).
CODE_CHECK_FINDINGS = {
    "reads-ranges": "sensor-ignored",
    "main-unchanged": "main-modified",
}


@dataclass(frozen=True)
class Finding:
    """One observed cause for a failed check.

    ``observation`` is appended to the check message, so it states only what
    the robot did. It is left out when the message already contains
    ``unless_message_has`` (the harness reported the same fact).
    """

    hint_key: str
    observation: str
    unless_message_has: str = ""


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


def _count(phase: dict) -> int:
    value = phase.get("count")
    return int(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else 0


def _any_commands(observations: dict) -> bool:
    phases = observations.get("phases") if isinstance(observations, dict) else None
    if not isinstance(phases, dict):
        return False
    return any(_count(value) > 0 for value in phases.values() if isinstance(value, dict))


def _rate(observations: dict) -> float | None:
    rate = observations.get("rate_hz") if isinstance(observations, dict) else None
    return float(rate) if isinstance(rate, (int, float)) and not isinstance(rate, bool) else None


def _failed(passed: dict[str, bool], test_id: str) -> bool:
    return passed.get(test_id, True) is False


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
            f"Your robot published linear.x up to {high:.2f} m/s {where}.",
        )
    if STOP_TOLERANCE < low < FORWARD_MIN - 1e-9:
        return Finding(
            "speed-too-low",
            f"Your robot published linear.x as low as {low:.2f} m/s {where}.",
        )
    return None


def _rate_finding(rate: float | None) -> Finding | None:
    """The measured rate, unless the check message already reports it."""
    if rate is None or rate <= 0:
        # No command at all: a crash, a hang, or unfinished wiring, which the
        # gate checks and the execution error describe instead.
        return None
    return Finding(
        "publishes-too-rarely",
        f"Your robot published about {rate:.1f} commands per second.",
        unless_message_has="published about",
    )


def wall_stop_findings(passed: dict[str, bool], observations: dict) -> dict[str, Finding]:
    """Findings for the open-structure wall-stop harness (Assignment 7)."""
    findings: dict[str, Finding] = {}
    rate = _rate(observations)
    rate_failed = _failed(passed, "publish-rate")
    if rate_failed:
        found = _rate_finding(rate)
        if found:
            findings["publish-rate"] = found
    failed_behavior = [test_id for test_id in WALL_STOP_BEHAVIOR if _failed(passed, test_id)]
    if not _any_commands(observations):
        # Nothing was published while the situations were checked, so no
        # behaviour can be described. A node that published, but too rarely
        # to be seen, has that as its cause.
        if rate_failed and rate is not None and rate > 0:
            rare = Finding(
                "publishes-too-rarely",
                "Your robot published no command while this situation was checked "
                f"(about {rate:.1f} commands per second overall).",
                unless_message_has="No command arrived",
            )
            for test_id in failed_behavior:
                if test_id != "straight-motion":
                    findings[test_id] = rare
        return findings

    open_, far = _phase(observations, "open"), _phase(observations, "far")
    near, close = _phase(observations, "near"), _phase(observations, "close")
    hold, resume = _phase(observations, "hold"), _phase(observations, "resume")
    close_phases_driving = _drives(near) or _drives(close)
    turn = max(
        (_number(_phase(observations, name), "angular_max_abs") or 0.0)
        for name in ("open", "far", "near", "close", "hold", "resume")
    )
    if _failed(passed, "straight-motion") and turn > ANGULAR_TOLERANCE:
        findings["straight-motion"] = Finding(
            "turns-while-driving",
            f"Your robot published angular.z up to {turn:.2f} rad/s.",
        )

    pattern = None
    if _stopped(open_) and _stopped(far) and close_phases_driving:
        pattern = Finding(
            "wrong-threshold-direction",
            "Your robot stayed stopped while the way was clear and drove "
            "while the wall was close.",
        )
    elif _stopped(open_) and _stopped(far) and not any(
        _drives(phase) for phase in (open_, far, near, close, hold, resume)
    ):
        pattern = Finding(
            "never-drives",
            "Your robot never drove forward: it published linear.x 0.00 m/s "
            "with nothing in range and with the wall 1.2 m away.",
        )
    if pattern is not None:
        for test_id in failed_behavior:
            findings.setdefault(test_id, pattern)
        return findings

    if _failed(passed, "drive-open-floor"):
        found = _speed_finding(open_, "with nothing in range")
        if found is None and _stopped(open_) and _drives(far):
            found = Finding(
                "infinity-treated-as-obstacle",
                "Your robot stayed stopped while every reading was +inf, but "
                "drove with the wall 1.2 m away.",
            )
        if found:
            findings["drive-open-floor"] = found
    stopped_far = _stopped(far) and _drives(open_)
    if _failed(passed, "drive-wall-far"):
        found = _speed_finding(far, "with the wall 1.2 m away")
        if found is None and stopped_far:
            found = Finding(
                "stops-too-early",
                "Your robot published linear.x 0.00 m/s with the wall 1.2 m away.",
            )
        if found:
            findings["drive-wall-far"] = found
    sensor_ignored = _failed(passed, "reads-ranges")
    for test_id, phase, distance in (
        ("stop-wall-0-3", near, "0.3"),
        ("stop-wall-0-2", close, "0.2"),
        ("stay-stopped", hold, "0.2"),
    ):
        if not _failed(passed, test_id):
            continue
        speed = _number(phase, "linear_max")
        if not (_drives(open_) or _drives(far)):
            findings[test_id] = Finding(
                "must-drive-first",
                "Your robot did not drive forward with nothing in range or with "
                "the wall 1.2 m away.",
            )
        elif speed is not None and speed > STOP_TOLERANCE:
            observation = (
                f"Your robot still published linear.x {speed:.2f} m/s with the "
                f"wall {distance} m away."
            )
            if sensor_ignored:
                key = "sensor-ignored"
            elif test_id == "stop-wall-0-3" and _stopped(close):
                key = "stop-distance-at-boundary"
                observation = (
                    f"Your robot still published linear.x {speed:.2f} m/s with the "
                    "wall 0.3 m away, but stopped with the wall 0.2 m away."
                )
            else:
                key = "stops-too-late"
            findings[test_id] = Finding(key, observation)
    if _failed(passed, "resume-motion"):
        found = _speed_finding(resume, "after the wall moved away")
        if found is None and _stopped(resume):
            if stopped_far:
                # Same cause as the far-wall check: the wall at 1.2 m stops it.
                found = Finding(
                    "stops-too-early",
                    "Your robot also stayed stopped when the wall moved back to 1.2 m.",
                )
            elif _drives(far) and _stopped(hold):
                found = Finding(
                    "does-not-resume",
                    "Your robot stopped for the close wall but stayed stopped after "
                    "the wall moved back to 1.2 m.",
                )
        if found:
            findings["resume-motion"] = found

    if rate_failed and rate is not None and 0 < rate < MINIMUM_RATE_HZ:
        # A node that answers only some scans reacts late; that, not the stop
        # rule, explains late stops and a missed restart.
        note = f"It published only about {rate:.1f} commands per second."
        for test_id in failed_behavior:
            found = findings.get(test_id)
            if found is None:
                findings[test_id] = Finding(
                    "publishes-too-rarely",
                    f"Your robot published only about {rate:.1f} commands per second.",
                )
            elif found.hint_key in {
                "stops-too-late", "stop-distance-at-boundary", "does-not-resume",
            }:
                findings[test_id] = Finding(
                    "publishes-too-rarely", f"{found.observation} {note}"
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
    wiring = ("node-start", "flbr-response", "cmd-vel-topic")
    if _failed(passed, "node-start") and observations.get("alive") is True:
        # A running node that never answered: unfinished wiring or a callback
        # that never returns. A crash is reported as a runtime error instead.
        cause = (
            Finding(
                "silent-callback",
                "Your node subscribed to /flbr but never published a Twist.",
            )
            if observations.get("subscribed") is True
            else Finding(
                "not-wired",
                "Your node never subscribed to /flbr or published on /cmd_vel.",
            )
        )
        for test_id in wiring:
            if _failed(passed, test_id):
                findings[test_id] = cause
        return findings
    if not _any_commands(observations):
        return findings
    clear = _phase(observations, "clear")
    differ = _phase(observations, "clear-sides-differ")
    left_open = _phase(observations, "left-open")
    right_open = _phase(observations, "right-open")
    failed_behavior = [test_id for test_id in OPEN_SIDE_BEHAVIOR if _failed(passed, test_id)]
    if not _count(clear) and _count(left_open):
        skipped = Finding(
            "skips-clear-messages",
            "Your node published a Twist only when the front was blocked and "
            "nothing while the front was clear.",
        )
        for test_id in (*wiring, "clear-path-forward"):
            if _failed(passed, test_id):
                findings[test_id] = skipped
        return findings
    threshold = _phase(observations, "threshold")
    sides_equal = _phase(observations, "sides-equal")
    side_unknown = _phase(observations, "side-unknown")
    resume = _phase(observations, "resume")
    blocked_drives = _drives(left_open) or _drives(right_open)

    # Whole-rule patterns first, so their configured tags are not hidden
    # behind a narrower finding about one situation.
    if _stopped(clear) and blocked_drives:
        speed = max(
            _number(left_open, "linear_max") or 0.0,
            _number(right_open, "linear_max") or 0.0,
        )
        reversed_front = Finding(
            "front-check-reversed",
            "Your robot did not drive with the front 2.0 m away and drove at "
            f"linear.x {speed:.2f} m/s with the front 0.5 m away.",
        )
        for test_id in failed_behavior:
            findings[test_id] = reversed_front
        return findings
    blocked = (left_open, right_open, threshold, sides_equal)
    if all(_stopped(phase) and _turn(phase) == 0.0 for phase in (clear, *blocked)):
        never_moves = Finding(
            "never-moves",
            "Your robot published linear.x 0.00 and angular.z 0.00 in every situation.",
        )
        for test_id in failed_behavior:
            findings[test_id] = never_moves
        return findings

    if _failed(passed, "clear-path-forward"):
        clear_turn = next(
            (
                _number(phase, "angular_max")
                for phase in (clear, differ)
                if _turn(phase) not in (None, 0.0)
            ),
            None,
        )
        if clear_turn is not None:
            findings["clear-path-forward"] = Finding(
                "turns-while-clear",
                f"Your robot published angular.z {clear_turn:+.2f} rad/s while the "
                "front was clear.",
            )
        elif _drives(clear) and not (0.18 <= (_number(clear, "linear_max") or 0.0) <= 0.22):
            findings["clear-path-forward"] = Finding(
                "forward-speed-wrong",
                f"Your robot drove at linear.x = {_number(clear, 'linear_max'):.2f} m/s "
                "with the front clear.",
                unless_message_has="With the front clear, linear.x was",
            )
    turn_finding = None
    if blocked_drives:
        speed = max(
            _number(left_open, "linear_max") or 0.0,
            _number(right_open, "linear_max") or 0.0,
        )
        turn_finding = Finding(
            "drives-when-blocked",
            f"Your robot kept driving at linear.x {speed:.2f} m/s with the front "
            "0.5 m away.",
        )
        for test_id in ("stop-when-blocked", "turn-toward-open-side"):
            if _failed(passed, test_id):
                findings[test_id] = turn_finding
    elif _failed(passed, "turn-toward-open-side"):
        left_turn, right_turn = _turn(left_open), _turn(right_open)
        if left_turn == -1.0 and right_turn == 1.0:
            turn_finding = Finding(
                "turn-direction-swapped",
                "Your robot turned right when the left had more space and left "
                "when the right had more space.",
            )
        elif left_turn == 0.0 and right_turn == 0.0:
            turn_finding = Finding(
                "no-turn-when-blocked",
                "Your robot stopped when the front was blocked but kept angular.z "
                "at 0.0.",
            )
        elif left_turn is not None and left_turn == right_turn and left_turn != 0.0:
            way = "left" if left_turn > 0 else "right"
            turn_finding = Finding(
                "same-turn-every-time",
                f"Your robot turned {way} whether the left or the right had more space.",
            )
        if turn_finding:
            findings["turn-toward-open-side"] = turn_finding
    if _drives(threshold) and not blocked_drives:
        boundary = Finding(
            "threshold-boundary",
            "Your robot drove with the front exactly 0.75 m away.",
        )
        for test_id in ("stop-at-threshold", "stop-when-blocked"):
            if _failed(passed, test_id):
                findings[test_id] = boundary
    elif _failed(passed, "stop-at-threshold") and turn_finding:
        # Stopped at 0.75 m but turned the wrong way: same cause as the turn check.
        findings["stop-at-threshold"] = turn_finding
    if _failed(passed, "equal-sides-turn-right") and turn_finding:
        findings["equal-sides-turn-right"] = turn_finding
    elif _failed(passed, "equal-sides-turn-right") and _turn(sides_equal) == 1.0:
        findings["equal-sides-turn-right"] = Finding(
            "tie-goes-left",
            "Your robot turned left when the left and right distances were equal.",
        )
    if _failed(passed, "unknown-distance-safe") and turn_finding:
        # A turn rule that is wrong everywhere also fails the NaN situations;
        # name that cause instead of blaming the NaN handling.
        findings["unknown-distance-safe"] = turn_finding
    elif _failed(passed, "unknown-distance-safe") and _turn(side_unknown) == -1.0:
        findings["unknown-distance-safe"] = Finding(
            "nan-side-chosen",
            "Your robot turned right, toward the side whose distance was NaN (unknown).",
        )
    if _failed(passed, "resume-forward") and _stopped(resume) and _drives(clear):
        findings["resume-forward"] = Finding(
            "open-side-no-resume",
            "Your robot stayed stopped after the front cleared again.",
        )
    return findings


_CLASSIFIERS: dict[str, Callable[[dict[str, bool], dict], dict[str, Finding]]] = {
    "wall_stop_open": wall_stop_findings,
    "open_side": open_side_findings,
}


def classify(harness: str, passed: dict[str, bool], observations: Any) -> dict[str, Finding]:
    """Findings for failed checks, or none for harnesses without a classifier."""
    classifier = _CLASSIFIERS.get(harness)
    findings: dict[str, Finding] = {}
    if classifier is not None and isinstance(observations, dict):
        findings = classifier(passed, observations)
    # A failed source check is explicit evidence on its own; the harnesses
    # for older assignments report none of these checks. Not reading the scan
    # is a pattern only for a node that publishes commands: an unfinished
    # starter that never runs is not "motion decided without the sensor".
    if classifier is not None:
        for test_id, hint_key in CODE_CHECK_FINDINGS.items():
            if not _failed(passed, test_id):
                continue
            if test_id == "reads-ranges" and not _any_commands(observations):
                continue
            findings.setdefault(test_id, Finding(hint_key, ""))
    # The one-command-per-callback contract has its own hint ladder. Commands
    # published from outside the callback (for example a timer) mix into
    # every situation, so behaviour findings would describe the wrong cause.
    if classifier is not None and isinstance(observations, dict):
        contract = "one-command-per-scan" if harness == "wall_stop_open" else "flbr-response"
        callbacks = observations.get("callbacks") or {}
        if _failed(passed, contract) and contract not in findings:
            findings[contract] = Finding(
                "publisher-queue-depth"
                if isinstance(callbacks, dict) and callbacks.get("queue_depth_wrong")
                else "one-command-contract",
                "",
            )
        if observations.get("unused_axes_used"):
            extra = Finding(
                "extra-axes",
                "Your robot published a value other than 0.0 on linear.y, linear.z, "
                "angular.x or angular.y.",
            )
            for test_id in _CONTRACT_MIXED_CHECKS:
                if _failed(passed, test_id):
                    findings.setdefault(test_id, extra)
        if isinstance(callbacks, dict) and callbacks.get("published_outside"):
            outside = Finding(
                "one-command-contract",
                "Some commands came from outside the callback, so the commands seen "
                "in this situation are mixed.",
            )
            for test_id, ok in passed.items():
                if not ok and test_id != contract and test_id not in CODE_CHECK_FINDINGS:
                    if test_id in _CONTRACT_MIXED_CHECKS:
                        findings[test_id] = outside
    return findings


_CONTRACT_MIXED_CHECKS = frozenset({
    "drive-open-floor", "drive-wall-far", "stop-wall-0-3", "stop-wall-0-2", "stay-stopped",
    "resume-motion", "straight-motion", "clear-path-forward", "stop-when-blocked",
    "turn-toward-open-side", "stop-at-threshold", "equal-sides-turn-right",
    "unknown-distance-safe", "resume-forward",
})


# Hints are part of the TDD + AI condition only. Each ladder adds one step per
# level; level 4 names the change in words, never as a ready-made expression.
HINT_LADDERS: dict[str, HintLadder] = {
    "publisher-queue-depth": HintLadder(
        "Your /cmd_vel publisher does not use the queue depth the rules ask for.",
        "Which number did you pass as the last argument when you created the publisher?",
        (
            "The last argument of create_publisher is the queue depth.",
            "The rules ask for a queue depth of 10 on the /cmd_vel publisher.",
            "The queue depth is a history size, not a rate; it does not change how often you publish.",
            "Create the /cmd_vel publisher with the queue depth given in the rules.",
        ),
        "Set the publisher's queue depth as the rules ask, then rerun the tests.",
    ),
    "extra-axes": HintLadder(
        "Your robot sets parts of the Twist that the lab robot does not use.",
        "Which fields of your Twist do you set, apart from linear.x and angular.z?",
        (
            "The lab robot only drives forward and turns: it uses linear.x and angular.z.",
            "A new Twist starts with every field at 0.0; any other field you set is sent as well.",
            "Check every line that writes to your Twist message.",
            "Set only linear.x and angular.z, and leave the other four fields at 0.0.",
        ),
        "Leave the unused Twist fields at 0.0, then rerun the tests.",
    ),
    "one-command-contract": HintLadder(
        "Your node does not publish exactly one Twist, from inside its callback, for every message.",
        "Where in your code does each command get published, and how many times per message?",
        (
            "Each message that arrives should lead to exactly one command, published by the callback that received it.",
            "Look for a timer, a second publish call, or a path through the callback that publishes nothing.",
            "Commands from a timer or from outside the callback are not tied to a message, so they cannot be checked against it.",
            "Decide the command in the callback and publish it there once, on every path, even when it has not changed.",
        ),
        "Publish once per message inside the callback, then rerun the tests.",
    ),
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
            "Check your STOP_DISTANCE value: the rules ask for a value above 0.3 m and at most 1.0 m.",
            "Print the reading you compare and the stop distance for one scan to see which branch runs.",
            "Choose a stop distance above 0.3 m and at most 1.0 m, and drive whenever the reading ahead is greater than it.",
        ),
        "Adjust the stop distance into the allowed range and rerun the tests.",
    ),
    "stops-too-late": HintLadder(
        "Your robot keeps driving when the wall is already close.",
        "Which reading does your node compare with the stop distance, and how large is that stop distance?",
        (
            "With the wall 0.3 m ahead the robot must be stopped. Which value decides whether it stops?",
            "Check your STOP_DISTANCE: it must be above 0.3 m and at most 1.0 m, so a wall 0.3 m ahead is inside it.",
            "Check which reading you compare: the one straight ahead is the middle of scan.ranges. In Simulate, the highlighted beams are the ones your node reacts to.",
            "Compare the reading straight ahead with a stop distance above 0.3 m, and publish zero forward speed when the reading is not greater than it.",
        ),
        "Check the reading and the stop distance, then rerun the tests.",
    ),
    "stop-distance-at-boundary": HintLadder(
        "Your robot stops for a wall 0.2 m away but still drives at 0.3 m, so its stop rule ends just short of 0.3 m.",
        "What value does a wall 0.3 m away arrive as, and is that at or below your stop distance?",
        (
            "Compare what your robot did at 0.3 m and at 0.2 m: the difference is right at the boundary.",
            "A reading of 0.3 m arrives as a float32 slightly above 0.3, so a stop distance of exactly 0.3 m does not stop for it.",
            "Check both your STOP_DISTANCE value and whether your comparison includes the stop distance itself.",
            "Pick a stop distance clearly above 0.3 m and at most 1.0 m, and stop whenever the reading ahead is at or below it.",
        ),
        "Move the stop distance above 0.3 m and rerun the tests.",
    ),
    "wrong-threshold-direction": HintLadder(
        "The drive and stop branches are swapped: the robot stops when clear and drives when close.",
        "When the reading is larger than your stop distance, should the robot drive or stop?",
        (
            "Your robot did the opposite of the rule in both directions. Look at the comparison.",
            "A large reading means the wall is far away, so the robot should drive.",
            "Read your if-condition aloud with a reading of 1.2 m and a stop distance of 0.5 m.",
            "Drive when the reading is greater than the stop distance; otherwise publish zero forward speed.",
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
    "never-drives": HintLadder(
        "Your robot never drives forward, so none of the drive or stop checks can pass yet.",
        "Which command does your node publish when nothing is in range?",
        (
            "With nothing in range the robot must drive. Which value of linear.x does your node publish then?",
            "Check that your drive branch sets linear.x to your forward-speed constant, and that this branch can run.",
            "Print the reading ahead and the branch your callback takes for one scan; with +inf or 1.2 m it should take the drive branch.",
            "Make the clear-way branch publish your forward speed (0.1 to 0.3 m/s) and keep zero speed for a close wall only.",
        ),
        "Make the robot drive when the way is clear, then rerun the tests.",
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
    "sensor-ignored": HintLadder(
        "Your node does not read scan.ranges, so its commands cannot depend on the wall.",
        "Where in your callback do you look at the distances in the scan?",
        (
            "The robot must decide from each scan. Which part of the LaserScan message holds the distances?",
            "scan.ranges holds the distances in metres; the middle reading points straight ahead.",
            "Motion that is timed or fixed does not react when the wall moves; read the scan inside the scan callback.",
            "In the scan callback, take the reading straight ahead from scan.ranges and choose drive or stop from it.",
        ),
        "Read the distance from scan.ranges in your callback and rerun the tests.",
    ),
    "main-modified": HintLadder(
        "main() differs from the starter code, and the grader starts your node through it.",
        "What did you change in main(), and could that code live in your node instead?",
        (
            "Compare your main() with main() in the starter code, line by line.",
            "Your node, its publisher, and its subscription belong in your own code; main() only starts the node.",
            "Move any code you added to main() into your node or its callback.",
            "Restore main() exactly as given in the starter code and keep your own code outside it.",
        ),
        "Put main() back as given and rerun the tests.",
    ),
    "turns-while-clear": HintLadder(
        "Your robot turns even though the front is clear.",
        "When the front distance is greater than 0.75 m, which value should angular.z have?",
        (
            "With the front clear the robot drives straight. Which branch sets angular.z?",
            "Turning belongs only to the blocked case; the clear case keeps angular.z at 0.0.",
            "Use one if/else on the front distance: the drive branch sets only linear.x.",
            "When the front is clear, publish only the forward speed and leave the turn speed at zero.",
        ),
        "Make the clear branch drive straight and rerun the tests.",
    ),
    "forward-speed-wrong": HintLadder(
        "Your robot drives with the front clear, but not at the required speed.",
        "Which value does your node publish as linear.x when the front is clear?",
        (
            "Compare the speed you published with the rule: 0.20 m/s.",
            "Check the forward-speed attribute set in __init__ and where you use it.",
            "Look for a different number written where the forward speed is used.",
            "Whenever the front is clear, publish the given forward speed of 0.20 m/s.",
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
            "Drive only when the front distance is greater than the stop distance; in every other case stop and turn.",
        ),
        "Fix the comparison direction and rerun the tests.",
    ),
    "drives-when-blocked": HintLadder(
        "Your robot keeps driving forward when the front is blocked.",
        "What should your node publish when the front distance is 0.75 m or less?",
        (
            "With the front 0.5 m away the robot must stop and turn. Which branch does your node take then?",
            "Check that your node compares msg.front with the stop distance before it chooses the command.",
            "Print msg.front and the branch your callback takes for one blocked message.",
            "When the front is not greater than the stop distance, stop the forward motion and turn toward the side with more space.",
        ),
        "Make the blocked case stop and turn, then rerun the tests.",
    ),
    "never-moves": HintLadder(
        "Your node answers every message, but the robot never drives or turns.",
        "Which values does handle_flbr set in the Twist before publishing it?",
        (
            "A new Twist starts at zero. Which of its fields does your callback change?",
            "Choose the command from msg.front: drive when the front is clear, stop and turn when it is blocked.",
            "Print msg.front and the command you publish for one message.",
            "Set the forward speed in the clear case and the turn speed in the blocked case before publishing.",
        ),
        "Set the command from the distances and rerun the tests.",
    ),
    "turn-direction-swapped": HintLadder(
        "Your robot turns toward the side with less space.",
        "Which sign of angular.z turns a ROS robot to the left?",
        (
            "Compare the turn you published with the side that had more space.",
            "In ROS, positive angular.z turns left (counter-clockwise) and negative turns right.",
            "Check which side your comparison picks and which sign you then publish.",
            "Turn left with a positive turn speed when the left has more space, and right with a negative one otherwise.",
        ),
        "Fix the turn sign and rerun the tests.",
    ),
    "no-turn-when-blocked": HintLadder(
        "Your robot stops for a blocked front but does not turn, so it stays stuck.",
        "After stopping, how does the robot find a new way forward?",
        (
            "With the front blocked, the robot must turn on the spot toward more space.",
            "Set angular.z in the blocked branch, as well as stopping the forward motion.",
            "Compare msg.left with msg.right to choose the direction.",
            "In the blocked branch, stop the forward motion and set the turn speed toward the side with more space.",
        ),
        "Add the turn to the blocked branch and rerun the tests.",
    ),
    "not-wired": HintLadder(
        "Your node is not connected yet: it has no /cmd_vel publisher or /flbr subscription.",
        "Which two lines in __init__ still say None?",
        (
            "Start with TODO 1 and TODO 2 in __init__; the robot cannot hear or move without them.",
            "TODO 1 creates a Twist publisher on /cmd_vel with queue depth 10.",
            "TODO 2 subscribes to Flbr on /flbr with queue depth 10 and calls self.handle_flbr.",
            "Replace each None with the matching publisher or subscription you create on the node.",
        ),
        "Complete TODO 1 and TODO 2, then run the tests again.",
    ),
    "silent-callback": HintLadder(
        "Your node receives /flbr messages but never publishes a reply.",
        "Does handle_flbr always reach the publish line, and does it finish quickly?",
        (
            "Every /flbr message must get exactly one Twist on /cmd_vel.",
            "Check that the publish call runs on every path through handle_flbr.",
            "A loop that never ends, or waiting inside the callback, stops all replies.",
            "Build one Twist, set it from the distances, publish it, and return.",
        ),
        "Make handle_flbr publish once and return, then rerun the tests.",
    ),
    "skips-clear-messages": HintLadder(
        "Your node answers only when the front is blocked, so it never drives forward.",
        "What does handle_flbr publish when the front is clear?",
        (
            "Every /flbr message needs a reply, including when the way ahead is clear.",
            "Look for a return or a branch that skips the publish call.",
            "Set the command in each branch, then publish once at the end of handle_flbr.",
            "When the front is clear, publish the forward speed too, so every message gets a reply.",
        ),
        "Publish for every message and rerun the tests.",
    ),
    "same-turn-every-time": HintLadder(
        "Your robot always turns the same way, no matter which side has more space.",
        "What should change in your command when the right, not the left, has more space?",
        (
            "Compare the turns your robot made when the left was open and when the right was open.",
            "The direction must come from comparing msg.left with msg.right.",
            "Check that the two branches publish different signs: one positive, one negative.",
            "Give the case where the left has more space a positive turn speed and every other case a negative one.",
        ),
        "Give each side its own turn sign and rerun the tests.",
    ),
    "threshold-boundary": HintLadder(
        "Your robot treats a front distance of exactly 0.75 m as clear.",
        "Is 0.75 greater than 0.75?",
        (
            "The rule drives only when the front is greater than 0.75 m.",
            "Check whether your comparison is > or >=.",
            "At exactly 0.75 m the robot must stop and turn.",
            "Make the drive branch require a front strictly greater than the stop distance.",
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
            "Turn left only when the left is strictly greater than the right, and turn right in every other case.",
        ),
        "Fix the side comparison and rerun the tests.",
    ),
    "nan-side-chosen": HintLadder(
        "Your robot turned toward a side whose distance is unknown (NaN).",
        "What does any comparison with NaN return in Python?",
        (
            "A NaN distance means that direction has no usable reading.",
            "Any comparison with NaN is False, so left > right can fail even when left is the known open side.",
            "Check each side for NaN before comparing; math.isnan() tells you when a distance is unknown.",
            "Treat a NaN side as having no space before you compare the sides, then choose the turn as usual.",
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
            "The rule is exactly one command in the scan callback for every scan, which is about 12 per second.",
            "Publish from the scan callback so every scan gets a command, and keep sleep() and waiting out of the callback.",
            "If you publish only when the decision changes, publish every time instead.",
            "Publish exactly one Twist at the end of every scan callback.",
        ),
        "Publish once per scan and rerun the tests.",
    ),
}
