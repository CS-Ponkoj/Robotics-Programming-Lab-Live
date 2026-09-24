from tokenize import TokenError

import black


class CodeFormattingError(ValueError):
    """Raised when submitted Python cannot be formatted safely."""


def format_python_code(code: str) -> str:
    try:
        return black.format_str(
            code,
            mode=black.Mode(line_length=88, target_versions={black.TargetVersion.PY314}),
        )
    except (black.InvalidInput, TokenError) as error:
        raise CodeFormattingError("Fix the Python syntax before formatting.") from error
