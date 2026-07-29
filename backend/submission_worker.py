"""Execute one student submission in a short-lived isolated Python process."""

from contextlib import redirect_stdout
import io
import json
import sys
import traceback


ALLOWED_IMPORTS = frozenset({"math", "numpy", "scipy"})
MAX_OUTPUT_CHARS = 20_000


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
    if type(value) in (bool, float, int, str) or value is None:
        return value
    item = getattr(value, "item", None)
    if callable(item):
        converted = item()
        if type(converted) in (bool, float, int, str) or converted is None:
            return converted
    return {"unsupported_type": type(value).__name__, "repr": repr(value)}


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
        with redirect_stdout(output):
            exec(request["code"], namespace, namespace)
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
