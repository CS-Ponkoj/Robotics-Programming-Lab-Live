import re

from graders.base import GradeResult
from models import Assignment
from ros2_executor import Ros2Executor
from ros2_feedback import Finding, classify
from schemas import TestEvidence

_NOT_RUN_STATUSES = {"not_run", "not-run", "not_checked", "skipped"}


def _not_run(item: dict) -> bool:
    """Whether a harness result marks its check as not run."""
    return (
        item.get("not_run") is True
        or item.get("skipped") is True
        or item.get("run") is False
        or str(item.get("status", "")).casefold() in _NOT_RUN_STATUSES
        or str(item.get("reason", "")).casefold() in _NOT_RUN_STATUSES
    )


def _sentences(text: str) -> list[str]:
    return [part.strip() for part in re.split(r"(?<=[.!?])\s+", text) if part.strip()]


def _normalized(text: str) -> str:
    return re.sub(r"[^a-z0-9.+-]+", " ", text.casefold()).strip()


def _new_sentences(finding: Finding, message: str) -> str:
    """The observation without anything the check message already says."""
    if finding.unless_message_has and finding.unless_message_has.casefold() in message.casefold():
        return ""
    said = _normalized(message)
    return " ".join(
        sentence for sentence in _sentences(finding.observation)
        if _normalized(sentence) not in said
    )


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
        evidence = self._with_findings(
            assignment, self._evidence(assignment, result), result, config
        )
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
                        + " Not credited yet: this counts once your robot passes"
                        " at least one driving check."
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
        # Open-structure tasks: a failed gate test (imports, entry point,
        # build, start) scores 0, and passing is decided by the listed tests
        # only, so style points never decide whether the task is passed.
        outcome = {item.test_id: item.passed for item in evidence}
        gate = [str(test_id) for test_id in config.get("gate_tests", [])]
        if gate and not all(outcome.get(test_id, False) for test_id in gate):
            score = 0
        required = [str(test_id) for test_id in config.get("pass_tests", [])]
        if required:
            passed = execution_succeeded and all(
                outcome.get(test_id, False) for test_id in gate + required
            )
        else:
            passed = execution_succeeded and bool(evidence) and all(
                item.passed for item in evidence
            )
        return GradeResult(
            execution_succeeded=execution_succeeded,
            passed=passed,
            score=score,
            code_output=result.get("output", ""),
            execution_error="" if execution_succeeded else result.get("error", ""),
            tested_names=[item.test_id for item in evidence],
            evidence=evidence,
        )

    @staticmethod
    def _with_findings(
        assignment: Assignment,
        evidence: list[TestEvidence],
        result: dict,
        config: dict,
    ) -> list[TestEvidence]:
        """Add what the robot did to each failed check, and its hint key.

        Only a tag the assignment configures becomes a misconception label;
        other observed patterns select hints but are not research labels.
        """
        reported = {
            str(item.get("id"))
            for item in result.get("tests", [])
            if isinstance(item, dict) and item.get("id") and not _not_run(item)
        }
        # A check the grader did not run (or did not report) is not evidence
        # of anything, so it neither gets a finding nor shapes another one.
        passed = {
            item.test_id: item.passed
            or item.test_id not in reported
            or item.reason == "not_checked"
            for item in evidence
        }
        findings = classify(
            str(config.get("harness", "")), passed, result.get("observations")
        )
        configured = {
            str(item.get("tag"))
            for item in (assignment.misconceptions or [])
            if isinstance(item, dict) and item.get("tag")
        }
        updated = []
        for item in evidence:
            finding = findings.get(item.test_id)
            if (
                finding is None
                and item.test_id == "returns-node"
                and not item.passed
                and "returned None" in item.message
            ):
                finding = Finding("build-node-returns-none", "")
            if item.passed or passed.get(item.test_id) or finding is None:
                updated.append(item)
                continue
            message = item.message
            observation = _new_sentences(finding, message)
            if observation:
                message = f"{message} {observation}"
            updated.append(
                item.model_copy(
                    update={
                        "message": message,
                        "hint_key": finding.hint_key,
                        "misconception_tag": (
                            finding.hint_key if finding.hint_key in configured else None
                        ),
                    }
                )
            )
        return updated

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
