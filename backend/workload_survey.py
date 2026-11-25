"""Raw NASA-TLX workload survey for the study assignments (study RQ6).

The form is identical in every feedback mode. Wording follows the NASA-TLX
manual (public domain, U.S. Government). Each scale is 0-100 in steps of 5
with no preset value; higher is worse on every scale, including Performance
(0 = good, 100 = poor), which is never reversed. Raw TLX is the mean of the
six ratings and only exists when all six are answered.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

FORM_VERSION = "tlx-raw-1"
PERFORMANCE_DIRECTION = "0 = good, 100 = poor"

# Offered only on the study assignments (Assignments 7 and 8; students see
# them as Assignments 1 and 2).
SURVEY_ASSIGNMENTS = frozenset({"ros2-wall-stop", "ros2-turn-open-side"})

TRIGGERS = frozenset({"finished_button", "full_pass_prompt"})

ITEMS: tuple[dict[str, str], ...] = (
    {
        "key": "mental_demand",
        "title": "Mental Demand",
        "question": "How mentally demanding was the task?",
        "definition": "How much mental and perceptual activity was required "
        "(e.g., thinking, deciding, calculating, remembering, looking, "
        "searching, etc.)? Was the task easy or demanding, simple or "
        "complex, exacting or forgiving?",
        "low": "Low",
        "high": "High",
    },
    {
        "key": "physical_demand",
        "title": "Physical Demand",
        "question": "How physically demanding was the task?",
        "definition": "How much physical activity was required (pushing, "
        "pulling, turning, controlling, activating, etc.)? Was the task easy "
        "or demanding, slow or brisk, slack or strenuous, restful or "
        "laborious?",
        "low": "Low",
        "high": "High",
    },
    {
        "key": "temporal_demand",
        "title": "Temporal Demand",
        "question": "How hurried or rushed was the pace of the task?",
        "definition": "How much time pressure did you feel due to the rate or "
        "pace at which the tasks or task elements occurred? Was the pace "
        "slow and leisurely or rapid and frantic?",
        "low": "Low",
        "high": "High",
    },
    {
        "key": "performance",
        "title": "Performance",
        "question": "How successful were you in accomplishing what you were "
        "asked to do?",
        "definition": "How successful do you think you were in accomplishing "
        "the goals of the task set by the experimenter (or yourself)? How "
        "satisfied were you with your performance in accomplishing these "
        "goals?",
        "low": "Good",
        "high": "Poor",
    },
    {
        "key": "effort",
        "title": "Effort",
        "question": "How hard did you have to work to accomplish your level "
        "of performance?",
        "definition": "How hard did you have to work (mentally and "
        "physically) to accomplish your level of performance?",
        "low": "Low",
        "high": "High",
    },
    {
        "key": "frustration",
        "title": "Frustration",
        "question": "How insecure, discouraged, irritated, stressed, and "
        "annoyed were you?",
        "definition": "How insecure, discouraged, irritated, stressed, and "
        "annoyed versus secure, gratified, content, relaxed, and complacent "
        "did you feel during the task?",
        "low": "Low",
        "high": "High",
    },
)
KEYS = tuple(item["key"] for item in ITEMS)


def form_payload() -> dict[str, Any]:
    return {
        "form_version": FORM_VERSION,
        "instructions": (
            "Rate the assignment you just worked on. Each scale goes from 0 "
            "to 100 in steps of 5. On every scale a higher number is worse, "
            "including Performance, where 0 means good and 100 means poor. "
            "Your answers do not change your score."
        ),
        "performance_direction": PERFORMANCE_DIRECTION,
        "step": 5,
        "items": [dict(item) for item in ITEMS],
    }


def validate_ratings(ratings: dict[str, Any]) -> dict[str, int | None]:
    """Six known scales, each null or 0-100 in steps of 5; at least one set."""
    unknown = set(ratings) - set(KEYS)
    if unknown:
        raise ValueError("Unknown workload scale.")
    clean: dict[str, int | None] = {}
    for key in KEYS:
        value = ratings.get(key)
        if value is None:
            clean[key] = None
            continue
        if isinstance(value, bool) or not isinstance(value, int):
            raise ValueError("Each rating must be a whole number.")
        if not 0 <= value <= 100 or value % 5:
            raise ValueError("Each rating must be 0-100 in steps of 5.")
        clean[key] = value
    if all(value is None for value in clean.values()):
        raise ValueError("Rate at least one scale.")
    return clean


def raw_tlx(ratings: dict[str, int | None]) -> float | None:
    """Mean of the six ratings, or None when any is missing (never imputed)."""
    values = [ratings.get(key) for key in KEYS]
    if any(value is None for value in values):
        return None
    return round(sum(values) / len(values), 2)


def bounded_opened_at(
    opened_at: datetime | None, submitted_at: datetime
) -> datetime | None:
    """The browser's time is kept only inside the hour before submitting."""
    if opened_at is None:
        return None
    moment = opened_at if opened_at.tzinfo else opened_at.replace(tzinfo=timezone.utc)
    if not submitted_at - timedelta(hours=1) <= moment <= submitted_at:
        return None
    return moment
