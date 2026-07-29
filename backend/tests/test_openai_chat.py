from types import SimpleNamespace
from unittest.mock import Mock

from hinter import get_one_sentence_hint


def test_hint_uses_tutor_prompt_without_a_live_api_call():
    response = SimpleNamespace(
        choices=[
            SimpleNamespace(
                message=SimpleNamespace(content="Check the sign of your result.")
            )
        ]
    )

    create = Mock(return_value=response)
    client = SimpleNamespace(
        chat=SimpleNamespace(completions=SimpleNamespace(create=create))
    )
    hint = get_one_sentence_hint(
        assignment_id="2",
        prompt="Calculate the path length.",
        code="total_path_length = 0",
        test_output="Expected 14.",
        client=client,
    )

    assert hint == "Check the sign of your result."
    request = create.call_args.kwargs
    assert request["model"] == "gpt-4.1-mini"
    assert request["temperature"] == 0.0
    assert request["max_tokens"] == 30
    assert "Provide exactly one concise sentence hint" in request["messages"][0]["content"]
    assert "total_path_length = 0" in request["messages"][1]["content"]
