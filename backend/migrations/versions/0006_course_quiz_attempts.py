"""Save student quiz scores separately from graded code submissions.

Revision ID: 0006_course_quiz_attempts
Revises: 0005_code_drafts
"""

from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0006_course_quiz_attempts"
down_revision: str | None = "0005_code_drafts"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    if "course_quiz_attempts" in sa.inspect(op.get_bind()).get_table_names():
        return
    op.create_table(
        "course_quiz_attempts",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("user_id", sa.String(length=36), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("topic_id", sa.String(length=120), nullable=False),
        sa.Column("quiz_version", sa.String(length=16), nullable=False),
        sa.Column("correct_count", sa.Integer(), nullable=False),
        sa.Column("total_questions", sa.Integer(), nullable=False),
        sa.Column("score_percent", sa.Integer(), nullable=False),
        sa.Column("submitted_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("correct_count >= 0", name="ck_course_quiz_correct_nonnegative"),
        sa.CheckConstraint("correct_count <= total_questions", name="ck_course_quiz_correct_bounded"),
        sa.CheckConstraint("total_questions >= 10", name="ck_course_quiz_total_minimum"),
        sa.CheckConstraint("score_percent BETWEEN 0 AND 100", name="ck_course_quiz_score_range"),
    )
    op.create_index("ix_course_quiz_attempts_user_id", "course_quiz_attempts", ["user_id"])
    op.create_index("ix_course_quiz_attempts_topic_id", "course_quiz_attempts", ["topic_id"])


def downgrade() -> None:
    if "course_quiz_attempts" in sa.inspect(op.get_bind()).get_table_names():
        op.drop_table("course_quiz_attempts")
