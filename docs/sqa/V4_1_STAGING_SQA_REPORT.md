# V4.1 Staging SQA Report

**Release candidate:** V4.1 research study data and instructor analytics

**Test date:** 2026-08-05

**Repository:** `CS-Ponkoj/Robotics-Programming-Lab-Staging` (`main`)

**Decision:** PASS for staging publication

## Result summary

| Area | Verification | Result | Evidence |
|---|---|---:|---|
| Backend regression | Full API, authentication, assignments, grading, sandbox rules, migrations and research tests | PASS | 91 pytest tests passed |
| Python environment | Installed dependency consistency and bytecode compilation | PASS | `pip check`; `compileall` |
| Database migration | Baseline-to-head upgrade, downgrade and existing-database column migration | PASS | Alembic migration tests |
| Study sessions | Start, heartbeat, end, duration cap and idempotent session handling | PASS | Backend research tests and browser session |
| Learning events | Assignment open, submit, hint, solution, tab and AI-toggle event capture | PASS | API tests and browser timeline |
| Student privacy | Student receives only their participant-level progress | PASS | Authorization/API tests and student dashboard |
| Instructor authorization | Research summary, participant detail and exports require instructor role | PASS | Role-isolation API tests |
| Participant identifiers | Duplicate participant codes are rejected on create, update and account sync | PASS | Focused backend tests |
| CSV export | UTF-8 CSV downloads without passwords, login IDs or submitted code | PASS | HTTP 200 and sensitive-field scan |
| Excel export | Complete workbook downloads with valid XLSX signature and three research datasets | PASS | HTTP 200; `PK` XLSX signature |
| Spreadsheet safety | Exported cells neutralize spreadsheet-formula prefixes | PASS | Export unit tests |
| Student UI | Study-progress summary and recent-attempt view | PASS | Flutter widget tests and browser check |
| Instructor UI | Summary, participant table, detail timeline and export menu | PASS | Flutter widget tests and browser check |
| Responsive UI | Dashboard and results at 390 x 844 mobile viewport | PASS | Widget overflow test and browser check |
| Keyboard/accessibility baseline | Existing keyboard run flow and semantic controls remain working | PASS | Flutter regression tests |
| AI behavior | AI tutor remains available but disabled by default | PASS | Browser check and existing widget behavior |
| Frontend static analysis | Flutter analyzer | PASS | No issues found |
| Frontend regression | Full Flutter widget/unit suite | PASS | 36 tests passed |
| Production-equivalent frontend | Flutter release web compilation with configured API base URL | PASS | Release web build succeeded |
| Local service health | API and sandbox health endpoints | PASS | Both returned `ok`; API version `4.1.0` |
| Browser console | Student and instructor desktop/mobile flows | PASS | No console errors or warnings observed |
| Git hygiene | Whitespace/error-marker validation | PASS | `git diff --check` before commit |

## Manual browser flow covered

1. Logged in as the demo student without credentials being displayed on the login page.
2. Opened Assignment 1 and confirmed AI was off by default.
3. Ran starter code and confirmed the grader returned a completed result rather than hanging.
4. Confirmed assignment-open and submission activity appeared in the research dataset.
5. Logged out after an active study interval and confirmed the study session ended with recorded active time.
6. Logged in as the demo instructor, opened Research Dashboard, inspected the participant timeline and opened every export option.
7. Repeated the dashboard layout check at a 390 x 844 mobile viewport.

## Non-blocking follow-up checks

| Item | Current status | Reason / next action |
|---|---|---|
| Physical second-device/network check | NOT RUN | Local staging was verified in a clean browser origin and mobile viewport, but not from another physical computer/network. Run this after a staging URL is deployed. |
| OpenAI paid response | NOT RUN | AI is intentionally off by default and the configured account currently has no required credit. The non-AI grading workflow is unaffected. |
| Master Excel SQA checklist update | BLOCKED BY TOOLING | The approved spreadsheet artifact runtime was unavailable in this Codex session. This Markdown report is the committed V4.1 evidence record; copy these rows into the master workbook when that runtime is available. |

These follow-ups do not block publication to the **staging Git repository**. They do block claiming that a future hosted production deployment has been tested from an external network.
