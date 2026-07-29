from types import SimpleNamespace
from hinter import get_one_sentence_hint


def test_hint_strips_surrounding_whitespace():
    response = SimpleNamespace(
        choices=[
            SimpleNamespace(
                message=SimpleNamespace(content="  Recheck the obstacle perimeter.  ")
            )
        ]
    )

    client = SimpleNamespace(
        chat=SimpleNamespace(
            completions=SimpleNamespace(create=lambda **kwargs: response)
        )
    )
    hint = get_one_sentence_hint("2", "Prompt", "code", "failure", client=client)

    assert hint == "Recheck the obstacle perimeter."
