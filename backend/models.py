from datetime import datetime, timezone
from uuid import uuid4

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, JSON, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from database import Base


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


class Assignment(Base):
    __tablename__ = "assignments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    stable_id: Mapped[str] = mapped_column(String(120), unique=True, index=True)
    version: Mapped[int] = mapped_column(Integer, default=1)
    title: Mapped[str] = mapped_column(String(300))
    description: Mapped[str] = mapped_column(Text, default="")
    assignment_html: Mapped[str] = mapped_column(Text, default="")
    starter_code: Mapped[str] = mapped_column(Text, default="")
    language: Mapped[str] = mapped_column(String(50), default="python")
    status: Mapped[str] = mapped_column(String(30), default="draft", index=True)
    learning_objectives: Mapped[list] = mapped_column(JSON, default=list)
    execution_settings: Mapped[dict] = mapped_column(JSON, default=dict)
    public_tests: Mapped[list] = mapped_column(JSON, default=list)
    rubric: Mapped[list] = mapped_column(JSON, default=list)
    misconceptions: Mapped[list] = mapped_column(JSON, default=list)
    tutoring_rules: Mapped[dict] = mapped_column(JSON, default=dict)
    simulation_config: Mapped[dict] = mapped_column(JSON, default=dict)
    asset_manifest: Mapped[list] = mapped_column(JSON, default=list)
    grader_type: Mapped[str] = mapped_column(
        String(80), default="python_variables"
    )
    grader_config: Mapped[dict] = mapped_column(JSON, default=dict)
    solution_html: Mapped[str] = mapped_column(Text, default="")
    reference_solution_path: Mapped[str | None] = mapped_column(
        String(500), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now, onupdate=utc_now
    )

    submissions: Mapped[list["Submission"]] = relationship(
        back_populates="assignment", cascade="all, delete-orphan"
    )


class Submission(Base):
    __tablename__ = "submissions"

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid4())
    )
    assignment_id: Mapped[int] = mapped_column(ForeignKey("assignments.id"), index=True)
    assignment_version: Mapped[int] = mapped_column(Integer)
    student_id: Mapped[str] = mapped_column(String(120), default="anonymous", index=True)
    mode: Mapped[str] = mapped_column(String(20), default="submit")
    code: Mapped[str] = mapped_column(Text)
    execution_succeeded: Mapped[bool] = mapped_column(Boolean, default=False)
    passed: Mapped[bool] = mapped_column(Boolean, default=False)
    score: Mapped[int] = mapped_column(Integer, default=0)
    evidence: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)

    assignment: Mapped[Assignment] = relationship(back_populates="submissions")
    hints: Mapped[list["HintInteraction"]] = relationship(
        back_populates="submission", cascade="all, delete-orphan"
    )


class HintInteraction(Base):
    __tablename__ = "hint_interactions"

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid4())
    )
    submission_id: Mapped[str] = mapped_column(
        ForeignKey("submissions.id"), index=True
    )
    hint_level: Mapped[int] = mapped_column(Integer)
    feedback: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)

    submission: Mapped[Submission] = relationship(back_populates="hints")
