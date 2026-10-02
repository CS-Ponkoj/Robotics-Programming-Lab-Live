import pytest

from config import Settings, get_settings


@pytest.fixture(autouse=True)
def isolated_config_environment(monkeypatch):
    for key in (
        "ENVIRONMENT",
        "DATABASE_URL",
        "NEON_DATABASE_URL",
        "NEON_DATABASE_NAME",
    ):
        monkeypatch.delenv(key, raising=False)


def test_get_settings_uses_configured_env_file(tmp_path, monkeypatch):
    env_file = tmp_path / "local-package.env"
    env_file.write_text("OPENAI_HINT_MODEL=package-test-model\n", encoding="utf-8")
    monkeypatch.setenv("ROBOTICS_ENV_FILE", str(env_file))
    get_settings.cache_clear()
    try:
        assert get_settings().openai_hint_model == "package-test-model"
    finally:
        get_settings.cache_clear()


def test_cloud_database_url_uses_dedicated_staging_database():
    from config import Settings

    settings = Settings(
        neon_database_url=(
            "postgresql://account:secret@example.neon.tech/neondb"
            "?sslmode=require&channel_binding=require"
        )
    )

    assert settings.cloud_database_url == (
        "postgresql://account:secret@example.neon.tech/robotics_lab_staging"
        "?sslmode=require&channel_binding=require"
    )


def test_application_database_defaults_to_neon_without_local_override():
    settings = Settings(
        neon_database_url="postgresql://user:secret@example.neon.tech/neondb"
    )
    assert settings.database_url == ""
    assert settings.application_database_url.endswith("/robotics_lab_staging")


@pytest.mark.parametrize(
    "url",
    [
        None,
        "sqlite:///local.db",
        "postgresql://user:secret@localhost/db",
        "postgresql://user:secret@fake.neon.tech.example/db",
    ],
)
def test_application_database_refuses_missing_or_non_neon_connection(url):
    with pytest.raises(RuntimeError):
        Settings(neon_database_url=url).application_database_url


def test_application_database_refuses_conflicting_local_override():
    with pytest.raises(RuntimeError, match="conflicts"):
        Settings(
            neon_database_url="postgresql://user:secret@example.neon.tech/neondb",
            database_url="sqlite:///local.db",
        ).application_database_url


def test_application_database_accepts_launcher_driver_normalization():
    settings = Settings(
        neon_database_url="postgresql://user:secret@example.neon.tech/neondb",
        database_url="postgresql+psycopg://user:secret@example.neon.tech/robotics_lab_staging",
    )
    assert settings.application_database_url == settings.cloud_database_url


def test_test_database_requires_explicit_isolated_configuration():
    assert (
        Settings(
            environment="testing", database_url="sqlite://"
        ).application_database_url
        == "sqlite://"
    )
    with pytest.raises(RuntimeError, match="disposable"):
        Settings(environment="testing").application_database_url


def test_production_connection_keeps_its_database_name():
    settings = Settings(
        environment="production",
        database_url="postgresql://user:secret@example.neon.tech/neondb",
    )
    assert settings.application_database_url.endswith("/neondb")
