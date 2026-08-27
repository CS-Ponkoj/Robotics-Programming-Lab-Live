"""Add version-specific assignment activity tracking.

Revision ID: 0004_basic_research_analytics
Revises: 0003_standardize_existing_data
"""

from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0004_basic_research_analytics"
down_revision: str | None = "0003_standardize_existing_data"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    submission_columns = {
        column["name"] for column in inspector.get_columns("submissions")
    }
    if "active_seconds_at_attempt" not in submission_columns:
        with op.batch_alter_table("submissions") as batch:
            batch.add_column(
                sa.Column("active_seconds_at_attempt", sa.Integer(), nullable=True)
            )

    inspector = sa.inspect(op.get_bind())
    if "assignment_activities" not in inspector.get_table_names():
        op.create_table(
            "assignment_activities",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("user_id", sa.String(length=36), nullable=False),
        sa.Column("assignment_id", sa.Integer(), nullable=False),
        sa.Column("assignment_version", sa.Integer(), nullable=False),
        sa.Column(
            "data_schema_version",
            sa.Integer(),
            nullable=False,
            server_default="1",
        ),
        sa.Column("first_active_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_active_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "active_seconds", sa.Integer(), nullable=False, server_default="0"
        ),
        sa.Column("first_completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "active_seconds_to_completion", sa.Integer(), nullable=True
        ),
        sa.CheckConstraint(
            "assignment_version >= 1",
            name="ck_assignment_activities_version_positive",
        ),
        sa.CheckConstraint(
            "active_seconds >= 0",
            name="ck_assignment_activities_active_seconds_nonnegative",
        ),
        sa.CheckConstraint(
            "active_seconds_to_completion IS NULL OR "
            "active_seconds_to_completion >= 0",
            name="ck_assignment_activities_completion_seconds_nonnegative",
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "assignment_id",
            "assignment_version",
            name="uq_assignment_activity_user_assignment_version",
        ),
        )

    inspector = sa.inspect(op.get_bind())
    activity_indexes = {
        item["name"] for item in inspector.get_indexes("assignment_activities")
    }
    if "ix_assignment_activities_user_id" not in activity_indexes:
        op.create_index(
            "ix_assignment_activities_user_id",
            "assignment_activities",
            ["user_id"],
        )
    if "ix_assignment_activities_assignment_id" not in activity_indexes:
        op.create_index(
            "ix_assignment_activities_assignment_id",
            "assignment_activities",
            ["assignment_id"],
        )
    submission_indexes = {
        item["name"] for item in inspector.get_indexes("submissions")
    }
    if "ix_submissions_assignment_version_created" not in submission_indexes:
        op.create_index(
            "ix_submissions_assignment_version_created",
            "submissions",
            ["assignment_id", "assignment_version", "created_at"],
        )


def downgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    submission_indexes = {
        item["name"] for item in inspector.get_indexes("submissions")
    }
    if "ix_submissions_assignment_version_created" in submission_indexes:
        op.drop_index(
            "ix_submissions_assignment_version_created", table_name="submissions"
        )
    if "assignment_activities" in inspector.get_table_names():
        op.drop_table("assignment_activities")
    if "active_seconds_at_attempt" in {
        column["name"]
        for column in sa.inspect(op.get_bind()).get_columns("submissions")
    }:
        with op.batch_alter_table("submissions") as batch:
            batch.drop_column("active_seconds_at_attempt")
