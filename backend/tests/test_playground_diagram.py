import copy
import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app import create_app
from config import Settings
from data_contracts import SimulationConfig
from graders.python_function import (
    PythonFunctionGrader,
    parse_playground_arguments,
    playground_json_value,
)
from models import Assignment
from sandbox import SubprocessSandbox


ASSIGNMENTS = Path(__file__).parents[1] / "assignments"


def source(number: int) -> dict:
    return json.loads(
        (ASSIGNMENTS / f"assignment_{number}.json").read_text(encoding="utf-8")
    )


def route_diagram() -> dict:
    return copy.deepcopy(source(3)["simulation_config"]["diagram"])


@pytest.mark.parametrize("number", [1, 2, 3, 4])
def test_function_assignments_declare_a_valid_diagram(number):
    data = source(number)
    config = SimulationConfig.model_validate(data["simulation_config"])

    assert config.enabled is True
    assert config.provider == "diagram"
    diagram = config.diagram
    function_criteria = len(data["grader_config"]["criteria"])
    # Every reference points at a real function argument or returned value.
    parameters = data["starter_code"].split(
        f"def {data['grader_config']['function_name']}(", 1
    )[1].split(")", 1)[0]
    argument_count = len([item for item in parameters.split(",") if item.strip()])
    argument_refs = [item.arg for item in diagram.points]
    argument_refs += [item.from_arg for item in diagram.arcs]
    argument_refs += [item.to_arg for item in diagram.arcs]
    argument_refs += [item.arg for item in diagram.rays if item.arg is not None]
    argument_refs += [
        item.half_width_arg for item in diagram.rays if item.half_width_arg is not None
    ]
    if diagram.readings:
        argument_refs.append(diagram.readings.arg)
    assert all(index < argument_count for index in argument_refs)
    value_refs = [item.value for item in diagram.paths if item.value is not None]
    value_refs += [item.value for item in diagram.rays if item.value is not None]
    value_refs += diagram.legend_values
    for check in diagram.checks:
        value_refs += [*check.parts, *check.candidates]
        value_refs += [item for item in (check.total, check.label, check.best) if item is not None]
    assert all(index < function_criteria for index in value_refs)


@pytest.mark.parametrize("number", [1, 2, 3, 4])
def test_diagrams_hold_no_grading_numbers(number):
    """Diagrams only reference indices; protected case values never appear."""
    data = source(number)
    diagram_text = json.dumps(data["simulation_config"]["diagram"])
    for case in data["grader_config"]["cases"]:
        for expected in case["expected"]:
            if isinstance(expected, float):
                assert repr(expected) not in diagram_text


@pytest.mark.parametrize("number", [5, 6])
def test_assignments_without_a_diagram_keep_their_stored_shape(number):
    config = SimulationConfig.model_validate(source(number)["simulation_config"])
    assert "diagram" not in config.model_dump(mode="json")


@pytest.mark.parametrize(
    "mutate, message",
    [
        (lambda d: d["paths"][0]["points"].__setitem__(0, "Q"), "unknown point"),
        (lambda d: d["paths"][0]["points"].__setitem__(1, "M"), "only for a point list"),
        (lambda d: d["paths"][1]["points"].__setitem__(1, "E_s*"), "only for a point list"),
        (lambda d: d["points"].append({"id": "S", "arg": 1}), "unique"),
        (lambda d: d["points"].__setitem__(0, {"id": "S", "arg": 20}), "less than or equal"),
        (lambda d: d["paths"][0].__setitem__("value", 30), "less than or equal"),
        (lambda d: d["paths"][0].__setitem__("points", ["S"]), "at least 2"),
        (lambda d: d["checks"][0].__setitem__("tie_index", 2), "tie_index"),
        (lambda d: d["checks"][0].__setitem__("labels", ["Main Elevator"]), "matching"),
        (lambda d: d.__setitem__("view", "3d"), "route"),
        (lambda d: d.__setitem__("extra", True), "Extra inputs"),
        (lambda d: d.__setitem__("paths", []), "needs points and paths"),
    ],
)
def test_route_diagram_rejects_inconsistent_configuration(mutate, message):
    diagram = route_diagram()
    mutate(diagram)
    with pytest.raises(ValidationError, match=message):
        SimulationConfig.model_validate({"enabled": True, "diagram": diagram})


@pytest.mark.parametrize(
    "diagram, message",
    [
        ({"view": "polar"}, "needs readings"),
        (
            {"view": "polar", "readings": {"arg": 0}, "rays": [{"label": "x"}]},
            "exactly one of arg or value",
        ),
        (
            {
                "view": "polar",
                "readings": {"arg": 0},
                "rays": [{"arg": 1, "value": 2, "label": "x"}],
            },
            "exactly one of arg or value",
        ),
        (
            {
                "view": "route",
                "points": [{"id": "S", "arg": 0}, {"id": "G", "arg": 1}],
                "paths": [{"points": ["S", "G"]}],
                "checks": [{"type": "sum", "parts": [0], "total": 1}],
            },
            "at least two parts",
        ),
    ],
)
def test_polar_and_check_configuration_is_validated(diagram, message):
    with pytest.raises(ValidationError, match=message):
        SimulationConfig.model_validate({"enabled": True, "diagram": diagram})


