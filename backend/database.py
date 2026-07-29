from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker
from sqlalchemy.pool import StaticPool

from config import get_settings


class Base(DeclarativeBase):
    pass


def build_engine(database_url: str):
    arguments = {}
    poolclass = None
    if database_url.startswith("sqlite"):
        arguments["check_same_thread"] = False
        if database_url in {"sqlite://", "sqlite:///:memory:"}:
            poolclass = StaticPool
    return create_engine(
        database_url,
        connect_args=arguments,
        pool_pre_ping=True,
        poolclass=poolclass,
    )


engine = build_engine(get_settings().database_url)
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


def get_session() -> Generator[Session, None, None]:
    with SessionLocal() as session:
        yield session
