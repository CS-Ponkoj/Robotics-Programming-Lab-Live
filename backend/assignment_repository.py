import json
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session

from models import Assignment
from schemas import AdminAssignmentPayload, AssignmentStudent


BASE_DIR = Path(__file__).resolve().parent
ASSIGNMENTS_DIR = BASE_DIR / "assignments"
COURSE_MATERIALS = BASE_DIR.parent / "course_materials"
REFERENCE_SOLUTIONS = {
    1: COURSE_MATERIALS
    / "content"
    / "Obstacle Avoidance"
    / "Assignment_Bug_Algorithm"
    / "Scenario_1"
    / "math_question_1_solution.py",
    2: COURSE_MATERIALS
    / "content"
    / "Obstacle Avoidance"
    / "Assignment_Bug_Algorithm"
    / "Scenario_2"
    / "Programing_Question_1_solution.py",
    3: COURSE_MATERIALS
    / "content"
    / "Obstacle Avoidance"
    / "Assignment_OA"
    / "question_1_solution.py",
    4: COURSE_MATERIALS
    / "content"
    / "Obstacle Avoidance"
    / "Assignment_VFH"
    / "question_1_VFH_solution.py",
}


def _default_objectives(title: str) -> list[str]:
    return [
        f"Apply robotics programming concepts in {title}.",
        "Interpret automated test evidence and refine a solution.",
    ]


def _default_rubric(expected_values: dict) -> list[dict]:
    count = max(len(expected_values), 1)
    return [
        {
            "criterion": name,
            "description": f"Calculate {name} correctly.",
            "weight": round(100 / count, 2),
        }
        for name in expected_values
    ]


def _default_misconceptions(expected_values: dict) -> list[dict]:
    return [
        {
            "tag": f"incorrect-{name.replace('_', '-')}",
            "description": f"The learner may be calculating {name} incorrectly.",
        }
        for name in expected_values
    ]


