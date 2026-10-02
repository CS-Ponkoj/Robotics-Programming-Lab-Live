# Generated course content

Do not edit these files by hand. They are generated from the controlled
source documents in `course_materials/content/`, which is the source of truth.

`scripts/build_course_content.py` converts the reviewed source documents into
the student-safe pages served by the API. `quiz_answers.json` is the
server-only quiz answer key; it is never sent to the browser.

After a reviewed source-document change, rebuild from the repository root in
a separate content-authoring Python environment with
`scripts/requirements-course-content.txt` installed:

```text
python scripts/build_course_content.py
```

Commit the regenerated files together with the source change.
