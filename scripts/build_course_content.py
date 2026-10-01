"""Build student-safe web pages from the six source content folders.

Run with a Python environment containing python-docx 1.2.0. Generated pages
are checked into backend/course_content; python-docx is not needed at runtime.
"""

from __future__ import annotations

import hashlib
import html
import json
import re
from collections import defaultdict
from pathlib import Path

from docx import Document
from docx.table import Table
from docx.text.hyperlink import Hyperlink
from docx.text.paragraph import Paragraph


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "course_materials" / "content"
OUTPUT = ROOT / "backend" / "course_content"
ASSETS = OUTPUT / "assets"

TOPICS = {
    "Obstacle Avoidance": (
        "obstacle-avoidance",
        "Obstacle Avoidance",
        "Detect obstacles and choose safe routes around them.",
    ),
    "Path Planning": (
        "path-planning",
        "Path Planning",
        "Explore search algorithms and robot routes through constrained spaces.",
    ),
    "Sensor Fusion": (
        "sensor-fusion",
        "Sensor Fusion",
        "Combine readings from multiple sensors to estimate robot state.",
    ),
    "Range Sensors": (
        "range-sensors",
        "Range Sensors",
        "Compare distance sensors and interpret obstacle measurements.",
    ),
    "Locomotion": (
        "locomotion",
        "Locomotion",
        "Study robot mobility, stability, and motion calculations.",
    ),
    "Hybrid Navigation GPS": (
        "hybrid-navigation-gps",
        "Hybrid Navigation and GPS",
        "Navigate when satellite positioning is unreliable or unavailable.",
    ),
}

IMAGE_TYPES = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg"}
ANSWER_START = re.compile(r"^(?:answer|solution|solutions)\s*(?::|$)", re.I)
QUESTION_START = re.compile(r"^question(?:\s+\d+)?\s*(?::|$)", re.I)
CHOICE = re.compile(r"^([A-D])[.)]\s*(.+)", re.I)


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")


def student_source(path: Path) -> bool:
    parts = [part.lower() for part in path.relative_to(SOURCE).parts]
    return not any("reference" in part for part in parts) and not any(
        marker in path.stem.lower() for marker in ("solution", "unittest", "step_by_step_explanation")
    )


def visible_paragraphs(document: Document, *, strip_answers: bool) -> set:
    visible: set = set()
    in_answer = False
    for index, paragraph in enumerate(document.paragraphs):
        text = paragraph.text.strip()
        if strip_answers and ANSWER_START.match(text):
            in_answer = True
            continue
        if strip_answers and (QUESTION_START.match(text) or text.lower().startswith("extra question:")):
            in_answer = False
        if strip_answers and text.lower().startswith("references:"):
            in_answer = True
        if not in_answer:
            visible.add(paragraph._p)
    return visible


def image_html(document: Document, paragraph: Paragraph, label: str) -> str:
    images: list[str] = []
    for blip in paragraph._p.xpath(".//a:blip"):
        relation = blip.get(
            "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}embed"
        )
        if not relation or relation not in document.part.related_parts:
            continue
        part = document.part.related_parts[relation]
        extension = Path(str(part.partname)).suffix.lower()
        if extension not in IMAGE_TYPES:
            continue
        blob = part.blob
        name = f"{hashlib.sha256(blob).hexdigest()[:20]}{extension}"
        destination = ASSETS / name
        if not destination.exists():
            destination.write_bytes(blob)
        images.append(
            f'<figure><img src="/content-assets/{name}" '
            f'alt="Diagram from {html.escape(label, quote=True)}" '
            'loading="lazy" /></figure>'
        )
    return "".join(images)


