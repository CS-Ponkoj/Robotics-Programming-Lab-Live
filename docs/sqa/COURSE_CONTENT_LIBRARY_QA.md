# Course content library — staging QA

Scope: Windows local staging verification only; hosted deployment was not tested.
Tested source commit: `6a3992d` (`v6`).

## Scope

- Six topic pages generated from the six `course_materials/content` folders.
- 34 student-facing sections: six lessons, 20 question-only exercise groups,
  six quizzes, and two math-practice sections. Each topic has one 10-question
  quiz; Python exercise files are not shown.
- Diagrams are served as separate web images. The `References` folders,
  official solution files, worked-answer blocks, and quiz answer keys are not
  returned as student pages. Quiz keys are read only by the backend.
- Complete-quiz submission shows a score. Persistent student quiz attempts are
  saved separately from graded coding assignments. Demo and instructor quiz
  previews never create quiz-attempt rows.

## Checks

| Check | Result | Evidence |
| --- | --- | --- |
| Authenticated access; six topics; all sections | Pass | `backend/tests/test_course_content.py` |
| Quiz submit, 100% and 0% scores, rejected incomplete and invalid answers | Pass | `backend/tests/test_course_content.py` |
| Student-private history, restart persistence, demo non-persistence | Pass | `backend/tests/test_course_content.py` with disposable database |
| Exercise and math pages omit answer headings | Pass | Generated-page scan and backend test |
| Lesson images load | Pass | Backend asset test and local browser diagram view |
| Student navigation and course page | Pass | Isolated local browser with temporary in-memory database |
| UTF-8 symbols and punctuation | Pass | Local browser recheck after client fix |
| Mobile-width topic navigation and score-after-submit behavior | Pass | Flutter widget test at 390-pixel width |
| Fresh/upgrade/rollback migration | Pass | `backend/tests/test_migrations.py` |
| Full backend regression, dependency/compile validation, Flutter analysis/tests/release build, source completeness, and service health | Pass | `./scripts/verify-local.ps1 -ApiBaseUrl http://127.0.0.1:5100` on the Windows staging checkout |
| Hosted deployment | Not run | No hosted deployment was performed |

## Issues found and fixed during QA

1. Some Word math-practice answers survived the first importer pass. The
   importer now tracks actual paragraph elements and removes answer blocks.
2. One exercise document contained a worked `Solution` section. All exercise
   documents now strip answer/solution blocks; a regression test checks this.
3. The Flutter HTTP client decoded UTF-8 lesson text as Latin-1. It now decodes
   response bytes explicitly as UTF-8, preserving quotes and math symbols.
4. Exercises initially displayed Python starter files. The generator now emits
   only question/instruction documents and scenarios, while leaving source
   Python files untouched in `course_materials/`.

## Remaining review

Four topics had no quiz in the source documents, so 40 new questions were
authored from the associated lessons. The two existing 10-question quizzes
remain sourced from course documents. An instructor should review all question
wording, answer keys, source teaching claims, and copyright permissions before
classroom use. The pre-existing local moves of PDFs into `References` were
preserved and are not part of this change.
