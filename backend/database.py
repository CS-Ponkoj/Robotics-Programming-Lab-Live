from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker
from sqlalchemy.pool import StaticPool

from config import get_settings


class Base(DeclarativeBase):
    pass


def normalize_database_url(database_url: str) -> str:
    if database_url.startswith("postgresql://"):
        return database_url.replace("postgresql://", "postgresql+psycopg://", 1)
    if database_url.startswith("postgres://"):
        return database_url.replace("postgres://", "postgresql+psycopg://", 1)
    return database_url


def build_engine(database_url: str):
    database_url = normalize_database_url(database_url)
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
