"""Raw NASA-TLX workload survey responses (study RQ6).

Revision ID: 0012_workload_surveys
Revises: 0011_quiz_attempt_details

Additive only: a new table, one row per student per study assignment
version. Ratings are 0-100 in steps of 5 or null when unanswered; higher is
worse on every scale, including performance (0 = good). Downgrade drops the
table, so dump the database before downgrading a deployment with responses.
"""

from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0012_workload_surveys"
down_revision: str | None = "0011_quiz_attempt_details"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

TABLE = "workload_surveys"
RATINGS = (
    "mental_demand", "physical_demand", "temporal_demand",
    "performance", "effort", "frustration",
)


def upgrade() -> None:
    if TABLE in sa.inspect(op.get_bind()).get_table_names():
        return
    op.create_table(
        TABLE,
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("user_id", sa.String(length=36), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("assignment_id", sa.Integer(), nullable=False),
        sa.Column("assignment_version", sa.Integer(), nullable=False),
        sa.Column("feedback_mode", sa.String(length=20), nullable=True),
        sa.Column("final_attempt_id", sa.String(length=36), nullable=True),
        sa.Column("trigger", sa.String(length=30), nullable=False),
        sa.Column("form_version", sa.String(length=20), nullable=False),
        sa.Column("opened_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("submitted_at", sa.DateTime(timezone=True), nullable=False),
        *(sa.Column(name, sa.Integer(), nullable=True) for name in RATINGS),
        sa.Column("data_schema_version", sa.Integer(), nullable=False, server_default="1"),
        sa.UniqueConstraint(
            "user_id", "assignment_id", "assignment_version",
            name="uq_workload_surveys_user_assignment_version",
        ),
        sa.CheckConstraint(
            "assignment_version >= 1",
            name="ck_workload_surveys_assignment_version_positive",
        ),
        *(
            sa.CheckConstraint(
                f"{name} IS NULL OR ({name} BETWEEN 0 AND 100 AND {name} % 5 = 0)",
                name=f"ck_workload_surveys_{name}_scale",
            )
            for name in RATINGS
        ),
    )
    op.create_index("ix_workload_surveys_user_id", TABLE, ["user_id"])
    op.create_index("ix_workload_surveys_assignment_id", TABLE, ["assignment_id"])


def downgrade() -> None:
    if TABLE not in sa.inspect(op.get_bind()).get_table_names():
        return
    op.drop_index("ix_workload_surveys_assignment_id", table_name=TABLE)
    op.drop_index("ix_workload_surveys_user_id", table_name=TABLE)
    op.drop_table(TABLE)
