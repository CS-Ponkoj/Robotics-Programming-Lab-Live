from pathlib import Path

import pytest
from sqlalchemy import create_engine, select

from database import Base
from database_transfer import (
    DatabaseTransferError,
    table_counts,
    transfer_database,
    transfer_database_if_empty,
)
from models import Assignment, Submission, User


def _database_url(path: Path) -> str:
    return f"sqlite:///{path.as_posix()}"


def _create_database(path: Path) -> str:
    database_url = _database_url(path)
    engine = create_engine(database_url)
    Base.metadata.create_all(engine)
    engine.dispose()
    return database_url


def test_transfer_database_copies_all_rows_and_relationships(tmp_path):
    source_url = _create_database(tmp_path / "source.db")
    target_url = _create_database(tmp_path / "target.db")
    source = create_engine(source_url)
    with source.begin() as connection:
        connection.execute(
            User.__table__.insert(),
            {
                "id": "user-1",
                "login_id": "student-one",
                "password_hash": "hashed",
                "role": "student",
                "is_active": True,
                "is_demo": False,
                "must_change_password": False,
            },
        )
        assignment_id = connection.execute(
            Assignment.__table__.insert().returning(Assignment.id),
            {
                "stable_id": "transfer-assignment",
                "version": 3,
                "title": "Transfer test",
                "status": "published",
            },
        ).scalar_one()
        connection.execute(
            Submission.__table__.insert(),
            {
                "id": "submission-1",
                "assignment_id": assignment_id,
                "assignment_version": 3,
                "student_id": "student-one",
                "user_id": "user-1",
                "mode": "submit",
                "code": "answer = 1",
                "execution_succeeded": True,
                "execution_status": "completed",
                "passed": True,
                "score": 100,
                "evidence": {"checks": [True]},
            },
        )
    source.dispose()

    result = transfer_database(source_url, target_url)

    assert result["status"] == "copied"
    assert result["total_rows"] == 3
    assert table_counts(create_engine(target_url))["submissions"] == 1
    target = create_engine(target_url)
    with target.connect() as connection:
        submission = connection.execute(select(Submission.__table__)).mappings().one()
        assert submission["assignment_version"] == 3
        assert submission["evidence"] == {"checks": [True]}
    target.dispose()


def test_transfer_database_refuses_to_merge_into_nonempty_target(tmp_path):
    source_url = _create_database(tmp_path / "source.db")
    target_url = _create_database(tmp_path / "target.db")
    target = create_engine(target_url)
    with target.begin() as connection:
        connection.execute(
            User.__table__.insert(),
            {
                "id": "existing-user",
                "login_id": "existing",
                "password_hash": "hashed",
                "role": "student",
                "is_active": True,
                "is_demo": False,
                "must_change_password": False,
            },
        )
    target.dispose()

    with pytest.raises(DatabaseTransferError, match="Target database is not empty"):
        transfer_database(source_url, target_url)


def test_transfer_database_if_empty_preserves_existing_target(tmp_path):
    source_url = _create_database(tmp_path / "source.db")
    target_url = _create_database(tmp_path / "target.db")
    target = create_engine(target_url)
    with target.begin() as connection:
        connection.execute(
            User.__table__.insert(),
            {
                "id": "existing-user",
                "login_id": "existing",
                "password_hash": "hashed",
                "role": "student",
                "is_active": True,
                "is_demo": False,
                "must_change_password": False,
            },
        )
    target.dispose()

    result = transfer_database_if_empty(source_url, target_url)

    assert result["status"] == "skipped_nonempty_target"
    assert result["tables"]["users"] == 1
