# V6.2 Learning Workbench QA

Scope: local staging only. Preserve deterministic grading, role privacy,
quiz persistence, optional AI (off by default), and the existing shared header.

| Increment | Intended result | Validation | Status |
|---|---|---|---|
| Visual foundations and catalogs | Soft teal, sand and lavender surfaces; clear best/latest scores and next actions | Theme contrast >= 4.5:1 on new surfaces; catalog widgets; desktop/narrow layouts | PASS |
| Results workbench | Non-modal resizable desktop dock; narrow-screen drawer; minimize/reopen | Workspace widgets; browser opening, resizing, editing beside results and retained narrow-screen results | PASS |
| Reading | Section navigation without changing lesson or assignment content | Reading widgets; authored HTML retained; browser outline jump to VFH | PASS |
| Role dashboards and recovery | Clear student/instructor hierarchy; useful retry state | Dashboard widgets; session-expired 401 and retry checks; persistent student analytics browser review | PASS |
| Integrated release | Analysis, tests, release build, backend regression, manual browser QA | 215 backend tests, 89 Flutter tests, clean analysis, release build, real ROS graders | PASS |

## Evidence and scope — 2026-09-28

- Canonical checkout: Robotics-Programming-Lab-Staging; production untouched.
- Browser URL remains `http://127.0.0.1:8180/app`; API port 5100 and sandbox port 5101.
- Backend: `215 passed in 80.65s`; `pip check` found no broken requirements.
- Flutter: analysis clean; all 89 tests passed; release web build passed (52.3 seconds).
- Real Docker ROS graders: Assignment 5 maintained answer 7/7; Assignment 6 9/9.
- Persistent student browser checks: login, current assignment progress, saved Sensor Fusion quiz score and version-separated study analytics loaded successfully.
- Instructor browser checks: login, six published assignment entries in the studio and participant-code classroom dashboard loaded. No accounts, questions or records were modified.
- Disposable demo browser checks: untouched Assignment 1 starter 0% (0/4); complete solution 100% (4/4); editor usable alongside the dock; AI switches remained off. Demo refresh returned to login, with no permanent student attempts added.
- Responsive browser checks: 1440 × 900 desktop and 390 × 844 narrow workspace. Outline selection moved to the requested lesson heading after the scroll settled.
- Excel: appended a V6.2 Workbench evidence sheet; prior 11 sheets' cell values/formulas, table names, validations, merges and chart counts verified unchanged. Before/after renders reviewed.
- AGENTS.md maintenance review: no new architecture, environment or working-policy change requiring an instruction update.

## Confirmed issues fixed during implementation

| Issue | Fix | Verification |
|---|---|---|
| Initial candidate tint gave primary text only 4.48:1 contrast | Lightened teal/lavender surfaces | Contrast regression passed |
| Additional catalog badges overflowed the existing row | Flexible status row; increased card height; single-column layout for enlarged text | Catalog/responsive widget tests passed |
| Empty results content could overflow a shallow dock | Scrollable empty-results body | Workspace tests passed |
| Expired-session Contents request appeared as an unexplained content failure | Dedicated sign-in-again message for HTTP 401 | API/widget regression passed |

## Limitations / not run

- No production deployment, physical Ubuntu/new-device run or paid OpenAI request. AI behavior is covered by the existing mocked tests; this is not evidence of provider availability.
- This release is a visual/workflow upgrade, not a rewrite of assignment questions, grading or research formulas. Broader accessibility certification and every browser/zoom combination are not claimed.
- Backend regression ran an export of the exact staged Git tree, including the existing maintained-answer paths. The local user answer moves were not restored, deleted or published.

Unrelated local moves of answer files and reference PDFs are excluded from this
release. Do not treat those working-tree changes as part of the UI upgrade.
