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
    "assignments",
    "audit_events",
    "auth_sessions",
    "hint_interactions",
    "password_reset_tokens",
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
    engine.dispose()


def test_alembic_adopts_an_existing_v3_schema(tmp_path, monkeypatch):
    database_path = tmp_path / "existing.sqlite"
    engine = build_engine(f"sqlite:///{database_path.as_posix()}")
    Base.metadata.create_all(engine)
    engine.dispose()

    _upgrade(database_path, monkeypatch)

    migrated_engine = build_engine(f"sqlite:///{database_path.as_posix()}")
    assert EXPECTED_TABLES.issubset(
        set(inspect(migrated_engine).get_table_names())
    )
    migrated_engine.dispose()
