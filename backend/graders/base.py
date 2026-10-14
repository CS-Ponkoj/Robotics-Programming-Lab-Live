import re
from dataclasses import dataclass, field
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
    # The student's own call stack when their code raised, outermost first.
    error_frames: list[dict] = field(default_factory=list)

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


_FRAME_NAME = re.compile(r"^(<module>|[A-Za-z_][A-Za-z0-9_]{0,79})$")


def safe_error_frames(raw) -> list[dict]:
    """Keep only well-formed student frames: a line number and a name."""
    if not isinstance(raw, list):
        return []
    frames = []
    for item in raw[-20:]:
        if not isinstance(item, dict):
            continue
        line, name = item.get("line"), item.get("name")
        if (
            isinstance(line, int)
            and not isinstance(line, bool)
            and 1 <= line <= 100_000
            and isinstance(name, str)
            and _FRAME_NAME.fullmatch(name)
        ):
            frames.append({"line": line, "name": name})
    return frames
