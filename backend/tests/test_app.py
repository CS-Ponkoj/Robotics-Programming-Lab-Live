from pathlib import Path
from unittest.mock import patch

import pytest

from app import app


CORRECT_ASSIGNMENT_2 = """
distance_to_obstacle = 4
perimeter_of_obstacle = 6
distance_from_obstacle_to_goal = 4
total_path_length = 14
"""

INCORRECT_ASSIGNMENT_2 = """
distance_to_obstacle = 0
perimeter_of_obstacle = 0
distance_from_obstacle_to_goal = 0
total_path_length = 0
"""

COURSE_MATERIALS = Path(__file__).resolve().parents[2] / "course_materials"
OFFICIAL_SOLUTIONS = {
    1: COURSE_MATERIALS
    / "content"
    / "Obstacle Avoidance"
    / "Assignment_Bug_Algorithm"
    / "Scenario_1"
    / "math_question_1_solution.py",
    2: COURSE_MATERIALS
    / "content"
    / "Obstacle Avoidance"
    / "Assignment_Bug_Algorithm"
    / "Scenario_2"
    / "Programing_Question_1_solution.py",
    3: COURSE_MATERIALS
    / "content"
    / "Obstacle Avoidance"
    / "Assignment_OA"
    / "question_1_solution.py",
    4: COURSE_MATERIALS
    / "content"
    / "Obstacle Avoidance"
    / "Assignment_VFH"
    / "question_1_VFH_solution.py",
}


@pytest.fixture()
def client():
    app.config.update(TESTING=True)
    return app.test_client()


def test_lists_all_assignments(client):
    response = client.get("/assignments/")

    assert response.status_code == 200
    assert response.is_json
    assignments = response.get_json()["assignments"]
    assert [assignment["id"] for assignment in assignments] == [1, 2, 3, 4]


@pytest.mark.parametrize("assignment_id", [1, 2, 3, 4])
def test_gets_each_assignment(client, assignment_id):
    response = client.get(f"/assignments/{assignment_id}")

    assert response.status_code == 200
    assignment = response.get_json()
    assert assignment["id"] == assignment_id
    assert assignment["solution_html"].strip()


def test_serves_assignment_image(client):
    response = client.get("/images/1")

    assert response.status_code == 200
    assert response.content_type == "image/png"
    assert response.data.startswith(b"\x89PNG")


def test_missing_assignment_and_image_return_json_404(client):
    assignment_response = client.get("/assignments/999")
    image_response = client.get("/images/999")

    assert assignment_response.status_code == 404
    assert assignment_response.get_json()["error"] == "Assignment not found."
    assert image_response.status_code == 404
    assert image_response.get_json()["error"] == "Image not found."


def test_grade_rejects_unknown_assignment(client):
    response = client.post("/grade/999", json={"code": "answer = 1"})

    assert response.status_code == 404
    assert response.get_json()["error"] == "Assignment not found."


def test_grade_rejects_oversized_submission(client):
    response = client.post("/grade/2", json={"code": "x" * 50_001})

    assert response.status_code == 413
    assert response.get_json()["error"] == "Submitted code is too large."


def test_correct_submission_passes_without_requesting_hint(client):
    with patch("app.get_one_sentence_hint") as hint:
        response = client.post("/grade/2", json={"code": CORRECT_ASSIGNMENT_2})

    body = response.get_json()
    assert response.status_code == 200
    assert body["pass"] is True
    assert body["ex_success"] is True
    assert body["unittest_pass_results"] == [True, True, True, True]
    hint.assert_not_called()


@pytest.mark.parametrize("assignment_id", [1, 2, 3, 4])
def test_official_solution_passes(client, assignment_id):
    code = OFFICIAL_SOLUTIONS[assignment_id].read_text(encoding="utf-8")

    with patch("app.get_one_sentence_hint") as hint:
        response = client.post(f"/grade/{assignment_id}", json={"code": code})

    body = response.get_json()
    assert response.status_code == 200
    assert body["pass"] is True
    assert all(body["unittest_pass_results"])
    hint.assert_not_called()


def test_incorrect_submission_fails_and_requests_hint(client):
    with patch("app.get_one_sentence_hint", return_value="Try the perimeter again.") as hint:
        response = client.post("/grade/2", json={"code": INCORRECT_ASSIGNMENT_2})

    body = response.get_json()
    assert response.status_code == 200
    assert body["pass"] is False
    assert body["ex_success"] is True
    assert body["unittest_pass_results"] == [False, False, False, False]
    assert body["hint"] == "Try the perimeter again."
    hint.assert_called_once()


@pytest.mark.parametrize(
    ("payload", "content_type"),
    [
        ("{}", "text/plain"),
        ({}, "application/json"),
        ({"code": ""}, "application/json"),
    ],
)
def test_rejects_missing_code(client, payload, content_type):
    if isinstance(payload, dict):
        response = client.post("/grade/2", json=payload)
    else:
        response = client.post("/grade/2", data=payload, content_type=content_type)

    assert response.status_code == 400
