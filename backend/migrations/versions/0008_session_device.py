"""Record the device category (phone, tablet, computer) of each sign-in.

Revision ID: 0008_session_device
Revises: 0007_page_feedback
"""

from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0008_session_device"
down_revision: str | None = "0007_page_feedback"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _columns() -> set[str]:
    return {
        column["name"]
        for column in sa.inspect(op.get_bind()).get_columns("auth_sessions")
    }


def upgrade() -> None:
    if "device" not in _columns():
        op.add_column(
            "auth_sessions",
            sa.Column("device", sa.String(length=20), nullable=True),
        )


def downgrade() -> None:
    if "device" in _columns():
        with op.batch_alter_table("auth_sessions") as batch:
            batch.drop_column("device")
