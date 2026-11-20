"""Per-account feedback modes for the study's three conditions.

An instructor assigns each student account one mode. The server enforces it:
responses are trimmed to what the mode allows, so hiding a Flutter control is
never the only barrier. Grading is identical in every mode.

traditional  Knowledge of results: score, pass state, and how many checks
             passed. Build and runtime errors at the student's own line stay
             visible so a broken node is not a dead end. The plain simulation
             replay is part of the lab for every mode (owner decision
             2026-11-20); its diagnostic parts (beam probe, printed output,
             links from failed checks) are not.
tdd          Test-based feedback: check names and messages, the program's
             printed output, and the full simulation. No hints (see
             TDD_BUILT_IN_HINTS).
tdd_ai       Everything in tdd plus hints: the AI tutor (still gated by
             ai_policy) with the built-in hint ladder as its fallback.

Instructors always see tdd_ai. The public demo is tdd but keeps the built-in
hints, because it is a showcase, not a study condition.
"""
from __future__ import annotations

from typing import Any

from models import User

TRADITIONAL = "traditional"
TDD = "tdd"
TDD_AI = "tdd_ai"
FEEDBACK_MODES = (TRADITIONAL, TDD, TDD_AI)
DEFAULT_FEEDBACK_MODE = TDD

NO_HINTS_MESSAGE = "Hints are not part of this account's feedback."
NO_TUTOR_MESSAGE = "The tutor is not part of this account's feedback."
NO_SIMULATION_MESSAGE = "The simulation is not part of this account's feedback."
MODE_WITHOUT_AI = "Not part of this account's feedback. Built-in hints still work."

# Owner decision (2026-11-20): the tdd condition gives test feedback only, so
# each mode adds one feedback level (score -> test details -> hints). The
# built-in hint code is kept; set this to True to give tdd its hints back.
TDD_BUILT_IN_HINTS = False


def feedback_mode_for(user: User, *, demo: bool = False) -> str:
    """The mode that governs this request; unknown values fall back to tdd."""
    if demo:
        return TDD
    if user.role != "student":
        return TDD_AI
    mode = getattr(user, "feedback_mode", None)
    return mode if mode in FEEDBACK_MODES else DEFAULT_FEEDBACK_MODE


def allows_hints(mode: str, *, demo: bool = False) -> bool:
    if demo or mode == TDD_AI:
        return True
    return mode == TDD and TDD_BUILT_IN_HINTS


def allows_simulation(mode: str) -> bool:
    return mode in FEEDBACK_MODES


def shape_simulation_response(payload: dict[str, Any], mode: str) -> dict[str, Any]:
    """Traditional sees the plain replay, not the beam probe or printed output."""
    if mode != TRADITIONAL:
        return payload
    shaped = {**payload, "output": ""}
    replay = shaped.get("simulation")
    if isinstance(replay, dict):
        shaped["simulation"] = {
            key: value for key, value in replay.items() if key != "sensitivity"
        }
    return shaped


def allows_ai(mode: str) -> bool:
    return mode == TDD_AI


def shape_submission_response(
    payload: dict[str, Any], mode: str, *, demo: bool = False
) -> dict[str, Any]:
    """Remove the feedback a mode does not include from a run/submit response."""
    shaped = {**payload, "feedback_mode": mode}
    if not allows_hints(mode, demo=demo):
        shaped.update({"hint": "", "tutor_feedback": None})
    if mode != TRADITIONAL:
        return shaped
    passes = list(payload.get("unittest_pass_results") or [])
    shaped.update(
        {
            # Counts stay derivable; names, messages and evidence do not.
            "tested_vals": [],
            "unittest_results": ["" for _ in passes],
            "unittest_pass_results": passes,
            "evidence": [],
            "code_output": "",
            "hint": "",
            "tutor_feedback": None,
        }
    )
    return shaped
