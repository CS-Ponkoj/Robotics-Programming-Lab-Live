from config import get_settings


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
