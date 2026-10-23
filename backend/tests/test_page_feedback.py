import pytest
from fastapi.testclient import TestClient

from app import create_app
from config import Settings


ADMIN = {"X-Admin-Token": "test-admin"}


@pytest.fixture()
def client(tmp_path):
    settings = Settings(
        database_url="sqlite://",
        admin_api_token="test-admin",
        openai_api_key=None,
        study_accounts_file=tmp_path / "study_accounts.json",
    )
    app = create_app(settings=settings, database_url="sqlite://")
    with TestClient(app) as test_client:
        yield test_client


def login(client, login_id, password):
    response = client.post(
        "/auth/login", json={"login_id": login_id, "password": password}
    )
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['token']}"}


def send(client, headers, **overrides):
    body = {
        "page": "Assignment 2",
        "category": "bug",
        "message": "The diagram does not load.",
        **overrides,
    }
    return client.post("/feedback", json=body, headers=headers)


def test_student_feedback_is_listed_for_instructors_with_sender(client):
    student = login(client, "student", "student")

    assert send(client, student).status_code == 201

    listing = client.get("/admin/feedback", headers=ADMIN)
    assert listing.status_code == 200
    payload = listing.json()
    assert payload["total"] == 1
    assert payload["new_count"] == 1
    item = payload["items"][0]
    assert item["page"] == "Assignment 2"
    assert item["category"] == "bug"
    assert item["message"] == "The diagram does not load."
    assert item["sender_role"] == "student"
    assert item["sender_login_id"] == "student"
    assert item["status"] == "new"


def test_instructor_bearer_can_read_and_resolve_feedback(client):
    send(client, login(client, "student", "student"))
    instructor = login(client, "instructor", "instructor")

    item = client.get("/admin/feedback", headers=instructor).json()["items"][0]
    resolved = client.patch(
        f"/admin/feedback/{item['id']}",
        json={"status": "resolved"},
        headers=instructor,
    )

    assert resolved.status_code == 200
    assert resolved.json()["status"] == "resolved"
    assert resolved.json()["resolved_at"] is not None
    assert client.get("/admin/feedback?status=new", headers=ADMIN).json()["total"] == 0
    reopened = client.patch(
        f"/admin/feedback/{item['id']}", json={"status": "new"}, headers=ADMIN
    )
    assert reopened.json()["resolved_at"] is None


def test_students_cannot_read_or_change_feedback(client):
    student = login(client, "student", "student")
    send(client, student)
    item_id = client.get("/admin/feedback", headers=ADMIN).json()["items"][0]["id"]

    assert client.get("/admin/feedback", headers=student).status_code == 403
    assert (
        client.patch(
            f"/admin/feedback/{item_id}", json={"status": "resolved"}, headers=student
        ).status_code
        == 403
    )
    assert client.get("/admin/feedback").status_code == 401


def test_feedback_requires_a_session(client):
    assert send(client, {}).status_code == 401


def test_demo_feedback_is_stored_without_the_shared_demo_account(client):
    token = client.post("/auth/demo").json()["token"]

    assert send(client, {"Authorization": f"Bearer {token}"}).status_code == 201

    item = client.get("/admin/feedback", headers=ADMIN).json()["items"][0]
    assert item["sender_role"] == "demo"
    assert item["sender_login_id"] is None


@pytest.mark.parametrize(
    "overrides",
    [
        {"category": "praise"},
        {"message": "   "},
        {"message": "x" * 2001},
        {"page": ""},
    ],
)
def test_invalid_feedback_is_rejected(client, overrides):
    student = login(client, "student", "student")
    # The app maps request validation errors to a stable 400 response.
    assert send(client, student, **overrides).status_code == 400


def test_feedback_is_rate_limited(client):
    student = login(client, "student", "student")
    statuses = [send(client, student).status_code for _ in range(6)]
    assert statuses[:5] == [201] * 5
    assert statuses[5] == 429


def test_unknown_feedback_id_returns_404(client):
    response = client.patch(
        "/admin/feedback/missing", json={"status": "resolved"}, headers=ADMIN
    )
    assert response.status_code == 404
