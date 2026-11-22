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
# Assignments whose instructions name a narrower set of imports. Assignment 8
# (open_side) reads the course's Flbr message, never a raw LaserScan.
HARNESS_IMPORT_ROOTS = {
    "wall_stop_open": frozenset({"geometry_msgs", "math", "rclpy", "sensor_msgs"}),
    "open_side": frozenset({"geometry_msgs", "math", "rclpy"}),
}
# Built-ins and attributes that reach around the import allow-list or read
# files. Docker remains the security boundary; this keeps the rules honest.
FORBIDDEN_NAMES = frozenset({
    "__import__", "__builtins__", "__loader__", "__spec__", "breakpoint", "compile",
    "delattr", "eval", "exec", "getattr", "globals", "input", "locals", "open",
    "setattr", "vars",
})
ALLOWED_DUNDER_ATTRIBUTES = frozenset({"__init__", "__name__"})
ROS2_HARNESSES = {
    "drive_forward": "/grader/ros2_topic_harness.py",
    "obstacle_stop": "/grader/ros2_obstacle_harness.py",
    "wall_stop_open": "/grader/ros2_wall_stop_harness.py",
    "open_side": "/grader/ros2_open_side_harness.py",
}
# Checks each open-structure harness reports, so a run that stops early can
# still answer every check with one clear status instead of N failures.
HARNESS_CHECK_IDS = {
    "wall_stop_open": (
        "node-start", "returns-node", "cmd-vel-publisher", "scan-subscription",
        "drive-open-floor", "drive-wall-far", "stop-wall-0-3", "stop-wall-0-2",
        "stay-stopped", "resume-motion", "straight-motion", "publish-rate",
        "one-command-per-scan",
    ),
    "open_side": (
        "node-start", "flbr-response", "cmd-vel-topic", "clear-path-forward",
        "stop-when-blocked", "turn-toward-open-side", "stop-at-threshold",
        "equal-sides-turn-right", "unknown-distance-safe", "resume-forward",
    ),
}
NOT_RUN_MESSAGE = "Not run: the code stopped with an error before this check."
# Course interfaces (rse_msgs) built into the image; see Dockerfile.ros2.
COURSE_OVERLAY_SETUP = "/opt/rse_ws/install/setup.bash"
SIMULATION_HARNESS = "/grader/ros2_sim_harness.py"
HARNESS_TIMEOUT_SECONDS = 12
SIMULATION_TIMEOUT_SECONDS = 16


class ForbiddenCodeError(ImportError):
    """controller.py uses a built-in that bypasses the import rules."""


def allowed_import_roots(config: dict) -> frozenset[str]:
    if not isinstance(config, dict):
        return ALLOWED_IMPORT_ROOTS
    base = HARNESS_IMPORT_ROOTS.get(str(config.get("harness", "")), ALLOWED_IMPORT_ROOTS)
    extra = config.get("extra_import_roots", [])
    if not isinstance(extra, list):
        return base
    return base | (frozenset(map(str, extra)) & OPTIONAL_IMPORT_ROOTS)


ALWAYS_FORBIDDEN = frozenset({"__import__", "__builtins__", "__loader__", "__spec__"})
# Every forbidden name except input(), which cannot reach anything here.
STRICTLY_FORBIDDEN = (FORBIDDEN_NAMES | ALWAYS_FORBIDDEN) - {"input"}


def _defined_names(tree: ast.AST) -> set[str]:
    """Names the student's own code binds: variables, parameters, functions,
    classes and import aliases. Such a name no longer means the built-in."""
    names: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Name) and isinstance(node.ctx, (ast.Store, ast.Del)):
            names.add(node.id)
        elif isinstance(node, ast.arg):
            names.add(node.arg)
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            names.add(node.name)
        elif isinstance(node, (ast.Import, ast.ImportFrom)):
            names.update((alias.asname or alias.name).split(".", 1)[0] for alias in node.names)
    return names


def _article(word: str) -> str:
    return "an" if word[:1].lower() in "aeiou" else "a"


