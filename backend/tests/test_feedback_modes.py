"""Each account's feedback mode is enforced by the server, not the browser."""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select

from app import create_app
from config import Settings
from feedback_modes import (
    NO_HINTS_MESSAGE,
    SOLUTION_UNAVAILABLE_MESSAGE,
    feedback_mode_for,
    mode_without_ai_message,
    shape_simulation_response,
    shape_submission_response,
)
from models import AuditEvent, HintInteraction, LearningEvent, Submission, User

PASSWORD = "Study-Password-4827"


@pytest.fixture()
def app_client(tmp_path):
    settings = Settings(
        database_url="sqlite://",
        openai_api_key=None,
        study_accounts_file=tmp_path / "study_accounts.json",
        public_app_url="http://study.test",
    )
    application = create_app(settings=settings, database_url="sqlite://")
    with TestClient(application) as test_client:
        yield application, test_client


def login(client, login_id, password):
    response = client.post("/auth/login", json={"login_id": login_id, "password": password})
    assert response.status_code == 200
    return response.json()


def bearer(body):
    return {"Authorization": f"Bearer {body['token']}"}


def instructor(client):
    return bearer(login(client, "instructor", "instructor"))


def create(client, login_id, mode=None):
    body = {"login_id": login_id, "temporary_password": PASSWORD}
    if mode:
        body["feedback_mode"] = mode
    created = client.post("/admin/students", headers=instructor(client), json=body)
    assert created.status_code == 201, created.text
    return created.json()["user"]


def run_starter(client, student, study_session_id=None):
    starter = client.get("/assignments/1", headers=bearer(student)).json()["starter_code"]
    body = {"code": starter, "use_ai_tutor": True}
    if study_session_id:
        body["study_session_id"] = study_session_id
    response = client.post("/assignments/1/submit", headers=bearer(student), json=body)
    assert response.status_code == 200
    return response.json()


@pytest.fixture()
def accounts(app_client):
    _, client = app_client
    for login_id, mode in (("traditional", "traditional"), ("tdd", "tdd"), ("ai", "tdd_ai")):
        assert create(client, login_id, mode)["feedback_mode"] == mode
    return {name: login(client, name, PASSWORD) for name in ("traditional", "tdd", "ai")}


def test_new_accounts_default_to_tdd_and_login_reports_the_mode(app_client):
    _, client = app_client
    assert create(client, "plain")["feedback_mode"] == "tdd"
    assert login(client, "plain", PASSWORD)["user"]["feedback_mode"] == "tdd"
    assert login(client, "instructor", "instructor")["user"]["feedback_mode"] == "tdd_ai"


def test_traditional_gets_only_knowledge_of_results(app_client, accounts):
    _, client = app_client
    result = run_starter(client, accounts["traditional"])
    assert result["feedback_mode"] == "traditional"
    assert result["pass"] is False and isinstance(result["score"], int)
    assert result["unittest_pass_results"]  # counts stay derivable
    assert set(result["unittest_results"]) == {""}
    assert result["tested_vals"] == [] and result["evidence"] == []
    assert result["hint"] == "" and result["tutor_feedback"] is None
    assert result["hints_available"] is False
    assert result["code_output"] == ""

    sid = result["submission_id"]
    hint = client.post(
        "/assignments/1/hint", headers=bearer(accounts["traditional"]),
        json={"submission_id": sid, "hint_level": 2},
    )
    assert hint.status_code == 403
    tutor = client.post(
        "/assignments/1/tutor", headers=bearer(accounts["traditional"]),
        json={"submission_id": sid, "question": "Why does it fail?", "hint_level": 1},
    )
    assert tutor.status_code == 403
    simulate = client.post(
        "/assignments/7/simulate", headers=bearer(accounts["traditional"]),
        json={"code": "x = 1", "use_ai_tutor": False},
    )
    # The plain replay is part of the lab for every mode.
    assert simulate.status_code != 403


def test_tdd_gets_check_feedback_but_no_hints_or_tutor(app_client, accounts):
    _, client = app_client
    result = run_starter(client, accounts["tdd"])
    assert result["feedback_mode"] == "tdd"
    assert any(result["unittest_results"]) and result["evidence"]
    assert result["hint"] == "" and result["tutor_feedback"] is None
    assert result["hints_available"] is False
    hint = client.post(
        "/assignments/1/hint", headers=bearer(accounts["tdd"]),
        json={"submission_id": result["submission_id"], "hint_level": 2, "use_ai_tutor": True},
    )
    assert hint.status_code == 403
    tutor = client.post(
        "/assignments/1/tutor", headers=bearer(accounts["tdd"]),
        json={"submission_id": result["submission_id"], "question": "Why?", "hint_level": 1},
    )
    assert tutor.status_code == 403


