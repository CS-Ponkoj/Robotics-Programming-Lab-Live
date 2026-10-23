"""Store bug reports and suggestions sent from the page Feedback button.

Revision ID: 0007_page_feedback
Revises: 0006_course_quiz_attempts
"""

from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0007_page_feedback"
down_revision: str | None = "0006_course_quiz_attempts"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    if "page_feedback" in sa.inspect(op.get_bind()).get_table_names():
        return
    op.create_table(
        "page_feedback",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("user_id", sa.String(length=36), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("sender_role", sa.String(length=20), nullable=False),
        sa.Column("page", sa.String(length=200), nullable=False),
        sa.Column("category", sa.String(length=20), nullable=False),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "category IN ('bug', 'suggestion', 'content', 'other')",
            name="ck_page_feedback_category",
        ),
        sa.CheckConstraint("status IN ('new', 'resolved')", name="ck_page_feedback_status"),
        sa.CheckConstraint(
            "sender_role IN ('student', 'instructor', 'demo')",
            name="ck_page_feedback_sender_role",
        ),
    )
    op.create_index("ix_page_feedback_user_id", "page_feedback", ["user_id"])
    op.create_index("ix_page_feedback_status", "page_feedback", ["status"])
    op.create_index("ix_page_feedback_created_at", "page_feedback", ["created_at"])


def downgrade() -> None:
    if "page_feedback" in sa.inspect(op.get_bind()).get_table_names():
        op.drop_table("page_feedback")
