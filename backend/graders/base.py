from dataclasses import dataclass
from typing import Protocol

from data_contracts import ExecutionStatus, classify_execution_status
from models import Assignment
from schemas import TestEvidence


@dataclass
class GradeResult:
    execution_succeeded: bool
    passed: bool
    score: int
    code_output: str
    execution_error: str
    tested_names: list[str]
    evidence: list[TestEvidence]
    execution_status: ExecutionStatus | None = None

    def __post_init__(self) -> None:
        if self.execution_status is None:
            self.execution_status = classify_execution_status(
                self.execution_succeeded, self.execution_error
            )


class AssignmentGrader(Protocol):
    def grade(self, assignment: Assignment, code: str) -> GradeResult:
        ...

    def run(self, assignment: Assignment, code: str) -> GradeResult:
        ...
