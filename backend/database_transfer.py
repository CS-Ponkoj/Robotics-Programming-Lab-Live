"""One-time, lossless transfer of local application data between databases.

The local launcher uses this module only when the managed PostgreSQL database is
empty and no synchronized PostgreSQL backup exists.  The source database is
opened for reading and is never modified or deleted.
"""

from __future__ import annotations

import argparse
import json
from collections.abc import Iterable
from pathlib import Path

from sqlalchemy import MetaData, create_engine, func, inspect, select, text
from sqlalchemy.engine import Connection, Engine

from database import normalize_database_url


APPLICATION_TABLES = (
    "users",
    "assignments",
    "study_sessions",
    "submissions",
    "assignment_activities",
    "hint_interactions",
    "learning_events",
    "auth_sessions",
    "password_reset_tokens",
    "audit_events",
)

# V5.2 added this table after the original SQLite prototype and early local
# PostgreSQL backups already existed.  Treat its absence in a source database
# as an empty table so those backups remain recoverable.  The migrated target
# must still contain the current table through Alembic.
OPTIONAL_LEGACY_SOURCE_TABLES = frozenset({"assignment_activities"})


class DatabaseTransferError(RuntimeError):
    """Raised when a transfer would be incomplete or unsafe."""


def _build_engine(database_url: str) -> Engine:
    return create_engine(normalize_database_url(database_url), pool_pre_ping=True)


def _reflect_application_tables(
    engine: Engine,
    *,
    optional_missing: frozenset[str] = frozenset(),
) -> MetaData:
    available = set(inspect(engine).get_table_names())
    missing = set(APPLICATION_TABLES) - available - optional_missing
    if missing:
        raise DatabaseTransferError(
            "Database schema is incomplete; missing tables: "
            + ", ".join(sorted(missing))
        )
    metadata = MetaData()
    metadata.reflect(
        bind=engine,
        only=[name for name in APPLICATION_TABLES if name in available],
    )
    return metadata


def table_counts(
    engine: Engine,
    *,
    optional_missing: frozenset[str] = frozenset(),
) -> dict[str, int]:
    metadata = _reflect_application_tables(
        engine,
        optional_missing=optional_missing,
    )
    with engine.connect() as connection:
        return {
            table_name: (
                int(
                    connection.execute(
                        select(func.count()).select_from(metadata.tables[table_name])
                    ).scalar_one()
                )
                if table_name in metadata.tables
                else 0
            )
            for table_name in APPLICATION_TABLES
        }


def _batched(rows: list[dict], size: int = 500) -> Iterable[list[dict]]:
    for start in range(0, len(rows), size):
        yield rows[start : start + size]


def _reset_postgresql_sequences(connection: Connection) -> None:
    if connection.dialect.name != "postgresql":
        return
    # assignments.id is currently the only integer auto-incrementing primary key.
    connection.execute(
        text(
            "SELECT setval("
            "pg_get_serial_sequence('assignments', 'id'), "
            "COALESCE((SELECT MAX(id) FROM assignments), 1), "
            "EXISTS(SELECT 1 FROM assignments)"
            ")"
        )
    )


def transfer_database(source_url: str, target_url: str) -> dict[str, object]:
    """Copy every application row into an already-migrated empty database."""

    source_engine = _build_engine(source_url)
    target_engine = _build_engine(target_url)
    try:
        source_metadata = _reflect_application_tables(
            source_engine,
            optional_missing=OPTIONAL_LEGACY_SOURCE_TABLES,
        )
        target_metadata = _reflect_application_tables(target_engine)
        source_counts = table_counts(
            source_engine,
            optional_missing=OPTIONAL_LEGACY_SOURCE_TABLES,
        )
        target_counts = table_counts(target_engine)
        nonempty = {name: count for name, count in target_counts.items() if count}
        if nonempty:
            details = ", ".join(f"{name}={count}" for name, count in nonempty.items())
            raise DatabaseTransferError(
                "Target database is not empty; refusing to merge records: " + details
            )

        with source_engine.connect() as source, target_engine.begin() as target:
            if target.dialect.name == "postgresql":
                target.execute(text("SET CONSTRAINTS ALL DEFERRED"))
            for table_name in APPLICATION_TABLES:
                target_table = target_metadata.tables[table_name]
                source_table = source_metadata.tables.get(table_name)
                rows = (
                    [
                        dict(row)
                        for row in source.execute(select(source_table)).mappings()
                    ]
                    if source_table is not None
                    else []
                )
                for batch in _batched(rows):
                    target.execute(target_table.insert(), batch)
            _reset_postgresql_sequences(target)

        copied_counts = table_counts(target_engine)
        if copied_counts != source_counts:
            raise DatabaseTransferError(
                "Transfer verification failed: source and target row counts differ"
            )
        return {
            "status": "copied",
            "tables": copied_counts,
            "total_rows": sum(copied_counts.values()),
        }
    finally:
        source_engine.dispose()
        target_engine.dispose()


def transfer_database_if_empty(source_url: str, target_url: str) -> dict[str, object]:
    target_engine = _build_engine(target_url)
    try:
        counts = table_counts(target_engine)
    finally:
        target_engine.dispose()
    if any(counts.values()):
        return {
            "status": "skipped_nonempty_target",
            "tables": counts,
            "total_rows": sum(counts.values()),
        }
    return transfer_database(source_url, target_url)


def _sqlite_url(path: Path) -> str:
    return f"sqlite:///{path.resolve().as_posix()}"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Copy an existing SQLite Robotics Lab database to PostgreSQL."
    )
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--sqlite", type=Path)
    source.add_argument("--source-url")
    parser.add_argument("--target-url", required=True)
    parser.add_argument("--report", type=Path)
    parser.add_argument(
        "--if-empty",
        action="store_true",
        help="Skip safely when the target already contains application records.",
    )
    args = parser.parse_args()

    if args.sqlite is not None and not args.sqlite.is_file():
        raise DatabaseTransferError(f"SQLite source does not exist: {args.sqlite}")

    transfer = transfer_database_if_empty if args.if_empty else transfer_database
    source_url = args.source_url or _sqlite_url(args.sqlite)
    result = transfer(source_url, args.target_url)
    serialized = json.dumps(result, indent=2, sort_keys=True)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(serialized + "\n", encoding="utf-8")
    print(serialized)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
