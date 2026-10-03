"""Student-facing course content and server-only quiz keys."""

import re
from sqlalchemy import select
from models import CourseQuizAttempt

import pytest
from fastapi.testclient import TestClient

from app import create_app
from auth_service import create_user
from config import Settings
from course_content_repository import CourseContentRepository


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


def test_catalog_quiz_progress_is_self_only_and_versioned(client):
    login(client)
    quiz = client.get('/contents/path-planning/sections/quiz').json()
    with client.app.state.SessionLocal() as session:
        from models import User
        student = session.scalar(select(User).where(User.login_id == 'student'))
        other = create_user(session, login_id='quiz-other', password='other-password', role='student')
        for owner, version, score in [
            (student.id, quiz['version'], 100),
            (student.id, quiz['version'], 40),
            (student.id, 'old-version', 90),
            (other.id, quiz['version'], 70),
        ]:
            session.add(CourseQuizAttempt(
                user_id=owner, topic_id='path-planning', quiz_version=version,
                correct_count=score // 10, total_questions=10, score_percent=score,
            ))
        session.commit()
    topics = client.get('/contents').json()['topics']
    progress = next(t for t in topics if t['id'] == 'path-planning')['quiz_progress']
    assert progress == {'quiz_version': quiz['version'], 'attempt_count': 2,
                        'best_score': 100, 'latest_score': 40, 'temporary': False}
    assert next(t for t in topics if t['id'] == 'locomotion')['quiz_progress']['latest_score'] is None
    login(client, 'quiz-other', 'other-password')
    progress = next(t for t in client.get('/contents').json()['topics'] if t['id'] == 'path-planning')['quiz_progress']
    assert progress['attempt_count'] == 1
    assert progress['best_score'] == 70


def test_demo_catalog_progress_is_temporary_and_session_isolated(client):
    token = client.post('/auth/demo').json()['token']
    client.headers.update({'Authorization': f'Bearer {token}'})
    quiz = client.get('/contents/path-planning/sections/quiz').json()
    answers = CourseContentRepository()._read(CourseContentRepository().root / 'quiz_answers.json')['path-planning/quiz']
    assert client.post('/contents/path-planning/quiz/submit', json={
        'quiz_version': quiz['version'], 'choices': answers,
    }).json()['saved'] is False
    progress = next(t for t in client.get('/contents').json()['topics'] if t['id'] == 'path-planning')['quiz_progress']
    assert progress['latest_score'] == 100
    assert progress['temporary'] is True
    with client.app.state.SessionLocal() as session:
        assert session.scalar(select(CourseQuizAttempt)) is None
    token = client.post('/auth/demo').json()['token']
    client.headers.update({'Authorization': f'Bearer {token}'})
    progress = next(t for t in client.get('/contents').json()['topics'] if t['id'] == 'path-planning')['quiz_progress']
    assert progress['attempt_count'] == 0


def test_course_content_requires_login_and_has_all_six_topics(client):
    assert client.get("/contents").status_code == 401
    assert client.get("/contents/path-planning/quiz/attempts").status_code == 401
    assert client.post("/contents/path-planning/quiz/submit", json={
        "quiz_version": "old", "choices": {},
    }).status_code == 401
    login(client)
    topics = client.get("/contents").json()["topics"]
    assert len(topics) == 6
    assert {topic["id"] for topic in topics} == {
        "obstacle-avoidance", "path-planning", "sensor-fusion",
        "range-sensors", "locomotion", "hybrid-navigation-gps",
    }
    assert all("reference" not in str(topic).lower() for topic in topics)


