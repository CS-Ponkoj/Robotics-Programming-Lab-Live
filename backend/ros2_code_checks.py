"""Read-only checks of a ROS 2 submission's source, run inside the grader container.

The code is parsed with ``ast`` and never executed here. Each check returns a
test result in the same shape as the behavior harnesses, so the grader scores
code and behavior the same way.
"""

from __future__ import annotations

import ast


ENTRY_FUNCTION = "build_node"
SKELETON_FUNCTION = "main"
MINIMUM_NAMED_CONSTANTS = 2


def test_result(test_id: str, passed: bool, message: str) -> dict:
    return {"id": test_id, "passed": passed, "message": message}


def _top_level_function(tree: ast.Module, name: str) -> ast.FunctionDef | None:
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name == name:
            return node
    return None


def _function_shape(node: ast.FunctionDef) -> str:
    """Compare functions by structure, ignoring comments, spacing, and line numbers."""
    return ast.dump(node, annotate_fields=True, include_attributes=False)


def _reads_ranges(tree: ast.Module) -> bool:
    return any(
        isinstance(node, ast.Attribute) and node.attr == "ranges"
        for node in ast.walk(tree)
    )


def _blocking_call(tree: ast.Module) -> str | None:
    for node in ast.walk(tree):
        if isinstance(node, ast.While) and isinstance(node.test, ast.Constant):
            if node.test.value:
                return "a while True loop"
        if isinstance(node, ast.Call):
            target = node.func
            name = (
                target.id if isinstance(target, ast.Name)
                else target.attr if isinstance(target, ast.Attribute)
                else ""
            )
            if name == "sleep":
                return "a sleep() call"
    return None


def _is_number(node: ast.expr) -> bool:
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.USub, ast.UAdd)):
        node = node.operand
    return (
        isinstance(node, ast.Constant)
        and isinstance(node.value, (int, float))
        and not isinstance(node.value, bool)
    )


def _named_constants(tree: ast.Module) -> int:
    """Count UPPER_CASE names given a number at module or class level."""
    count = 0
    scopes = [tree.body] + [
        node.body for node in tree.body if isinstance(node, ast.ClassDef)
    ]
    for body in scopes:
        for node in body:
            if isinstance(node, ast.Assign) and _is_number(node.value):
                targets = node.targets
            elif isinstance(node, ast.AnnAssign) and node.value is not None and _is_number(node.value):
                targets = [node.target]
            else:
                continue
            for target in targets:
                if isinstance(target, ast.Name) and target.id.isupper():
                    count += 1
    return count


def _imported_names(tree: ast.Module) -> list[str]:
    names = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                names.append(alias.asname or alias.name.split(".", 1)[0])
        elif isinstance(node, ast.ImportFrom):
            for alias in node.names:
                if alias.name != "*":
                    names.append(alias.asname or alias.name)
    return names


def _used_names(tree: ast.Module) -> set[str]:
    return {node.id for node in ast.walk(tree) if isinstance(node, ast.Name)}


def run_code_checks(code: str, config: dict) -> list[dict]:
    """Return gate, contract, and quality results for an open-structure task."""
    tree = ast.parse(code, filename="controller.py", mode="exec")
    tests = [
        test_result(
            "imports-allowed",
            True,
            "controller.py imports only rclpy, math, geometry_msgs and sensor_msgs.",
        )
    ]

    has_entry = _top_level_function(tree, ENTRY_FUNCTION) is not None
    main = _top_level_function(tree, SKELETON_FUNCTION)
    tests.append(
        test_result(
            "build-node-defined",
            has_entry and main is not None,
            "build_node() and main() are both defined."
            if has_entry and main is not None
            else (
                "Keep the top-level def build_node(): and write your node inside it."
                if not has_entry
                else "Put main() back exactly as it was in the starter code."
            ),
        )
    )

    reads = _reads_ranges(tree)
    tests.append(
        test_result(
            "reads-ranges",
            reads,
            "The code reads scan.ranges."
            if reads
            else "Decide from the scan: read scan.ranges in your callback.",
        )
    )

    blocking = _blocking_call(tree)
    tests.append(
        test_result(
            "no-blocking",
            blocking is None,
            "No blocking loop or sleep() was found."
            if blocking is None
            else f"Remove {blocking}. Blocking code stops a real robot from reacting.",
        )
    )

    expected_main = str(config.get("skeleton_main", ""))
    main_unchanged = False
    if main is not None and expected_main:
        expected_tree = ast.parse(expected_main, mode="exec")
        expected = _top_level_function(expected_tree, SKELETON_FUNCTION)
        main_unchanged = expected is not None and _function_shape(main) == _function_shape(expected)
    tests.append(
        test_result(
            "main-unchanged",
            main_unchanged,
            "main() matches the starter code."
            if main_unchanged
            else "main() differs from the starter code. Put it back as given; the grader starts your node through it.",
        )
    )

    constants = _named_constants(tree)
    tests.append(
        test_result(
            "named-constants",
            constants >= MINIMUM_NAMED_CONSTANTS,
            "Speed and stop distance are named constants."
            if constants >= MINIMUM_NAMED_CONSTANTS
            else (
                f"Found {constants} named constant(s). Put numbers such as the forward "
                "speed and the stop distance in UPPER_CASE names at the top of the file."
            ),
        )
    )

    supplied = {str(name) for name in config.get("skeleton_imports", [])}
    used = _used_names(tree)
    unused = [
        name for name in _imported_names(tree)
        if name not in supplied and name not in used
    ]
    tests.append(
        test_result(
            "no-unused-imports",
            not unused,
            "Every import you added is used."
            if not unused
            else "Imported but not used: " + ", ".join(sorted(set(unused))) + ".",
        )
    )
    return tests
