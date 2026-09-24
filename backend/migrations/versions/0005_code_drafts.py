"""Add version-specific authenticated code drafts.

Revision ID: 0005_code_drafts
Revises: 0004_basic_research_analytics
"""

from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0005_code_drafts"
down_revision: str | None = "0004_basic_research_analytics"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    if "code_drafts" in inspector.get_table_names():
        return
    op.create_table(
        "code_drafts",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("user_id", sa.String(length=36), nullable=False),
        sa.Column("assignment_id", sa.Integer(), nullable=False),
        sa.Column("assignment_version", sa.Integer(), nullable=False),
        sa.Column("code", sa.Text(), nullable=False, server_default=""),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "assignment_version >= 1",
            name="ck_code_drafts_assignment_version_positive",
        ),
        sa.ForeignKeyConstraint(["assignment_id"], ["assignments.id"]),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "assignment_id",
            "assignment_version",
            name="uq_code_draft_user_assignment_version",
        ),
    )
    op.create_index("ix_code_drafts_user_id", "code_drafts", ["user_id"])
    op.create_index(
        "ix_code_drafts_assignment_id", "code_drafts", ["assignment_id"]
    )


def downgrade() -> None:
    if "code_drafts" in sa.inspect(op.get_bind()).get_table_names():
        op.drop_table("code_drafts")
