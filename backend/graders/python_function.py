from __future__ import annotations

from math import isclose
import re

from graders.base import GradeResult
from models import Assignment
from sandbox import Sandbox
from schemas import TestEvidence


_FUNCTION_NAME = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")


class PythonFunctionGrader:
    """Grade a required function against deterministic server-only cases."""

    def __init__(self, sandbox: Sandbox):
        self.sandbox = sandbox

    def run(self, assignment: Assignment, code: str) -> GradeResult:
        return self.grade(assignment, code)

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
                criterion_passes[index] = criterion_passes[index] and self._matches(
                    actual_values.get(name), expected[index]
                )

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
                )
                for index, item in enumerate(criteria)
            ],
        )

    @staticmethod
    def _matches(actual, expected) -> bool:
        if isinstance(actual, dict) and "unsupported_type" in actual:
            return False
        if isinstance(actual, (int, float)) and isinstance(expected, (int, float)):
            return isclose(float(actual), float(expected), rel_tol=1e-7, abs_tol=1e-7)
        return actual == expected
