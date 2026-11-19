"""Build and evaluate one trusted-template ROS 2 Python submission."""

from __future__ import annotations

import ast
import json
import os
from pathlib import Path
import subprocess
import sys


WORKSPACE = Path("/workspace")
MAX_PROJECT_FILES = 30
MAX_FILE_CHARS = 100_000
ALLOWED_IMPORT_ROOTS = frozenset(
    {"geometry_msgs", "math", "rclpy", "sensor_msgs"}
)
# Extra import roots an assignment may opt into with grader_config
# "extra_import_roots"; only course interfaces built into the image qualify.
OPTIONAL_IMPORT_ROOTS = frozenset({"rse_msgs"})
ROS2_HARNESSES = {
    "drive_forward": "/grader/ros2_topic_harness.py",
    "obstacle_stop": "/grader/ros2_obstacle_harness.py",
    "wall_stop_open": "/grader/ros2_wall_stop_harness.py",
    "open_side": "/grader/ros2_open_side_harness.py",
}
# Course interfaces (rse_msgs) built into the image; see Dockerfile.ros2.
COURSE_OVERLAY_SETUP = "/opt/rse_ws/install/setup.bash"
SIMULATION_HARNESS = "/grader/ros2_sim_harness.py"
HARNESS_TIMEOUT_SECONDS = 12
SIMULATION_TIMEOUT_SECONDS = 16


def allowed_import_roots(config: dict) -> frozenset[str]:
    extra = config.get("extra_import_roots", []) if isinstance(config, dict) else []
    if not isinstance(extra, list):
        return ALLOWED_IMPORT_ROOTS
    return ALLOWED_IMPORT_ROOTS | (frozenset(map(str, extra)) & OPTIONAL_IMPORT_ROOTS)


def validate_controller(code: str, allowed: frozenset[str] = ALLOWED_IMPORT_ROOTS) -> None:
    tree = ast.parse(code, filename="controller.py", mode="exec")
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names = [alias.name for alias in node.names]
        elif isinstance(node, ast.ImportFrom):
            if node.level:
                raise ImportError("Relative imports are not allowed in controller.py")
            names = [node.module or ""]
        else:
            continue
        for name in names:
            root = name.split(".", 1)[0]
            if root not in allowed:
                raise ImportError(f"Import of '{name}' is not allowed")


def prepare_workspace(request: dict) -> None:
    code = request.get("code", "")
    files = request.get("project_files", [])
    if not isinstance(code, str) or not code.strip():
        raise ValueError("A non-empty controller.py submission is required")
    if not isinstance(files, list) or len(files) > MAX_PROJECT_FILES:
        raise ValueError("Invalid ROS project file manifest")
    validate_controller(code, allowed_import_roots(request.get("config", {})))

    editable_count = 0
    for item in files:
        if not isinstance(item, dict):
            raise ValueError("Invalid ROS project file entry")
        relative = Path(str(item.get("path", "")))
        if relative.is_absolute() or ".." in relative.parts or not relative.parts:
            raise ValueError("Invalid ROS project file path")
        content = str(item.get("content", ""))
        if item.get("editable") is True:
            editable_count += 1
            content = code
        if len(content) > MAX_FILE_CHARS:
            raise ValueError("ROS project file is too large")
        destination = WORKSPACE / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(content, encoding="utf-8")
    if editable_count != 1:
        raise ValueError("The ROS assignment must define exactly one editable file")


def run_command(command: list[str], timeout: float) -> subprocess.CompletedProcess:
    return subprocess.run(
        command,
        cwd=WORKSPACE,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
        env=os.environ.copy(),
    )


def simulating(config: dict) -> bool:
    return isinstance(config, dict) and config.get("mode") == "simulate"


def select_harness(config: dict) -> str:
    if simulating(config):
        if not isinstance(config.get("simulation"), dict):
            raise ValueError("This assignment has no simulation scenario.")
        return SIMULATION_HARNESS
    harness_name = str(config.get("harness", "drive_forward"))
    try:
        return ROS2_HARNESSES[harness_name]
    except KeyError as error:
        raise ValueError(f"Unsupported ROS 2 harness: {harness_name}") from error


def static_code_tests(request: dict) -> list[dict]:
    """Source checks for assignments whose structure the student designs."""
    config = request.get("config", {})
    if not isinstance(config, dict) or not config.get("code_checks") or simulating(config):
        return []
    from ros2_code_checks import run_code_checks

    return run_code_checks(str(request.get("code", "")), config)


