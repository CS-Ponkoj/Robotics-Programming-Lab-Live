"""Parse playground inputs as plain Python literals without running code.

Kept free of application imports so data contracts can validate stored
sample inputs with the same parser the playground endpoint uses.
"""

from __future__ import annotations

import ast
from math import isfinite

MAX_PLAYGROUND_ARGUMENTS = 20
PLAYGROUND_INPUT_HELP = (
    "Enter Python values separated by commas, for example (2, 1), 4.5, [1, 2]."
)


class PlaygroundInputError(ValueError):
    """The student's playground inputs are not plain Python literal values."""


def parse_playground_arguments(text: str) -> list:
    """Parse comma-separated literal arguments without evaluating any code."""
    source = text.strip()
    if not source:
        return []
    try:
        call = ast.parse(f"_({source})", mode="eval").body
    except SyntaxError as error:
        raise PlaygroundInputError(PLAYGROUND_INPUT_HELP) from error
    if (
        not isinstance(call, ast.Call)
        or call.keywords
        or any(isinstance(item, ast.Starred) for item in call.args)
    ):
        raise PlaygroundInputError(PLAYGROUND_INPUT_HELP)
    if len(call.args) > MAX_PLAYGROUND_ARGUMENTS:
        raise PlaygroundInputError(
            f"Use at most {MAX_PLAYGROUND_ARGUMENTS} inputs."
        )
    try:
        arguments = [ast.literal_eval(item) for item in call.args]
    except (ValueError, TypeError, SyntaxError, RecursionError) as error:
        raise PlaygroundInputError(
            "Inputs can contain only numbers, text, True, False, None, "
            "tuples, lists, and dictionaries."
        ) from error
    if not _finite_literals(arguments):
        raise PlaygroundInputError("Inputs must use finite numbers.")
    return arguments


def _finite_literals(value) -> bool:
    if isinstance(value, float):
        return isfinite(value)
    if isinstance(value, complex):
        return isfinite(value.real) and isfinite(value.imag)
    if isinstance(value, dict):
        return all(_finite_literals(item) for item in [*value.keys(), *value.values()])
    if isinstance(value, (list, tuple, set, frozenset)):
        return all(_finite_literals(item) for item in value)
    return True
