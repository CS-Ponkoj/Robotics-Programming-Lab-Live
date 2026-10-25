from models import Assignment
import json
from pathlib import Path

import pytest
from graders.python_function import PythonFunctionGrader
from sandbox import SubprocessSandbox


def assignment() -> Assignment:
    return Assignment(
        id=99,
        stable_id="function-grader-test",
        version=1,
        title="Function grader test",
        grader_type="python_function",
        grader_config={
            "function_name": "calculate_values",
            "criteria": [
                {
                    "id": "sum",
                    "label": "Sum",
                    "weight": 40,
                    "success_feedback": "The sum is correct for every scenario.",
                    "failure_feedback": "Recheck how the two inputs are added.",
                },
                {
                    "id": "product",
                    "label": "Product",
                    "weight": 60,
                    "success_feedback": "The product is correct for every scenario.",
                    "failure_feedback": "Recheck how the two inputs are multiplied.",
                },
            ],
            "cases": [
                {"arguments": [2, 3], "expected": [5, 6]},
                {"arguments": [-4, 5], "expected": [1, -20]},
            ],
        },
    )


def test_function_grader_rejects_hardcoded_original_outputs():
    result = PythonFunctionGrader(SubprocessSandbox()).grade(
        assignment(),
        "def calculate_values(first, second):\n    return 5, 6",
    )

    assert result.execution_succeeded is True
    assert result.passed is False
    assert result.score == 0
    assert [item.passed for item in result.evidence] == [False, False]


def test_function_grader_awards_weighted_partial_credit_and_feedback():
    result = PythonFunctionGrader(SubprocessSandbox()).grade(
        assignment(),
        "def calculate_values(first, second):\n    return first + second, 0",
    )

    assert result.execution_succeeded is True
    assert result.passed is False
    assert result.score == 40
    assert [item.passed for item in result.evidence] == [True, False]
    assert result.evidence[1].message.startswith("Recheck how the two inputs are multiplied.")
    assert "every input scenario" in result.evidence[1].message


def test_function_grader_accepts_general_solution_without_exposing_cases():
    result = PythonFunctionGrader(SubprocessSandbox()).grade(
        assignment(),
        (
            "def calculate_values(first, second):\n"
            "    print(first, second)\n"
            "    return first + second, first * second"
        ),
    )

    assert result.execution_succeeded is True
    assert result.passed is True
    assert result.score == 100
    assert result.code_output == ""
    assert all(item.visibility == "hidden" for item in result.evidence)


def test_function_grader_returns_safe_error_when_function_is_missing():
    result = PythonFunctionGrader(SubprocessSandbox()).grade(
        assignment(), "answer = 11"
    )

    assert result.execution_succeeded is False
    assert result.passed is False
    assert result.score == 0
    assert result.execution_error == (
        "The required function could not complete every grading scenario (NameError)."
    )
    assert "2" not in result.execution_error
    assert "3" not in result.execution_error


def test_function_grader_passes_configured_dict_arguments_as_dicts():
    target = assignment()
    target.grader_config = {
        "function_name": "count_keys",
        "criteria": [{"id": "keys", "label": "Keys", "weight": 100}],
        "cases": [
            {"dict_arguments": [0], "arguments": [[[0, 10], [5, 2]]], "expected": [2]},
            {"dict_arguments": [0], "arguments": [[[3, 1]]], "expected": [1]},
        ],
    }
    result = PythonFunctionGrader(SubprocessSandbox()).grade(
        target,
        "def count_keys(readings):\n"
        "    copied = readings.copy()\n"
        "    return (len({angle for angle, distance in copied.items()}),)\n",
    )

    assert result.score == 100


@pytest.mark.parametrize("dict_arguments", [[1], [-1], ["0"], 0])
def test_function_grader_rejects_invalid_dict_argument_configuration(dict_arguments):
    target = assignment()
    target.grader_config = {
        **target.grader_config,
        "cases": [{"dict_arguments": dict_arguments, "arguments": [[[0, 1]]], "expected": [1, 1]}],
    }

    with pytest.raises(ValueError, match="test case configuration"):
        PythonFunctionGrader(SubprocessSandbox()).grade(
            target, "def calculate_values(first, second=0):\n    return 1, 1\n"
        )


@pytest.mark.parametrize(
    "copy_expression",
    [
        "dict(seed_readings)",
        "seed_readings.copy()",
        "{**seed_readings}",
        "{angle: distance for angle, distance in seed_readings.items()}",
    ],
)
def test_assignment_four_accepts_every_documented_way_to_copy_readings(copy_expression):
    data = json.loads((Path(__file__).parents[1] / "assignments/assignment_4.json").read_text(encoding="utf-8"))
    target = Assignment(id=4, stable_id=data["stable_id"], version=data["version"],
                        title=data["title"], grader_type=data["grader_type"], grader_config=data["grader_config"])
    answer = (Path(__file__).parents[2] / "assignments_answers/assignment_4_answer.py").read_text(encoding="utf-8")
    code = answer.replace("lidar_readings = dict(seed_readings)", f"lidar_readings = {copy_expression}")

    result = PythonFunctionGrader(SubprocessSandbox()).grade(target, code)

    assert result.score == 100