def evaluate(request: dict) -> dict:
    try:
        prepare_workspace(request)
    except (SyntaxError, ImportError, ValueError) as error:
        response = failure(f"{error.__class__.__name__}: {error}")
        if isinstance(error, ImportError) and request.get("config", {}).get("code_checks"):
            response["tests"] = [
                test_result("imports-allowed", False, f"{error}. Use only rclpy, math, geometry_msgs and sensor_msgs.")
            ]
        return response
    code_tests = static_code_tests(request)

    build = run_command(
        [
            "colcon",
            "build",
            "--base-paths",
            "src",
            "--packages-select",
            str(request.get("config", {}).get("package_name", "robot_motion")),
            "--event-handlers",
            "console_direct+",
        ],
        timeout=10,
    )
    if build.returncode != 0:
        detail = (build.stderr or build.stdout).strip()[-3000:]
        return {
            "success": False,
            "error": detail or "The ROS 2 package did not build.",
            "output": "",
            "tests": [
                test_result(
                    "package-build",
                    False,
                    "The ROS 2 package did not build. Review controller.py for syntax or import errors.",
                ),
                *code_tests,
            ],
        }

    config = request.get("config", {})
    try:
        harness_path = select_harness(config)
    except ValueError as error:
        return failure(str(error))
    config_json = json.dumps(config)
    overlay = (
        f"source {COURSE_OVERLAY_SETUP} && " if Path(COURSE_OVERLAY_SETUP).is_file() else ""
    )
    shell_command = (
        "source /opt/ros/jazzy/setup.bash && "
        f"{overlay}"
        "source /workspace/install/setup.bash && "
        f"python3 {harness_path}"
    )
    environment = os.environ.copy()
    environment["ROS_GRADER_CONFIG"] = config_json
    try:
        harness = subprocess.run(
            ["bash", "-lc", shell_command],
            cwd=WORKSPACE,
            capture_output=True,
            text=True,
            timeout=SIMULATION_TIMEOUT_SECONDS if simulating(config) else HARNESS_TIMEOUT_SECONDS,
            check=False,
            env=environment,
        )
    except subprocess.TimeoutExpired:
        return failure("The ROS 2 node exceeded the execution time limit.")
    if harness.returncode != 0:
        return failure(
            redact_grader_frames(harness.stderr.strip())[-2000:]
            or "The ROS 2 node test failed."
        )
    try:
        runtime = json.loads(harness.stdout)
    except json.JSONDecodeError:
        return failure("The ROS 2 runtime test returned an invalid response.")
    runtime_tests = runtime.get("tests", []) if isinstance(runtime, dict) else []
    runtime_error = str(runtime.get("runtime_error", ""))
    tests = [
        test_result("package-build", True, "The ROS 2 package built successfully."),
        *code_tests,
        *runtime_tests,
    ]
    response = {
        "success": not bool(runtime_error),
        "error": runtime_error,
        "output": runtime.get("output", ""),
        "tests": tests,
    }
    if simulating(config):
        replay = runtime.get("simulation")
        response["simulation"] = replay if isinstance(replay, dict) else None
        response["tests"] = []
    elif isinstance(runtime.get("observations"), dict):
        response["observations"] = runtime["observations"]
    return response


def redact_grader_frames(text: str) -> str:
    """Remove hidden-harness traceback frames, keeping the student's frames."""
    kept = []
    skipping = False
    for line in text.splitlines():
        if line.startswith('  File "'):
            skipping = '"/grader/' in line
            if skipping:
                continue
        elif skipping and line.startswith("    "):
            continue
        else:
            skipping = False
        kept.append(line.replace("/grader/", "<grader>/"))
    return "\n".join(kept)


def test_result(test_id: str, passed: bool, message: str) -> dict:
    return {"id": test_id, "passed": passed, "message": message}


def failure(message: str) -> dict:
    return {"success": False, "error": message, "output": "", "tests": []}


def main() -> None:
    try:
        request = json.load(sys.stdin)
        response = evaluate(request)
    except BaseException as error:
        response = failure(f"ROS 2 grader error: {error}")
    json.dump(response, sys.stdout)


if __name__ == "__main__":
    main()
