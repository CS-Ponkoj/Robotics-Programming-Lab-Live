import json
import os
from pathlib import Path
import subprocess
import sys
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
        try:
            completed = subprocess.run(
                [sys.executable, "-I", str(WORKER_PATH)],
                input=request_data,
                capture_output=True,
                text=True,
                timeout=self.timeout_seconds,
                check=False,
                creationflags=creation_flags,
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
