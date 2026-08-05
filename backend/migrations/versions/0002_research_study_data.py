"""Add privacy-safe research sessions, events, and submission links.

Revision ID: 0002_research_study_data
Revises: 0001_v4_baseline
"""
from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0002_research_study_data"
down_revision: str | None = "0001_v4_baseline"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    tables = set(inspector.get_table_names())

    if "study_sessions" not in tables:
        op.create_table(
            "study_sessions",
            sa.Column("id", sa.String(length=36), nullable=False),
            sa.Column("user_id", sa.String(length=36), nullable=False),
            sa.Column("client_session_id", sa.String(length=120), nullable=False),
            sa.Column("participant_code", sa.String(length=120), nullable=True),
            sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("last_active_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("active_seconds", sa.Integer(), nullable=False),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint(
                "user_id",
                "client_session_id",
                name="uq_study_session_user_client",
            ),
        )
        op.create_index(
            op.f("ix_study_sessions_user_id"),
            "study_sessions",
            ["user_id"],
            unique=False,
        )
        op.create_index(
            op.f("ix_study_sessions_client_session_id"),
            "study_sessions",
            ["client_session_id"],
            unique=False,
        )
        op.create_index(
            op.f("ix_study_sessions_participant_code"),
            "study_sessions",
            ["participant_code"],
            unique=False,
        )

    inspector = sa.inspect(bind)
    tables = set(inspector.get_table_names())
    if "learning_events" not in tables:
        op.create_table(
            "learning_events",
            sa.Column("id", sa.String(length=36), nullable=False),
            sa.Column("study_session_id", sa.String(length=36), nullable=False),
            sa.Column("user_id", sa.String(length=36), nullable=False),
            sa.Column("assignment_id", sa.Integer(), nullable=True),
            sa.Column("assignment_version", sa.Integer(), nullable=True),
            sa.Column("event_type", sa.String(length=80), nullable=False),
            sa.Column("event_data", sa.JSON(), nullable=False),
            sa.Column("client_occurred_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.ForeignKeyConstraint(["assignment_id"], ["assignments.id"]),
            sa.ForeignKeyConstraint(["study_session_id"], ["study_sessions.id"]),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
            sa.PrimaryKeyConstraint("id"),
        )
        for column in (
            "study_session_id",
            "user_id",
            "assignment_id",
            "event_type",
            "created_at",
        ):
            op.create_index(
                op.f(f"ix_learning_events_{column}"),
                "learning_events",
                [column],
                unique=False,
            )

    submission_columns = {
        column["name"] for column in sa.inspect(bind).get_columns("submissions")
    }
    missing_submission_columns = {
        "user_id",
        "study_session_id",
    } - submission_columns
    if missing_submission_columns:
        # SQLite requires a table rebuild for foreign-key additions. Alembic
        # batch mode also produces a normal ALTER sequence on PostgreSQL.
        with op.batch_alter_table("submissions") as batch:
            if "user_id" in missing_submission_columns:
                batch.add_column(
                    sa.Column(
                        "user_id",
                        sa.String(length=36),
                        sa.ForeignKey(
                            "users.id", name="fk_submissions_user_id_users"
                        ),
                        nullable=True,
                    )
                )
                batch.create_index(
                    op.f("ix_submissions_user_id"), ["user_id"], unique=False
                )
            if "study_session_id" in missing_submission_columns:
                batch.add_column(
                    sa.Column(
                        "study_session_id",
                        sa.String(length=36),
                        sa.ForeignKey(
                            "study_sessions.id",
                            name="fk_submissions_study_session_id_study_sessions",
                        ),
                        nullable=True,
                    )
                )
                batch.create_index(
                    op.f("ix_submissions_study_session_id"),
                    ["study_session_id"],
                    unique=False,
                )


def downgrade() -> None:
    bind = op.get_bind()
    tables = set(sa.inspect(bind).get_table_names())
    if "submissions" in tables:
        columns = {
            column["name"] for column in sa.inspect(bind).get_columns("submissions")
        }
        if {"study_session_id", "user_id"} & columns:
            # Batch mode safely rebuilds SQLite tables that contain foreign keys;
            # PostgreSQL uses the same migration definition without data loss.
            with op.batch_alter_table("submissions") as batch:
                if "study_session_id" in columns:
                    batch.drop_index(op.f("ix_submissions_study_session_id"))
                    batch.drop_column("study_session_id")
                if "user_id" in columns:
                    batch.drop_index(op.f("ix_submissions_user_id"))
                    batch.drop_column("user_id")
    tables = set(sa.inspect(bind).get_table_names())
    if "learning_events" in tables:
        op.drop_table("learning_events")
    tables = set(sa.inspect(bind).get_table_names())
    if "study_sessions" in tables:
        op.drop_table("study_sessions")
