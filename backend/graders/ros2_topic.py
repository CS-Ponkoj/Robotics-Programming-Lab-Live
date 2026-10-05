from graders.base import GradeResult
from models import Assignment
from ros2_executor import Ros2Executor
from schemas import TestEvidence


class Ros2TopicGrader:
    def __init__(self, executor: Ros2Executor):
        self.executor = executor

    def run(self, assignment: Assignment, code: str) -> GradeResult:
        return self._evaluate(assignment, code)

    def grade(self, assignment: Assignment, code: str) -> GradeResult:
        return self._evaluate(assignment, code)

    def _evaluate(self, assignment: Assignment, code: str) -> GradeResult:
        project_files = [
            item
            for item in (assignment.asset_manifest or [])
            if isinstance(item, dict) and item.get("kind") == "project_file"
        ]
        result = self.executor.execute(
            code,
            project_files,
            assignment.grader_config or {},
        )
        config = assignment.grader_config or {}
        evidence = self._evidence(assignment, result)
        weights = config.get("test_weights", {})
        # Supplied scaffold (build/start) earns credit only once the student's
        # own code passes at least one behavior check; a starter earns 0%.
        scaffold = {str(test_id) for test_id in config.get("scaffold_tests", [])}
        behavior_passed = any(
            item.passed for item in evidence if item.test_id not in scaffold
        )
        if scaffold and not behavior_passed:
            evidence = [
                item.model_copy(
                    update={
                        "message": item.message
                        + " This supplied-scaffold credit counts once your code"
                        " passes at least one behavior check."
                    }
                )
                if item.test_id in scaffold and item.passed
                else item
                for item in evidence
            ]
        total_weight = sum(float(weights.get(item.test_id, 1)) for item in evidence)
        passed_weight = sum(
            float(weights.get(item.test_id, 1))
            for item in evidence
            if item.passed and (behavior_passed or item.test_id not in scaffold)
        )
        if weights:
            # Show each check's points, as function assignments do; held-back
            # scaffold credit is recorded as earning nothing yet.
            evidence = [
                item.model_copy(
                    update={
                        "weight": float(weights.get(item.test_id, 1)),
                        "earned_weight": (
                            0.0
                            if item.passed and item.test_id in scaffold
                            and not behavior_passed
                            else None
                        ),
                    }
                )
                for item in evidence
            ]
        score = round((passed_weight / total_weight) * 100) if total_weight else 0
        execution_succeeded = result.get("success") is True
        return GradeResult(
            execution_succeeded=execution_succeeded,
            passed=execution_succeeded and bool(evidence) and all(
                item.passed for item in evidence
            ),
            score=score,
            code_output=result.get("output", ""),
            execution_error="" if execution_succeeded else result.get("error", ""),
            tested_names=[item.test_id for item in evidence],
            evidence=evidence,
        )

    @staticmethod
    def _evidence(assignment: Assignment, result: dict) -> list[TestEvidence]:
        configured = {
            str(item.get("id")): str(item.get("label", item.get("id", "Test")))
            for item in (assignment.public_tests or [])
            if isinstance(item, dict) and item.get("id")
        }
        returned = {
            str(item.get("id")): item
            for item in result.get("tests", [])
            if isinstance(item, dict) and item.get("id") in configured
        }
        evidence = []
        for test_id, label in configured.items():
            item = returned.get(test_id, {})
            evidence.append(
                TestEvidence(
                    test_id=test_id,
                    label=label,
                    passed=item.get("passed") is True,
                    message=str(
                        item.get(
                            "message",
                            "The grader could not confirm this requirement.",
                        )
                    ),
                    visibility="public",
                )
            )
        if evidence:
            return evidence
        return [
            TestEvidence(
                test_id="ros2-execution",
                label="ROS 2 execution",
                passed=False,
                message=result.get("error", "The ROS 2 grader could not run."),
                visibility="public",
            )
        ]
