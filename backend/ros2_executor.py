from __future__ import annotations

import json
import logging
import os
import secrets
import shutil
import subprocess
import threading
import time
from dataclasses import dataclass
from typing import Protocol


logger = logging.getLogger(__name__)

# The harness returns a compact JSON report; anything larger is abuse.
MAX_CONTAINER_OUTPUT_BYTES = 1_000_000


class Ros2Executor(Protocol):
    def execute(
        self,
        code: str,
        project_files: list[dict],
        config: dict,
    ) -> dict:
        ...


class DockerRos2Executor:
    """Run one ROS 2 submission in a short-lived, networkless container."""

    def __init__(self, image: str, timeout_seconds: float = 20.0):
        self.image = image
        self.timeout_seconds = timeout_seconds

    def execute(
        self,
        code: str,
        project_files: list[dict],
        config: dict,
    ) -> dict:
        request_data = json.dumps(
            {
                "code": code,
                "project_files": project_files,
                "config": _safe_config(config),
            }
        )
        docker_executable = shutil.which("docker")
        if docker_executable is None and os.name == "nt":
            installed = (
                r"C:\Program Files\Docker\Docker\resources\bin\docker.exe"
            )
            if os.path.isfile(installed):
                docker_executable = installed
        if docker_executable is None:
            return _executor_error(
                "The local ROS 2 grader is unavailable. Install and start Docker Desktop."
            )
        domain_id = str(secrets.randbelow(200) + 1)
        # A known name lets the API remove the container itself; killing only
        # the docker CLI client can leave the container running.
        container_name = f"rpl-ros2-{secrets.token_hex(8)}"
        command = [
            docker_executable,
            "run",
            "--rm",
            "-i",
            "--name",
            container_name,
            "--network",
            "none",
            "--read-only",
            "--tmpfs",
            "/workspace:rw,nosuid,nodev,exec,size=256m,uid=10001,gid=10001",
            "--tmpfs",
            "/tmp:rw,nosuid,nodev,noexec,size=64m,uid=10001,gid=10001",
            "--memory",
            "768m",
            "--cpus",
            "1",
            "--pids-limit",
            "128",
            "--cap-drop",
            "ALL",
            "--security-opt",
            "no-new-privileges",
            "--env",
            "ROS_LOCALHOST_ONLY=1",
            "--env",
            f"ROS_DOMAIN_ID={domain_id}",
            "--env",
            "HOME=/tmp",
            self.image,
        ]
        creation_flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
        try:
            completed = _run_bounded(
                command,
                request_data.encode("utf-8"),
                timeout_seconds=self.timeout_seconds + 5,
                output_limit=MAX_CONTAINER_OUTPUT_BYTES,
                creation_flags=creation_flags,
            )
        except FileNotFoundError:
            return _executor_error(
                "The local ROS 2 grader is unavailable. Install and start Docker Desktop."
            )
        if completed.timed_out or completed.overflowed:
            _remove_container(docker_executable, container_name, creation_flags)
        if completed.timed_out:
            return _executor_error(
                f"The ROS 2 test exceeded {self.timeout_seconds:g} seconds and was stopped."
            )
        if completed.overflowed:
            return _executor_error(
                "The ROS 2 test produced too much output and was stopped. "
                "Reduce printing or logging in your node."
            )
        if completed.returncode != 0:
            return _executor_error(_container_failure_message(completed.stderr))
        try:
            result = json.loads(completed.stdout)
        except json.JSONDecodeError:
            return _executor_error("The ROS 2 grader returned an invalid response.")
        if not _valid_result(result):
            return _executor_error("The ROS 2 grader returned an invalid response.")
        return result


@dataclass
class _BoundedResult:
    returncode: int | None
    stdout: str
    stderr: str
    timed_out: bool = False
    overflowed: bool = False


