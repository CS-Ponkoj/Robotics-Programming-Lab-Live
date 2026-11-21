"""Read the reviewed, generated course pages without exposing source documents."""

import json
import re
from pathlib import Path


CONTENT_ROOT = Path(__file__).resolve().parent / "course_content"
ASSET_NAME = re.compile(r"^[0-9a-f]{20}\.(?:png|jpg|jpeg|gif)$")


class CourseContentRepository:
    def __init__(self, root: Path = CONTENT_ROOT):
        self.root = root

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
        return self._read(self.root / topic_id / f"{section_id}.json")

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
