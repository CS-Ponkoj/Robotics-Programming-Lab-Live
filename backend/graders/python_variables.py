from math import isclose

from graders.base import GradeResult
from models import Assignment
from sandbox import Sandbox
from schemas import TestEvidence


class PythonVariableGrader:
    def __init__(self, sandbox: Sandbox):
        self.sandbox = sandbox

    def run(self, assignment: Assignment, code: str) -> GradeResult:
        result = self.sandbox.execute(code, [])
        success = result.get("success") is True
        evidence = [
            TestEvidence(
                test_id="public-execution",
                label="Program execution",
                passed=success,
                message=(
                    "The program executed successfully."
                    if success
                    else result.get("error", "The program could not be executed.")
                ),
                visibility="public",
            )
        ]
        return GradeResult(
            execution_succeeded=success,
            passed=success,
            score=100 if success else 0,
            code_output=result.get("output", ""),
            execution_error="" if success else result.get("error", ""),
            tested_names=[],
            evidence=evidence,
        )

    def grade(self, assignment: Assignment, code: str) -> GradeResult:
        expected = (assignment.grader_config or {}).get("expected_values", {})
        names = list(expected)
        result = self.sandbox.execute(code, names)
        execution_succeeded = result.get("success") is True
        actual_values = result.get("values", {}) if execution_succeeded else {}
        evidence: list[TestEvidence] = []
        for index, name in enumerate(names):
            found = name in actual_values
            passed = found and self._matches(actual_values[name], expected[name])
            if not found:
                message = f"The value of {name} is not found in the provided namespace"
            elif passed:
                message = f"The value provided for {name} is correct, good work!"
            else:
                message = f"Recheck how {name} is calculated."
            evidence.append(
                TestEvidence(
                    test_id=f"hidden-{index + 1}",
                    label=f"Check {name}",
                    passed=passed,
                    message=message,
                    visibility="hidden",
                )
            )
        if not execution_succeeded and not evidence:
            evidence.append(
                TestEvidence(
                    test_id="hidden-execution",
                    label="Program execution",
                    passed=False,
                    message=result.get("error", "The program could not be executed."),
                    visibility="hidden",
                )
            )
        passed_count = sum(item.passed for item in evidence)
        score = round((passed_count / len(evidence)) * 100) if evidence else 0
        return GradeResult(
            execution_succeeded=execution_succeeded,
            passed=execution_succeeded and bool(evidence) and passed_count == len(evidence),
            score=score,
            code_output=result.get("output", ""),
            execution_error="" if execution_succeeded else result.get("error", ""),
            tested_names=names,
            evidence=evidence,
        )

    @staticmethod
    def _matches(actual, expected) -> bool:
        if isinstance(actual, dict) and "unsupported_type" in actual:
            return False
        if isinstance(actual, (int, float)) and isinstance(expected, (int, float)):
            return isclose(float(actual), float(expected), rel_tol=1e-7, abs_tol=1e-7)
        return actual == expected
