from __future__ import annotations

import ast
from dataclasses import dataclass, field
from math import isclose, isfinite
import re

from graders.base import GradeResult
from models import Assignment
from sandbox import Sandbox
from schemas import TestEvidence


_FUNCTION_NAME = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")
MAX_PLAYGROUND_ARGUMENTS = 20
# Extra returned values beyond the required count are still shown, up to a bound.
MAX_PLAYGROUND_EXTRA_VALUES = 4
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


@dataclass
class PlaygroundOutcome:
    success: bool
    call: str
    output: str
    error: str
    returned: str = ""
    return_count: int | None = None
    expected_return_count: int = 0
    values: list[dict] = field(default_factory=list)


class PythonFunctionGrader:
    """Grade a required function against deterministic server-only cases."""

    def __init__(self, sandbox: Sandbox):
        self.sandbox = sandbox

    def run(self, assignment: Assignment, code: str) -> GradeResult:
        return self.grade(assignment, code)

    def try_arguments(
        self, assignment: Assignment, code: str, arguments: list
    ) -> PlaygroundOutcome:
        """Call the student's function with their own inputs; never grade."""
        config = assignment.grader_config or {}
        function_name = str(config.get("function_name", ""))
        criteria = config.get("criteria", [])
        if not _FUNCTION_NAME.fullmatch(function_name) or not isinstance(criteria, list):
            raise ValueError("Invalid python_function grader configuration.")
        labels = [
            str(item.get("label", item.get("id", f"Value {index + 1}")))
            for index, item in enumerate(criteria)
        ]
        call_text = f"{function_name}({', '.join(repr(item) for item in arguments)})"
        value_names = [
            f"playground_value_{index}"
            for index in range(len(labels) + MAX_PLAYGROUND_EXTRA_VALUES)
        ]
        harness_lines = [
            code,
            "",
            f"playground_raw = {function_name}(*{tuple(arguments)!r})",
            "try:",
            "    playground_return_count = len(playground_raw)",
            "except:",
            "    playground_return_count = None",
        ]
        for index, name in enumerate(value_names):
            harness_lines.extend(
                [
                    "try:",
                    f"    {name} = playground_raw[{index}]",
                    "except:",
                    f"    {name} = None",
                ]
            )
        result = self.sandbox.execute(
            "\n".join(harness_lines),
            ["playground_raw", "playground_return_count", *value_names],
        )
        outcome = PlaygroundOutcome(
            success=result.get("success") is True,
            call=call_text,
            output=str(result.get("output", "")),
            error=str(result.get("error", "")),
            expected_return_count=len(labels),
        )
        if not outcome.success:
            return outcome
        values = result.get("values", {})
        raw = values.get("playground_raw")
        outcome.returned = _display_value(raw)
        is_sequence = isinstance(raw, dict) and raw.get("unsupported_type") in {
            "tuple",
            "list",
        }
        count = values.get("playground_return_count")
        if not is_sequence or not isinstance(count, int):
            return outcome
        outcome.return_count = count
        for index, name in enumerate(value_names[:count]):
            label = labels[index] if index < len(labels) else f"Extra value {index + 1}"
            value = values.get(name)
            # Python's own spelling keeps 0.0 distinct from 0 in the browser.
            outcome.values.append(
                {"label": label, "value": value, "display": _display_value(value)}
            )
        return outcome

    def grade(self, assignment: Assignment, code: str) -> GradeResult:
        config = assignment.grader_config or {}
        function_name = str(config.get("function_name", ""))
        criteria = config.get("criteria", [])
        cases = config.get("cases", [])
        if (
            not _FUNCTION_NAME.fullmatch(function_name)
            or not isinstance(criteria, list)
            or not criteria
            or not isinstance(cases, list)
            or not cases
        ):
            raise ValueError("Invalid python_function grader configuration.")

        base_result = self.sandbox.execute(code, [])
        if base_result.get("success") is not True:
            return self._execution_failure(criteria, base_result)

        criterion_passes = [True] * len(criteria)
        failed_case_counts = [0] * len(criteria)
        unsupported_values = [False] * len(criteria)
        hidden_execution_failed = False
        hidden_error_type = ""
        for case in cases:
            arguments = case.get("arguments", [])
            expected = case.get("expected", [])
            dict_arguments = case.get("dict_arguments", [])
            if (
                not isinstance(arguments, list)
                or len(expected) != len(criteria)
                or not isinstance(dict_arguments, list)
                or any(
                    not isinstance(index, int) or not 0 <= index < len(arguments)
                    for index in dict_arguments
                )
            ):
                raise ValueError("Invalid python_function test case configuration.")
            # JSON cannot hold integer-keyed dicts, so configured arguments are
            # stored as (key, value) pairs and passed as the dict students see.
            literals = [repr(value) for value in arguments]
            for index in dict_arguments:
                literals[index] = f"dict({literals[index]})"
            result_names = [f"grader_value_{index}" for index in range(len(criteria))]
            harness_lines = [
                code,
                "",
                f"grader_values = {function_name}({', '.join(literals)})",
                "grader_return_count = len(grader_values)",
                *[
                    f"{name} = grader_values[{index}]"
                    for index, name in enumerate(result_names)
                ],
            ]
            result = self.sandbox.execute(
                "\n".join(harness_lines), [*result_names, "grader_return_count"]
            )
            if result.get("success") is not True:
                hidden_execution_failed = True
                # Share only the exception class; its message could echo inputs.
                hidden_error_type = str(result.get("error", "")).split(" ", 1)[0]
                criterion_passes = [False] * len(criteria)
                break
            actual_values = result.get("values", {})
            if actual_values.get("grader_return_count") != len(criteria):
                return self._execution_failure(criteria, {
                    "output": base_result.get("output", ""),
                    "error": f"Return exactly {len(criteria)} values in the required order.",
                })
            for index, name in enumerate(result_names):
                actual = actual_values.get(name)
                if self._matches(actual, expected[index]):
                    continue
                criterion_passes[index] = False
                failed_case_counts[index] += 1
                if isinstance(actual, dict) and "unsupported_type" in actual:
                    unsupported_values[index] = True

        evidence = []
        earned_weight = 0.0
        total_weight = 0.0
        for index, criterion in enumerate(criteria):
            weight = float(criterion.get("weight", 1))
            total_weight += weight
            passed = criterion_passes[index]
            if passed:
                earned_weight += weight
            label = str(criterion.get("label", criterion.get("id", "Criterion")))
            message = (
                str(criterion.get("success_feedback", f"{label} is correct."))
                if passed
                else str(
                    criterion.get(
                        "failure_feedback",
                        f"Recheck {label.lower()} and try another test case.",
                    )
                )
            )
            if not passed:
                message += (
                    " This check must work for every input scenario. Use the function "
                    "parameters; correct output for the printed example alone is not enough."
                )
            evidence.append(
                TestEvidence(
                    test_id=str(criterion.get("id", f"criterion-{index + 1}")),
                    label=label,
                    passed=passed,
                    message=message,
                    visibility="hidden",
                    reason=self._failure_reason(
                        passed=passed,
                        execution_failed=hidden_execution_failed,
                        unsupported=unsupported_values[index],
                        failed_cases=failed_case_counts[index],
                        total_cases=len(cases),
                    ),
                    weight=weight,
                )
            )

        score = round((earned_weight / total_weight) * 100) if total_weight else 0
        execution_succeeded = not hidden_execution_failed
        return GradeResult(
            execution_succeeded=execution_succeeded,
            passed=execution_succeeded and all(criterion_passes),
            score=score,
            code_output=base_result.get("output", ""),
            execution_error=(
                ""
                if execution_succeeded
                else "The required function could not complete every grading scenario"
                + (
                    f" ({hidden_error_type})."
                    if hidden_error_type.isidentifier()
                    else "."
                )
            ),
            tested_names=[str(item.get("id", "")) for item in criteria],
            evidence=evidence,
        )

    @staticmethod
    def _execution_failure(criteria: list[dict], result: dict) -> GradeResult:
        return GradeResult(
            execution_succeeded=False,
            passed=False,
            score=0,
            code_output=result.get("output", ""),
            execution_error=result.get("error", "The program could not be executed."),
            tested_names=[str(item.get("id", "")) for item in criteria],
            evidence=[
                TestEvidence(
                    test_id=str(item.get("id", f"criterion-{index + 1}")),
                    label=str(item.get("label", item.get("id", "Criterion"))),
                    passed=False,
                    message=str(
                        item.get(
                            "failure_feedback",
                            "Fix the execution error before checking this criterion.",
                        )
                    ),
                    visibility="hidden",
                    reason="not_checked",
                    weight=float(item.get("weight", 1)),
                )
                for index, item in enumerate(criteria)
            ],
        )

    @staticmethod
    def _failure_reason(
        *,
        passed: bool,
        execution_failed: bool,
        unsupported: bool,
        failed_cases: int,
        total_cases: int,
    ) -> str:
        """Classify a criterion result without exposing any protected case."""
        if passed:
            return "passed"
        if execution_failed:
            return "error_on_some_inputs"
        if unsupported:
            return "unsupported_type"
        if failed_cases >= total_cases:
            return "wrong_all_inputs"
        return "wrong_some_inputs"

    @staticmethod
    def _matches(actual, expected) -> bool:
        if isinstance(actual, dict) and "unsupported_type" in actual:
            return False
        if isinstance(actual, (int, float)) and isinstance(expected, (int, float)):
            return isclose(float(actual), float(expected), rel_tol=1e-7, abs_tol=1e-7)
        return actual == expected


def _display_value(value) -> str:
    if isinstance(value, dict) and "unsupported_type" in value:
        return str(value.get("repr", ""))
    return repr(value)
