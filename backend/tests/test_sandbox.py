from sandbox import SubprocessSandbox


def test_subprocess_sandbox_rejects_python_object_introspection():
    result = SubprocessSandbox().execute(
        "classes = ().__class__.__base__.__subclasses__()",
        ["classes"],
    )

    assert result["success"] is False
    assert "Attribute '__subclasses__' is not allowed" in result["error"]


def test_subprocess_sandbox_rejects_unsafe_numpy_file_api():
    result = SubprocessSandbox().execute(
        "import numpy as np\nvalue = np.load('/tmp/secret')",
        ["value"],
    )

    assert result["success"] is False
    assert "Use of 'np.load' is not allowed" in result["error"]


def test_subprocess_sandbox_keeps_supported_scientific_math():
    result = SubprocessSandbox().execute(
        """
import math
import numpy as np
from scipy.spatial import distance

value = math.sqrt(9) + np.sin(np.radians(90)) + distance.euclidean((0, 0), (3, 4))
""",
        ["value"],
    )

    assert result["success"] is True
    assert result["values"]["value"] == 9.0
