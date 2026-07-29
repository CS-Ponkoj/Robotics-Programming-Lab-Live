import json
import logging
from typing import Any

from openai import OpenAI

from config import Settings
from models import Assignment, Submission
from schemas import TutorFeedback


logger = logging.getLogger(__name__)


class TutorService:
    def __init__(self, settings: Settings, client: OpenAI | None = None):
        self.settings = settings
        self.client = client

    def feedback(
        self,
        assignment: Assignment,
        submission: Submission,
        hint_level: int = 1,
    ) -> TutorFeedback:
        fallback = self._fallback(assignment, submission, hint_level)
        if self.client is None and not self.settings.openai_api_key:
            return fallback
        try:
            client = self.client or OpenAI(
                api_key=self.settings.openai_api_key,
                timeout=self.settings.openai_timeout_seconds,
                max_retries=self.settings.openai_max_retries,
            )
            response = client.responses.create(
                model=self.settings.openai_hint_model,
                instructions=(
                    "You are a robotics programming tutor. Use only the supplied "
                    "student-visible evidence. Never disclose hidden tests, expected "
                    "values, grader configuration, or an official solution. Do not "
                    "write replacement code. Return one JSON object with the keys "
                    "diagnosis, misconception, guiding_question, hint, next_action. "
                    "Keep every value concise and adapt to the requested hint level."
                ),
                input=json.dumps(
                    {
                        "assignment": {
                            "id": assignment.stable_id,
                            "version": assignment.version,
                            "title": assignment.title,
                            "description": assignment.description,
                            "learning_objectives": assignment.learning_objectives,
                            "common_misconceptions": assignment.misconceptions,
                            "tutoring_rules": assignment.tutoring_rules,
                        },
                        "student_code": submission.code,
                        "visible_evidence": self._visible_evidence(submission.evidence),
                        "hint_level": hint_level,
                    }
                ),
                max_output_tokens=220,
            )
            parsed = json.loads(response.output_text)
            return TutorFeedback(
                diagnosis=str(parsed.get("diagnosis", fallback.diagnosis)),
                misconception=str(
                    parsed.get("misconception", fallback.misconception)
                ),
                hint_level=hint_level,
                guiding_question=str(
                    parsed.get("guiding_question", fallback.guiding_question)
                ),
                hint=str(parsed.get("hint", fallback.hint)),
                next_action=str(parsed.get("next_action", fallback.next_action)),
                solution_revealed=False,
                source="openai",
            )
        except Exception as error:
            logger.warning("AI tutor unavailable; using deterministic feedback: %s", error)
            return fallback

    @staticmethod
    def _visible_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
        return {
            "execution_succeeded": evidence.get("execution_succeeded", False),
            "score": evidence.get("score", 0),
            "execution_error": evidence.get("execution_error", ""),
            "tests": [
                {
                    "label": item.get("label", "Test"),
                    "passed": item.get("passed", False),
                    "message": item.get("message", ""),
                }
                for item in evidence.get("tests", [])
            ],
        }

    @staticmethod
    def _fallback(
        assignment: Assignment,
        submission: Submission,
        hint_level: int,
    ) -> TutorFeedback:
        evidence = submission.evidence or {}
        failed = next(
            (
                item
                for item in evidence.get("tests", [])
                if not item.get("passed", False)
            ),
            None,
        )
        misconceptions = assignment.misconceptions or []
        misconception = ""
        if misconceptions:
            first = misconceptions[min(hint_level - 1, len(misconceptions) - 1)]
            misconception = (
                str(first.get("tag", first.get("description", "")))
                if isinstance(first, dict)
                else str(first)
            )
        if not evidence.get("execution_succeeded", False):
            diagnosis = "The program must execute before its calculations can be checked."
            guiding_question = "What is the first error message and line number?"
            hint = "Fix the first execution error, then run the tests again."
            next_action = "Inspect the reported line and complete or correct that expression."
        else:
            label = failed.get("label", "a required calculation") if failed else "the task"
            diagnosis = f"Your program runs, but {label.lower()} still needs attention."
            guiding_question = (
                "Which intermediate value can you calculate by hand and compare "
                "with the value produced by your program?"
            )
            level_hints = {
                1: "Trace the inputs and formula for the first failing calculation.",
                2: "Print the relevant intermediate values and compare each step with the assignment data.",
                3: "Re-read the rubric for the failing calculation and verify units, signs, and path segments.",
                4: "Break the failing calculation into named intermediate expressions, then recombine them.",
            }
            hint = level_hints[hint_level]
            next_action = "Change one calculation, rerun the tests, and use the new evidence."
        return TutorFeedback(
            diagnosis=diagnosis,
            misconception=misconception,
            hint_level=hint_level,
            guiding_question=guiding_question,
            hint=hint,
            next_action=next_action,
            solution_revealed=False,
            source="fallback",
        )
