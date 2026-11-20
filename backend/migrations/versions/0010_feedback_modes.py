"""Per-account feedback mode and the mode each attempt ran under.

Revision ID: 0010_feedback_modes
Revises: 0009_course_settings

Additive only: existing accounts become "tdd", which is what every student
saw before modes existed. Existing attempts keep a null feedback_mode, since
the mode they ran under was not recorded.
"""

from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0010_feedback_modes"
down_revision: str | None = "0009_course_settings"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _columns(table: str) -> set[str]:
    return {item["name"] for item in sa.inspect(op.get_bind()).get_columns(table)}


def upgrade() -> None:
    if "feedback_mode" not in _columns("users"):
        op.add_column(
            "users",
            sa.Column(
                "feedback_mode",
                sa.String(length=20),
                nullable=False,
                server_default="tdd",
            ),
        )
    if "feedback_mode" not in _columns("submissions"):
        op.add_column(
            "submissions",
            sa.Column("feedback_mode", sa.String(length=20), nullable=True),
        )


def downgrade() -> None:
    if "feedback_mode" in _columns("submissions"):
        op.drop_column("submissions", "feedback_mode")
    if "feedback_mode" in _columns("users"):
        op.drop_column("users", "feedback_mode")
