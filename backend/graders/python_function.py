from __future__ import annotations

from dataclasses import dataclass, field
from math import isclose
import re

from graders.base import GradeResult, safe_error_frames
from playground_inputs import (  # noqa: F401 - re-exported for the API
    MAX_PLAYGROUND_ARGUMENTS,
    PLAYGROUND_INPUT_HELP,
    PlaygroundInputError,
    parse_playground_arguments,
)
from models import Assignment
from sandbox import Sandbox
from schemas import TestEvidence


_FUNCTION_NAME = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")
_WORKER_ERROR = re.compile(r"^([A-Za-z_]\w*) at line \d+ of submission: (.*)$", re.DOTALL)
# Python's own wording for errors that depend only on the student's code.
# Any other message could echo a hidden input, so only its class is shown.
_NAME_MESSAGES = {
    "NameError": re.compile(r"^name '([A-Za-z_]\w*)' is not defined$"),
    "UnboundLocalError": re.compile(
        r"^cannot access local variable '([A-Za-z_]\w*)' where it is not "
        r"associated with a value$"
    ),
}
_FIXED_MESSAGES = {
    "ZeroDivisionError": {
        "division by zero",
        "float division by zero",
        "float floor division by zero",
        "float modulo by zero",
        "integer division or modulo by zero",
        "integer modulo by zero",
    },
    "RecursionError": {"maximum recursion depth exceeded"},
}
# Extra returned values beyond the required count are still shown, up to a bound.
MAX_PLAYGROUND_EXTRA_VALUES = 4


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
    # JSON-safe copy of the parsed inputs so diagrams never re-parse Python.
    arguments: list = field(default_factory=list)


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
            arguments=[playground_json_value(item) for item in arguments],
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
        # Opt-in: a criterion may list positional arguments the function must
        # leave unchanged (for example a dict it should copy before editing).
        unchanged_by_criterion = [
            item.get("unchanged_arguments", []) for item in criteria
        ]
        if any(
            not isinstance(indexes, list)
            or any(not isinstance(index, int) or index < 0 for index in indexes)
            for indexes in unchanged_by_criterion
        ):
            raise ValueError("Invalid python_function grader configuration.")
        unchanged_indexes = sorted(
            {index for indexes in unchanged_by_criterion for index in indexes}
        )

        base_result = self.sandbox.execute(code, [])
        if base_result.get("success") is not True:
            return self._execution_failure(criteria, base_result)

        criterion_passes = [True] * len(criteria)
        failed_case_counts = [0] * len(criteria)
        changed_argument = [False] * len(criteria)
        value_failed = [False] * len(criteria)
        unsupported_values = [False] * len(criteria)
        hidden_execution_failed = False
        hidden_error_type = ""
        hidden_error_message = ""
        hidden_error_frames: list[dict] = []
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
                or any(index >= len(arguments) for index in unchanged_indexes)
            ):
                raise ValueError("Invalid python_function test case configuration.")
            # JSON cannot hold integer-keyed dicts, so configured arguments are
            # stored as (key, value) pairs and passed as the dict students see.
            literals = [repr(value) for value in arguments]
            for index in dict_arguments:
                literals[index] = f"dict({literals[index]})"
            # A watched argument is passed as a named object, then compared with
            # a fresh copy built from the same literal after the call.
            call_arguments = list(literals)
            setup_lines = []
            check_lines = []
            for index in unchanged_indexes:
                setup_lines.append(f"grader_argument_{index} = {literals[index]}")
                call_arguments[index] = f"grader_argument_{index}"
                check_lines.extend(
                    [
                        "try:",
                        f"    grader_unchanged_{index} = True if "
                        f"grader_argument_{index} == {literals[index]} else False",
                        "except:",
                        f"    grader_unchanged_{index} = False",
                    ]
                )
            unchanged_names = [f"grader_unchanged_{index}" for index in unchanged_indexes]
            result_names = [f"grader_value_{index}" for index in range(len(criteria))]
            harness_lines = [
                code,
                "",
                *setup_lines,
                f"grader_values = {function_name}({', '.join(call_arguments)})",
                *check_lines,
                "grader_return_count = len(grader_values)",
                *[
                    f"{name} = grader_values[{index}]"
                    for index, name in enumerate(result_names)
                ],
            ]
            result = self.sandbox.execute(
                "\n".join(harness_lines),
                [*result_names, "grader_return_count", *unchanged_names],
            )
            if result.get("success") is not True:
                hidden_execution_failed = True
                # Share the class, the student's own frames, and only messages
                # that cannot echo a hidden input.
                error_text = str(result.get("error", ""))
                hidden_error_type = error_text.split(" ", 1)[0]
                hidden_error_message = _safe_crash_message(error_text, code)
                hidden_error_frames = _student_frames(result.get("frames"), code)
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
                value_matches = self._matches(actual, expected[index])
                argument_changed = any(
                    actual_values.get(f"grader_unchanged_{argument}") is not True
                    for argument in unchanged_by_criterion[index]
                )
                if argument_changed:
                    changed_argument[index] = True
                if value_matches and not argument_changed:
                    continue
                criterion_passes[index] = False
                failed_case_counts[index] += 1
                if not value_matches:
                    value_failed[index] = True
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
            # A changed input is reported on its own when the values were right.
            only_changed_argument = (
                not passed
                and not hidden_execution_failed
                and changed_argument[index]
                and not value_failed[index]
            )
            message = (
                str(criterion.get("success_feedback", f"{label} is correct."))
                if passed
                else ""
                if only_changed_argument
                else str(
                    criterion.get(
                        "failure_feedback",
                        f"Recheck {label.lower()} and try another test case.",
                    )
                )
            )
            if not passed and not only_changed_argument:
                message += (
                    " This check must work for every input scenario. Use the function "
                    "parameters; correct output for the printed example alone is not enough."
                )
            if not passed and changed_argument[index] and not hidden_execution_failed:
                message = " ".join(
                    part
                    for part in (
                        message,
                        str(
                            criterion.get(
                                "unchanged_feedback",
                                "Your function changed an input it was given. "
                                "Copy the input first and change the copy.",
                            )
                        ),
                    )
                    if part
                )
            reason = self._failure_reason(
                passed=passed,
                execution_failed=hidden_execution_failed,
                unsupported=unsupported_values[index],
                failed_cases=failed_case_counts[index],
                total_cases=len(cases),
            )
            # A tag is grader evidence only when this value was compared and
            # wrong; a crash says nothing about the student's concept.
            tag = str(criterion.get("misconception", "")).strip()
            evidence.append(
                TestEvidence(
                    test_id=str(criterion.get("id", f"criterion-{index + 1}")),
                    label=label,
                    passed=passed,
                    message=message,
                    visibility="hidden",
                    reason=reason,
                    weight=weight,
                    misconception_tag=(
                        tag
                        if tag
                        and value_failed[index]
                        and reason in {"wrong_all_inputs", "wrong_some_inputs"}
                        else None
                    ),
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
                    f" ({hidden_error_type}"
                    + (f": {hidden_error_message}" if hidden_error_message else "")
                    + ")."
                    if hidden_error_type.isidentifier()
                    else "."
                )
            ),
            error_frames=hidden_error_frames,
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
            # Only the student's own run of their code; hidden scenarios
            # never reach this path with frames.
            error_frames=safe_error_frames(result.get("frames")),
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