def _scope_bindings(scope: ast.AST) -> set[str]:
    """Names bound directly in one scope (not in nested functions)."""
    names: set[str] = set()
    if isinstance(scope, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda)):
        arguments = scope.args
        for arg in (*arguments.posonlyargs, *arguments.args, *arguments.kwonlyargs,
                    arguments.vararg, arguments.kwarg):
            if arg is not None:
                names.add(arg.arg)
    stack = list(ast.iter_child_nodes(scope))
    while stack:
        node = stack.pop()
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            names.add(node.name)
            continue
        if isinstance(node, ast.Lambda):
            continue
        if isinstance(node, ast.Name) and isinstance(node.ctx, (ast.Store, ast.Del)):
            names.add(node.id)
        elif isinstance(node, (ast.Import, ast.ImportFrom)):
            names.update((alias.asname or alias.name).split(".", 1)[0] for alias in node.names)
        stack.extend(ast.iter_child_nodes(node))
    return names


def _check_forbidden_names(scope: ast.AST, visible: frozenset[str]) -> None:
    own = visible | _scope_bindings(scope)
    stack = list(ast.iter_child_nodes(scope))
    while stack:
        node = stack.pop()
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and (
            node.name in STRICTLY_FORBIDDEN
        ):
            raise ForbiddenCodeError(f"Use of '{node.name}' is not allowed in controller.py")
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda)):
            for arg in (*node.args.posonlyargs, *node.args.args, *node.args.kwonlyargs,
                        node.args.vararg, node.args.kwarg):
                if arg is not None and arg.arg in STRICTLY_FORBIDDEN:
                    raise ForbiddenCodeError(f"Use of '{arg.arg}' is not allowed in controller.py")
            # Defaults and decorators belong to the outer scope.
            for outer in (*node.args.defaults, *node.args.kw_defaults,
                          *getattr(node, "decorator_list", [])):
                if outer is not None:
                    stack.append(outer)
            _check_forbidden_names(node, own)
            continue
        if isinstance(node, ast.ClassDef):
            stack.extend((*node.bases, *node.keywords, *node.decorator_list))
            for item in node.body:
                _check_forbidden_names(ast.Module(body=[item], type_ignores=[]), own)
            continue
        if isinstance(node, ast.Name) and (
            node.id in ALWAYS_FORBIDDEN
            or (node.id in FORBIDDEN_NAMES and node.id not in own)
        ):
            raise ForbiddenCodeError(f"Use of '{node.id}' is not allowed in controller.py")
        # These names reach outside the node; they may not be used or bound in
        # any form, because a binding that runs only sometimes (an if, a loop,
        # a comprehension) cannot be told apart from the built-in statically.
        bound = (
            node.id if isinstance(node, ast.Name)
            else node.arg if isinstance(node, ast.arg)
            else node.name if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef))
            else None
        )
        if bound in STRICTLY_FORBIDDEN:
            raise ForbiddenCodeError(f"Use of '{bound}' is not allowed in controller.py")
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            for alias in node.names:
                if (alias.asname or "") in STRICTLY_FORBIDDEN:
                    raise ForbiddenCodeError(f"Use of '{alias.asname}' is not allowed in controller.py")
        stack.extend(ast.iter_child_nodes(node))


def validate_controller(code: str, allowed: frozenset[str] = ALLOWED_IMPORT_ROOTS) -> None:
    tree = ast.parse(code, filename="controller.py", mode="exec")
    _check_forbidden_names(tree, frozenset())
    for node in ast.walk(tree):
        if (
            isinstance(node, ast.Attribute)
            and node.attr.startswith("__")
            and node.attr.endswith("__")
            and node.attr not in ALLOWED_DUNDER_ATTRIBUTES
        ):
            raise ForbiddenCodeError(f"Use of '{node.attr}' is not allowed in controller.py")
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


def code_checks_enabled(config: dict) -> bool:
    return isinstance(config, dict) and bool(config.get("code_checks")) and not simulating(config)


def static_code_tests(request: dict) -> list[dict]:
    """Source checks for assignments whose structure the student designs."""
    config = request.get("config", {})
    if not code_checks_enabled(config):
        return []
    from ros2_code_checks import run_code_checks

    return run_code_checks(
        str(request.get("code", "")), config, sorted(allowed_import_roots(config))
    )


def expected_check_ids(config: dict) -> list[str]:
    """Every check an open-structure run reports, or [] for older harnesses."""
    if not isinstance(config, dict) or simulating(config):
        return []
    runtime = HARNESS_CHECK_IDS.get(str(config.get("harness", "")))
    if runtime is None:
        return []
    code: tuple[str, ...] = ()
    if code_checks_enabled(config):
        from ros2_code_checks import selected_checks

        code = selected_checks(config)
    return ["package-build", *code, *runtime]


