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

## Quiz follow-up verification — September 28, 2026

Environment: Windows staging checkout, follow-up working-tree changes against
`831f5cd`; disposable PostgreSQL 17 and isolated browser preview. Shared Neon
and live deployment were not modified. The normal local launcher applies
`0006_course_quiz_attempts` on restart.

| Check | Result | Evidence |
| --- | --- | --- |
| All six quizzes at 0%, 50%, and 100% | Pass | API assertions in disposable PostgreSQL and course-content regression tests |
| Populated migration, restart persistence, student isolation, rollback/re-upgrade | Pass | Disposable PostgreSQL verification; migration regression tests |
| Browser submission and saved history | Pass | Path Planning: 100% in initial isolated test; 50% with five right/five wrong using PostgreSQL; saved score remains after reopening |
| Keyboard answer selection and submission | Pass | Browser radio controls selected with Space; submit with Enter |
| Demo and instructor preview do not save student attempts | Pass | Course-content regression tests |
| Flutter regression, analysis, release build, dependency integrity | Pass | 77 widget/unit tests; no analyzer issues; release web build; `pip check` |
| Final full backend rerun | Fail | 206 passed, 7 failed because maintained answers were moved from `manual_sqa_answers/` to untracked `assignments_answers/` during verification; tests still reference the old path |
| Shared Neon migration and hosted validation | Not run | No shared/live database mutation or deployment in this follow-up |

The unrelated answer-folder move was preserved. Do not claim a complete release
gate until the owner confirms that rename and its dependent paths are updated,
then reruns the full suite. A transient 401 occurred in the disposable
in-memory browser setup; it was not reproduced in the PostgreSQL browser
recheck. Temporary QA services/database were stopped and discarded; actual
study data was untouched.

## Content-card quiz progress — September 28, 2026

Course cards now display latest and best scores, current-version attempt count,
submission status, and a score-colored bar. Returning from a topic reloads the
catalog. Old quiz versions do not contribute to the current card. Demo progress
is session-memory-only, labeled temporary, and isolated between demo sessions;
instructor previews do not create student progress.

| Check | Result | Evidence |
|---|---|---|
| Course API regression | PASS | 9 tests; current-version latest/best/count, student isolation, and demo isolation/non-persistence |
| Flutter analysis and tests | PASS | No analyzer issues; 78 tests, including mobile catalog and zero-score presentation |
| Release web build | PASS | OneDrive-safe build using the normal backend address, http://127.0.0.1:5100 |
| Manual browser and shared Neon verification | NOT RUN | This follow-up used automated API/widget tests; the normal running stack was not restarted or its database modified |

No schema change was added for card progress. No commit, push, or deployment was
performed. Existing answer-folder rename/full-suite blocker above is unchanged.

### Consistent progress badges on every card

Every course card now always displays `Attempted: N`, `Best score`, and
`Last score` in rounded assignment-style badges. Missing scores use a neutral
dash, not a false 0%; submitted zero scores remain red 0%. Best and last badges
are colored independently using the existing red-to-green performance palette.
Focused course widget tests: 3 passed, including all five unstarted cards,
submitted progress, zero-score distinction, and mobile-width layout. Flutter
analysis passed. This visual follow-up does not change grading or persistence.

### Shared course header and navigation

Assignment and course pages reuse `frontend/lib/widgets/landing_page_header.dart`
for the branded logo/title, authenticated account name/menu, role-specific study
dashboard and instructor studio. Course catalog and topic pages include Home;
the catalog includes Assignments/Contents navigation. Sign-out removes nested
course routes after the logout callback completes. Narrow-screen navigation
wraps instead of overflowing, and the shared header uses a compact layout.

Verification: all 79 Flutter tests passed and analysis found no issues. Added
widget coverage checks branding, account name/menu, Assignments/Home navigation,
sign-out, and the topic header at mobile width. Browser inspection and normal
runtime restart were not performed in this follow-up. No backend, database,
grading, or live-system change; no commit or push. AGENTS.md did not require
another update for this presentation-only change.

### Fixed-header catalog toggle correction

The main landing page now keeps one header mounted while Assignments/Contents
switches only the body below it. Both selections share the same logo, title,
subtitle, back/Home controls and account menu. The selector is centered below
the header. Contents no longer opens a separate catalog route in this workflow.
Home/back on the main shell selects Assignments. Course-topic routes retain
the shared header.

Focused course tests: 5 passed; analyzer: no issues. The new navigation test
verifies that the exact header element remains mounted across both selections,
there is only one header, and Home returns to Assignments. The prior 79-test
regression predates this toggle correction; manual browser inspection and
runtime restart remain pending. No commit, push, or live change.
