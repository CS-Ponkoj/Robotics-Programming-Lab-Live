"""Create or adopt the v4 application schema.

Revision ID: 0001_v4_baseline
Revises:
"""
from typing import Sequence

from alembic import op

from database import Base
import models  # noqa: F401


revision: str = "0001_v4_baseline"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # create_all is intentional for this adoption migration: it creates a fresh
    # schema and safely stamps an existing v3 schema without recreating tables.
    Base.metadata.create_all(bind=op.get_bind())


def downgrade() -> None:
    Base.metadata.drop_all(bind=op.get_bind())
