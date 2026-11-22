# Generated course content

Do not edit these files by hand. They are generated from the controlled
source documents in `course_materials/content/`, which is the source of truth.

`scripts/build_course_content.py` converts the reviewed source documents into
the student-safe pages served by the API. `quiz_answers.json` is the
server-only quiz answer key; it is never sent with a quiz page. After a
student submits a complete quiz, the result names each correct option and,
from `quiz_explanations.json` (an "Explanation:" line after a question's
"Answer:" line in the quiz source), why it is correct. `worked_answers.json`
holds the worked answer of a practice page, built from a `*_solution.docx`
beside its exercise or math document; the app fetches it only when a student
presses Show answer.

After a reviewed source-document change, rebuild from the repository root in
a separate content-authoring Python environment with
`scripts/requirements-course-content.txt` installed:

```text
python scripts/build_course_content.py
```

Commit the regenerated files together with the source change.

Formatting the builder understands, beyond plain Word text:

- shaded paragraphs in a code font (Consolas, Courier New, ...) become one
  code block; runs in a code font become inline code;
- a shaded one-cell table whose first line is bold becomes a note box;
- a GIF becomes an animation that plays on its own with a Stop button; its
  first frame (written with Pillow) is the still shown when stopped or when
  the device asks for reduced motion;
- a paragraph `[interactive:<name>]` places one of the app's "Try it" tools
  (`scan-index`, `twist-path`, `wheel-speeds`);
- captions start with "Figure" or "Animation".

Section goals ("In this section you will") and ungraded quick checks are authored in `backend/course_lesson_extras.json`, not here. The API adds them to a lesson when it serves it, matched by each main heading's text, so a rebuild never overwrites them. Quick checks are answered in the browser and never stored, and must not repeat a quiz or pre-test question (a backend test checks this).

Topics listed in `OLD_TOPICS` in the builder are flagged `old` in
`catalog.json`, and the app shows them under Old contents.

A `pretest.docx` in a topic folder, in the same format as `quiz.docx`, becomes
the topic's Pre-test section. Its key is stored in `quiz_answers.json` under
`<topic>/pretest`; the app grades it once per student and never shows its
answers. Pre-test question k should test the same concept as quiz question k
with different wording or values, so the pre-test does not rehearse the quiz.
