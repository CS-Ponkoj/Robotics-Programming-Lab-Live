"""Old assignments: a home-page grouping that never changes access or grading."""

import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app import create_app
from assignment_repository import CATALOG_PATH, old_assignment_ids
from config import Settings


ASSIGNMENTS = Path(__file__).resolve().parents[1] / "assignments"
OLD = {"robotics-assignment-1", "robotics-assignment-2", "robotics-assignment-3",
       "robotics-assignment-4", "ros2-drive-forward", "ros2-obstacle-stop"}


@pytest.fixture()
def client(tmp_path):
    settings = Settings(database_url="sqlite://", admin_api_token="test-admin",
                        openai_api_key=None, study_accounts_file=tmp_path / "accounts.json")
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as test_client:
        token = test_client.post(
            "/auth/login", json={"login_id": "student", "password": "student"}
        ).json()["token"]
        test_client.headers.update({"Authorization": f"Bearer {token}"})
        yield test_client


def test_catalog_names_assignments_1_to_6_by_stable_id():
    stable_ids = {
        json.loads(path.read_text(encoding="utf-8"))["stable_id"]
        for path in ASSIGNMENTS.glob("assignment_*.json")
    }
    assert old_assignment_ids() == OLD
    assert OLD <= stable_ids
    assert "ros2-wall-stop" not in old_assignment_ids()


def test_student_list_groups_old_assignments_but_keeps_every_assignment(client):
    listed = client.get("/assignments").json()["assignments"]
    assert [item["id"] for item in listed] == [1, 2, 3, 4, 5, 6, 7, 8]
    assert {item["id"]: item["collection"] for item in listed} == {
        1: "old", 2: "old", 3: "old", 4: "old", 5: "old", 6: "old",
        7: "current", 8: "current",
    }
    assert client.get("/assignments/7").json()["collection"] == "current"
    # The current course is numbered 1 and 2 for students; IDs stay 7 and 8.
    assert {item["id"]: item["display_number"] for item in listed} == {
        1: None, 2: None, 3: None, 4: None, 5: None, 6: None, 7: 1, 8: 2,
    }


def test_old_assignments_stay_open_and_gradable(client):
    detail = client.get("/assignments/1").json()
    assert detail["collection"] == "old"
    response = client.post("/assignments/1/run", json={"code": detail["starter_code"]})
    assert response.status_code == 200
    assert response.json()["assignment_version"] == detail["version"]


def test_catalog_is_optional_and_validated(tmp_path):
    assert old_assignment_ids(tmp_path / "missing.json") == frozenset()
    broken = tmp_path / "catalog.json"
    broken.write_text(json.dumps({"old_assignments": "robotics-assignment-1"}), encoding="utf-8")
    with pytest.raises(ValueError):
        old_assignment_ids(broken)
    assert CATALOG_PATH.name == "catalog.json"  # not matched by the assignment_*.json seed glob


def test_instructor_can_choose_old_assignments_and_return_to_the_file(client):
    admin = {"X-Admin-Token": "test-admin"}
    assert client.get("/admin/course-settings/catalog", headers=admin).json() == {
        "old_stable_ids": sorted(OLD), "source": "file",
    }
    # Move Assignment 6 back to current; the change is the instructor's now.
    chosen = sorted(OLD - {"ros2-obstacle-stop"})
    response = client.put(
        "/admin/course-settings/catalog", json={"old_stable_ids": chosen}, headers=admin
    )
    assert response.json() == {"old_stable_ids": chosen, "source": "instructor"}
    listed = {item["id"]: item["collection"] for item in client.get("/assignments").json()["assignments"]}
    assert listed[6] == "current" and listed[5] == "old"
    assert client.get("/assignments/6").json()["collection"] == "current"

    # Unknown IDs are refused; students cannot change the grouping.
    assert client.put(
        "/admin/course-settings/catalog", json={"old_stable_ids": ["nope"]}, headers=admin
    ).status_code == 422
    assert client.put(
        "/admin/course-settings/catalog", json={"old_stable_ids": []}
    ).status_code in (401, 403)

    # null returns to catalog.json.
    reset = client.put(
        "/admin/course-settings/catalog", json={"old_stable_ids": None}, headers=admin
    )
    assert reset.json()["source"] == "file"
    assert client.get("/assignments/6").json()["collection"] == "old"