def with_not_run(config: dict, tests: list[dict], message: str = NOT_RUN_MESSAGE) -> list[dict]:
    """Answer every check the run did not reach with one clear "not run" status."""
    reported = {item.get("id") for item in tests}
    return tests + [
        not_run(test_id, message)
        for test_id in expected_check_ids(config)
        if test_id not in reported
    ]


def describe_roots(config: dict) -> str:
    from ros2_code_checks import describe_imports

    return describe_imports(allowed_import_roots(config))


def rejected_response(request: dict, error: Exception) -> dict:
    """Validation stopped the run: report the one cause and mark the rest not run."""
    config = request.get("config", {})
    config = config if isinstance(config, dict) else {}
    response = failure(f"{error.__class__.__name__}: {error}")
    if not expected_check_ids(config):
        if isinstance(error, ImportError) and config.get("code_checks"):
            response["tests"] = [
                test_result("imports-allowed", False, f"{error}. Use only {describe_roots(config)}.")
            ]
        return response
    if isinstance(error, SyntaxError):
        where = f" on line {error.lineno}" if error.lineno else ""
        cause = [test_result(
            "package-build", False,
            f"The package was not built: controller.py has {_article(error.__class__.__name__)} "
            f"{error.__class__.__name__}{where} "
            f"({error.msg}).",
        )]
    elif isinstance(error, ImportError):
        rule = f"{error}. Use only {describe_roots(config)}."
        if isinstance(error, ForbiddenCodeError):
            rule = (
                f"{error}. Import only {describe_roots(config)}; built-ins such as open(), "
                "eval(), exec() and __import__() are not allowed."
            )
        cause = [test_result("imports-allowed", False, rule)]
        if "imports-allowed" not in expected_check_ids(config):
            # Without its own check the import rule is reported on the build.
            cause.append(test_result("package-build", False, f"The package was not built: {rule}"))
    else:
        cause = [test_result("package-build", False, f"The package was not built: {error}.")]
    response["tests"] = with_not_run(config, cause)
    return response


def evaluate(request: dict) -> dict:
    try:
        prepare_workspace(request)
    except (SyntaxError, ImportError, ValueError) as error:
        return rejected_response(request, error)
    config = request.get("config", {})
    code_tests = static_code_tests(request)

    build = run_command(
        [
            "colcon",
            "build",
            "--base-paths",
            "src",
            "--packages-select",
            str(config.get("package_name", "robot_motion")),
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
            "tests": with_not_run(config, [
                test_result(
                    "package-build",
                    False,
                    "The ROS 2 package did not build. Review controller.py for syntax or import errors.",
                ),
                *code_tests,
            ]),
        }

    try:
        harness_path = select_harness(config)
    except ValueError as error:
        return failure(str(error))
    built = [test_result("package-build", True, "The ROS 2 package built successfully."), *code_tests]
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
        response = failure("The ROS 2 node exceeded the execution time limit.")
        response["tests"] = with_not_run(
            config, list(built) if expected_check_ids(config) else [],
            "Not checked: the test run exceeded its time limit and was stopped.",
        )
        return response
    if harness.returncode != 0:
        response = failure(
            redact_grader_frames(harness.stderr.strip())[-2000:]
            or "The ROS 2 node test failed."
        )
        response["tests"] = with_not_run(
            config, list(built) if expected_check_ids(config) else [],
            "Not checked: the grader could not finish this run. Run the tests again.",
        )
        return response
    try:
        runtime = json.loads(harness.stdout)
    except json.JSONDecodeError:
        return failure("The ROS 2 runtime test returned an invalid response.")
    runtime_tests = runtime.get("tests", []) if isinstance(runtime, dict) else []
    runtime_error = str(runtime.get("runtime_error", ""))
    response = {
        "success": not bool(runtime_error),
        "error": runtime_error,
        "output": runtime.get("output", ""),
        "tests": [*built, *runtime_tests],
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


def not_run(test_id: str, message: str = NOT_RUN_MESSAGE) -> dict:
    return {"id": test_id, "passed": False, "message": message, "status": "not_run"}


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
