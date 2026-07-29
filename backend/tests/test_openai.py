from hinter import get_one_sentence_hint


def test_hint_falls_back_when_openai_is_unavailable():
    class FailingCompletions:
        def create(self, **kwargs):
            raise RuntimeError("API unavailable")

    client = type(
        "Client",
        (),
        {"chat": type("Chat", (), {"completions": FailingCompletions()})()},
    )()
    hint = get_one_sentence_hint(
        assignment_id="1",
        prompt="Add two numbers.",
        code="answer = 0",
        test_output="Expected 3.",
        client=client,
    )

    assert hint == "Hint unavailable. Please check your logic and try again."
