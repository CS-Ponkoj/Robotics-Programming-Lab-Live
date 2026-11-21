"""Course-quiz attempts record the assessment, answers, and feedback mode.

Revision ID: 0011_quiz_attempt_details
Revises: 0010_feedback_modes

Additive only. Existing rows become topic quizzes ("quiz"), the only kind that
existed; their answers and feedback mode were not recorded, so both stay null.
A pre-test row ("pretest") is a student's single attempt before the lesson.
"""

from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0011_quiz_attempt_details"
down_revision: str | None = "0010_feedback_modes"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

TABLE = "course_quiz_attempts"


def _columns() -> set[str]:
    return {item["name"] for item in sa.inspect(op.get_bind()).get_columns(TABLE)}


def upgrade() -> None:
    columns = _columns()
    if "assessment" not in columns:
        op.add_column(
            TABLE,
            sa.Column("assessment", sa.String(length=20), nullable=False, server_default="quiz"),
        )
    if "feedback_mode" not in columns:
        op.add_column(TABLE, sa.Column("feedback_mode", sa.String(length=20), nullable=True))
    if "answers" not in columns:
        op.add_column(TABLE, sa.Column("answers", sa.JSON(), nullable=True))
    if "data_schema_version" not in columns:
        op.add_column(
            TABLE,
            sa.Column("data_schema_version", sa.Integer(), nullable=False, server_default="1"),
        )
    indexes = {item["name"] for item in sa.inspect(op.get_bind()).get_indexes(TABLE)}
    if "ix_course_quiz_attempts_assessment" not in indexes:
        op.create_index("ix_course_quiz_attempts_assessment", TABLE, ["assessment"])


def downgrade() -> None:
    indexes = {item["name"] for item in sa.inspect(op.get_bind()).get_indexes(TABLE)}
    if "ix_course_quiz_attempts_assessment" in indexes:
        op.drop_index("ix_course_quiz_attempts_assessment", table_name=TABLE)
    columns = _columns()
    for name in ("data_schema_version", "answers", "feedback_mode", "assessment"):
        if name in columns:
            op.drop_column(TABLE, name)
