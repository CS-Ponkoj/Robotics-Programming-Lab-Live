from datetime import datetime, timezone
from uuid import uuid4

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    JSON,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from database import Base


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


class Assignment(Base):
    __tablename__ = "assignments"
    __table_args__ = (
        CheckConstraint("version >= 1", name="ck_assignments_version_positive"),
        CheckConstraint(
            "data_schema_version >= 1",
            name="ck_assignments_data_schema_version_positive",
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    stable_id: Mapped[str] = mapped_column(String(120), unique=True, index=True)
    version: Mapped[int] = mapped_column(Integer, default=1)
    data_schema_version: Mapped[int] = mapped_column(
        Integer, default=1, server_default="1"
    )
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
    __table_args__ = (
        CheckConstraint(
            "assignment_version >= 1",
            name="ck_submissions_assignment_version_positive",
        ),
        CheckConstraint(
            "data_schema_version >= 1",
            name="ck_submissions_data_schema_version_positive",
        ),
        CheckConstraint(
            "mode IN ('run', 'submit')",
            name="ck_submissions_mode_known",
        ),
        CheckConstraint(
            "execution_status IN ("
            "'completed', 'syntax_error', 'runtime_error', 'timeout', "
            "'rejected', 'grader_unavailable', 'internal_error', 'execution_error'"
            ")",
            name="ck_submissions_execution_status_known",
        ),
        # Created by migration 0004; declared here so autogenerate keeps it.
        Index(
            "ix_submissions_assignment_version_created",
            "assignment_id",
            "assignment_version",
            "created_at",
        ),
    )

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid4())
    )
    assignment_id: Mapped[int] = mapped_column(ForeignKey("assignments.id"), index=True)
    assignment_version: Mapped[int] = mapped_column(Integer)
    data_schema_version: Mapped[int] = mapped_column(
        Integer, default=1, server_default="1"
    )
    student_id: Mapped[str] = mapped_column(String(120), default="anonymous", index=True)
    user_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.id"), nullable=True, index=True
    )
    study_session_id: Mapped[str | None] = mapped_column(
        ForeignKey("study_sessions.id"), nullable=True, index=True
    )
    mode: Mapped[str] = mapped_column(String(20), default="submit")
    code: Mapped[str] = mapped_column(Text)
    execution_succeeded: Mapped[bool] = mapped_column(Boolean, default=False)
    execution_status: Mapped[str] = mapped_column(
        String(40), default="execution_error", server_default="execution_error"
    )
    passed: Mapped[bool] = mapped_column(Boolean, default=False)
    score: Mapped[int] = mapped_column(Integer, default=0)
    active_seconds_at_attempt: Mapped[int | None] = mapped_column(
        Integer, nullable=True
    )
    evidence: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)

    assignment: Mapped[Assignment] = relationship(back_populates="submissions")
    hints: Mapped[list["HintInteraction"]] = relationship(
        back_populates="submission", cascade="all, delete-orphan"
    )