def paragraph_html(document: Document, paragraph: Paragraph, label: str) -> str:
    runs: list[str] = []
    for item in paragraph.iter_inner_content():
        if isinstance(item, Hyperlink):
            text = html.escape(item.text)
            url = item.url or ""
            if url.startswith(("https://", "http://")):
                runs.append(f'<a href="{html.escape(url, quote=True)}">{text}</a>')
            else:
                runs.append(text)
            continue
        run = item
        text = html.escape(run.text).replace("\n", "<br />")
        if not text:
            continue
        if run.bold:
            text = f"<strong>{text}</strong>"
        if run.italic:
            text = f"<em>{text}</em>"
        runs.append(text)
    text_html = "".join(runs)
    if not text_html and paragraph.text.strip():
        text_html = html.escape(paragraph.text.strip())
    math_tokens = [node.text or "" for node in paragraph._p.xpath(".//m:t")]
    if math_tokens:
        text_html += f'<span class="math-expression">{html.escape("".join(math_tokens))}</span>'
    images = image_html(document, paragraph, label)
    if not text_html.strip():
        return images
    style = paragraph.style.name.lower() if paragraph.style else ""
    if "heading" in style or style == "title":
        match = re.search(r"(\d+)", style)
        level = min(4, max(2, int(match.group(1)))) if match else 2
        return f"<h{level}>{text_html}</h{level}>{images}"
    if "list bullet" in style:
        return f"<ul><li>{text_html}</li></ul>{images}"
    if "list number" in style:
        return f"<ol><li>{text_html}</li></ol>{images}"
    return f"<p>{text_html}</p>{images}"


def table_html(table: Table) -> str:
    rows = []
    for row in table.rows:
        cells = "".join(
            f"<td>{html.escape(cell.text).replace(chr(10), '<br />')}</td>"
            for cell in row.cells
        )
        rows.append(f"<tr>{cells}</tr>")
    return f"<table>{''.join(rows)}</table>"


def document_html(path: Path, *, strip_answers: bool = False) -> str:
    document = Document(path)
    visible = visible_paragraphs(document, strip_answers=strip_answers)
    blocks: list[str] = []
    for block in document.iter_inner_content():
        if isinstance(block, Paragraph):
            if block._p in visible:
                blocks.append(paragraph_html(document, block, path.stem))
        elif isinstance(block, Table):
            blocks.append(table_html(block))
    return "\n".join(block for block in blocks if block)


def text_html(path: Path) -> str:
    text = path.read_text(encoding="utf-8-sig", errors="replace")
    return "\n".join(
        f"<p>{html.escape(line.strip())}</p>"
        for line in text.splitlines()
        if line.strip()
    )


def quiz_questions(path: Path) -> tuple[list[dict], dict[str, str]]:
    document = Document(path)
    questions: list[dict] = []
    answers: dict[str, str] = {}
    prompt: list[str] = []
    options: list[dict] = []
    for paragraph in document.paragraphs:
        value = paragraph.text.strip()
        if not value:
            continue
        answer = re.match(r"^Answer\s*:\s*([A-D])\b", value, re.I)
        if answer:
            question_id = f"q{len(questions) + 1}"
            if prompt and len(options) >= 2:
                questions.append({
                    "id": question_id,
                    "prompt": "\n".join(prompt),
                    "options": options,
                })
                answers[question_id] = answer.group(1).upper()
            prompt, options = [], []
            continue
        for line in value.splitlines():
            choice = CHOICE.match(line.strip())
            if choice:
                options.append({"id": choice.group(1).upper(), "text": choice.group(2)})
            elif line.strip():
                prompt.append(line.strip())
    if prompt or options or len(questions) != len(answers):
        raise ValueError(f"Incomplete answer key in {path}")
    return questions, answers


def label_for_group(path: Path, topic_root: Path) -> str:
    parts = path.relative_to(topic_root).parts
    readable = [part.replace("_", " ").replace("-", " ") for part in parts]
    readable = [re.sub(r"^Assignment\s+", "", value, flags=re.I) for value in readable]
    return " · ".join(readable).replace("  ", " ")