def test_tdd_hints_come_back_when_the_switch_is_on(app_client, accounts, monkeypatch):
    import feedback_modes

    monkeypatch.setattr(feedback_modes, "TDD_BUILT_IN_HINTS", True)
    _, client = app_client
    result = run_starter(client, accounts["tdd"])
    # Hints only on request: the run offers one, the Hint button gets it.
    assert result["hint"] == "" and result["hints_available"] is True
    hint = client.post(
        "/assignments/1/hint", headers=bearer(accounts["tdd"]),
        json={"submission_id": result["submission_id"], "hint_level": 1},
    )
    assert hint.status_code == 200 and hint.json()["source"] == "fallback"


def test_ai_mode_may_ask_the_tutor(app_client, accounts):
    _, client = app_client
    result = run_starter(client, accounts["ai"])
    assert result["feedback_mode"] == "tdd_ai" and result["evidence"]
    # Hints only on request; the built-in ladder is the AI mode's fallback.
    assert result["hint"] == "" and result["hints_available"] is True
    hint = client.post(
        "/assignments/1/hint", headers=bearer(accounts["ai"]),
        json={"submission_id": result["submission_id"], "hint_level": 1},
    )
    assert hint.status_code == 200 and hint.json()["source"] == "fallback"
    tutor = client.post(
        "/assignments/1/tutor", headers=bearer(accounts["ai"]),
        json={"submission_id": result["submission_id"], "question": "Why does it fail?", "hint_level": 1},
    )
    # No server key in tests, so the built-in tutor answers with the reason.
    assert tutor.status_code == 200 and tutor.json()["source"] == "fallback"


def test_ai_status_is_off_for_every_account_without_a_server_key(app_client, accounts):
    _, client = app_client
    for name in accounts:
        detail = client.get("/assignments/1", headers=bearer(accounts[name])).json()
        assert detail["ai_tutor_available"] is False and detail["ai_tutor_message"]


def test_attempts_and_events_keep_the_mode_they_ran_under(app_client, accounts):
    application, client = app_client
    study = client.post(
        "/research/sessions", headers=bearer(accounts["traditional"]),
        json={"client_session_id": "browser-mode-0001"},
    ).json()
    first = run_starter(client, accounts["traditional"], study["id"])

    user_id = accounts["traditional"]["user"]["id"]
    changed = client.patch(
        f"/admin/students/{user_id}", headers=instructor(client), json={"feedback_mode": "tdd"}
    )
    assert changed.status_code == 200 and changed.json()["feedback_mode"] == "tdd"
    second = run_starter(client, accounts["traditional"], study["id"])
    assert second["feedback_mode"] == "tdd"

    with application.state.SessionLocal() as session:
        modes = {
            item.id: item.feedback_mode
            for item in session.scalars(select(Submission).where(Submission.user_id == user_id))
        }
        assert modes == {first["submission_id"]: "traditional", second["submission_id"]: "tdd"}
        events = session.scalars(
            select(LearningEvent).where(
                LearningEvent.user_id == user_id,
                LearningEvent.event_type == "assignment_submitted",
            )
        ).all()
        assert sorted(item.event_data["feedback_mode"] for item in events) == ["tdd", "traditional"]
        audit = session.scalars(
            select(AuditEvent).where(AuditEvent.action == "student.feedback_mode_changed")
        ).one()
        assert (audit.details["from"], audit.details["to"]) == ("traditional", "tdd")
        # Traditional attempts never stored a hint the student could not see.
        assert session.scalar(
            select(HintInteraction).where(HintInteraction.submission_id == first["submission_id"])
        ) is None

    export = client.get(
        "/admin/research/export?dataset_name=assignment_attempts&format=csv",
        headers=instructor(client),
    )
    assert export.status_code == 200 and b"feedback_mode" in export.content


def test_students_cannot_change_their_own_mode(app_client, accounts):
    _, client = app_client
    user_id = accounts["traditional"]["user"]["id"]
    response = client.patch(
        f"/admin/students/{user_id}", headers=bearer(accounts["traditional"]),
        json={"feedback_mode": "tdd_ai"},
    )
    assert response.status_code in (401, 403)
    rejected = client.patch(
        f"/admin/students/{user_id}", headers=instructor(client), json={"feedback_mode": "everything"}
    )
    assert rejected.status_code == 400  # validation errors use 400 here


def test_demo_is_tdd_and_instructors_see_everything():
    student = User(login_id="s", password_hash="x", role="student", feedback_mode="traditional")
    teacher = User(login_id="t", password_hash="x", role="instructor", feedback_mode="traditional")
    assert feedback_mode_for(student) == "traditional"
    assert feedback_mode_for(student, demo=True) == "tdd"
    assert feedback_mode_for(teacher) == "tdd_ai"
    assert feedback_mode_for(User(login_id="u", password_hash="x", role="student", feedback_mode="bogus")) == "tdd"
    assert shape_submission_response({"hint": "h"}, "tdd")["hint"] == ""
    assert shape_submission_response({"hint": "h"}, "tdd", demo=True)["hint"] == "h"
    assert shape_submission_response({"hint": "h"}, "tdd_ai")["hint"] == "h"


