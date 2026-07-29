from dataclasses import dataclass
from typing import Protocol

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


class AssignmentGrader(Protocol):
    def grade(self, assignment: Assignment, code: str) -> GradeResult:
        ...

    def run(self, assignment: Assignment, code: str) -> GradeResult:
        ...