class HintInteraction(Base):
    __tablename__ = "hint_interactions"
    __table_args__ = (
        CheckConstraint(
            "data_schema_version >= 1",
            name="ck_hint_interactions_data_schema_version_positive",
        ),
        CheckConstraint(
            "hint_level >= 1",
            name="ck_hint_interactions_hint_level_positive",
        ),
    )

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid4())
    )
    submission_id: Mapped[str] = mapped_column(
        ForeignKey("submissions.id"), index=True
    )
    hint_level: Mapped[int] = mapped_column(Integer)
    data_schema_version: Mapped[int] = mapped_column(
        Integer, default=1, server_default="1"
    )
    feedback: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)

    submission: Mapped[Submission] = relationship(back_populates="hints")


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid4())
    )
    login_id: Mapped[str] = mapped_column(String(120), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(500))
    role: Mapped[str] = mapped_column(String(30), index=True)
    email: Mapped[str | None] = mapped_column(
        String(320), unique=True, nullable=True, index=True
    )
    participant_code: Mapped[str | None] = mapped_column(
        String(120), nullable=True, index=True
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    is_demo: Mapped[bool] = mapped_column(Boolean, default=False)
    must_change_password: Mapped[bool] = mapped_column(Boolean, default=False)
    created_by: Mapped[str | None] = mapped_column(
        ForeignKey("users.id"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now, onupdate=utc_now
    )
    last_login_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    password_changed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    sessions: Mapped[list["AuthSession"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    reset_tokens: Mapped[list["PasswordResetToken"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    study_sessions: Mapped[list["StudySession"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    learning_events: Mapped[list["LearningEvent"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    assignment_activities: Mapped[list["AssignmentActivity"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    code_drafts: Mapped[list["CodeDraft"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    course_quiz_attempts: Mapped[list["CourseQuizAttempt"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )


class CourseQuizAttempt(Base):
    __tablename__ = "course_quiz_attempts"
    __table_args__ = (
        CheckConstraint("correct_count >= 0", name="ck_course_quiz_correct_nonnegative"),
        CheckConstraint("correct_count <= total_questions", name="ck_course_quiz_correct_bounded"),
        CheckConstraint("total_questions >= 10", name="ck_course_quiz_total_minimum"),
        CheckConstraint("score_percent BETWEEN 0 AND 100", name="ck_course_quiz_score_range"),
    )

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid4())
    )
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    topic_id: Mapped[str] = mapped_column(String(120), index=True)
    quiz_version: Mapped[str] = mapped_column(String(16))
    correct_count: Mapped[int] = mapped_column(Integer)
    total_questions: Mapped[int] = mapped_column(Integer)
    score_percent: Mapped[int] = mapped_column(Integer)
    submitted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)

    user: Mapped[User] = relationship(back_populates="course_quiz_attempts")


class CodeDraft(Base):
    __tablename__ = "code_drafts"
    __table_args__ = (
        CheckConstraint(
            "assignment_version >= 1",
            name="ck_code_drafts_assignment_version_positive",
        ),
        UniqueConstraint(
            "user_id",
            "assignment_id",
            "assignment_version",
            name="uq_code_draft_user_assignment_version",
        ),
    )

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid4())
    )
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    assignment_id: Mapped[int] = mapped_column(
        ForeignKey("assignments.id"), index=True
    )
    assignment_version: Mapped[int] = mapped_column(Integer)
    code: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now, onupdate=utc_now
    )

    user: Mapped[User] = relationship(back_populates="code_drafts")


class StudySession(Base):
    __tablename__ = "study_sessions"
    __table_args__ = (
        UniqueConstraint(
            "user_id", "client_session_id", name="uq_study_session_user_client"
        ),
    )

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid4())
    )
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    client_session_id: Mapped[str] = mapped_column(String(120), index=True)
    participant_code: Mapped[str | None] = mapped_column(
        String(120), nullable=True, index=True
    )
    started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now
    )
    last_active_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now
    )
    ended_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    active_seconds: Mapped[int] = mapped_column(Integer, default=0)

    user: Mapped[User] = relationship(back_populates="study_sessions")
    events: Mapped[list["LearningEvent"]] = relationship(
        back_populates="study_session", cascade="all, delete-orphan"
    )


class AssignmentActivity(Base):
    """Version-specific active-time record for one student and assignment."""

    __tablename__ = "assignment_activities"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "assignment_id",
            "assignment_version",
            name="uq_assignment_activity_user_assignment_version",
        ),
        CheckConstraint(
            "assignment_version >= 1",
            name="ck_assignment_activities_version_positive",
        ),
        CheckConstraint(
            "active_seconds >= 0",
            name="ck_assignment_activities_active_seconds_nonnegative",
        ),
        CheckConstraint(
            "active_seconds_to_completion IS NULL OR "
            "active_seconds_to_completion >= 0",
            name="ck_assignment_activities_completion_seconds_nonnegative",
        ),
    )

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid4())
    )
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    assignment_id: Mapped[int] = mapped_column(Integer, index=True)
    assignment_version: Mapped[int] = mapped_column(Integer)
    data_schema_version: Mapped[int] = mapped_column(
        Integer, default=1, server_default="1"
    )
    first_active_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now
    )
    last_active_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now
    )
    active_seconds: Mapped[int] = mapped_column(Integer, default=0)
    first_completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    active_seconds_to_completion: Mapped[int | None] = mapped_column(
        Integer, nullable=True
    )

    user: Mapped[User] = relationship(back_populates="assignment_activities")


