# Course materials

This directory contains controlled source material used to design and verify
robotics assignments.

- `content/` contains teaching documents, research references, exercises, and
  source solutions. Assignments 1-4 currently reference selected solution files
  here, so paths must not be changed without updating assignment configuration
  and running all maintained-answer tests.
- `archive/screenshots/` preserves early interface screenshots for historical
  reference. The application does not load them at runtime.

`backend/course_content/` is the generated, student-safe copy of the course
pages that the API serves. Edit the documents here, then rebuild it with
`scripts/build_course_content.py`; never edit the generated copy directly.

Do not copy solution files, answer keys, or hidden grading details into the
Flutter frontend, student API responses, research exports, or AI tutor context.
Do not delete course content merely because it is not referenced by the current
six assignments; it may be research or future-assignment source material.
