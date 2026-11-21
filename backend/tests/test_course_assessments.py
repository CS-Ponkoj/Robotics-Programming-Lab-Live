"""Pre-test once, first quiz attempt as the score, answers kept for research."""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select

from app import create_app
from config import Settings
from course_content_repository import CourseContentRepository
from models import CourseQuizAttempt
from research_service import build_research_dataset

TOPIC = "ros2-mobile-robots"


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


def login(client, login_id="student", password="student"):
    response = client.post("/auth/login", json={"login_id": login_id, "password": password})
    assert response.status_code == 200
    client.headers.update({"Authorization": f"Bearer {response.json()['token']}"})


def key(section):
    repository = CourseContentRepository()
    return repository._read(repository.root / "quiz_answers.json")[f"{TOPIC}/{section}"]


def wrong_choices(page, answers):
    return {
        q["id"]: next(o["id"] for o in q["options"] if o["id"] != answers[q["id"]])
        for q in page["questions"]
    }


def test_pretest_page_has_no_answers_and_is_its_own_section(client):
    assert client.get(f"/contents/{TOPIC}/pretest").status_code == 401
    login(client)
    sections = client.get(f"/contents/{TOPIC}").json()["sections"]
    assert [s["kind"] for s in sections].count("pretest") == 1
    page = client.get(f"/contents/{TOPIC}/sections/pretest").json()
    assert len(page["questions"]) == 15 and len(page["version"]) == 16
    text = str(page)
    assert "answer" not in text.lower() and "explanation" not in text.lower()
    # The pre-test is not a copy of the quiz.
    quiz = client.get(f"/contents/{TOPIC}/sections/quiz").json()
    assert {q["prompt"] for q in page["questions"]}.isdisjoint(
        {q["prompt"] for q in quiz["questions"]})
    assert client.get("/contents/locomotion/pretest").status_code == 404


def test_pretest_is_taken_once_without_feedback_and_stored_with_answers(client):
    login(client)
    page = client.get(f"/contents/{TOPIC}/sections/pretest").json()
    assert client.get(f"/contents/{TOPIC}/pretest").json() == {"taken": False, "score_percent": None}
    answers = key("pretest")
    response = client.post(f"/contents/{TOPIC}/pretest/submit", json={
        "quiz_version": page["version"], "choices": answers,
    })
    assert response.status_code == 200
    body = response.json()
    assert body["score_percent"] == 100 and body["saved"] is True
    # No per-question feedback or answer key comes back from a pre-test.
    assert "results" not in body and "answers" not in body
    assert "correct_option" not in response.text and "explanation" not in response.text
    assert client.get(f"/contents/{TOPIC}/pretest").json() == {"taken": True, "score_percent": 100}
    again = client.post(f"/contents/{TOPIC}/pretest/submit", json={
        "quiz_version": page["version"], "choices": wrong_choices(page, answers),
    })
    assert again.status_code == 409
    with client.app.state.SessionLocal() as session:
        row = session.scalars(select(CourseQuizAttempt)).one()
        assert row.assessment == "pretest" and row.feedback_mode == "tdd"
        assert [item["choice"] for item in row.answers] == [answers[q["id"]] for q in page["questions"]]
        assert all(item["correct"] for item in row.answers) and row.data_schema_version == 1
    # A pre-test is not a quiz attempt.
    assert client.get(f"/contents/{TOPIC}/quiz/attempts").json()["attempts"] == []
    progress = next(t for t in client.get("/contents").json()["topics"] if t["id"] == TOPIC)
    assert progress["quiz_progress"]["pretest_score"] == 100
    assert progress["quiz_progress"]["attempt_count"] == 0


