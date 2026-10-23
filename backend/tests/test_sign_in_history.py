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


def test_history_lists_sign_ins_and_sign_outs_newest_first(client):
    first = login(client, "student", "student")
    assert client.post("/auth/logout", headers=first).status_code in (200, 204)
    login(client, "student", "student")

    history = client.get("/admin/sign-in-history", headers=ADMIN).json()

    assert history["total"] == 2
    newest, oldest = history["items"]
    assert newest["login_id"] == "student"
    assert newest["role"] == "student"
    assert newest["state"] == "active"
    assert newest["signed_out_at"] is None
    assert oldest["state"] == "signed_out"
    assert oldest["signed_out_at"] is not None
    assert newest["signed_in_at"] >= oldest["signed_in_at"]


def test_history_filters_to_one_user(client):
    login(client, "student", "student")
    instructor = login(client, "instructor", "instructor")
    student_id = next(
        item["user_id"]
        for item in client.get("/admin/sign-in-history", headers=ADMIN).json()["items"]
        if item["login_id"] == "student"
    )

    filtered = client.get(
        f"/admin/sign-in-history?user_id={student_id}", headers=instructor
    ).json()

    assert filtered["total"] == 1
    assert {item["login_id"] for item in filtered["items"]} == {"student"}


def test_history_is_admin_only(client):
    student = login(client, "student", "student")
    assert client.get("/admin/sign-in-history", headers=student).status_code == 403
    assert client.get("/admin/sign-in-history").status_code == 401


def test_demo_sessions_leave_no_history(client):
    client.post("/auth/demo")
    assert client.get("/admin/sign-in-history", headers=ADMIN).json()["total"] == 0


def test_history_never_exposes_session_tokens(client):
    login(client, "student", "student")
    item = client.get("/admin/sign-in-history", headers=ADMIN).json()["items"][0]
    assert "token" not in item and "token_hash" not in item
