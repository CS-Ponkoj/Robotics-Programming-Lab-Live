import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import Protocol


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


def build_sandbox(backend: str, image: str, timeout_seconds: float) -> Sandbox:
    if backend == "docker":
        return DockerSandbox(image=image, timeout_seconds=timeout_seconds)
    return SubprocessSandbox(timeout_seconds=timeout_seconds)
