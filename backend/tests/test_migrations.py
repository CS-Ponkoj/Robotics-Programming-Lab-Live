from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import inspect, select
from sqlalchemy.orm import Session

from config import get_settings
from database import Base, build_engine, normalize_database_url
import models  # noqa: F401


EXPECTED_TABLES = {
    "alembic_version",
    "assignment_activities",
    "assignments",
    "audit_events",
    "auth_sessions",
    "code_drafts",
    "course_quiz_attempts",
    "hint_interactions",
    "learning_events",
    "password_reset_tokens",
    "study_sessions",
    "submissions",
    "users",
}


def _upgrade(database_path: Path, monkeypatch) -> None:
    database_url = f"sqlite:///{database_path.as_posix()}"
    monkeypatch.setenv("DATABASE_URL", database_url)
    get_settings.cache_clear()
    config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
    command.upgrade(config, "head")
    get_settings.cache_clear()


def test_database_url_normalizes_neon_psycopg_driver():
    assert normalize_database_url(
        "postgresql://user:password@example.test/database?sslmode=require"
    ).startswith("postgresql+psycopg://")


def test_alembic_creates_a_fresh_schema(tmp_path, monkeypatch):
    database_path = tmp_path / "fresh.sqlite"
    _upgrade(database_path, monkeypatch)

    engine = build_engine(f"sqlite:///{database_path.as_posix()}")
    assert EXPECTED_TABLES.issubset(set(inspect(engine).get_table_names()))
    with Session(engine) as session:
        assert session.scalar(select(models.Assignment).limit(1)) is None
    assert "data_schema_version" in {
        column["name"] for column in inspect(engine).get_columns("assignments")
    }
    assert {"data_schema_version", "execution_status"}.issubset(
        {
            column["name"]
            for column in inspect(engine).get_columns("submissions")
        }
    )
    engine.dispose()


def test_alembic_upgrades_an_existing_v4_baseline(tmp_path, monkeypatch):
    database_path = tmp_path / "existing.sqlite"
    database_url = f"sqlite:///{database_path.as_posix()}"
    monkeypatch.setenv("DATABASE_URL", database_url)
    get_settings.cache_clear()
    config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
    command.upgrade(config, "head")
    command.downgrade(config, "0001_v4_baseline")

    baseline_engine = build_engine(database_url)
    baseline_tables = set(inspect(baseline_engine).get_table_names())
    baseline_columns = {
        column["name"] for column in inspect(baseline_engine).get_columns("submissions")
    }
    assert "study_sessions" not in baseline_tables
    assert "learning_events" not in baseline_tables
    assert "course_quiz_attempts" not in baseline_tables
    assert "study_session_id" not in baseline_columns
    baseline_engine.dispose()

    command.upgrade(config, "head")
    migrated_engine = build_engine(database_url)
    assert EXPECTED_TABLES.issubset(set(inspect(migrated_engine).get_table_names()))
    migrated_columns = {
        column["name"] for column in inspect(migrated_engine).get_columns("submissions")
    }
    assert {"user_id", "study_session_id"}.issubset(migrated_columns)
    migrated_engine.dispose()
    get_settings.cache_clear()


def test_disposable_database_rollback_and_recovery_rehearsal(tmp_path, monkeypatch):
    database_path = tmp_path / "rollback-rehearsal.sqlite"
    database_url = f"sqlite:///{database_path.as_posix()}"
    monkeypatch.setenv("DATABASE_URL", database_url)
    get_settings.cache_clear()
    config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))

    command.upgrade(config, "head")
    upgraded_engine = build_engine(database_url)
    assert EXPECTED_TABLES.issubset(set(inspect(upgraded_engine).get_table_names()))
    upgraded_engine.dispose()

    command.downgrade(config, "base")
    rolled_back_engine = build_engine(database_url)
    assert set(inspect(rolled_back_engine).get_table_names()) == {"alembic_version"}
    rolled_back_engine.dispose()

    command.upgrade(config, "head")
    recovered_engine = build_engine(database_url)
    assert EXPECTED_TABLES.issubset(set(inspect(recovered_engine).get_table_names()))
    recovered_engine.dispose()
    get_settings.cache_clear()
