from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


BASE_DIR = Path(__file__).resolve().parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=BASE_DIR / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    database_url: str = f"sqlite:///{(BASE_DIR / 'robotics_lab.db').as_posix()}"
    redis_url: str = "redis://127.0.0.1:6379/0"
    openai_api_key: str | None = None
    openai_hint_model: str = "gpt-4.1-mini"
    openai_timeout_seconds: float = 7.0
    openai_max_retries: int = 0
    admin_api_token: str | None = None
    sandbox_backend: str = "subprocess"
    sandbox_image: str = "robotics-lab-sandbox:latest"
    object_storage_root: Path = BASE_DIR / "managed_assets"
    max_submission_chars: int = 50_000
    execution_timeout_seconds: float = 5.0
    allowed_origins: str = "*"

    @property
    def cors_origins(self) -> list[str]:
        if self.allowed_origins.strip() == "*":
            return ["*"]
        return [
            origin.strip()
            for origin in self.allowed_origins.split(",")
            if origin.strip()
        ]


@lru_cache
def get_settings() -> Settings:
    return Settings()
