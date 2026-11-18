"""Course-wide instructor settings stored in the database.

Each setting is a small validated document under one key. A missing row means
the default, so a fresh database behaves exactly as before any instructor
changed anything.
"""
from __future__ import annotations

from typing import TypeVar

from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.orm import Session

from models import CourseSetting, User


class _Setting(BaseModel):
    model_config = ConfigDict(extra="forbid")


class AiTutorSettings(_Setting):
    """Whether students may ask the AI tutor, and how often each day."""

    enabled: bool = False
    daily_limit: int = Field(default=20, ge=1, le=200)


class CatalogSettings(_Setting):
    """Assignments shown in the Old assignments panel; None uses catalog.json."""

    old_assignment_ids: list[int] | None = Field(default=None, max_length=200)


KEYS: dict[str, type[_Setting]] = {
    "ai_tutor": AiTutorSettings,
    "catalog": CatalogSettings,
}

SettingT = TypeVar("SettingT", bound=_Setting)


def get_setting(session: Session, model: type[SettingT]) -> SettingT:
    key = _key_for(model)
    row = session.get(CourseSetting, key)
    if row is None or not isinstance(row.value, dict):
        return model()
    try:
        return model.model_validate(row.value)
    except ValueError:
        # A stored value that no longer validates falls back to the safe default.
        return model()


def set_setting(session: Session, value: _Setting, user: User | None) -> _Setting:
    key = _key_for(type(value))
    row = session.get(CourseSetting, key)
    if row is None:
        row = CourseSetting(key=key)
        session.add(row)
    row.value = value.model_dump(mode="json")
    row.updated_by_user_id = user.id if user else None
    session.commit()
    return value


def _key_for(model: type[_Setting]) -> str:
    for key, candidate in KEYS.items():
        if candidate is model:
            return key
    raise KeyError(model.__name__)
