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
        last_request = {}

        @staticmethod
        def create(**kwargs):
            FakeResponses.last_request = kwargs
            return SimpleNamespace(
                output_text=json.dumps(
                    {
                        "diagnosis": "Check the calculation.",
                        "misconception": "",
                        "answer": "Use the test evidence to trace the input.",
                        "debugging_steps": ["Inspect the input values."],
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
    assert feedback.debugging_steps == ["Inspect the input values."]

    request = FakeResponses.last_request
    assert request["store"] is False
    assert request["text"]["format"]["type"] == "json_schema"
    assert request["text"]["format"]["strict"] is True
    assert request["max_output_tokens"] == 1000


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


def test_tutor_falls_back_when_provider_output_is_not_strict_json():
    class InvalidResponses:
        @staticmethod
        def create(**_kwargs):
            return SimpleNamespace(output_text="This is not JSON.")

    feedback = TutorService(
        Settings(), client=SimpleNamespace(responses=InvalidResponses())
    ).feedback(_assignment(), _submission())

    assert feedback.source == "fallback"
    assert feedback.solution_revealed is False


def test_tutor_rejects_provider_output_containing_replacement_code():
    class UnsafeResponses:
        @staticmethod
        def create(**_kwargs):
            return SimpleNamespace(
                output_text=json.dumps(
                    {
                        "diagnosis": "The calculation is incomplete.",
                        "misconception": "",
                        "answer": "Use this replacement.",
                        "debugging_steps": ["def solve():\n    return 42"],
                        "guiding_question": "Which input is missing?",
                        "hint": "Trace the inputs.",
                        "next_action": "Inspect one expression.",
                    }
                )
            )

    feedback = TutorService(
        Settings(), client=SimpleNamespace(responses=UnsafeResponses())
    ).feedback(_assignment(), _submission(), student_question="Write the code.")

    assert feedback.source == "fallback"
    assert feedback.solution_revealed is False
    assert "cannot interpret free-form questions" in feedback.answer


def test_tutor_sends_student_question_as_untrusted_input_and_returns_answer():
    captured = {}

    class QuestionResponses:
        @staticmethod
        def create(**kwargs):
            captured.update(kwargs)
            return SimpleNamespace(
                output_text=json.dumps(
                    {
                        "diagnosis": "The formula uses only one coordinate.",
                        "misconception": "A diagonal is not one-dimensional.",
                        "answer": "A diagonal distance depends on both coordinate changes.",
                        "debugging_steps": ["Compare both coordinate differences."],
                        "guiding_question": "Which two differences define the segment?",
                        "hint": "Use both axes in the distance calculation.",
                        "next_action": "Trace the helper inputs.",
                    }
                )
            )

    feedback = TutorService(
        Settings(), client=SimpleNamespace(responses=QuestionResponses())
    ).feedback(
        _assignment(),
        _submission(),
        student_question="Why does a diagonal need both coordinates?",
    )

    payload = json.loads(captured["input"])
    assert payload["student_question"] == (
        "Why does a diagonal need both coordinates?"
    )
    assert feedback.answer == (
        "A diagonal distance depends on both coordinate changes."
    )
    assert feedback.source == "openai"


def test_tutor_payload_strips_non_allowlisted_grader_evidence():
    captured = {}

    class EvidenceResponses:
        @staticmethod
        def create(**kwargs):
            captured.update(kwargs)
            return SimpleNamespace(
                output_text=json.dumps(
                    {
                        "diagnosis": "The public check needs attention.",
                        "misconception": "",
                        "answer": "",
                        "debugging_steps": ["Trace the visible input."],
                        "guiding_question": "Which visible value differs?",
                        "hint": "Inspect the public evidence.",
                        "next_action": "Compare one visible value.",
                    }
                )
            )

    submission = _submission()
    submission.evidence["grader_config"] = {"expected_values": {"answer": 42}}
    submission.evidence["tests"][0].update(
        {
            "visibility": "hidden",
            "expected_value": 42,
            "test_source": "assert answer == 42",
        }
    )
    TutorService(
        Settings(), client=SimpleNamespace(responses=EvidenceResponses())
    ).feedback(_assignment(), submission)

    payload = json.loads(captured["input"])
    serialized = json.dumps(payload)
    assert "grader_config" not in serialized
    assert "expected_value" not in serialized
    assert "test_source" not in serialized
    assert "assert answer == 42" not in serialized
    assert payload["visible_evidence"]["tests"] == [
        {
            "label": "Check answer",
            "passed": False,
            "message": "Recheck how answer is calculated.",
        }
    ]