def test_every_topic_has_lesson_and_student_safe_sections(client):
    login(client)
    for topic in client.get("/contents").json()["topics"]:
        topic_id = topic["id"]
        overview = client.get(f"/contents/{topic_id}")
        assert overview.status_code == 200
        sections = overview.json()["sections"]
        assert any(section["kind"] == "lesson" for section in sections)
        assert any(section["kind"] == "exercise" for section in sections)
        assert sum(section["kind"] == "quiz" for section in sections) == 1
        for section in sections:
            response = client.get(f"/contents/{topic_id}/sections/{section['id']}")
            assert response.status_code == 200
            data = response.json()
            assert data["html"] or data["questions"]
            assert "quiz_answers" not in response.text
            if data["kind"] == "quiz":
                assert len(data["questions"]) >= 10
                assert len(data["version"]) == 16
                assert all("answer" not in question for question in data["questions"])
            if data["kind"] in {"exercise", "math"}:
                assert "<pre><code>" not in data["html"]
                for line in data["html"].splitlines():
                    visible_line = re.sub(r"<[^>]+>", "", line).strip()
                    assert visible_line.lower().rstrip(": ") not in {
                        "answer", "solution", "solutions"
                    }
    math = client.get("/contents/locomotion/sections/math-exercises-for-locomotion").json()["html"]
    assert "Question 12" in math
    assert "Answer:" not in math
    assert "Solution:" not in math
    exercise = client.get(
        "/contents/obstacle-avoidance/sections/assignment-bug-algorithm-scenario-1"
    ).json()["html"]
    assert "A small cleaning robot" in exercise
    assert "Here's a breakdown" not in exercise
    assert ">Solution<" not in exercise
    assert "<pre><code>" not in exercise


def test_quiz_submits_once_and_saves_score_without_returning_answer_key(client):
    login(client)
    quiz = client.get("/contents/obstacle-avoidance/sections/quiz").json()
    path = "/contents/obstacle-avoidance/quiz/submit"
    choices = {q["id"]: q["options"][0]["id"] for q in quiz["questions"]}
    payload = {"quiz_version": quiz["version"], "choices": choices}
    assert client.post(path, json={**payload, "choices": {}}).status_code == 400
    assert client.post(path, json={**payload, "quiz_version": "old"}).status_code == 400
    assert client.post(path, json={**payload, "choices": {**choices, "q999": "A"}}).status_code == 400
    assert client.post(path, json={**payload, "choices": {**choices, "q1": "Z"}}).status_code == 400
    result = client.post(path, json=payload)
    assert result.status_code == 200
    assert result.json()["saved"] is True
    assert result.json()["total_questions"] == len(quiz["questions"])
    assert "answer" not in result.text
    history = client.get("/contents/obstacle-avoidance/quiz/attempts").json()["attempts"]
    assert len(history) == 1
    assert history[0]["score_percent"] == result.json()["score_percent"]
    with client.app.state.SessionLocal() as session:
        row = session.scalar(select(CourseQuizAttempt))
        assert row is not None and row.quiz_version == quiz["version"]
    assert client.get("/contents/../quiz_answers.json").status_code != 200


def test_every_quiz_has_exactly_one_correct_choice_and_demo_is_not_saved(client):
    login(client)
    for topic in client.get("/contents").json()["topics"]:
        topic_id = topic["id"]
        quiz = client.get(f"/contents/{topic_id}/sections/quiz").json()
        assert len(quiz["questions"]) == 10
        # The server-side key can be inspected here, but is never in the response.
        repository = CourseContentRepository()
        answers = repository._read(repository.root / "quiz_answers.json")[f"{topic_id}/quiz"]
        result = client.post(f"/contents/{topic_id}/quiz/submit", json={
            "quiz_version": quiz["version"], "choices": answers,
        })
        assert result.status_code == 200 and result.json()["score_percent"] == 100
        wrong = {
            q["id"]: next(o["id"] for o in q["options"] if o["id"] != answers[q["id"]])
            for q in quiz["questions"]
        }
        half = dict(wrong)
        for question_id in list(answers)[:5]:
            half[question_id] = answers[question_id]
        for choices, score in ((wrong, 0), (half, 50)):
            response = client.post(f"/contents/{topic_id}/quiz/submit", json={
                "quiz_version": quiz["version"], "choices": choices,
            })
            assert response.status_code == 200
            assert response.json()["score_percent"] == score
    client.headers.clear()
    demo = client.post("/auth/demo")
    assert demo.status_code == 200
    client.headers.update({"Authorization": f"Bearer {demo.json()['token']}"})
    quiz = client.get("/contents/path-planning/sections/quiz").json()
    choices = {q["id"]: "A" for q in quiz["questions"]}
    response = client.post("/contents/path-planning/quiz/submit", json={
        "quiz_version": quiz["version"], "choices": choices,
    })
    assert response.status_code == 200 and response.json()["saved"] is False
    assert client.get("/contents/path-planning/quiz/attempts").json() == {"attempts": []}
    with client.app.state.SessionLocal() as session:
        assert len(session.scalars(select(CourseQuizAttempt)).all()) == 18