class LearningEvent(Base):
    __tablename__ = "learning_events"
    __table_args__ = (
        CheckConstraint(
            "data_schema_version >= 1",
            name="ck_learning_events_data_schema_version_positive",
        ),
        CheckConstraint(
            "(assignment_id IS NULL AND assignment_version IS NULL) OR "
            "(assignment_id IS NOT NULL AND assignment_version >= 1)",
            name="ck_learning_events_assignment_version_pair",
        ),
    )

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid4())
    )
    study_session_id: Mapped[str] = mapped_column(
        ForeignKey("study_sessions.id"), index=True
    )
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    assignment_id: Mapped[int | None] = mapped_column(
        ForeignKey("assignments.id"), nullable=True, index=True
    )
    assignment_version: Mapped[int | None] = mapped_column(Integer, nullable=True)
    data_schema_version: Mapped[int] = mapped_column(
        Integer, default=1, server_default="1"
    )
    event_type: Mapped[str] = mapped_column(String(80), index=True)
    event_data: Mapped[dict] = mapped_column(JSON, default=dict)
    client_occurred_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now, index=True
    )

    user: Mapped[User] = relationship(back_populates="learning_events")
    study_session: Mapped[StudySession] = relationship(back_populates="events")


class AuthSession(Base):
    __tablename__ = "auth_sessions"

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid4())
    )
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    last_used_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now
    )
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    # phone, tablet, or computer from the sign-in browser; empty when unknown.
    device: Mapped[str | None] = mapped_column(String(20), nullable=True)

    user: Mapped[User] = relationship(back_populates="sessions")


class PasswordResetToken(Base):
    __tablename__ = "password_reset_tokens"

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid4())
    )
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    purpose: Mapped[str] = mapped_column(String(40), default="password_reset")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    used_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    user: Mapped[User] = relationship(back_populates="reset_tokens")


class AuditEvent(Base):
    __tablename__ = "audit_events"

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid4())
    )
    actor_user_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.id"), nullable=True, index=True
    )
    action: Mapped[str] = mapped_column(String(120), index=True)
    resource_type: Mapped[str] = mapped_column(String(80), index=True)
    resource_id: Mapped[str | None] = mapped_column(String(120), nullable=True)
    details: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now
    )


class PageFeedback(Base):
    """A bug report or suggestion sent from the Feedback button on any page."""

    __tablename__ = "page_feedback"
    __table_args__ = (
        CheckConstraint(
            "category IN ('bug', 'suggestion', 'content', 'other')",
            name="ck_page_feedback_category",
        ),
        CheckConstraint(
            "status IN ('new', 'resolved')", name="ck_page_feedback_status"
        ),
        CheckConstraint(
            "sender_role IN ('student', 'instructor', 'demo')",
            name="ck_page_feedback_sender_role",
        ),
    )

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid4())
    )
    # Empty for the public student demo, which has no persistent account.
    user_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.id"), nullable=True, index=True
    )
    sender_role: Mapped[str] = mapped_column(String(20))
    page: Mapped[str] = mapped_column(String(200))
    category: Mapped[str] = mapped_column(String(20))
    message: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(20), default="new", index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now, index=True
    )
    resolved_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