def playground_json_value(value):
    """Convert a parsed literal into JSON: tuples and sets become lists and
    dictionary keys become strings; other non-JSON values become their repr."""
    if value is None or isinstance(value, (bool, int, float, str)):
        return value
    if isinstance(value, (list, tuple)):
        return [playground_json_value(item) for item in value]
    if isinstance(value, (set, frozenset)):
        return [playground_json_value(item) for item in sorted(value, key=repr)]
    if isinstance(value, dict):
        return {str(key): playground_json_value(item) for key, item in value.items()}
    return repr(value)


def _display_value(value) -> str:
    if isinstance(value, dict) and "unsupported_type" in value:
        return str(value.get("repr", ""))
    return repr(value)


def _student_frames(raw, code: str) -> list[dict]:
    """Frames inside the student's own lines; the grader's call line is dropped."""
    line_count = len(code.splitlines())
    return [
        frame for frame in safe_error_frames(raw) if frame["line"] <= line_count
    ]


def _safe_crash_message(error_text: str, code: str) -> str:
    match = _WORKER_ERROR.match(error_text.strip())
    if not match:
        return ""
    error_type, message = match.group(1), match.group(2).strip()
    pattern = _NAME_MESSAGES.get(error_type)
    if pattern:
        name = pattern.match(message)
        # The name must be one the student wrote, not a value from an input.
        if name and re.search(rf"\b{re.escape(name.group(1))}\b", code):
            return message
        return ""
    return message if message in _FIXED_MESSAGES.get(error_type, set()) else ""
