import httpx
import pytest
import subprocess

from sandbox import RemoteSandbox, SubprocessSandbox, build_sandbox


def test_subprocess_sandbox_rejects_python_object_introspection():
    result = SubprocessSandbox().execute(
        "classes = ().__class__.__base__.__subclasses__()",
        ["classes"],
    )

    assert result["success"] is False
    assert "Attribute '__subclasses__' is not allowed" in result["error"]


def test_subprocess_sandbox_rejects_unsafe_numpy_file_api():
    result = SubprocessSandbox().execute(
        "import numpy as np\nvalue = np.load('/tmp/secret')",
        ["value"],
    )

    assert result["success"] is False
    assert "Use of 'np.load' is not allowed" in result["error"]


@pytest.mark.parametrize(
    ("code", "expected"),
    [
        ("import math\ny = 2\nz = math.pow(2, 3)\n", "line 3 of submission"),
        ("import math\n\nvalue = '{:.2f}'.format(1.0)\n", "line 3 of submission"),
        ("value = 1\nimport os\n", "line 2 of submission"),
        ("def boom():\n    return 1 / 0\n\nboom()\n", "ZeroDivisionError at line 2 of submission"),
    ],
)
def test_subprocess_sandbox_reports_the_students_own_line_number(code, expected):
    result = SubprocessSandbox().execute(code, [])

    assert result["success"] is False
    assert expected in result["error"]


def test_subprocess_sandbox_keeps_supported_scientific_math():
    result = SubprocessSandbox().execute(
        """
import math
import numpy as np
from scipy.spatial import distance

value = math.sqrt(9) + np.sin(np.radians(90)) + distance.euclidean((0, 0), (3, 4))
""",
        ["value"],
    )

    assert result["success"] is True
    assert result["values"]["value"] == 9.0


def test_remote_sandbox_sends_only_execution_data_and_auth_token(monkeypatch):
    captured = {}

    class Response:
        status_code = 200

        @staticmethod
        def json():
            return {
                "success": True,
                "error": "",
                "output": "hello\n",
                "values": {"answer": 42},
            }

    def fake_post(url, *, headers, json, timeout):
        captured.update(
            {"url": url, "headers": headers, "json": json, "timeout": timeout}
        )
        return Response()

    monkeypatch.setattr("sandbox.httpx.post", fake_post)
    result = RemoteSandbox(
        "sandbox.internal:10000",
        "test-sandbox-token",
        timeout_seconds=4,
        http_timeout_seconds=20,
    ).execute("answer = 42", ["answer"])

    assert result["success"] is True
    request_timeout = captured.pop("timeout")
    assert request_timeout == pytest.approx(20, abs=0.1)
    assert captured == {
        "url": "http://sandbox.internal:10000/execute",
        "headers": {"Authorization": "Bearer test-sandbox-token"},
        "json": {
            "code": "answer = 42",
            "result_names": ["answer"],
            "timeout_seconds": 4,
        },
    }


def test_remote_sandbox_uses_https_for_render_external_hostname(monkeypatch):
    captured = {}

    class Response:
        status_code = 200

        @staticmethod
        def json():
            return {"success": True, "error": "", "output": "", "values": {}}

    def fake_post(url, **kwargs):
        captured["url"] = url
        captured.update(kwargs)
        return Response()

    monkeypatch.setattr("sandbox.httpx.post", fake_post)
    result = RemoteSandbox(
        "robotics-programming-lab-sandbox.onrender.com",
        "test-sandbox-token",
    ).execute("x = 1", ["x"])

    assert result["success"] is True
    assert captured["url"] == (
        "https://robotics-programming-lab-sandbox.onrender.com/execute"
    )


def test_remote_sandbox_returns_safe_error_without_leaking_provider_details(
    monkeypatch,
):
    def unavailable(*_args, **_kwargs):
        raise httpx.ConnectError("internal-hostname: secret-token")

    monkeypatch.setattr("sandbox.httpx.post", unavailable)
    result = RemoteSandbox(
        "https://sandbox.example.test",
        "secret-token",
    ).execute("answer = 42", ["answer"])

    assert result["success"] is False
    assert result["values"] == {}
    assert "internal-hostname" not in result["error"]
    assert "secret-token" not in result["error"]


def test_remote_sandbox_retries_temporary_rejection_then_succeeds(monkeypatch):
    responses = iter(
        [
            type("Response", (), {"status_code": 503})(),
            type(
                "Response",
                (),
                {
                    "status_code": 200,
                    "json": staticmethod(
                        lambda: {
                            "success": True,
                            "error": "",
                            "output": "",
                            "values": {"answer": 42},
                        }
                    ),
                },
            )(),
        ]
    )
    calls = []

    def fake_post(*_args, **_kwargs):
        calls.append(True)
        return next(responses)

    monkeypatch.setattr("sandbox.httpx.post", fake_post)
    result = RemoteSandbox(
        "https://sandbox.example.test",
        "secret-token",
        retry_delays_seconds=(0,),
    ).execute("answer = 42", ["answer"])

    assert result["success"] is True
    assert result["values"] == {"answer": 42}
    assert len(calls) == 2


