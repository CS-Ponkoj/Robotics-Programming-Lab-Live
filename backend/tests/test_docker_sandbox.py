"""Docker sandbox process handling, without needing Docker itself."""
import subprocess

import sandbox
from sandbox import DockerSandbox


def test_timeout_removes_the_named_container(monkeypatch):
    calls = []

    def fake_run(command, **kwargs):
        calls.append((command, kwargs))
        if command[1] == "run":
            raise subprocess.TimeoutExpired(command, kwargs["timeout"])
        return subprocess.CompletedProcess(command, 0, "", "")

    monkeypatch.setattr(sandbox.subprocess, "run", fake_run)
    result = DockerSandbox("image", timeout_seconds=2).execute("while True: pass", [])

    run_command = calls[0][0]
    name = run_command[run_command.index("--name") + 1]
    assert name.startswith("rpl-python-")
    # Killing only the docker client would leave the loop running.
    assert calls[1][0] == ["docker", "rm", "--force", name]
    assert result["success"] is False
    assert result["error"].startswith("TimeoutError in submission")


def test_output_is_decoded_as_utf8(monkeypatch):
    captured = {}

    def fake_run(command, **kwargs):
        captured.update(kwargs)
        return subprocess.CompletedProcess(
            command, 0, '{"success": true, "error": "", "output": "→ ✓", "values": {}}', ""
        )

    monkeypatch.setattr(sandbox.subprocess, "run", fake_run)
    result = DockerSandbox("image").execute("print('→ ✓')", [])

    assert captured["encoding"] == "utf-8"
    assert result["output"] == "→ ✓"