def test_arguments_are_echoed_as_json_without_evaluating_code():
    parsed = parse_playground_arguments(
        "{0: 10, 359: 9.5}, (1, 2), [(7.5, 4.5)], {3, 1}, None, True, 'x', 2j"
    )
    assert [playground_json_value(item) for item in parsed] == [
        {"0": 10, "359": 9.5},
        [1, 2],
        [[7.5, 4.5]],
        [1, 3],
        None,
        True,
        "x",
        "2j",
    ]


def function_assignment() -> Assignment:
    return Assignment(
        id=99,
        stable_id="diagram-test",
        version=1,
        title="Diagram test",
        grader_type="python_function",
        grader_config={
            "function_name": "route",
            "criteria": [{"id": "a", "label": "A"}, {"id": "b", "label": "B"}],
            "cases": [{"arguments": [[0, 0], [3, 4]], "expected": [5, 5]}],
        },
    )


def test_playground_echoes_arguments_even_when_the_function_fails():
    grader = PythonFunctionGrader(SubprocessSandbox())
    succeeded = grader.try_arguments(
        function_assignment(),
        "def route(start, goal):\n    return 1.0, 2.0",
        [(0, 0), (3, 4)],
    )
    failed = grader.try_arguments(
        function_assignment(),
        "def route(start, goal):\n    raise ValueError('no route')",
        [(0, 0), (3, 4)],
    )

    assert succeeded.arguments == [[0, 0], [3, 4]]
    assert failed.success is False
    assert failed.arguments == [[0, 0], [3, 4]]


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


def test_student_payload_and_playground_response_carry_diagram_data(client):
    token = client.post("/auth/demo").json()["token"]
    headers = {"Authorization": f"Bearer {token}"}
    assignment = client.get("/assignments/4", headers=headers).json()
    assert assignment["simulation_config"]["diagram"]["view"] == "polar"

    response = client.post(
        "/assignments/4/playground",
        json={
            "code": assignment["starter_code"],
            "arguments": "{0: 10, 1: 8, 2: 12, 358: 7, 359: 9}, 3, 357, 90, 10, 90",
        },
        headers=headers,
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["arguments"] == [
        {"0": 10, "1": 8, "2": 12, "358": 7, "359": 9},
        3,
        357,
        90,
        10,
        90,
    ]


def test_instructor_cannot_save_an_invalid_diagram(client):
    headers = {"X-Admin-Token": "test-admin"}
    assignment = client.get("/admin/assignments", headers=headers).json()[
        "assignments"
    ][0]
    assignment["simulation_config"]["diagram"]["paths"][0]["points"] = ["S", "Nowhere"]

    rejected = client.put("/admin/assignments/1", headers=headers, json=assignment)

    assert rejected.status_code in {400, 422}
    current = client.get("/admin/assignments", headers=headers).json()["assignments"][0]
    assert current["version"] == source(1)["version"]


def function_parameters(data: dict) -> list[str]:
    signature = data["starter_code"].split(
        f"def {data['grader_config']['function_name']}(", 1
    )[1].split(")", 1)[0]
    return [item.strip() for item in signature.split(",") if item.strip()]


@pytest.mark.parametrize("number", [1, 2, 3, 4])
def test_each_sample_input_matches_the_function_and_runs_on_starter_code(number):
    data = source(number)
    sample = data["simulation_config"]["playground"]["sample_arguments"]
    arguments = parse_playground_arguments(sample)
    assert len(arguments) == len(function_parameters(data))

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


@pytest.mark.parametrize(
    "sample",
    ["__import__('os')", "1 + 1", "x", ", ".join(["1"] * 21), "1e999", "1" * 2001],
)
def test_invalid_sample_inputs_are_rejected(sample):
    with pytest.raises(ValidationError):
        SimulationConfig.model_validate(
            {"enabled": True, "playground": {"sample_arguments": sample}}
        )


def test_playground_block_rejects_unknown_fields_and_stays_optional():
    with pytest.raises(ValidationError, match="Extra inputs"):
        SimulationConfig.model_validate(
            {"playground": {"sample_arguments": "1", "expected": [1]}}
        )
    assert "playground" not in SimulationConfig.model_validate(
        source(5)["simulation_config"]
    ).model_dump(mode="json")


def test_student_payload_carries_the_sample_input(client):
    token = client.post("/auth/demo").json()["token"]
    headers = {"Authorization": f"Bearer {token}"}
    assignment = client.get("/assignments/2", headers=headers).json()
    assert assignment["simulation_config"]["playground"]["sample_arguments"] == (
        source(2)["simulation_config"]["playground"]["sample_arguments"]
    )
