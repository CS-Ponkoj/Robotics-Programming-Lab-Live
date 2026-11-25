"""Research grouping of each study assignment's checks (analysis only).

Every check of a study assignment version belongs to exactly one group:

- ``setup``: the node builds, starts, and is wired to the right topics.
- ``behavior``: what the robot does; study RQ4 times the first attempt in
  which every behavior check passes ("full behavior pass").
- ``code_style``: structure and style checks that only add points.

This list never changes grading, scores, or what students see. It is keyed
by stable assignment ID and version, so a new assignment version needs its
own reviewed entry; unknown versions get no group rather than a guess.
"""

from __future__ import annotations

from typing import Any

SETUP = "setup"
BEHAVIOR = "behavior"
CODE_STYLE = "code_style"

_GROUPS: dict[tuple[str, int], dict[str, tuple[str, ...]]] = {
    # Assignment 7 v5 "Stop Before the Wall": the grader's gate tests are
    # setup and its pass tests are behavior (owner decision 2026-11-24: all 9).
    ("ros2-wall-stop", 5): {
        SETUP: (
            "imports-allowed", "build-node-defined", "package-build",
            "node-start", "returns-node",
        ),
        BEHAVIOR: (
            "drive-open-floor", "drive-wall-far", "stop-wall-0-3",
            "stop-wall-0-2", "stay-stopped", "resume-motion",
            "straight-motion", "publish-rate", "one-command-per-scan",
        ),
        CODE_STYLE: (
            "cmd-vel-publisher", "scan-subscription", "reads-ranges",
            "no-blocking", "main-unchanged", "named-constants",
            "no-unused-imports",
        ),
    },
    # Assignment 8 v3 "Turn Toward the Open Side".
    ("ros2-turn-open-side", 3): {
        SETUP: ("package-build", "node-start", "flbr-response", "cmd-vel-topic"),
        BEHAVIOR: (
            "clear-path-forward", "stop-when-blocked", "turn-toward-open-side",
            "stop-at-threshold", "equal-sides-turn-right",
            "unknown-distance-safe", "resume-forward",
        ),
        CODE_STYLE: ("imports-allowed", "no-blocking", "main-unchanged"),
    },
}

_LOOKUP: dict[tuple[str, int], dict[str, str]] = {
    key: {test_id: group for group, ids in groups.items() for test_id in ids}
    for key, groups in _GROUPS.items()
}


def check_group(stable_id: str, version: int, test_id: str) -> str:
    """The check's group, or "" when this assignment version is not mapped."""
    return _LOOKUP.get((stable_id, version), {}).get(test_id, "")


def behavior_checks(stable_id: str, version: int) -> frozenset[str]:
    """Behavior check IDs of a mapped assignment version (empty otherwise)."""
    return frozenset(_GROUPS.get((stable_id, version), {}).get(BEHAVIOR, ()))


def behavior_summary(
    stable_id: str,
    version: int,
    tests: list[dict[str, Any]] | None,
    execution_succeeded: bool,
) -> tuple[int, int, bool] | None:
    """(behavior checks passed, behavior checks, full behavior pass).

    None for an unmapped assignment version. A full pass needs a run that
    executed and every behavior check present and passed.
    """
    expected = behavior_checks(stable_id, version)
    if not expected:
        return None
    outcome = {
        str(test.get("test_id") or ""): test.get("passed") is True
        for test in tests or []
    }
    passed = sum(1 for test_id in expected if outcome.get(test_id))
    return passed, len(expected), bool(execution_succeeded) and passed == len(expected)