class AssignmentRepository:
    def __init__(self, session: Session):
        self.session = session

    def sync_seed_assignments(self) -> None:
        """Create missing seeds and apply only explicitly newer seed versions."""
        for path in sorted(
            ASSIGNMENTS_DIR.glob("assignment_*.json"),
            key=lambda item: int(item.stem.rsplit("_", 1)[1]),
        ):
            source = json.loads(path.read_text(encoding="utf-8"))
            assignment_id = int(source["id"])
            expected_values = source.get("vals", {})
            reference_path = REFERENCE_SOLUTIONS.get(assignment_id)
            assignment = Assignment(
                id=assignment_id,
                stable_id=source.get(
                    "stable_id", f"robotics-assignment-{assignment_id}"
                ),
                version=int(source.get("version", 1)),
                title=source["title"],
                description=source.get("description", ""),
                assignment_html=source.get("assignment_html", ""),
                starter_code=source.get("starter_code", ""),
                language=source.get("language", "python"),
                status=source.get("status", "published"),
                learning_objectives=source.get(
                    "learning_objectives", _default_objectives(source["title"])
                ),
                execution_settings=source.get(
                    "execution_settings",
                    {
                        "runtime": "python3.11",
                        "timeout_seconds": 5,
                        "allowed_imports": ["math", "numpy", "scipy"],
                    },
                ),
                public_tests=source.get(
                    "public_tests",
                    [
                        {
                            "id": "syntax",
                            "label": "Program executes without an error",
                        }
                    ],
                ),
                rubric=source.get("rubric", _default_rubric(expected_values)),
                misconceptions=source.get(
                    "common_misconceptions",
                    _default_misconceptions(expected_values),
                ),
                tutoring_rules=source.get(
                    "tutoring_rules",
                    {
                        "max_hint_level": 4,
                        "start_with_question": True,
                        "never_reveal_solution": True,
                        "tone": "encouraging and concise",
                    },
                ),
                simulation_config=source.get(
                    "simulation_config",
                    {"enabled": False, "provider": None, "scenario": None},
                ),
                asset_manifest=source.get("asset_manifest", []),
                grader_type=source.get("grader_type", "python_variables"),
                grader_config={"expected_values": expected_values},
                solution_html=source.get("solution_html", ""),
                reference_solution_path=(
                    str(reference_path.relative_to(BASE_DIR.parent))
                    if reference_path and reference_path.is_file()
                    else None
                ),
            )
            current = self.session.get(Assignment, assignment_id)
            if current is None:
                self.session.add(assignment)
                continue
            if assignment.version <= current.version:
                continue
            for field in (
                "stable_id",
                "version",
                "title",
                "description",
                "assignment_html",
                "starter_code",
                "language",
                "status",
                "learning_objectives",
                "execution_settings",
                "public_tests",
                "rubric",
                "misconceptions",
                "tutoring_rules",
                "simulation_config",
                "asset_manifest",
                "grader_type",
                "grader_config",
                "solution_html",
                "reference_solution_path",
            ):
                setattr(current, field, getattr(assignment, field))
        self.session.commit()

    def list_published(self) -> list[Assignment]:
        return list(
            self.session.scalars(
                select(Assignment)
                .where(Assignment.status == "published")
                .order_by(Assignment.id)
            )
        )

    def list_all(self) -> list[Assignment]:
        return list(self.session.scalars(select(Assignment).order_by(Assignment.id)))

    def get(self, assignment_id: int, include_drafts: bool = False) -> Assignment | None:
        statement = select(Assignment).where(Assignment.id == assignment_id)
        if not include_drafts:
            statement = statement.where(Assignment.status == "published")
        return self.session.scalar(statement)

    def create(self, payload: AdminAssignmentPayload) -> Assignment:
        values = payload.model_dump(exclude={"id"})
        assignment = Assignment(**values)
        if payload.id is not None:
            assignment.id = payload.id
        self.session.add(assignment)
        self.session.commit()
        self.session.refresh(assignment)
        return assignment

    def update(
        self, assignment: Assignment, payload: AdminAssignmentPayload
    ) -> Assignment:
        values = payload.model_dump(exclude={"id", "version", "status"})
        content_fields = {
            "title",
            "description",
            "assignment_html",
            "starter_code",
            "language",
            "learning_objectives",
            "execution_settings",
            "public_tests",
            "rubric",
            "misconceptions",
            "tutoring_rules",
            "simulation_config",
            "asset_manifest",
            "grader_type",
            "grader_config",
            "solution_html",
            "reference_solution_path",
        }
        changed = any(getattr(assignment, name) != values[name] for name in content_fields)
        for name, value in values.items():
            setattr(assignment, name, value)
        if changed:
            assignment.version += 1
            assignment.status = "draft"
        elif payload.status == "archived":
            assignment.status = "archived"
        self.session.commit()
        self.session.refresh(assignment)
        return assignment


def to_student_assignment(assignment: Assignment) -> AssignmentStudent:
    return AssignmentStudent(
        id=assignment.id,
        stable_id=assignment.stable_id,
        version=assignment.version,
        title=assignment.title,
        description=assignment.description,
        assignment_html=assignment.assignment_html,
        starter_code=assignment.starter_code,
        language=assignment.language,
        learning_objectives=assignment.learning_objectives or [],
        public_tests=assignment.public_tests or [],
        rubric=assignment.rubric or [],
        simulation_config=assignment.simulation_config or {},
        has_solution=bool(assignment.solution_html),
        solution_html="",
        vals={},
    )


def to_admin_payload(assignment: Assignment) -> AdminAssignmentPayload:
    return AdminAssignmentPayload(
        id=assignment.id,
        stable_id=assignment.stable_id,
        version=assignment.version,
        title=assignment.title,
        description=assignment.description,
        assignment_html=assignment.assignment_html,
        starter_code=assignment.starter_code,
        language=assignment.language,
        status=assignment.status,
        learning_objectives=assignment.learning_objectives or [],
        execution_settings=assignment.execution_settings or {},
        public_tests=assignment.public_tests or [],
        rubric=assignment.rubric or [],
        misconceptions=assignment.misconceptions or [],
        tutoring_rules=assignment.tutoring_rules or {},
        simulation_config=assignment.simulation_config or {},
        asset_manifest=assignment.asset_manifest or [],
        grader_type=assignment.grader_type,
        grader_config=assignment.grader_config or {},
        solution_html=assignment.solution_html,
        reference_solution_path=assignment.reference_solution_path,
    )
