import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app import create_app
from config import Settings
from data_contracts import SimulationConfig
from graders.python_function import PythonFunctionGrader, parse_playground_arguments
from models import Assignment
from playground_inputs import matches_parameter_kind, parameter_problems
from sandbox import SubprocessSandbox


ASSIGNMENTS = Path(__file__).parents[1] / "assignments"


def source(number: int) -> dict:
    return json.loads(
        (ASSIGNMENTS / f"assignment_{number}.json").read_text(encoding="utf-8")
    )


def function_parameters(data: dict) -> list[str]:
    signature = data["starter_code"].split(
        f"def {data['grader_config']['function_name']}(", 1
    )[1].split(")", 1)[0]
    return [item.strip() for item in signature.split(",") if item.strip()]


def example_arguments(data: dict) -> str:
    """The one-line sample the browser builds from the parameter examples."""
    return ", ".join(
        item["example"] for item in data["simulation_config"]["playground"]["parameters"]
    )


@pytest.mark.parametrize("number", [1, 2, 3, 4])
def test_parameters_describe_every_function_input_in_order(number):
    data = source(number)
    parameters = data["simulation_config"]["playground"]["parameters"]
    assert [item["name"] for item in parameters] == function_parameters(data)
    assert all(item["label"] and item["meaning"] for item in parameters)


@pytest.mark.parametrize("number", [1, 2, 3, 4])
def test_example_inputs_match_the_function_and_run_on_starter_code(number):
    data = source(number)
    arguments = parse_playground_arguments(example_arguments(data))
    parameters = data["simulation_config"]["playground"]["parameters"]
    assert parameter_problems(arguments, parameters) == []

    assignment = Assignment(
        id=number,
        stable_id=data["stable_id"],
        version=data["version"],
        title=data["title"],
        grader_type=data["grader_type"],
        grader_config=data["grader_config"],
    )
    outcome = PythonFunctionGrader(SubprocessSandbox(timeout_seconds=15)).try_arguments(
        assignment, data["starter_code"], arguments
    )
    assert outcome.success is True, outcome.error
    assert outcome.return_count == outcome.expected_return_count


def parameter(**overrides) -> dict:
    return {
        "name": "start",
        "kind": "point",
        "label": "Start",
        "example": "(1, 2)",
        **overrides,
    }


@pytest.mark.parametrize(
    "item, message",
    [
        (parameter(example="5"), "should be a point"),
        (parameter(example="(1, 2), (3, 4)"), "should be a point"),
        (parameter(example="__import__('os')"), "not valid input"),
        (parameter(kind="integer", example="2.5"), "whole number"),
        (parameter(kind="angle_map", example="{'north': 3}"), "whole-number angles"),
        (parameter(kind="list_of_points", example="[(1, 2), 3]"), "list of points"),
        (parameter(kind="vector"), "Input should be"),
        (parameter(name="2start"), "String should match pattern"),
        (parameter(label=""), "at least 1 character"),
    ],
)
def test_invalid_parameter_descriptions_are_rejected(item, message):
    with pytest.raises(ValidationError, match=message):
        SimulationConfig.model_validate({"playground": {"parameters": [item]}})


def test_playground_block_rules():
    with pytest.raises(ValidationError, match="unique"):
        SimulationConfig.model_validate(
            {"playground": {"parameters": [parameter(), parameter(label="Again")]}}
        )
    with pytest.raises(ValidationError, match="Extra inputs"):
        SimulationConfig.model_validate({"playground": {"expected": [1]}})
    # v6.3 stored a one-line sample; it is still accepted and then dropped.
    legacy = SimulationConfig.model_validate(
        {"playground": {"sample_arguments": "(1, 2)"}}
    ).model_dump(mode="json")
    assert legacy["playground"] == {
        "parameters": [],
        "scenarios": [],
        "hints_enabled": True,
    }
    assert "playground" not in SimulationConfig.model_validate(
        source(5)["simulation_config"]
    ).model_dump(mode="json")


@pytest.mark.parametrize(
    "kind, good, bad",
    [
        ("point", [(1, 2), [1.5, -2]], [(1,), (1, 2, 3), ("a", 1), (True, 1), 5]),
        ("number", [1, 2.5, -3], [True, "1", float("inf"), None]),
        ("integer", [0, 5, -2], [2.5, True, "5"]),
        ("list_of_points", [[], [(1, 2)], ((1, 2), (3, 4))], [[1, 2], [(1, 2), 3], "x"]),
        (
            "angle_map",
            [{}, {0: 10, 359: 9.5}],
            [{0.5: 1}, {True: 1}, {"0": 1}, {1: "far"}, [1]],
        ),
        ("text", ["Main Elevator", ""], [1, None]),
    ],
)
def test_parameter_kinds_accept_only_their_shape(kind, good, bad):
    assert all(matches_parameter_kind(kind, value) for value in good)
    assert not any(matches_parameter_kind(kind, value) for value in bad)


def test_parameter_problems_name_each_wrong_input():
    parameters = source(1)["simulation_config"]["playground"]["parameters"]
    problems = parameter_problems(
        parse_playground_arguments("(0, 0), 2, 3, (4, 5), (10, 5)"), parameters
    )
    assert problems == [
        {
            "parameter_index": 1,
            "message": "Hit point should be a point with two numbers, like (2.0, 1.0).",
        },
        {
            "parameter_index": 2,
            "message": "Corner should be a point with two numbers, like (2.0, 1.0).",
        },
    ]
    count = parameter_problems([(0, 0)], parameters)
    assert count[0]["parameter_index"] is None
    assert "Enter 5 inputs" in count[0]["message"]
    assert parameter_problems([1, 2], []) == []


