"""Course-wide instructor settings (AI tutor switch, Old assignments).

Revision ID: 0009_course_settings
Revises: 0008_session_device
"""

from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0009_course_settings"
down_revision: str | None = "0008_session_device"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    if "course_settings" in sa.inspect(op.get_bind()).get_table_names():
        return
    op.create_table(
        "course_settings",
        sa.Column("key", sa.String(length=64), primary_key=True),
        sa.Column("value", sa.JSON(), nullable=False),
        sa.Column(
            "updated_by_user_id",
            sa.String(length=36),
            sa.ForeignKey("users.id"),
            nullable=True,
        ),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )


def downgrade() -> None:
    if "course_settings" in sa.inspect(op.get_bind()).get_table_names():
        op.drop_table("course_settings")
