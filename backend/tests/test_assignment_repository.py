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
        assert [item.version for item in assignments] == [3, 2, 3, 2, 1]
        for assignment in assignments:
            compile(
                assignment.starter_code,
                f"assignment-{assignment.id}-starter.py",
                "exec",
            )

    engine.dispose()
