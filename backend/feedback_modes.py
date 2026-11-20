"""Per-account feedback modes for the study's three conditions.

An instructor assigns each student account one mode. The server enforces it:
responses are trimmed to what the mode allows, so hiding a Flutter control is
never the only barrier. Grading is identical in every mode.

traditional  Knowledge of results: score, pass state, and how many checks
             passed. Build and runtime errors at the student's own line stay
             visible so a broken node is not a dead end.
tdd          Rule-based elaborated feedback: check names and messages, the
             program's printed output, built-in hints, and the simulation.
tdd_ai       Everything in tdd plus the AI tutor (still gated by ai_policy).

Instructors always see tdd_ai, and the public demo is always tdd.
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


def feedback_mode_for(user: User, *, demo: bool = False) -> str:
    """The mode that governs this request; unknown values fall back to tdd."""
    if demo:
        return TDD
    if user.role != "student":
        return TDD_AI
    mode = getattr(user, "feedback_mode", None)
    return mode if mode in FEEDBACK_MODES else DEFAULT_FEEDBACK_MODE


def allows_hints(mode: str) -> bool:
    return mode != TRADITIONAL


def allows_simulation(mode: str) -> bool:
    return mode != TRADITIONAL


def allows_ai(mode: str) -> bool:
    return mode == TDD_AI


def shape_submission_response(payload: dict[str, Any], mode: str) -> dict[str, Any]:
    """Remove the feedback a mode does not include from a run/submit response."""
    shaped = {**payload, "feedback_mode": mode}
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