@pytest.fixture()
def client(tmp_path):
    settings = Settings(
        database_url="sqlite://",
        admin_api_token="test-admin",
        openai_api_key=None,
        study_accounts_file=tmp_path / "study_accounts.json",
    )
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as value:
        yield value


def demo_headers(client) -> dict:
    token = client.post("/auth/demo").json()["token"]
    return {"Authorization": f"Bearer {token}"}


def test_playground_route_reports_the_exact_wrong_input(client):
    headers = demo_headers(client)
    code = source(1)["starter_code"]

    wrong = client.post(
        "/assignments/1/playground",
        json={"code": code, "arguments": "(0, 0), 2, 3, (4, 5), (10, 5)"},
        headers=headers,
    )
    assert wrong.status_code == 400
    body = wrong.json()
    assert body["error"].startswith("Hit point should be a point")
    assert [item["parameter_index"] for item in body["details"]] == [1, 2]
    assert body["details"][0]["location"] == ["arguments", "1"]
    assert body["details"][0]["type"] == "parameter_kind"

    too_few = client.post(
        "/assignments/1/playground",
        json={"code": code, "arguments": "(0, 0)"},
        headers=headers,
    )
    assert too_few.status_code == 400
    assert too_few.json()["details"][0]["parameter_index"] is None

    good = client.post(
        "/assignments/1/playground",
        json={"code": code, "arguments": example_arguments(source(1))},
        headers=headers,
    )
    assert good.status_code == 200
    assert good.json()["success"] is True


def test_student_payload_carries_parameter_descriptions(client):
    assignment = client.get("/assignments/3", headers=demo_headers(client)).json()
    playground = assignment["simulation_config"]["playground"]
    assert [item["name"] for item in playground["parameters"]] == function_parameters(
        source(3)
    )
    assert playground["hints_enabled"] is True
    assert "sample_arguments" not in playground


ANSWERS = Path(__file__).parents[2] / "assignments_answers"


def scenario_line(data: dict, scenario: dict) -> str:
    """The one-line input a scenario fills, in parameter order."""
    parameters = data["simulation_config"]["playground"]["parameters"]
    return ", ".join(scenario["values"][item["name"]] for item in parameters)


@pytest.mark.parametrize("number", [1, 2, 3, 4])
def test_every_scenario_runs_on_starter_code_and_the_maintained_answer(number):
    data = source(number)
    assignment = Assignment(
        id=number,
        stable_id=data["stable_id"],
        version=data["version"],
        title=data["title"],
        grader_type=data["grader_type"],
        grader_config=data["grader_config"],
    )
    grader = PythonFunctionGrader(SubprocessSandbox(timeout_seconds=15))
    answer = (ANSWERS / f"assignment_{number}_answer.py").read_text(encoding="utf-8")
    scenarios = data["simulation_config"]["playground"]["scenarios"]
    assert len(scenarios) >= 3
    for scenario in scenarios:
        arguments = parse_playground_arguments(scenario_line(data, scenario))
        for code in (data["starter_code"], answer):
            outcome = grader.try_arguments(assignment, code, arguments)
            assert outcome.success is True, (scenario["id"], outcome.error)
            assert outcome.return_count == outcome.expected_return_count


@pytest.mark.parametrize("number", [1, 2, 3, 4])
def test_scenarios_hold_inputs_only(number):
    """Descriptions guide what to look at and never quote a grading value."""
    data = source(number)
    scenarios = data["simulation_config"]["playground"]["scenarios"]
    # Inputs may hold any number; the free text must never quote a result.
    text = " ".join(item["label"] + " " + item["description"] for item in scenarios)
    for case in data["grader_config"]["cases"]:
        for expected in case["expected"]:
            if isinstance(expected, float) and not expected.is_integer():
                assert repr(expected) not in text
                assert f"{expected:.2f}" not in text


def scenario(**overrides) -> dict:
    return {
        "id": "edge",
        "label": "Edge case",
        "values": {"start": "(0, 0)"},
        **overrides,
    }


@pytest.mark.parametrize(
    "item, message",
    [
        (scenario(values={}), "exactly one value for each parameter"),
        (scenario(values={"start": "(0, 0)", "goal": "(1, 1)"}), "exactly one value"),
        (scenario(values={"start": "5"}), "should be a point"),
        (scenario(values={"start": "__import__('os')"}), "not valid input"),
        (scenario(expected=[1.0]), "Extra inputs"),
        (scenario(id="Edge"), "String should match pattern"),
        (scenario(label=""), "at least 1 character"),
    ],
)
def test_invalid_scenarios_are_rejected(item, message):
    with pytest.raises(ValidationError, match=message):
        SimulationConfig.model_validate(
            {"playground": {"parameters": [parameter()], "scenarios": [item]}}
        )


def test_scenario_ids_are_unique_and_limited():
    with pytest.raises(ValidationError, match="unique"):
        SimulationConfig.model_validate(
            {
                "playground": {
                    "parameters": [parameter()],
                    "scenarios": [scenario(), scenario(label="Again")],
                }
            }
        )
    with pytest.raises(ValidationError, match="at most 8"):
        SimulationConfig.model_validate(
            {
                "playground": {
                    "parameters": [parameter()],
                    "scenarios": [scenario(id=f"edge_{index}") for index in range(9)],
                }
            }
        )
