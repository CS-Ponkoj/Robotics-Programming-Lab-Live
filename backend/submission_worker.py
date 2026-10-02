"""Execute one student submission in a short-lived isolated Python process."""

import ast
from contextlib import redirect_stdout
import io
import json
import sys
import traceback


ALLOWED_IMPORTS = frozenset({"math", "numpy", "scipy"})
MAX_OUTPUT_CHARS = 20_000
MAX_VALUE_CHARS = 20_000
ALLOWED_MODULE_ATTRIBUTES = {
    "math": {
        "acos", "asin", "atan", "atan2", "ceil", "cos", "degrees", "dist", "e",
        "exp", "fabs", "floor", "hypot", "inf", "isclose", "log", "log10",
        "pi", "radians", "sin", "sqrt", "tan", "tau",
    },
    "numpy": {
        "abs", "arange", "cos", "degrees", "e", "exp", "linspace", "pi",
        "radians", "sin", "sqrt", "tan",
    },
    "scipy.spatial": {"distance"},
    "scipy.spatial.distance": {"euclidean"},
}
ALLOWED_VALUE_METHODS = {
    "append", "clear", "copy", "count", "endswith", "extend", "get",
    "index", "insert", "items", "join", "keys", "lower", "pop", "remove",
    "replace", "reverse", "sort", "split", "startswith", "strip", "upper",
    "values",
}


class SubmissionSyntaxValidator(ast.NodeVisitor):
    """Reject access to Python introspection and unsafe scientific APIs."""

    def __init__(self):
        self.module_aliases = {}

    def visit_Import(self, node):
        for alias in node.names:
            root = alias.name.split(".", 1)[0]
            if root not in ALLOWED_IMPORTS:
                raise ImportError(f"Import of '{alias.name}' is not allowed")
            self.module_aliases[alias.asname or root] = alias.name

    def visit_ImportFrom(self, node):
        module = node.module or ""
        root = module.split(".", 1)[0]
        if node.level or root not in ALLOWED_IMPORTS:
            raise ImportError(f"Import of '{module}' is not allowed")
        allowed = ALLOWED_MODULE_ATTRIBUTES.get(module, set())
        for alias in node.names:
            if alias.name == "*" or alias.name not in allowed:
                raise ImportError(
                    f"Import of '{module}.{alias.name}' is not allowed"
                )
            self.module_aliases[alias.asname or alias.name] = (
                f"{module}.{alias.name}"
            )

    def visit_Name(self, node):
        if node.id.startswith("_"):
            raise ValueError(f"Name '{node.id}' is not allowed")

    def visit_Attribute(self, node):
        if node.attr.startswith("_"):
            raise ValueError(f"Attribute '{node.attr}' is not allowed")
        path = self._attribute_path(node)
        imported = self.module_aliases.get(path[0]) if path else None
        if imported:
            canonical = ".".join([imported, *path[1:-1]])
            if node.attr not in ALLOWED_MODULE_ATTRIBUTES.get(canonical, set()):
                raise ValueError(
                    f"Use of '{'.'.join(path)}' is not allowed"
                )
        elif node.attr not in ALLOWED_VALUE_METHODS:
            # Applies to every receiver, including literals and call results,
            # so "'{0.__globals__}'.format(f)" cannot bypass the allowlist.
            raise ValueError(f"Attribute '{node.attr}' is not allowed")
        self.generic_visit(node)

    @staticmethod
    def _attribute_path(node):
        parts = []
        current = node
        while isinstance(current, ast.Attribute):
            parts.append(current.attr)
            current = current.value
        if not isinstance(current, ast.Name):
            return None
        return [current.id, *reversed(parts)]


def validate_submission(code):
    tree = ast.parse(code, filename="<submission>", mode="exec")
    SubmissionSyntaxValidator().visit(tree)
    return tree


class CappedOutput(io.TextIOBase):
    def __init__(self, limit=MAX_OUTPUT_CHARS):
        self.limit = limit
        self.parts = []
        self.length = 0
        self.truncated = False

    def write(self, text):
        text = str(text)
        remaining = self.limit - self.length
        if remaining > 0:
            kept = text[:remaining]
            self.parts.append(kept)
            self.length += len(kept)
        if len(text) > remaining:
            self.truncated = True
        return len(text)

    def getvalue(self):
        output = "".join(self.parts)
        if self.truncated:
            output += "\n[output truncated]"
        return output


def safe_import(name, globals=None, locals=None, fromlist=(), level=0):
    root_module = name.split(".", 1)[0]
    if level != 0 or root_module not in ALLOWED_IMPORTS:
        raise ImportError(f"Import of '{name}' is not allowed")
    return __import__(name, globals, locals, fromlist, level)


def safe_builtins():
    return {
        "abs": abs,
        "all": all,
        "any": any,
        "bool": bool,
        "dict": dict,
        "enumerate": enumerate,
        "filter": filter,
        "float": float,
        "int": int,
        "len": len,
        "list": list,
        "map": map,
        "max": max,
        "min": min,
        "pow": pow,
        "print": print,
        "range": range,
        "repr": repr,
        "reversed": reversed,
        "round": round,
        "set": set,
        "sorted": sorted,
        "str": str,
        "sum": sum,
        "tuple": tuple,
        "zip": zip,
        "__build_class__": __build_class__,
        "__import__": safe_import,
    }


def json_safe_value(value):
    if type(value) in (bool, float, int) or value is None:
        return value
    if type(value) is str:
        return _bounded_text(value, "str")
    item = getattr(value, "item", None)
    if callable(item):
        converted = item()
        if type(converted) in (bool, float, int) or converted is None:
            return converted
        if type(converted) is str:
            return _bounded_text(converted, "str")
    text = repr(value)
    if len(text) > MAX_VALUE_CHARS:
        return _too_large(type(value).__name__)
    return {"unsupported_type": type(value).__name__, "repr": text}


def _bounded_text(value, type_name):
    return value if len(value) <= MAX_VALUE_CHARS else _too_large(type_name)


def _too_large(type_name):
    # Oversized results are never accepted as answers and are not copied back.
    return {"unsupported_type": type_name, "repr": "[value too large]"}


def format_error(error):
    if isinstance(error, SyntaxError):
        line_number = error.lineno or 0
    else:
        extracted = traceback.extract_tb(error.__traceback__)
        line_number = extracted[-1].lineno if extracted else 0
    return (
        f"{error.__class__.__name__} at line {line_number} of submission: "
        f"{error}"
    )


def execute(request):
    namespace = {
        "__builtins__": safe_builtins(),
        "__name__": "__submission__",
    }
    output = CappedOutput()

    try:
        tree = validate_submission(request["code"])
        with redirect_stdout(output):
            exec(compile(tree, "<submission>", "exec"), namespace, namespace)
    except BaseException as error:
        return {
            "success": False,
            "error": format_error(error),
            "output": output.getvalue(),
            "values": {},
        }

    values = {
        name: json_safe_value(namespace[name])
        for name in request["result_names"]
        if name in namespace
    }
    return {
        "success": True,
        "error": "",
        "output": output.getvalue(),
        "values": values,
    }


def main():
    try:
        request = json.load(sys.stdin)
        response = execute(request)
    except BaseException as error:
        response = {
            "success": False,
            "error": format_error(error),
            "output": "",
            "values": {},
        }
    json.dump(response, sys.stdout)


if __name__ == "__main__":
    main()
