import pytest
from fastapi.testclient import TestClient

from app import create_app
from config import Settings


@pytest.fixture()
def editor_client(tmp_path):
    settings = Settings(
        database_url="sqlite://",
        admin_api_token="test-admin",
        openai_api_key=None,
        study_accounts_file=tmp_path / "study_accounts.json",
    )
    with TestClient(create_app(settings=settings, database_url="sqlite://")) as client:
        yield client


def _login(client: TestClient, login_id: str, password: str) -> dict:
    response = client.post(
        "/auth/login",
        json={"login_id": login_id, "password": password},
    )
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['token']}"}


def test_authenticated_drafts_are_versioned_and_isolated(editor_client):
    student_headers = _login(editor_client, "student", "student")
    instructor_headers = _login(editor_client, "instructor", "instructor")

    assignment = editor_client.get(
        "/assignments/1", headers=student_headers
    ).json()
    version = assignment["version"]
    initial = editor_client.get(
        "/assignments/1/draft", headers=student_headers
    )
    assert initial.status_code == 200
    assert initial.json()["saved"] is False
    assert initial.json()["code"] is None

    saved = editor_client.put(
        "/assignments/1/draft",
        headers=student_headers,
        json={"assignment_version": version, "code": "print('student draft')"},
    )
    assert saved.status_code == 200
    assert saved.json()["saved"] is True

    restored = editor_client.get(
        "/assignments/1/draft", headers=student_headers
    )
    assert restored.json()["code"] == "print('student draft')"
    assert restored.json()["assignment_version"] == version

    other_user = editor_client.get(
        "/assignments/1/draft", headers=instructor_headers
    )
    assert other_user.status_code == 200
    assert other_user.json()["saved"] is False
    assert other_user.json()["code"] is None

    stale = editor_client.put(
        "/assignments/1/draft",
        headers=student_headers,
        json={"assignment_version": version + 1, "code": "stale"},
    )
    assert stale.status_code == 409

    cleared = editor_client.delete(
        f"/assignments/1/draft?assignment_version={version}",
        headers=student_headers,
    )
    assert cleared.status_code == 204
    assert editor_client.get(
        "/assignments/1/draft", headers=student_headers
    ).json()["saved"] is False


def test_demo_drafts_remain_ephemeral(editor_client):
    demo = editor_client.post("/auth/demo")
    assert demo.status_code == 200
    headers = {"Authorization": f"Bearer {demo.json()['token']}"}
    assignment = editor_client.get("/assignments/1", headers=headers).json()

    saved = editor_client.put(
        "/assignments/1/draft",
        headers=headers,
        json={
            "assignment_version": assignment["version"],
            "code": "temporary demo draft",
        },
    )
    assert saved.status_code == 200
    assert saved.json()["saved"] is False
    assert editor_client.get(
        "/assignments/1/draft", headers=headers
    ).json()["code"] is None


def test_draft_routes_require_authentication(editor_client):
    assert editor_client.get("/assignments/1/draft").status_code == 401
    assert editor_client.put(
        "/assignments/1/draft",
        json={"assignment_version": 1, "code": "print('x')"},
    ).status_code == 401


def test_python_formatter_is_manual_safe_and_reports_invalid_code(editor_client):
    headers = _login(editor_client, "student", "student")
    response = editor_client.post(
        "/assignments/1/format",
        headers=headers,
        json={"code": "def add(a,b):\n return a+b\n"},
    )
    assert response.status_code == 200
    assert response.json() == {
        "code": "def add(a, b):\n    return a + b\n",
        "changed": True,
    }

    ros_response = editor_client.post(
        "/assignments/5/format",
        headers=headers,
        json={"code": "def publish(speed):\n return speed\n"},
    )
    assert ros_response.status_code == 200
    assert ros_response.json()["code"] == (
        "def publish(speed):\n    return speed\n"
    )

    invalid = editor_client.post(
        "/assignments/1/format",
        headers=headers,
        json={"code": "def broken(:\n    pass"},
    )
    assert invalid.status_code == 422
    assert invalid.json()["error"] == "Fix the Python syntax before formatting."


def _saved_flags(client: TestClient, headers: dict) -> dict[int, bool]:
    assignments = client.get("/assignments", headers=headers).json()["assignments"]
    return {item["id"]: item["has_saved_draft"] for item in assignments}


def test_assignment_list_shows_saved_work_on_any_computer(editor_client):
    """The home page can say Continue even where no local copy exists."""
    student = _login(editor_client, "student", "student")
    instructor = _login(editor_client, "instructor", "instructor")
    assert not any(_saved_flags(editor_client, student).values())

    first = editor_client.get("/assignments/1", headers=student).json()
    second = editor_client.get("/assignments/2", headers=student).json()
    editor_client.put(
        "/assignments/1/draft",
        headers=student,
        json={"assignment_version": first["version"], "code": "answer = 1"},
    )
    # A draft identical to the starter code is not saved work yet.
    editor_client.put(
        "/assignments/2/draft",
        headers=student,
        json={"assignment_version": second["version"], "code": second["starter_code"]},
    )

    flags = _saved_flags(editor_client, student)
    assert flags[1] is True
    assert flags[2] is False
    assert not any(value for key, value in flags.items() if key != 1)
    # Another account never sees this student's work.
    assert not any(_saved_flags(editor_client, instructor).values())


def test_assignment_list_shows_no_saved_work_for_demo(editor_client):
    demo = {"Authorization": f"Bearer {editor_client.post('/auth/demo').json()['token']}"}
    version = editor_client.get("/assignments/1", headers=demo).json()["version"]
    editor_client.put(
        "/assignments/1/draft",
        headers=demo,
        json={"assignment_version": version, "code": "answer = 1"},
    )
    assert not any(_saved_flags(editor_client, demo).values())
