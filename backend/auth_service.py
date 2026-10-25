from __future__ import annotations

import hashlib
import secrets
from datetime import datetime, timedelta, timezone

from pwdlib import PasswordHash
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from models import AuthSession, AuditEvent, PasswordResetToken, User, utc_now


password_hasher = PasswordHash.recommended()
# Verified for unknown accounts so login takes the same time either way.
_TIMING_DUMMY_HASH = password_hasher.hash(secrets.token_urlsafe(16))
VALID_ROLES = {"student", "instructor"}


def normalize_login_id(value: str) -> str:
    return value.strip().lower()


def normalize_email(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = value.strip().lower()
    return normalized or None


def normalize_participant_code(value: str | None) -> str | None:
    normalized = (value or "").strip()
    return normalized or None


def hash_password(password: str) -> str:
    return password_hasher.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return password_hasher.verify(password, password_hash)
    except (TypeError, ValueError):
        return False


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def generate_temporary_password() -> str:
    return f"Robot-{secrets.token_hex(3).upper()}-{secrets.token_hex(3).upper()}"


def create_user(
    session: Session,
    *,
    login_id: str,
    password: str,
    role: str,
    email: str | None = None,
    participant_code: str | None = None,
    is_active: bool = True,
    is_demo: bool = False,
    must_change_password: bool = False,
    created_by: str | None = None,
) -> User:
    normalized_login = normalize_login_id(login_id)
    if not normalized_login:
        raise ValueError("Login ID is required.")
    if role not in VALID_ROLES:
        raise ValueError("Role must be student or instructor.")
    normalized_email = normalize_email(email)
    normalized_participant_code = normalize_participant_code(participant_code)
    if session.scalar(select(User).where(User.login_id == normalized_login)):
        raise ValueError("Login ID already exists.")
    if normalized_email and session.scalar(
        select(User).where(User.email == normalized_email)
    ):
        raise ValueError("Email address already exists.")
    if role == "student" and normalized_participant_code and session.scalar(
        select(User).where(
            User.role == "student",
            User.participant_code == normalized_participant_code,
        )
    ):
        raise ValueError("Participant code already exists.")
    user = User(
        login_id=normalized_login,
        password_hash=hash_password(password),
        role=role,
        email=normalized_email,
        participant_code=normalized_participant_code,
        is_active=is_active,
        is_demo=is_demo,
        must_change_password=must_change_password,
        created_by=created_by,
        password_changed_at=utc_now(),
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    return user


def authenticate_user(session: Session, login_id: str, password: str) -> User | None:
    user = session.scalar(
        select(User).where(User.login_id == normalize_login_id(login_id))
    )
    if user is None or not user.is_active:
        verify_password(password, _TIMING_DUMMY_HASH)
        return None
    if not verify_password(password, user.password_hash):
        return None
    user.last_login_at = utc_now()
    session.commit()
    session.refresh(user)
    return user


def device_category(user_agent: str | None) -> str | None:
    """Reduce a browser User-Agent to phone, tablet, or computer.

    Only the category is stored, never the full User-Agent string.
    """
    if not user_agent:
        return None
    agent = user_agent.lower()
    if "ipad" in agent or "tablet" in agent or (
        "android" in agent and "mobile" not in agent
    ):
        return "tablet"
    if any(word in agent for word in ("iphone", "ipod", "android", "mobile")):
        return "phone"
    if any(word in agent for word in ("windows", "macintosh", "mac os", "linux", "cros")):
        return "computer"
    return None


def create_session(
    session: Session,
    user: User,
    *,
    duration_hours: int,
    device: str | None = None,
) -> tuple[str, AuthSession]:
    raw_token = secrets.token_urlsafe(32)
    auth_session = AuthSession(
        token_hash=hash_token(raw_token),
        user_id=user.id,
        expires_at=utc_now() + timedelta(hours=max(1, duration_hours)),
        device=device,
    )
    session.add(auth_session)
    session.commit()
    session.refresh(auth_session)
    return raw_token, auth_session


def user_for_session_token(session: Session, token: str | None) -> User | None:
    if not token:
        return None
    auth_session = session.scalar(
        select(AuthSession).where(AuthSession.token_hash == hash_token(token))
    )
    if auth_session is None or auth_session.revoked_at is not None:
        return None
    if aware_utc(auth_session.expires_at) <= utc_now():
        return None
    user = session.get(User, auth_session.user_id)
    if user is None or not user.is_active:
        return None
    auth_session.last_used_at = utc_now()
    session.commit()
    return user


def revoke_session_token(session: Session, token: str | None) -> None:
    if not token:
        return
    auth_session = session.scalar(
        select(AuthSession).where(AuthSession.token_hash == hash_token(token))
    )
    if auth_session is not None and auth_session.revoked_at is None:
        auth_session.revoked_at = utc_now()
        session.commit()


def revoke_user_sessions(session: Session, user_id: str) -> None:
    session.execute(
        update(AuthSession)
        .where(AuthSession.user_id == user_id, AuthSession.revoked_at.is_(None))
        .values(revoked_at=utc_now())
    )
    session.commit()


def change_password(session: Session, user: User, password: str) -> None:
    user.password_hash = hash_password(password)
    user.must_change_password = False
    user.password_changed_at = utc_now()
    # Any outstanding reset or activation link must stop working.
    session.execute(
        update(PasswordResetToken)
        .where(
            PasswordResetToken.user_id == user.id,
            PasswordResetToken.used_at.is_(None),
        )
        .values(used_at=utc_now())
    )
    session.commit()
    revoke_user_sessions(session, user.id)


def create_password_reset_token(
    session: Session,
    user: User,
    *,
    duration_minutes: int,
    purpose: str = "password_reset",
) -> str:
    raw_token = secrets.token_urlsafe(32)
    reset_token = PasswordResetToken(
        token_hash=hash_token(raw_token),
        user_id=user.id,
        purpose=purpose,
        expires_at=utc_now() + timedelta(minutes=max(5, duration_minutes)),
    )
    session.add(reset_token)
    session.commit()
    return raw_token


def consume_password_reset_token(
    session: Session, raw_token: str
) -> tuple[PasswordResetToken, User] | None:
    reset_token = session.scalar(
        select(PasswordResetToken).where(
            PasswordResetToken.token_hash == hash_token(raw_token)
        )
    )
    if reset_token is None or reset_token.used_at is not None:
        return None
    if aware_utc(reset_token.expires_at) <= utc_now():
        return None
    user = session.get(User, reset_token.user_id)
    if user is None or not user.is_active:
        return None
    reset_token.used_at = utc_now()
    session.commit()
    return reset_token, user


def record_audit(
    session: Session,
    *,
    action: str,
    resource_type: str,
    resource_id: str | None,
    actor_user_id: str | None,
    details: dict | None = None,
) -> None:
    session.add(
        AuditEvent(
            actor_user_id=actor_user_id,
            action=action,
            resource_type=resource_type,
            resource_id=resource_id,
            details=details or {},
        )
    )
    session.commit()
