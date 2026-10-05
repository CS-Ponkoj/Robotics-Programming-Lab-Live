import json
from pathlib import Path

import pytest
from sqlalchemy.orm import sessionmaker

from assignment_repository import AssignmentRepository
from database import Base, build_engine
from models import Assignment


def test_newer_seed_versions_upgrade_existing_local_assignments():
    engine = build_engine("sqlite://")
    Base.metadata.create_all(engine)
    local_session = sessionmaker(bind=engine, expire_on_commit=False)

    with local_session() as session:
        session.add(
            Assignment(
                id=1,
                stable_id="robotics-assignment-1",
                version=1,
                title="Old assignment",
                starter_code="answer =",
                status="published",
            )
        )
        session.commit()

        AssignmentRepository(session).sync_seed_assignments()

        assignments = AssignmentRepository(session).list_all()
        assert [item.version for item in assignments] == [13, 13, 14, 13, 8, 8]
        for assignment in assignments:
            assert assignment.data_schema_version == 1
            assert assignment.execution_settings["runtime"]
            assert assignment.public_tests
            assert assignment.tutoring_rules["ai_enabled_by_default"] is False
            compile(
                assignment.starter_code,
                f"assignment-{assignment.id}-starter.py",
                "exec",
            )

    engine.dispose()


def test_assignment_2_explains_euclidean_distance_and_only_defined_route_points():
    payload = json.loads(
        (Path(__file__).resolve().parents[1] / "assignments/assignment_2.json")
        .read_text(encoding="utf-8")
    )
    instructions = payload["assignment_html"]
    assert "Euclidean distance (straight-line distance between two points)" in instructions
    assert "math.sqrt((x2 - x1)**2 + (y2 - y1)**2)" in instructions
    assert "math.hypot(dx, dy)" in instructions
    assert "direct hit-to-leave distance" in instructions
    assert "C, D" not in instructions
    assert "Do not use the upper boundary or the full obstacle perimeter" in instructions
    namespace = {}
    exec(compile(payload["starter_code"], "assignment-2-starter", "exec"), namespace)
    assert namespace["calculate_distance"]((0, 0), (3, 4)) == pytest.approx(5)
    assert namespace["results"] == (0.0, 0.0, 0.0, 0.0)


def test_assignments_1_through_4_use_instructor_authored_learning_metadata():
    assignments_dir = Path(__file__).resolve().parents[1] / "assignments"

    for assignment_id in range(1, 5):
        payload = json.loads(
            (assignments_dir / f"assignment_{assignment_id}.json").read_text(
                encoding="utf-8"
            )
        )

        assert payload["stable_id"] == f"robotics-assignment-{assignment_id}"
        assert payload["language"] == "python"
        assert payload["status"] == "published"
        assert len(payload["learning_objectives"]) >= 4
        assert not any(
            objective.startswith("Apply robotics programming concepts")
            for objective in payload["learning_objectives"]
        )
        assert payload["public_tests"]
        assert sum(item["weight"] for item in payload["rubric"]) == pytest.approx(
            100
        )
        assert len(payload["common_misconceptions"]) == len(payload["vals"])
        assert not any(
            item["description"].startswith("Calculate ")
            and item["description"].endswith(" correctly.")
            for item in payload["common_misconceptions"]
        )
        assert payload["tutoring_rules"]["ai_enabled_by_default"] is False
        assert payload["tutoring_rules"]["never_reveal_solution"] is True
        assert payload["tutoring_rules"]["never_reveal_hidden_tests"] is True
        # Function assignments draw a playground diagram from student data only.
        assert payload["simulation_config"]["enabled"] is True
        assert payload["simulation_config"]["provider"] == "diagram"
        assert payload["simulation_config"]["diagram"]["view"] in {"route", "polar"}
        assert payload["grader_type"] == "python_function"
        assert payload["grader_config"]["cases"]
        assert payload["reference_solution_path"]
