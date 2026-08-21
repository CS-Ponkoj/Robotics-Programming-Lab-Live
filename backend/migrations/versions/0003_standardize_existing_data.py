"""Standardize assignment, submission, hint, and research data contracts.

Revision ID: 0003_standardize_existing_data
Revises: 0002_research_study_data
"""

from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0003_standardize_existing_data"
down_revision: str | None = "0002_research_study_data"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _column_names(table_name: str) -> set[str]:
    return {
        column["name"]
        for column in sa.inspect(op.get_bind()).get_columns(table_name)
    }


def _check_names(table_name: str) -> set[str]:
    return {
        item["name"]
        for item in sa.inspect(op.get_bind()).get_check_constraints(table_name)
        if item.get("name")
    }


def _add_columns() -> None:
    if "data_schema_version" not in _column_names("assignments"):
        with op.batch_alter_table("assignments") as batch:
            batch.add_column(
                sa.Column(
                    "data_schema_version",
                    sa.Integer(),
                    nullable=False,
                    server_default="1",
                )
            )

    submission_columns = _column_names("submissions")
    if {"data_schema_version", "execution_status"} - submission_columns:
        with op.batch_alter_table("submissions") as batch:
            if "data_schema_version" not in submission_columns:
                batch.add_column(
                    sa.Column(
                        "data_schema_version",
                        sa.Integer(),
                        nullable=False,
                        server_default="1",
                    )
                )
            if "execution_status" not in submission_columns:
                batch.add_column(
                    sa.Column(
                        "execution_status",
                        sa.String(length=40),
                        nullable=False,
                        server_default="execution_error",
                    )
                )

    if "data_schema_version" not in _column_names("hint_interactions"):
        with op.batch_alter_table("hint_interactions") as batch:
            batch.add_column(
                sa.Column(
                    "data_schema_version",
                    sa.Integer(),
                    nullable=False,
                    server_default="1",
                )
            )

    if "data_schema_version" not in _column_names("learning_events"):
        with op.batch_alter_table("learning_events") as batch:
            batch.add_column(
                sa.Column(
                    "data_schema_version",
                    sa.Integer(),
                    nullable=False,
                    server_default="1",
                )
            )


def _backfill_existing_rows() -> None:
    op.execute(
        sa.text(
            "UPDATE submissions SET execution_status = "
            "CASE WHEN execution_succeeded THEN 'completed' "
            "ELSE 'execution_error' END"
        )
    )
    op.execute(
        sa.text(
            "UPDATE learning_events SET assignment_version = NULL "
            "WHERE assignment_id IS NULL"
        )
    )
    op.execute(
        sa.text(
            "UPDATE learning_events SET assignment_version = "
            "(SELECT assignments.version FROM assignments "
            "WHERE assignments.id = learning_events.assignment_id) "
            "WHERE assignment_id IS NOT NULL AND assignment_version IS NULL"
        )
    )


def _create_checks() -> None:
    checks = _check_names("assignments")
    with op.batch_alter_table("assignments") as batch:
        if "ck_assignments_version_positive" not in checks:
            batch.create_check_constraint(
                "ck_assignments_version_positive", "version >= 1"
            )
        if "ck_assignments_data_schema_version_positive" not in checks:
            batch.create_check_constraint(
                "ck_assignments_data_schema_version_positive",
                "data_schema_version >= 1",
            )

    checks = _check_names("submissions")
    with op.batch_alter_table("submissions") as batch:
        if "ck_submissions_assignment_version_positive" not in checks:
            batch.create_check_constraint(
                "ck_submissions_assignment_version_positive",
                "assignment_version >= 1",
            )
        if "ck_submissions_data_schema_version_positive" not in checks:
            batch.create_check_constraint(
                "ck_submissions_data_schema_version_positive",
                "data_schema_version >= 1",
            )
        if "ck_submissions_mode_known" not in checks:
            batch.create_check_constraint(
                "ck_submissions_mode_known", "mode IN ('run', 'submit')"
            )
        if "ck_submissions_execution_status_known" not in checks:
            batch.create_check_constraint(
                "ck_submissions_execution_status_known",
                "execution_status IN ("
                "'completed', 'syntax_error', 'runtime_error', 'timeout', "
                "'rejected', 'grader_unavailable', 'internal_error', "
                "'execution_error')",
            )

    checks = _check_names("hint_interactions")
    with op.batch_alter_table("hint_interactions") as batch:
        if "ck_hint_interactions_data_schema_version_positive" not in checks:
            batch.create_check_constraint(
                "ck_hint_interactions_data_schema_version_positive",
                "data_schema_version >= 1",
            )
        if "ck_hint_interactions_hint_level_positive" not in checks:
            batch.create_check_constraint(
                "ck_hint_interactions_hint_level_positive", "hint_level >= 1"
            )

    checks = _check_names("learning_events")
    with op.batch_alter_table("learning_events") as batch:
        if "ck_learning_events_data_schema_version_positive" not in checks:
            batch.create_check_constraint(
                "ck_learning_events_data_schema_version_positive",
                "data_schema_version >= 1",
            )
        if "ck_learning_events_assignment_version_pair" not in checks:
            batch.create_check_constraint(
                "ck_learning_events_assignment_version_pair",
                "(assignment_id IS NULL AND assignment_version IS NULL) OR "
                "(assignment_id IS NOT NULL AND assignment_version >= 1)",
            )


def upgrade() -> None:
    _add_columns()
    _backfill_existing_rows()
    _create_checks()


def _drop_known_checks(table_name: str, names: tuple[str, ...]) -> None:
    existing = _check_names(table_name)
    with op.batch_alter_table(table_name) as batch:
        for name in names:
            if name in existing:
                batch.drop_constraint(name, type_="check")


def downgrade() -> None:
    _drop_known_checks(
        "learning_events",
        (
            "ck_learning_events_assignment_version_pair",
            "ck_learning_events_data_schema_version_positive",
        ),
    )
    if "data_schema_version" in _column_names("learning_events"):
        with op.batch_alter_table("learning_events") as batch:
            batch.drop_column("data_schema_version")

    _drop_known_checks(
        "hint_interactions",
        (
            "ck_hint_interactions_hint_level_positive",
            "ck_hint_interactions_data_schema_version_positive",
        ),
    )
    if "data_schema_version" in _column_names("hint_interactions"):
        with op.batch_alter_table("hint_interactions") as batch:
            batch.drop_column("data_schema_version")

    _drop_known_checks(
        "submissions",
        (
            "ck_submissions_execution_status_known",
            "ck_submissions_mode_known",
            "ck_submissions_data_schema_version_positive",
            "ck_submissions_assignment_version_positive",
        ),
    )
    submission_columns = _column_names("submissions")
    with op.batch_alter_table("submissions") as batch:
        if "execution_status" in submission_columns:
            batch.drop_column("execution_status")
        if "data_schema_version" in submission_columns:
            batch.drop_column("data_schema_version")

    _drop_known_checks(
        "assignments",
        (
            "ck_assignments_data_schema_version_positive",
            "ck_assignments_version_positive",
        ),
    )
    if "data_schema_version" in _column_names("assignments"):
        with op.batch_alter_table("assignments") as batch:
            batch.drop_column("data_schema_version")
