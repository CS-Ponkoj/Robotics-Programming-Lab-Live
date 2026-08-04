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
    record_audit,
    revoke_user_sessions,
)
from models import User


DEMO_ACCOUNT_ROLES = (
    {"login_id": "instructor", "role": "instructor"},
    {"login_id": "student", "role": "student"},
)


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
    for account in DEMO_ACCOUNT_ROLES:
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
                is_demo=True,
            )
            record_audit(
                session,
                action="account.demo_seeded",
                resource_type="user",
                resource_id=user.id,
                actor_user_id=None,
                details={"login_id": user.login_id, "role": user.role},
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

    sanitized_accounts: list[dict] = []
    for index, raw_account in enumerate(accounts, start=1):
        if not isinstance(raw_account, dict):
            report["errors"].append(f"Account {index} must be a JSON object.")
            continue
        account = dict(raw_account)
        login_id = normalize_login_id(str(account.get("login_id", "")))
        role = str(account.get("role", "")).strip().lower()
        temporary_password = account.get("temporary_password")
        active = bool(account.get("active", True))
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
            participant_code = (
                str(account.get("participant_code") or "").strip() or None
            )
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
    if sanitized_payload != payload:
        _write_json_atomic(path, sanitized_payload)
    report_path = path.with_name("study_accounts_import_report.json")
    _write_json_atomic(report_path, report)
    return report
