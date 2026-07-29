import json
from types import SimpleNamespace

from config import Settings
from models import Assignment, Submission
from tutor import TutorService


def _assignment() -> Assignment:
    return Assignment(
        stable_id="test-assignment",
        version=1,
        title="Test assignment",
        description="",
        learning_objectives=[],
        misconceptions=[],
        tutoring_rules={},
    )


def _submission() -> Submission:
    return Submission(
        code="answer = 0",
        evidence={
            "execution_succeeded": True,
            "score": 0,
            "tests": [
                {
                    "label": "Check answer",
                    "passed": False,
                    "message": "Recheck how answer is calculated.",
                }
            ],
        },
    )


def test_openai_client_uses_bounded_timeout_and_no_retries(monkeypatch):
    captured = {}

    class FakeResponses:
        @staticmethod
        def create(**_kwargs):
            return SimpleNamespace(
                output_text=json.dumps(
                    {
                        "diagnosis": "Check the calculation.",
                        "misconception": "",
                        "guiding_question": "Which input should you inspect?",
                        "hint": "Trace the calculation.",
                        "next_action": "Change one expression.",
                    }
                )
            )

    class FakeOpenAI:
        def __init__(self, **kwargs):
            captured.update(kwargs)
            self.responses = FakeResponses()

    monkeypatch.setattr("tutor.OpenAI", FakeOpenAI)
    settings = Settings(
        openai_api_key="test-key",
        openai_timeout_seconds=6.5,
        openai_max_retries=0,
    )

    feedback = TutorService(settings).feedback(_assignment(), _submission())

    assert captured["timeout"] == 6.5
    assert captured["max_retries"] == 0
    assert feedback.hint == "Trace the calculation."
    assert feedback.source == "openai"


def test_tutor_falls_back_when_openai_times_out():
    class TimedOutResponses:
        @staticmethod
        def create(**_kwargs):
            raise TimeoutError("simulated timeout")

    client = SimpleNamespace(responses=TimedOutResponses())
    feedback = TutorService(Settings()).feedback(
        _assignment(),
        _submission(),
        hint_level=1,
    )

    assert feedback.hint == (
        "Trace the inputs and formula for the first failing calculation."
    )
    assert feedback.solution_revealed is False
    assert feedback.source == "fallback"