def test_quiz_history_is_student_private_and_scores_survive_restart(tmp_path):
    database_url = f"sqlite:///{(tmp_path / 'quiz.sqlite').as_posix()}"
    settings = Settings(
        database_url=database_url,
        admin_api_token="test-admin",
        openai_api_key=None,
        study_accounts_file=tmp_path / "accounts.json",
    )
    with TestClient(create_app(settings=settings, database_url=database_url)) as first:
        login(first)
        quiz = first.get("/contents/path-planning/sections/quiz").json()
        answers = CourseContentRepository()._read(
            CourseContentRepository().root / "quiz_answers.json"
        )["path-planning/quiz"]
        wrong = {
            q["id"]: next(o["id"] for o in q["options"] if o["id"] != answers[q["id"]])
            for q in quiz["questions"]
        }
        zero = first.post("/contents/path-planning/quiz/submit", json={
            "quiz_version": quiz["version"], "choices": wrong,
        })
        assert zero.status_code == 200 and zero.json()["score_percent"] == 0
        mixed = dict(wrong)
        for question_id in list(answers)[:5]:
            mixed[question_id] = answers[question_id]
        half = first.post("/contents/path-planning/quiz/submit", json={
            "quiz_version": quiz["version"], "choices": mixed,
        })
        assert half.status_code == 200 and half.json()["score_percent"] == 50
        with first.app.state.SessionLocal() as session:
            create_user(session, login_id="second", password="second123", role="student")
        login(first, "second", "second123")
        assert first.get("/contents/path-planning/quiz/attempts").json() == {"attempts": []}
    with TestClient(create_app(settings=settings, database_url=database_url)) as restarted:
        login(restarted)
        history = restarted.get("/contents/path-planning/quiz/attempts").json()
        assert len(history["attempts"]) == 2
        assert history["attempts"][0]["score_percent"] == 50
        assert history["attempts"][1]["score_percent"] == 0


def test_content_asset_is_bounded_and_reachable(client):
    login(client)
    lesson = client.get("/contents/hybrid-navigation-gps/sections/lesson").json()
    match = re.search(r'/content-assets/([0-9a-f]{20}\.png)', lesson["html"])
    assert match
    assert client.get(match.group()).status_code == 200
    assert client.get("/content-assets/quiz_answers.json").status_code == 404


def test_instructor_can_read_contents(client):
    login(client, "instructor", "instructor")
    assert client.get("/contents").status_code == 200
    quiz = client.get("/contents/range-sensors/sections/quiz").json()
    answers = CourseContentRepository()._read(
        CourseContentRepository().root / "quiz_answers.json"
    )["range-sensors/quiz"]
    preview = client.post("/contents/range-sensors/quiz/submit", json={
        "quiz_version": quiz["version"], "choices": answers,
    })
    assert preview.status_code == 200
    assert preview.json()["score_percent"] == 100
    assert preview.json()["saved"] is False
    with client.app.state.SessionLocal() as session:
        assert session.scalar(select(CourseQuizAttempt)) is None


def test_generated_pages_keep_word_structure():
    """Lists, headings, table headers, captions, and equations survive conversion."""
    repository = CourseContentRepository()
    for topic in repository.topics():
        lesson = repository.section(topic["id"], "lesson")["html"]
        assert len(re.findall(r"<h[23][ >]", lesson)) >= 2, topic["id"]
        assert "<li>" in lesson, topic["id"]
    path_planning = repository.section("path-planning", "lesson")["html"]
    # Equation symbols stay where Word placed them, not at the paragraph end.
    assert 'Let G <span class="math-expression">⊂</span> X be' in path_planning
    assert "<sub>att</sub>" in path_planning
    assert path_planning.count("<thead>") == 5
    assert '<th scope="row">Working Principle</th>' in repository.section(
        "range-sensors", "lesson")["html"]
    locomotion = repository.section("locomotion", "lesson")["html"]
    assert "<figcaption>" in locomotion
    assert 'alt="Ball or spherical wheel mechanism"' in locomotion
