from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from auth_service import (
    VALID_ROLES,
    change_password,
    create_user,
    normalize_email,
    normalize_login_id,
    normalize_participant_code,
    record_audit,
    revoke_user_sessions,
)
from models import User


REPOSITORY_ACCOUNT_ROSTER = Path(__file__).resolve().parent / "data" / "study_accounts.json"


DEFAULT_ACCOUNT_ROLES = (
    {"login_id": "instructor", "role": "instructor"},
    {"login_id": "student", "role": "student"},
)
DEFAULT_ACCOUNT_LOGIN_IDS = {item["login_id"] for item in DEFAULT_ACCOUNT_ROLES}


def seed_demo_accounts(
    session: Session,
    enabled: bool,
    *,
    student_password: str,
    instructor_password: str,
) -> None:
    if not enabled:
        return
    passwords = {
        "student": student_password,
        "instructor": instructor_password,
    }
    for account in DEFAULT_ACCOUNT_ROLES:
        existing = session.scalar(
            select(User).where(User.login_id == account["login_id"])
        )
        if existing is None:
            user = create_user(
                session,
                login_id=account["login_id"],
                password=passwords[account["role"]],
                role=account["role"],
                participant_code="DEMO" if account["role"] == "student" else None,
                is_demo=False,
            )
            record_audit(
                session,
                action="account.demo_seeded",
                resource_type="user",
                resource_id=user.id,
                actor_user_id=None,
                details={"login_id": user.login_id, "role": user.role},
            )
        elif existing.is_demo:
            # Demo behavior belongs to the server-issued /auth/demo session,
            # not to accounts authenticated with a login ID and password.
            # Correct databases created by older releases during startup.
            existing.is_demo = False
            session.commit()
            record_audit(
                session,
                action="account.default_demo_flag_removed",
                resource_type="user",
                resource_id=existing.id,
                actor_user_id=None,
                details={"login_id": existing.login_id, "role": existing.role},
            )


def active_instructor_count(session: Session) -> int:
    return int(
        session.scalar(
            select(func.count()).select_from(User).where(
                User.role == "instructor", User.is_active.is_(True)
            )
        )
        or 0
    )


def _safe_account_payload(account: dict) -> dict:
    return {
        "login_id": account.get("login_id"),
        "temporary_password": None,
        "role": account.get("role"),
        "email": account.get("email"),
        "participant_code": account.get("participant_code"),
        "active": bool(account.get("active", True)),
        "demo": bool(account.get("demo", False)),
    }


def _write_json_atomic(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = path.with_suffix(path.suffix + ".tmp")
    temporary_path.write_text(
        json.dumps(payload, indent=2) + "\n", encoding="utf-8"
    )
    temporary_path.replace(path)


def sync_accounts_from_json(session: Session, path: Path) -> dict:
    report = {
        "imported_at": datetime.now(timezone.utc).isoformat(),
        "created": [],
        "updated": [],
        "deactivated": [],
        "errors": [],
    }
    if not path.is_file():
        return report

    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        report["errors"].append(f"Could not read account file: {error}")
        return report

    accounts = payload.get("accounts")
    if not isinstance(accounts, list):
        report["errors"].append("The account file must contain an accounts list.")
        return report

    repository_roster = path.resolve() == REPOSITORY_ACCOUNT_ROSTER.resolve()
    sanitized_accounts: list[dict] = []
    for index, raw_account in enumerate(accounts, start=1):
        if not isinstance(raw_account, dict):
            report["errors"].append(f"Account {index} must be a JSON object.")
            continue
        account = dict(raw_account)
        login_id = normalize_login_id(str(account.get("login_id", "")))
        role = str(account.get("role", "")).strip().lower()
        temporary_password = account.get("temporary_password")
        if repository_roster and isinstance(temporary_password, str) and temporary_password:
            report["errors"].append(
                f"{login_id or f'Account {index}'}: tracked account roster cannot contain a temporary_password. Use Instructor Studio."
            )
            continue
        active = bool(account.get("active", True))
        if login_id in DEFAULT_ACCOUNT_LOGIN_IDS:
            # Password-authenticated default accounts are persistent study
            # accounts. Only server-issued /auth/demo sessions are ephemeral.
            account["demo"] = False
        sanitized_accounts.append(_safe_account_payload(account))
        if not login_id:
            report["errors"].append(f"Account {index} has no login_id.")
            continue
        if role not in VALID_ROLES:
            report["errors"].append(
                f"{login_id}: role must be student or instructor."
            )
            continue

        user = session.scalar(select(User).where(User.login_id == login_id))
        try:
            if user is None:
                if not isinstance(temporary_password, str) or not temporary_password:
                    raise ValueError("a temporary_password is required for new accounts.")
                user = create_user(
                    session,
                    login_id=login_id,
                    password=temporary_password,
                    role=role,
                    email=account.get("email"),
                    participant_code=account.get("participant_code"),
                    is_active=active,
                    is_demo=bool(account.get("demo", False)),
                )
                report["created"].append(login_id)
                record_audit(
                    session,
                    action="account.json_created",
                    resource_type="user",
                    resource_id=user.id,
                    actor_user_id=None,
                    details={"login_id": login_id, "role": role},
                )
                continue

            if (
                user.role == "instructor"
                and (role != "instructor" or not active)
                and active_instructor_count(session) <= 1
            ):
                raise ValueError("the last active instructor cannot be disabled or demoted.")

            changed = False
            new_email = normalize_email(account.get("email"))
            participant_code = normalize_participant_code(
                str(account.get("participant_code") or "")
            )
            duplicate_participant = (
                session.scalar(
                    select(User).where(
                        User.role == "student",
                        User.participant_code == participant_code,
                        User.id != user.id,
                    )
                )
                if role == "student" and participant_code
                else None
            )
            if duplicate_participant is not None:
                raise ValueError("participant code already exists")
            if user.role != role:
                user.role = role
                changed = True
            if user.email != new_email:
                user.email = new_email
                changed = True
            if user.participant_code != participant_code:
                user.participant_code = participant_code
                changed = True
            if user.is_active != active:
                user.is_active = active
                changed = True
                if not active:
                    report["deactivated"].append(login_id)
            user.is_demo = bool(account.get("demo", user.is_demo))
            if isinstance(temporary_password, str) and temporary_password:
                session.commit()
                change_password(session, user, temporary_password)
                changed = True
            else:
                session.commit()
                if not active:
                    revoke_user_sessions(session, user.id)
            if changed:
                report["updated"].append(login_id)
                record_audit(
                    session,
                    action="account.json_updated",
                    resource_type="user",
                    resource_id=user.id,
                    actor_user_id=None,
                    details={"login_id": login_id, "role": role, "active": active},
                )
        except (ValueError, TypeError) as error:
            session.rollback()
            report["errors"].append(f"{login_id}: {error}")
        except Exception as error:
            session.rollback()
            report["errors"].append(f"{login_id}: account update failed: {error}")

    sanitized_payload = {
        "version": payload.get("version", 1),
        "accounts": sanitized_accounts,
    }
    if sanitized_payload != payload and not repository_roster:
        _write_json_atomic(path, sanitized_payload)
    return report
