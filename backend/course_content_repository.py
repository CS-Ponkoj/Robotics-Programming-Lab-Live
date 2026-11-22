"""Read the reviewed, generated course pages without exposing source documents."""

import html
import json
import re
from pathlib import Path


CONTENT_ROOT = Path(__file__).resolve().parent / "course_content"
# Authored section goals and ungraded quick checks, added to a lesson when it
# is served so the generated lesson files stay as the builder wrote them.
LESSON_EXTRAS = Path(__file__).resolve().parent / "course_lesson_extras.json"
_H2 = re.compile(r"<h2(?:\s[^>]*)?>(.*?)</h2>", re.S)


def _plain(fragment: str) -> str:
    text = html.unescape(re.sub(r"<[^>]+>", "", fragment))
    return " ".join(text.split())


def _goals_html(goals: list[str]) -> str:
    items = "".join(f"<li>{html.escape(goal)}</li>" for goal in goals)
    return (
        '<div class="lesson-goals"><p><strong>In this section you will</strong></p>'
        f"<ul>{items}</ul></div>"
    )


def _quick_check_html(check: dict) -> str:
    payload = json.dumps(
        {
            "prompt": str(check["prompt"]),
            "options": [str(option) for option in check["options"]],
            "answer": int(check["answer"]),
            "explanation": str(check.get("explanation", "")),
        },
        ensure_ascii=False,
    )
    return (
        '<div data-interactive="quick-check" '
        f'data-check="{html.escape(payload, quote=True)}"></div>'
    )


def add_lesson_extras(lesson_html: str, sections: list[dict]) -> str:
    """Puts each section's goals under its heading and its quick check at the
    end of the section. Sections are matched by their heading text."""
    by_heading = {_plain(item["heading"]): item for item in sections}
    matches = list(_H2.finditer(lesson_html))
    if not matches or not by_heading:
        return lesson_html
    pieces = [lesson_html[: matches[0].start()]]
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(lesson_html)
        body = lesson_html[match.end():end]
        extra = by_heading.get(_plain(match.group(1)))
        pieces.append(match.group(0))
        if extra and extra.get("goals"):
            pieces.append(_goals_html(extra["goals"]))
        pieces.append(body)
        if extra and extra.get("quick_check"):
            pieces.append(_quick_check_html(extra["quick_check"]))
    return "".join(pieces)
ASSET_NAME = re.compile(r"^[0-9a-f]{20}\.(?:png|jpg|jpeg|gif)$")


class CourseContentRepository:
    def __init__(self, root: Path = CONTENT_ROOT, extras: Path | None = LESSON_EXTRAS):
        self.root = root
        self.extras = extras

    @staticmethod
    def _read(path: Path) -> dict:
        return json.loads(path.read_text(encoding="utf-8"))

    def _optional(self, path: Path) -> dict:
        return self._read(path) if path.is_file() else {}

    def worked_answer(self, topic_id: str, section_id: str) -> str | None:
        """A practice page's worked answer, for a student who asks to see it."""
        section = self.section(topic_id, section_id)
        if section is None or section.get("kind") not in {"exercise", "math"}:
            return None
        return self._optional(self.root / "worked_answers.json").get(f"{topic_id}/{section_id}")

    def topics(self) -> list[dict]:
        return self._read(self.root / "catalog.json")["topics"]

    def topic(self, topic_id: str) -> dict | None:
        if topic_id not in {topic["id"] for topic in self.topics()}:
            return None
        return self._read(self.root / topic_id / "index.json")

    def section(self, topic_id: str, section_id: str) -> dict | None:
        topic = self.topic(topic_id)
        if topic is None or section_id not in {s["id"] for s in topic["sections"]}:
            return None
        section = self._read(self.root / topic_id / f"{section_id}.json")
        if section.get("kind") == "lesson" and self.extras is not None:
            extras = self._optional(self.extras).get("topics", {}).get(topic_id, {})
            if extras.get("sections"):
                section = {
                    **section,
                    "html": add_lesson_extras(section.get("html", ""), extras["sections"]),
                }
        return section

    def grade_quiz(
        self, topic_id: str, version: str, choices: dict[str, str], section_id: str = "quiz"
    ) -> dict | None:
        """Grade a complete quiz or pre-test (section_id "quiz" or "pretest")."""
        if section_id not in {"quiz", "pretest"}:
            return None
        section = self.section(topic_id, section_id)
        if section is None:
            return None
        if section["version"] != version:
            raise ValueError("The quiz changed. Reload it before submitting.")
        questions = section["questions"]
        expected_ids = {question["id"] for question in questions}
        if set(choices) != expected_ids:
            raise ValueError("Answer every quiz question before submitting.")
        for question in questions:
            valid = {option["id"] for option in question["options"]}
            if choices[question["id"]] not in valid:
                raise ValueError("The quiz contains an invalid choice.")
        answers = self._read(self.root / "quiz_answers.json")[f"{topic_id}/{section_id}"]
        explanations = self._optional(self.root / "quiz_explanations.json").get(
            f"{topic_id}/{section_id}", {}
        )
        # Graded only after a complete submission, so each result may name the
        # correct option and, when the topic provides one, why it is correct.
        results = []
        for question in questions:
            question_id = question["id"]
            result = {
                "question_id": question_id,
                "correct": choices[question_id] == answers.get(question_id),
                "correct_option": answers.get(question_id),
            }
            if question_id in explanations:
                result["explanation"] = explanations[question_id]
            results.append(result)
        correct = sum(result["correct"] for result in results)
        total = len(questions)
        return {
            "topic_id": topic_id,
            "quiz_version": version,
            "correct_count": correct,
            "total_questions": total,
            "score_percent": round(correct * 100 / total),
            "results": results,
            # Stored with the attempt for research; never returned for a pre-test.
            "answers": [
                {"question_id": result["question_id"],
                 "choice": choices[result["question_id"]],
                 "correct": result["correct"]}
                for result in results
            ],
        }

    def asset(self, name: str) -> Path | None:
        if not ASSET_NAME.fullmatch(name):
            return None
        path = self.root / "assets" / name
        return path if path.is_file() else None