def test_first_quiz_attempt_is_the_score_and_retakes_are_practice(client):
    login(client)
    quiz = client.get(f"/contents/{TOPIC}/sections/quiz").json()
    answers = key("quiz")
    first = client.post(f"/contents/{TOPIC}/quiz/submit", json={
        "quiz_version": quiz["version"], "choices": wrong_choices(quiz, answers),
    }).json()
    assert first["score_percent"] == 0 and first["scored"] is True
    assert first["learning_score"] == 0
    retake = client.post(f"/contents/{TOPIC}/quiz/submit", json={
        "quiz_version": quiz["version"], "choices": answers,
    }).json()
    assert retake["score_percent"] == 100 and retake["scored"] is False
    assert retake["learning_score"] == 0
    history = client.get(f"/contents/{TOPIC}/quiz/attempts").json()
    assert history["learning_score"] == 0
    assert [a["scored"] for a in history["attempts"]] == [False, True]
    progress = next(t for t in client.get("/contents").json()["topics"] if t["id"] == TOPIC)
    assert progress["quiz_progress"]["first_score"] == 0
    assert progress["quiz_progress"]["best_score"] == 100
    with client.app.state.SessionLocal() as session:
        rows = session.scalars(
            select(CourseQuizAttempt).order_by(CourseQuizAttempt.submitted_at)
        ).all()
        assert [r.assessment for r in rows] == ["quiz", "quiz"]
        assert all(r.feedback_mode == "tdd" and len(r.answers) == 15 for r in rows)
        assert [item["correct"] for item in rows[1].answers] == [True] * 15


def test_demo_and_instructor_pretests_are_not_stored(client):
    demo = client.post("/auth/demo").json()
    client.headers.update({"Authorization": f"Bearer {demo['token']}"})
    page = client.get(f"/contents/{TOPIC}/sections/pretest").json()
    answers = key("pretest")
    payload = {"quiz_version": page["version"], "choices": answers}
    assert client.post(f"/contents/{TOPIC}/pretest/submit", json=payload).json()["saved"] is False
    assert client.post(f"/contents/{TOPIC}/pretest/submit", json=payload).status_code == 409
    assert client.get(f"/contents/{TOPIC}/pretest").json()["taken"] is True
    client.headers.clear()
    login(client, "instructor", "instructor")
    for _ in range(2):
        response = client.post(f"/contents/{TOPIC}/pretest/submit", json=payload)
        assert response.status_code == 200 and response.json()["saved"] is False
    with client.app.state.SessionLocal() as session:
        assert session.scalars(select(CourseQuizAttempt)).all() == []


def test_research_export_reports_pretest_first_quiz_score_and_gain(client):
    login(client)
    pretest = client.get(f"/contents/{TOPIC}/sections/pretest").json()
    quiz = client.get(f"/contents/{TOPIC}/sections/quiz").json()
    client.post(f"/contents/{TOPIC}/pretest/submit", json={
        "quiz_version": pretest["version"], "choices": wrong_choices(pretest, key("pretest")),
    })
    for choices in (key("quiz"), wrong_choices(quiz, key("quiz"))):
        client.post(f"/contents/{TOPIC}/quiz/submit", json={
            "quiz_version": quiz["version"], "choices": choices,
        })
    with client.app.state.SessionLocal() as session:
        dataset = build_research_dataset(session)
    attempts = [r for r in dataset["course_assessment_attempts"] if r["topic_id"] == TOPIC]
    assert [(r["assessment"], r["attempt_number"], r["scored"]) for r in attempts] == [
        ("pretest", 1, True), ("quiz", 1, True), ("quiz", 2, False),
    ]
    assert attempts[1]["correct_pattern"] == "1" * 15
    assert attempts[0]["correct_pattern"] == "0" * 15
    assert all("login" not in field and "student_id" not in field for field in attempts[0])
    summary = [r for r in dataset["course_learning_summary"] if r["topic_id"] == TOPIC][0]
    assert summary["pretest_score"] == 0 and summary["quiz_score"] == 100
    assert summary["learning_gain"] == 100 and summary["quiz_attempts"] == 2
    assert summary["best_quiz_score"] == 100 and summary["feedback_mode"] == "tdd"