def build() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    ASSETS.mkdir(parents=True, exist_ok=True)
    catalog: list[dict] = []
    answer_key: dict[str, dict[str, str]] = {}
    authored_quizzes = json.loads(
        (ROOT / "scripts" / "course_quiz_bank.json").read_text(encoding="utf-8")
    )
    for folder_name, (topic_id, title, summary) in TOPICS.items():
        topic_root = SOURCE / folder_name
        topic_dir = OUTPUT / topic_id
        direct_docs = sorted(
            path for path in topic_root.glob("*.docx") if student_source(path)
        )
        lessons = [
            path for path in direct_docs
            if "quiz" not in path.stem.lower() and "math" not in path.stem.lower()
        ]
        if len(lessons) != 1:
            raise ValueError(f"Expected one lesson document for {folder_name}: {lessons}")
        sections: list[dict] = []

        def add_section(section_id: str, name: str, kind: str, body: str,
                        questions: list[dict] | None = None) -> None:
            metadata = {"id": section_id, "title": name, "kind": kind}
            sections.append(metadata)
            write_json(topic_dir / f"{section_id}.json", {
                **metadata, "topic_id": topic_id, "html": body,
                "questions": questions or [],
            })

        add_section("lesson", "Lesson", "lesson", document_html(lessons[0]))

        exercise_files: dict[Path, list[Path]] = defaultdict(list)
        for path in sorted(topic_root.rglob("*")):
            if not path.is_file() or path.parent == topic_root or not student_source(path):
                continue
            if path.suffix.lower() in {".docx", ".txt"}:
                exercise_files[path.parent].append(path)
        for directory, files in sorted(exercise_files.items()):
            section_id = slug(str(directory.relative_to(topic_root)))
            name = label_for_group(directory, topic_root)
            pieces = []
            ordered = sorted(files, key=lambda path: (
                "instruction" not in path.stem.lower()
                and "scenario" not in path.stem.lower()
                and "senario" not in path.stem.lower(),
                path.name.lower(),
            ))
            for path in ordered:
                if path.suffix.lower() == ".docx":
                    pieces.append(document_html(path, strip_answers=True))
                elif path.suffix.lower() == ".txt":
                    pieces.append(text_html(path))
                else:
                    pieces.append(text_html(path))
            add_section(section_id, name, "exercise", "\n".join(pieces))

        source_quiz = next(
            (path for path in direct_docs if path.stem.lower() == "quiz"), None
        )
        if source_quiz is not None:
            questions, answers = quiz_questions(source_quiz)
        else:
            rows = authored_quizzes[topic_id]
            questions, answers = [], {}
            for number, (prompt, choices, correct) in enumerate(rows, start=1):
                if len(choices) != 4 or correct not in "ABCD":
                    raise ValueError(f"Invalid authored question in {topic_id}")
                # Rotate the location of the right answer; it must not always be A.
                rotation = (number - 1) % 4
                rotated = choices[rotation:] + choices[:rotation]
                question_id = f"q{number}"
                questions.append({
                    "id": question_id,
                    "prompt": prompt,
                    "options": [
                        {"id": letter, "text": choice}
                        for letter, choice in zip("ABCD", rotated)
                    ],
                })
                answers[question_id] = "ABCD"[("ABCD".index(correct) - rotation) % 4]
        if len(questions) < 10 or len(answers) != len(questions):
            raise ValueError(f"Expected at least 10 complete quiz questions for {topic_id}")
        section_id = "quiz"
        version = hashlib.sha256(
            json.dumps([questions, answers], ensure_ascii=False, sort_keys=True).encode("utf-8")
        ).hexdigest()[:16]
        add_section(section_id, "Quiz", "quiz", "", questions)
        quiz_file = topic_dir / "quiz.json"
        quiz_payload = json.loads(quiz_file.read_text(encoding="utf-8"))
        quiz_payload["version"] = version
        write_json(quiz_file, quiz_payload)
        answer_key[f"{topic_id}/{section_id}"] = answers

        for path in direct_docs:
            if path == lessons[0] or "quiz" in path.stem.lower():
                continue
            add_section(
                slug(path.stem), path.stem.replace("_", " "),
                "math", document_html(path, strip_answers=True),
            )

        write_json(topic_dir / "index.json", {
            "id": topic_id, "title": title, "summary": summary,
            "sections": sections,
        })
        # Remove pages from a previous build that are no longer listed.
        current = {"index.json", *(f"{section['id']}.json" for section in sections)}
        for old_page in topic_dir.glob("*.json"):
            if old_page.name not in current:
                old_page.unlink()
        catalog.append({
            "id": topic_id, "title": title, "summary": summary,
            "section_counts": {
                kind: sum(section["kind"] == kind for section in sections)
                for kind in ("lesson", "exercise", "quiz", "math")
            },
        })
    write_json(OUTPUT / "catalog.json", {"topics": catalog})
    write_json(OUTPUT / "quiz_answers.json", answer_key)
    print(f"Built {len(catalog)} topics and {sum(len(v) for v in answer_key.values())} quiz questions")


if __name__ == "__main__":
    build()