def _run_bounded(
    command: list[str],
    input_data: bytes,
    timeout_seconds: float,
    output_limit: int,
    creation_flags: int = 0,
) -> _BoundedResult:
    """Run a process with a wall-clock limit and a cap on retained output."""
    process = subprocess.Popen(
        command,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        creationflags=creation_flags,
    )
    overflowed = threading.Event()
    captured: dict[str, list[bytes]] = {"stdout": [], "stderr": []}

    def read(stream, sink: list[bytes]) -> None:
        kept = 0
        # Keep draining after the cap so the child never blocks on a full pipe.
        while chunk := stream.read(65536):
            if kept < output_limit:
                sink.append(chunk[: output_limit - kept])
            kept += len(chunk)
            if kept > output_limit:
                overflowed.set()

    def write() -> None:
        try:
            process.stdin.write(input_data)
            process.stdin.close()
        except OSError:
            pass

    threads = [
        threading.Thread(target=read, args=(process.stdout, captured["stdout"]), daemon=True),
        threading.Thread(target=read, args=(process.stderr, captured["stderr"]), daemon=True),
        threading.Thread(target=write, daemon=True),
    ]
    for thread in threads:
        thread.start()
    deadline = time.monotonic() + timeout_seconds
    timed_out = False
    while process.poll() is None:
        if overflowed.is_set():
            break
        if time.monotonic() >= deadline:
            timed_out = True
            break
        time.sleep(0.05)
    if process.poll() is None:
        process.kill()
        process.wait()
    for thread in threads:
        thread.join(timeout=2)
    return _BoundedResult(
        returncode=process.returncode,
        stdout=b"".join(captured["stdout"]).decode("utf-8", errors="replace"),
        stderr=b"".join(captured["stderr"]).decode("utf-8", errors="replace"),
        timed_out=timed_out,
        overflowed=overflowed.is_set(),
    )


def _remove_container(docker_executable: str, name: str, creation_flags: int) -> None:
    try:
        subprocess.run(
            [docker_executable, "rm", "--force", name],
            capture_output=True,
            timeout=15,
            check=False,
            creationflags=creation_flags,
        )
    except (OSError, subprocess.TimeoutExpired):
        logger.warning("Could not remove ROS 2 grader container %s", name)


def _safe_config(config: dict) -> dict:
    allowed = {
        "harness",
        "package_name",
        "executable",
        "topic",
        "message_type",
        "scan_topic",
        "scan_message_type",
        "expected_linear_x",
        "linear_tolerance",
        "angular_tolerance",
        "stop_distance",
        "move_seconds",
        "stop_tolerance_seconds",
        "minimum_publish_rate_hz",
        "test_weights",
    }
    return {key: value for key, value in config.items() if key in allowed}


def _valid_result(result: object) -> bool:
    return (
        isinstance(result, dict)
        and isinstance(result.get("success"), bool)
        and isinstance(result.get("error"), str)
        and isinstance(result.get("output"), str)
        and isinstance(result.get("tests"), list)
    )


def _container_failure_message(stderr: str) -> str:
    message = stderr.strip()
    lowered = message.lower()
    daemon_unavailable_markers = (
        "failed to connect to the docker api",
        "cannot connect to the docker daemon",
        "dockerdesktoplinuxengine",
        "is the docker daemon running",
    )
    if any(marker in lowered for marker in daemon_unavailable_markers):
        return (
            "The local ROS 2 grader cannot reach Docker Desktop. Start Docker "
            "Desktop with Linux containers, wait until it is ready, and run the tests again."
        )
    # Raw container output can reveal grader internals; keep it server-side.
    if message:
        logger.warning("ROS 2 grader container failed: %s", message[-2000:])
    return (
        "The ROS 2 grader stopped unexpectedly. Run the tests again; if this "
        "keeps happening, ask your instructor."
    )


def _executor_error(message: str) -> dict:
    return {
        "success": False,
        "error": message,
        "output": "",
        "tests": [],
    }