@pytest.mark.parametrize("use_parameters, expected_score", [(False, 0), (True, 50)])
def test_assignment_two_screenshot_global_points_and_genuine_partial_credit(use_parameters, expected_score):
    data = json.loads((Path(__file__).parents[1] / "assignments/assignment_2.json").read_text(encoding="utf-8"))
    target = Assignment(id=2, stable_id=data["stable_id"], version=data["version"],
                        title=data["title"], grader_type=data["grader_type"], grader_config=data["grader_config"])
    code = data["starter_code"].replace(
        "distance_to_hit = 0.0", "distance_to_hit = calculate_distance(start_point, hit_point)"
    ).replace(
        "distance_along_obstacle = 0.0",
        "distance_along_obstacle = (calculate_distance(hit_point, corner_a) + "
        "calculate_distance(corner_a, corner_b) + calculate_distance(corner_b, leave_point))",
    )
    if use_parameters:
        code = code.replace("calculate_distance(start_point, hit_point)", "calculate_distance(start, hit)")
        code = code.replace("calculate_distance(hit_point, corner_a)", "calculate_distance(hit, corner_a)")
        code = code.replace("calculate_distance(corner_b, leave_point)", "calculate_distance(corner_b, leave)")
    result = PythonFunctionGrader(SubprocessSandbox()).grade(target, code)
    assert result.score == expected_score
    if not use_parameters:
        # The example points live inside main(), so reading them from the
        # route function fails immediately and names the missing variable.
        assert result.execution_succeeded is False
        assert "NameError" in result.execution_error
        assert "start_point" in result.execution_error
        return
    assert result.execution_succeeded is True
    assert result.code_output.strip() == "4.0 4.0 0.0 0.0"
    assert [item.passed for item in result.evidence] == [True, True, False, False]
    for item in result.evidence:
        if not item.passed:
            assert "every input scenario" in item.message
            assert "printed example alone is not enough" in item.message


@pytest.mark.parametrize(
    "code, expected_reasons",
    [
        (
            "def calculate_values(first, second):\n    return first + second, first * second",
            ["passed", "passed"],
        ),
        # Hardcoding the first scenario is right for some inputs, never for all.
        (
            "def calculate_values(first, second):\n    return 5, 6",
            ["wrong_some_inputs", "wrong_some_inputs"],
        ),
        (
            "def calculate_values(first, second):\n    return first - second, 0",
            ["wrong_all_inputs", "wrong_all_inputs"],
        ),
        (
            "def calculate_values(first, second):\n"
            "    return first + second, {first * second}",
            ["passed", "unsupported_type"],
        ),
        (
            "def calculate_values(first, second):\n"
            "    if first < 0:\n"
            "        raise ValueError('negative')\n"
            "    return first + second, first * second",
            ["error_on_some_inputs", "error_on_some_inputs"],
        ),
        # A missing function fails while the grading scenarios run.
        ("answer = 11", ["error_on_some_inputs", "error_on_some_inputs"]),
        ("def calculate_values(first, second)\n    return 1, 2", ["not_checked", "not_checked"]),
    ],
)
def test_function_grader_classifies_failure_reasons_with_weights(code, expected_reasons):
    result = PythonFunctionGrader(SubprocessSandbox()).grade(assignment(), code)

    assert [item.reason for item in result.evidence] == expected_reasons
    assert [item.weight for item in result.evidence] == [40.0, 60.0]
    for item in result.evidence:
        dumped = item.model_dump()
        # Reasons classify the outcome without exposing protected case data.
        assert set(dumped) == {
            "test_id", "label", "passed", "message", "visibility", "reason", "weight",
            "earned_weight", "misconception_tag",
        }
        assert dumped["earned_weight"] is None
        assert dumped["visibility"] == "hidden"


def test_function_grader_attaches_misconception_tags_only_to_wrong_values():
    tagged = assignment()
    tagged.grader_config = {
        **tagged.grader_config,
        "criteria": [
            {**item, "misconception": f"incorrect-{item['id']}"}
            for item in tagged.grader_config["criteria"]
        ],
    }
    grader = PythonFunctionGrader(SubprocessSandbox())

    wrong_product = grader.grade(
        tagged, "def calculate_values(first, second):\n    return first + second, 0"
    )
    crashed = grader.grade(
        tagged, "def calculate_values(first, second):\n    return 1 / 0, 0"
    )

    assert [item.misconception_tag for item in wrong_product.evidence] == [
        None, "incorrect-product",
    ]
    # A crash is not evidence about the student's concept.
    assert [item.misconception_tag for item in crashed.evidence] == [None, None]