def test_traditional_simulation_is_the_plain_replay():
    reply = {
        "success": True, "error": "", "output": "printed",
        "simulation": {"frames": [1], "sensitivity": {"status": "ok", "beams": [3]}},
    }
    plain = shape_simulation_response(reply, "traditional")
    assert plain["output"] == "" and plain["simulation"] == {"frames": [1]}
    assert shape_simulation_response(reply, "tdd") == reply
    assert reply["simulation"]["sensitivity"]  # the input is not changed


def test_traditional_counts_have_no_check_order_and_no_check_labels(app_client, accounts):
    _, client = app_client
    result = run_starter(client, accounts["traditional"])
    passes = result["unittest_pass_results"]
    assert passes == sorted(passes, reverse=True)  # passed first: order-free
    assert "error_frames" in result and "code_exec_result" in result
    traditional = client.get("/assignments/1", headers=bearer(accounts["traditional"])).json()
    tdd = client.get("/assignments/1", headers=bearer(accounts["tdd"])).json()
    assert traditional["public_tests"] == [] and tdd["public_tests"]
    listed = client.get("/assignments", headers=bearer(accounts["traditional"])).json()
    assert all(item["public_tests"] == [] for item in listed["assignments"])
    shaped = shape_submission_response(
        {"unittest_pass_results": [False, True, False, True]}, "traditional"
    )
    assert shaped["unittest_pass_results"] == [True, True, False, False]


def test_hints_follow_the_accounts_current_mode(app_client, accounts):
    _, client = app_client
    result = run_starter(client, accounts["ai"])
    request = {"submission_id": result["submission_id"], "hint_level": 2}
    assert client.post(
        "/assignments/1/hint", headers=bearer(accounts["ai"]), json=request
    ).status_code == 200
    user_id = accounts["ai"]["user"]["id"]
    for mode in ("tdd", "traditional"):
        assert client.patch(
            f"/admin/students/{user_id}", headers=instructor(client),
            json={"feedback_mode": mode},
        ).status_code == 200
        hint = client.post("/assignments/1/hint", headers=bearer(accounts["ai"]), json=request)
        assert hint.status_code == 403 and hint.json()["error"] == NO_HINTS_MESSAGE


@pytest.mark.parametrize("name", ["traditional", "tdd", "ai"])
def test_study_students_never_get_the_solution_approach(app_client, accounts, name):
    _, client = app_client
    result = run_starter(client, accounts[name])
    for item in client.get("/assignments", headers=bearer(accounts[name])).json()["assignments"]:
        assert item["has_solution"] is False and item["solution_html"] == ""
    detail = client.get("/assignments/1", headers=bearer(accounts[name])).json()
    assert detail["has_solution"] is False
    reveal = client.post(
        "/assignments/1/solution", headers=bearer(accounts[name]),
        json={"submission_id": result["submission_id"]},
    )
    assert reveal.status_code == 403
    assert reveal.json()["error"] == SOLUTION_UNAVAILABLE_MESSAGE


def test_instructors_keep_the_solution_approach(app_client):
    _, client = app_client
    headers = instructor(client)
    assert client.get("/assignments/1", headers=headers).json()["has_solution"] is True
    starter = client.get("/assignments/1", headers=headers).json()["starter_code"]
    run = client.post("/assignments/1/submit", headers=headers, json={"code": starter}).json()
    reveal = client.post(
        "/assignments/1/solution", headers=headers, json={"submission_id": run["submission_id"]}
    )
    assert reveal.status_code == 200 and reveal.json()["solution_html"]


def test_accounts_without_hints_are_not_promised_built_in_hints(app_client, accounts):
    _, client = app_client
    for name in ("traditional", "tdd"):
        message = client.get("/assignments/1", headers=bearer(accounts[name])).json()[
            "ai_tutor_message"
        ]
        assert message and "hints still work" not in message.lower()
    ai = client.get("/assignments/1", headers=bearer(accounts["ai"])).json()
    assert "Built-in hints still work" in ai["ai_tutor_message"]
    for mode in ("traditional", "tdd"):
        assert "hint" not in mode_without_ai_message(mode).replace("without hints", "")


def test_traditional_counts_keep_not_run_checks_apart_without_names():
    from feedback_modes import NOT_RUN_COUNT_MESSAGE, shape_submission_response

    payload = {
        "unittest_pass_results": [False, True, False, False],
        "unittest_results": [
            "Not run: the code stopped with an error before this check.",
            "Imports only rclpy.",
            "The package was not built: controller.py has a SyntaxError on line 4.",
            "Not checked: the node stopped before this situation.",
        ],
        "evidence": [{"test_id": "x"}],
        "hint": "h",
    }
    shaped = shape_submission_response(payload, "traditional")
    assert shaped["unittest_pass_results"] == [True, False, False, False]
    assert shaped["unittest_results"] == ["", "", NOT_RUN_COUNT_MESSAGE, NOT_RUN_COUNT_MESSAGE]
    assert shaped["evidence"] == [] and shaped["hint"] == ""
    assert "SyntaxError" not in str(shaped["unittest_results"])
