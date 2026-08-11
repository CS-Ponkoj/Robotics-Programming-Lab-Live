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

    environment: str = "development"
    database_url: str = f"sqlite:///{(BASE_DIR / 'robotics_lab.db').as_posix()}"
    auto_create_schema: bool = True
    redis_url: str = "redis://127.0.0.1:6379/0"
    openai_api_key: str | None = None
    openai_hint_model: str = "gpt-4.1-mini"
    openai_timeout_seconds: float = 7.0
    openai_max_retries: int = 0
    admin_api_token: str | None = None
    enable_demo_accounts: bool = True
    enable_password_reset: bool = False
    enable_email_features: bool = False
    demo_student_password: str = "student"
    demo_instructor_password: str = "instructor"
    study_accounts_file: Path = BASE_DIR / "data" / "study_accounts.json"
    public_app_url: str = "http://127.0.0.1:8080"
    auth_session_hours: int = 12
    password_reset_minutes: int = 30
    smtp_host: str | None = None
    smtp_port: int = 587
    smtp_username: str | None = None
    smtp_password: str | None = None
    smtp_from: str = "Robotics Programming Lab <no-reply@example.invalid>"
    smtp_use_tls: bool = True
    sandbox_backend: str = "subprocess"
    sandbox_image: str = "robotics-lab-sandbox:latest"
    sandbox_url: str | None = None
    sandbox_api_token: str | None = None
    sandbox_http_timeout_seconds: float = 75.0
    ros2_grader_image: str = "robotics-lab-ros2-grader:jazzy-v1"
    object_storage_root: Path = BASE_DIR / "managed_assets"
    max_submission_chars: int = 50_000
    max_request_bytes: int = 100_000
    execution_timeout_seconds: float = 5.0
    max_concurrent_executions: int = 2
    execution_requests_per_minute: int = 30
    tutor_requests_per_minute: int = 10
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

    def validate_runtime(self) -> None:
        if self.environment.lower() != "production":
            return
        problems = []
        if self.database_url.startswith("sqlite"):
            problems.append("DATABASE_URL must use PostgreSQL")
        if self.auto_create_schema:
            problems.append("AUTO_CREATE_SCHEMA must be false")
        if self.allowed_origins.strip() == "*":
            problems.append("ALLOWED_ORIGINS must name the deployed frontend")
        if self.sandbox_backend not in {"remote", "docker"}:
            problems.append(
                "SANDBOX_BACKEND must use remote or docker isolation"
            )
        if self.sandbox_backend == "remote":
            if not self.sandbox_url:
                problems.append("SANDBOX_URL is required for remote isolation")
            if not self.sandbox_api_token or len(self.sandbox_api_token) < 24:
                problems.append(
                    "SANDBOX_API_TOKEN must contain at least 24 characters"
                )
        if problems:
            raise RuntimeError(
                "Invalid production configuration: " + "; ".join(problems)
            )


@lru_cache
def get_settings() -> Settings:
    return Settings()
