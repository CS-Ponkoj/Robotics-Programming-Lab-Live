from fastapi.testclient import TestClient

from app import create_app
from config import Settings
from sandbox_service import create_sandbox_service


class RecordingSandbox:
    def __init__(self, timeout, calls):
        self.timeout = timeout
        self.calls = calls

    def execute(self, code, result_names):
        self.calls.append((self.timeout, code, result_names))
        return {
            "success": True,
            "error": "",
            "output": "",
            "values": {"answer": 42},
        }


def test_sandbox_service_requires_shared_secret_and_executes_valid_request():
    calls = []
    app = create_sandbox_service(
        api_token="sandbox-test-token",
        executor_factory=lambda timeout: RecordingSandbox(timeout, calls),
    )
    with TestClient(app) as client:
        health = client.get("/health")
        unauthorized = client.post(
            "/execute",
            json={"code": "answer = 42", "result_names": ["answer"]},
        )
        executed = client.post(
            "/execute",
            headers={"Authorization": "Bearer sandbox-test-token"},
            json={
                "code": "answer = 42",
                "result_names": ["answer"],
                "timeout_seconds": 4,
            },
        )

    assert health.status_code == 200
    assert health.json()["isolation"] == "dedicated-service"
    assert unauthorized.status_code == 401
    assert executed.status_code == 200
    assert executed.json()["values"] == {"answer": 42}
    assert calls == [(4, "answer = 42", ["answer"])]


def test_sandbox_service_fails_health_when_secret_is_missing():
    with TestClient(create_sandbox_service(api_token="")) as client:
        response = client.get("/health")

    assert response.status_code == 503


def test_sandbox_service_rejects_oversized_code_before_execution():
    calls = []
    app = create_sandbox_service(
        api_token="sandbox-test-token",
        executor_factory=lambda timeout: RecordingSandbox(timeout, calls),
    )
    with TestClient(app) as client:
        response = client.post(
            "/execute",
            headers={"Authorization": "Bearer sandbox-test-token"},
            json={"code": "x" * 50_001, "result_names": []},
        )

    assert response.status_code == 400
    assert calls == []


def test_sandbox_service_fails_fast_when_capacity_is_full():
    app = create_sandbox_service(
        api_token="sandbox-test-token",
        max_concurrent_executions=1,
    )
    assert app.state.execution_slots.acquire(blocking=False)
    try:
        with TestClient(app) as client:
            response = client.post(
                "/execute",
                headers={"Authorization": "Bearer sandbox-test-token"},
                json={"code": "answer = 42", "result_names": ["answer"]},
            )
    finally:
        app.state.execution_slots.release()

    assert response.status_code == 503


def test_backend_grades_through_real_remote_sandbox_contract(
    tmp_path,
    monkeypatch,
):
    sandbox_app = create_sandbox_service(api_token="sandbox-test-token")
    sandbox_client = TestClient(sandbox_app)

    def bridge_request(_url, *, headers, json, timeout):
        assert timeout == 20
        return sandbox_client.post("/execute", headers=headers, json=json)

    monkeypatch.setattr("sandbox.httpx.post", bridge_request)
    settings = Settings(
        database_url="sqlite://",
        openai_api_key=None,
        study_accounts_file=tmp_path / "study_accounts.json",
        sandbox_backend="remote",
        sandbox_url="sandbox.internal:10000",
        sandbox_api_token="sandbox-test-token",
        sandbox_http_timeout_seconds=20,
    )
    with sandbox_client, TestClient(
        create_app(settings=settings, database_url="sqlite://")
    ) as api_client:
        login = api_client.post(
            "/auth/login",
            json={"login_id": "student", "password": "student"},
        )
        response = api_client.post(
            "/assignments/2/submit",
            headers={"Authorization": f"Bearer {login.json()['token']}"},
            json={
                "code": (
                    "distance_to_obstacle = 4\n"
                    "perimeter_of_obstacle = 6\n"
                    "distance_from_obstacle_to_goal = 4\n"
                    "total_path_length = 14\n"
                )
            },
        )

    assert response.status_code == 200
    assert response.json()["pass"] is True
    assert response.json()["assignment_version"] == 2
