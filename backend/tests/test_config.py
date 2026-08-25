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
