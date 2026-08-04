import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import Protocol

import httpx


WORKER_PATH = Path(__file__).with_name("submission_worker.py")


class Sandbox(Protocol):
    def execute(self, code: str, result_names: list[str]) -> dict:
        ...


class SubprocessSandbox:
    def __init__(self, timeout_seconds: float = 5.0):
        self.timeout_seconds = timeout_seconds

    def execute(self, code: str, result_names: list[str]) -> dict:
        request_data = json.dumps({"code": code, "result_names": result_names})
        creation_flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
        child_environment = {
            key: value
            for key, value in os.environ.items()
            if key.upper() in {"PATH", "SYSTEMROOT", "WINDIR"}
        }
        child_environment.update(
            {
                "OPENBLAS_NUM_THREADS": "1",
                "OMP_NUM_THREADS": "1",
                "PYTHONHASHSEED": "0",
                "PYTHONIOENCODING": "utf-8",
            }
        )
        resource_limits = _linux_resource_limits if os.name != "nt" else None
        try:
            with tempfile.TemporaryDirectory(prefix="robotics-submission-") as workdir:
                completed = subprocess.run(
                    [sys.executable, "-I", str(WORKER_PATH)],
                    input=request_data,
                    capture_output=True,
                    text=True,
                    timeout=self.timeout_seconds,
                    check=False,
                    cwd=workdir,
                    env=child_environment,
                    creationflags=creation_flags,
                    preexec_fn=resource_limits,
                )
        except subprocess.TimeoutExpired:
            return {
                "success": False,
                "error": (
                    "TimeoutError in submission: execution exceeded "
                    f"{self.timeout_seconds:g} seconds"
                ),
                "output": "",
                "values": {},
            }
        if completed.returncode != 0:
            return {
                "success": False,
                "error": completed.stderr.strip() or "Submission worker failed.",
                "output": "",
                "values": {},
            }
        try:
            return json.loads(completed.stdout)
        except json.JSONDecodeError:
            return {
                "success": False,
                "error": "Submission worker returned an invalid response.",
                "output": "",
                "values": {},
            }


def _linux_resource_limits() -> None:
    """Apply defense-in-depth limits inside the short-lived Linux worker."""
    import resource

    memory_bytes = 384 * 1024 * 1024
    resource.setrlimit(resource.RLIMIT_AS, (memory_bytes, memory_bytes))
    resource.setrlimit(resource.RLIMIT_CPU, (6, 6))
    resource.setrlimit(resource.RLIMIT_FSIZE, (1024 * 1024, 1024 * 1024))
    resource.setrlimit(resource.RLIMIT_NOFILE, (32, 32))
    if hasattr(resource, "RLIMIT_NPROC"):
        resource.setrlimit(resource.RLIMIT_NPROC, (16, 16))


class DockerSandbox:
    def __init__(self, image: str, timeout_seconds: float = 5.0):
        self.image = image
        self.timeout_seconds = timeout_seconds

    def execute(self, code: str, result_names: list[str]) -> dict:
        request_data = json.dumps({"code": code, "result_names": result_names})
        command = [
            "docker",
            "run",
            "--rm",
            "-i",
            "--network",
            "none",
            "--memory",
            "256m",
            "--cpus",
            "1",
            "--pids-limit",
            "64",
            self.image,
        ]
        try:
            completed = subprocess.run(
                command,
                input=request_data,
                capture_output=True,
                text=True,
                timeout=self.timeout_seconds + 3,
                check=False,
            )
        except (FileNotFoundError, subprocess.TimeoutExpired) as error:
            return {
                "success": False,
                "error": f"Docker sandbox unavailable: {error}",
                "output": "",
                "values": {},
            }
        if completed.returncode != 0:
            return {
                "success": False,
                "error": completed.stderr.strip() or "Docker sandbox failed.",
                "output": "",
                "values": {},
            }
        try:
            return json.loads(completed.stdout)
        except json.JSONDecodeError:
            return {
                "success": False,
                "error": "Docker sandbox returned an invalid response.",
                "output": "",
                "values": {},
            }


class RemoteSandbox:
    """Execute submissions in a separate, secret-free sandbox service."""

    def __init__(
        self,
        url: str,
        api_token: str,
        timeout_seconds: float = 5.0,
        http_timeout_seconds: float = 75.0,
    ):
        normalized_url = url.strip().rstrip("/")
        if normalized_url and "://" not in normalized_url:
            normalized_url = f"http://{normalized_url}"
        self.url = normalized_url
        self.api_token = api_token
        self.timeout_seconds = timeout_seconds
        self.http_timeout_seconds = max(
            http_timeout_seconds,
            timeout_seconds + 2,
        )

    def execute(self, code: str, result_names: list[str]) -> dict:
        try:
            response = httpx.post(
                f"{self.url}/execute",
                headers={"Authorization": f"Bearer {self.api_token}"},
                json={
                    "code": code,
                    "result_names": result_names,
                    "timeout_seconds": self.timeout_seconds,
                },
                timeout=self.http_timeout_seconds,
            )
        except (httpx.TimeoutException, httpx.NetworkError):
            return _sandbox_error(
                "The secure grader is temporarily unavailable. Please try again."
            )
        if response.status_code != 200:
            return _sandbox_error(
                "The secure grader rejected the execution request. Please try again."
            )
        try:
            result = response.json()
        except (json.JSONDecodeError, ValueError):
            return _sandbox_error("The secure grader returned an invalid response.")
        if not _valid_result(result):
            return _sandbox_error("The secure grader returned an invalid response.")
        return result


def _valid_result(result: object) -> bool:
    if not isinstance(result, dict):
        return False
    return (
        isinstance(result.get("success"), bool)
        and isinstance(result.get("error"), str)
        and isinstance(result.get("output"), str)
        and isinstance(result.get("values"), dict)
    )


def _sandbox_error(message: str) -> dict:
    return {
        "success": False,
        "error": message,
        "output": "",
        "values": {},
    }


def build_sandbox(
    backend: str,
    image: str,
    timeout_seconds: float,
    *,
    remote_url: str | None = None,
    remote_api_token: str | None = None,
    remote_http_timeout_seconds: float = 75.0,
) -> Sandbox:
    if backend == "docker":
        return DockerSandbox(image=image, timeout_seconds=timeout_seconds)
    if backend == "remote":
        if not remote_url or not remote_api_token:
            raise RuntimeError(
                "Remote sandbox requires SANDBOX_URL and SANDBOX_API_TOKEN."
            )
        return RemoteSandbox(
            url=remote_url,
            api_token=remote_api_token,
            timeout_seconds=timeout_seconds,
            http_timeout_seconds=remote_http_timeout_seconds,
        )
    if backend == "subprocess":
        return SubprocessSandbox(timeout_seconds=timeout_seconds)
    raise RuntimeError(f"Unsupported sandbox backend: {backend}.")
