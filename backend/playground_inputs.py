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


PARAMETER_KINDS = ("point", "number", "integer", "list_of_points", "angle_map", "text")

_KIND_HINTS = {
    "point": "a point with two numbers, like (2.0, 1.0)",
    "number": "a number, like 1.5",
    "integer": "a whole number, like 5",
    "list_of_points": "a list of points, like [(7.5, 4.5), (8.5, 4.5)]",
    "angle_map": "a map of whole-number angles to distances, like {0: 10, 90: 8}",
    "text": "text in quotes, like 'Main Elevator'",
}


def _is_number(value) -> bool:
    return (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and isfinite(value)
    )


def _is_point(value) -> bool:
    return (
        isinstance(value, (list, tuple))
        and len(value) == 2
        and all(_is_number(item) for item in value)
    )


def matches_parameter_kind(kind: str, value) -> bool:
    """Whether a parsed literal has the shape a parameter kind expects."""
    if kind == "point":
        return _is_point(value)
    if kind == "number":
        return _is_number(value)
    if kind == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if kind == "list_of_points":
        return isinstance(value, (list, tuple)) and all(_is_point(item) for item in value)
    if kind == "angle_map":
        return isinstance(value, dict) and all(
            isinstance(key, int) and not isinstance(key, bool) and _is_number(item)
            for key, item in value.items()
        )
    if kind == "text":
        return isinstance(value, str)
    return False


def parameter_kind_hint(kind: str) -> str:
    return _KIND_HINTS.get(kind, "a Python value")


def parameter_problems(arguments: list, parameters: list[dict]) -> list[dict]:
    """Describe inputs that do not match the declared parameters.

    Returns entries of {"parameter_index": int | None, "message": str}; an
    empty list means every input has the expected shape.
    """
    if not parameters:
        return []
    if len(arguments) != len(parameters):
        names = ", ".join(str(item.get("name", "")) for item in parameters)
        return [
            {
                "parameter_index": None,
                "message": (
                    f"Enter {len(parameters)} inputs, one for each parameter "
                    f"({names}); you entered {len(arguments)}."
                ),
            }
        ]
    problems = []
    for index, (value, parameter) in enumerate(zip(arguments, parameters)):
        kind = str(parameter.get("kind", ""))
        if not matches_parameter_kind(kind, value):
            label = str(parameter.get("label") or parameter.get("name") or f"Input {index + 1}")
            problems.append(
                {
                    "parameter_index": index,
                    "message": f"{label} should be {parameter_kind_hint(kind)}.",
                }
            )
    return problems