def test_remote_sandbox_does_not_retry_authentication_failure(monkeypatch):
    calls = []

    class Response:
        status_code = 401

    def fake_post(*_args, **_kwargs):
        calls.append(True)
        return Response()

    monkeypatch.setattr("sandbox.httpx.post", fake_post)
    result = RemoteSandbox(
        "https://sandbox.example.test",
        "secret-token",
        retry_delays_seconds=(0, 0),
    ).execute("answer = 42", ["answer"])

    assert result["success"] is False
    assert "not configured correctly" in result["error"]
    assert len(calls) == 1


def test_remote_sandbox_reports_persistent_temporary_failure(monkeypatch):
    calls = []

    class Response:
        status_code = 503

    def fake_post(*_args, **_kwargs):
        calls.append(True)
        return Response()

    monkeypatch.setattr("sandbox.httpx.post", fake_post)
    result = RemoteSandbox(
        "https://sandbox.example.test",
        "secret-token",
        retry_delays_seconds=(0, 0),
    ).execute("answer = 42", ["answer"])

    assert result["success"] is False
    assert "starting or temporarily busy" in result["error"]
    assert len(calls) == 3


def test_remote_sandbox_rejects_malformed_success_response(monkeypatch):
    class Response:
        status_code = 200

        @staticmethod
        def json():
            return {"success": "yes", "values": []}

    monkeypatch.setattr("sandbox.httpx.post", lambda *_args, **_kwargs: Response())
    result = RemoteSandbox(
        "https://sandbox.example.test",
        "secret-token",
        retry_delays_seconds=(),
    ).execute("answer = 42", ["answer"])

    assert result["success"] is False
    assert result["error"] == "The secure grader returned an invalid response."


def test_build_remote_sandbox_requires_url_and_token():
    try:
        build_sandbox("remote", "unused", 5)
    except RuntimeError as error:
        assert "SANDBOX_URL" in str(error)
    else:
        raise AssertionError("Missing remote sandbox configuration was accepted")


def test_build_sandbox_rejects_unknown_backend():
    try:
        build_sandbox("typo", "unused", 5)
    except RuntimeError as error:
        assert "Unsupported sandbox backend" in str(error)
    else:
        raise AssertionError("Unknown sandbox backend was accepted")


def test_subprocess_worker_environment_excludes_application_secrets(
    monkeypatch,
    tmp_path,
):
    captured = {}

    def fake_run(*_args, **kwargs):
        captured["env"] = kwargs["env"]
        return subprocess.CompletedProcess(
            args=[],
            returncode=0,
            stdout='{"success": true, "error": "", "output": "", "values": {}}',
            stderr="",
        )

    monkeypatch.setenv("OPENAI_API_KEY", "must-not-reach-worker")
    monkeypatch.setenv("DATABASE_URL", "must-not-reach-worker")
    monkeypatch.setenv("SANDBOX_API_TOKEN", "must-not-reach-worker")
    monkeypatch.setattr("sandbox.subprocess.run", fake_run)

    result = SubprocessSandbox().execute("answer = 42", [])

    assert result["success"] is True
    assert "OPENAI_API_KEY" not in captured["env"]
    assert "DATABASE_URL" not in captured["env"]
    assert "SANDBOX_API_TOKEN" not in captured["env"]


@pytest.mark.parametrize(
    "code",
    [
        "value = '{0.__globals__}'.format(len)",
        "value = '{0.__class__}'.format(1)",
        "value = ''.format_map({})",
        "value = '1'.zfill(3)",
        "value = (1).to_bytes(4, 'big')",
        "value = str(1).zfill(3)",
    ],
)
def test_subprocess_sandbox_applies_method_allowlist_to_every_receiver(code):
    result = SubprocessSandbox().execute(code, ["value"])

    assert result["success"] is False
    assert "is not allowed" in result["error"]


def test_subprocess_sandbox_keeps_allowed_methods_on_literals_and_calls():
    result = SubprocessSandbox().execute(
        "value = ', '.join(sorted(['b', 'a'])).upper() + f'{3.14159:.2f}'",
        ["value"],
    )

    assert result["success"] is True
    assert result["values"]["value"] == "A, B3.14"


def test_subprocess_sandbox_does_not_return_oversized_values():
    result = SubprocessSandbox().execute(
        "text = 'x' * 5_000_000\nitems = list(range(100_000))\nsmall = 'ok'",
        ["text", "items", "small"],
    )

    assert result["success"] is True
    assert result["values"]["text"] == {
        "unsupported_type": "str",
        "repr": "[value too large]",
    }
    assert result["values"]["items"]["repr"] == "[value too large]"
    assert result["values"]["small"] == "ok"
