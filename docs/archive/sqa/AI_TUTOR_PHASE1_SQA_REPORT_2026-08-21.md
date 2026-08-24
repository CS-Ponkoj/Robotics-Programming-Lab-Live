# AI Tutor Phase 1 Staging SQA Report

**Date:** 2026-08-21

**Repository:** `CS-Ponkoj/Robotics-Programming-Lab-Staging`

**Local checkout:** `Robotics-Programming-Lab-Staging`

**Branch:** `ai-tutor-phase1`

**Baseline commit:** `09c2517e8e6950882901b048af262f06317a7880`

**Tested source state:** baseline commit plus the uncommitted Phase 1 working-tree
diff listed in this report

**Environment:** Windows 11, Flutter web, FastAPI, SQLite, remote Python
sandbox, ROS 2 Jazzy Docker grader

**AI mode:** opt-in; OpenAI key configured locally; deterministic fallback
available

## Outcome

Phase 1 is functionally ready in staging. Test-case grading remains the only
grading authority. The tutor can explain the first observed problem, recommend
debugging steps, provide gradual hints, and answer a question about the latest
attempt without receiving hidden tests, protected expected values, grader
configuration, credentials, or official solutions.

All automated gates, maintained answers for Assignments 1-6, adversarial
execution checks, student flows, instructor flows, desktop layout, mobile-width
layout, keyboard behavior, research privacy checks, and safe fallback behavior
passed. Real OpenAI wording and pedagogical correctness remain **blocked** from
certification because the configured account returned `429 insufficient_quota`.
The application handled that condition correctly and grading remained fully
available.

## Feature and QA results

| Area | Test | Expected | Result | Evidence |
|---|---|---|---|---|
| Grading boundary | AI disabled by default | Ordinary test grading makes no model request | PASS | UI default and backend opt-in tests |
| Grading boundary | AI cannot change grade | Score/pass state comes only from grader evidence | PASS | API tests and manual Assignment 1 run |
| Structured feedback | Diagnosis, answer, debugging steps, guiding question, hint, next action | Strict bounded response | PASS | Tutor schema tests and rendered tutor card |
| Student questions | Ask about latest owned submission | Structured answer or safe fallback | PASS | Endpoint, ownership, Flutter success/retry/manual tests |
| Progressive support | Hint levels 1-4 | Increasing guidance without direct solution | PASS | Existing hint tests and tutor UI |
| Solution protection | Request full answer/code | Refuse replacement solution | PASS | Policy tests and 24 instructor cases |
| Hidden-test protection | Tutor input construction | No hidden source/config/expected values | PASS | Secret-sentinel and serialization tests |
| Output protection | Model returns code/protected phrases/malformed JSON | Reject and use deterministic fallback | PASS | Tutor policy regression tests |
| Privacy | Model response storage | OpenAI `store=false` | PASS | Captured request assertion |
| Privacy | Student question research event | Store length/type, not raw question | PASS | Research contract and persistence tests |
| Authorization | Student asks about another student's submission | Reject | PASS | Cross-student API test |
| Authorization | Unauthenticated tutor request | Reject | PASS | API authentication test |
| Abuse control | Repeated questions | Rate limit with recoverable UI error | PASS | Backend 429 and Flutter retry tests |
| Reliability | Missing key/provider error/malformed response | Grading succeeds with built-in tutor | PASS | Unit tests and manual no-credit fallback |
| Assignment coverage | AI evaluation datasets | Four cases for each Assignment 1-6 | PASS | 24/24 controlled cases passed safe pipeline |
| Assignment 1 | Maintained Python answer | 100%, 4/4 | PASS | Local authenticated API: 0.40 s |
| Assignment 2 | Maintained Python answer | 100%, 4/4 | PASS | Local authenticated API: 0.39 s |
| Assignment 3 | Maintained Python answer | 100%, 6/6 | PASS | Local authenticated API: 0.74 s |
| Assignment 4 | Maintained Python answer | 100%, 2/2 | PASS | Local authenticated API: 0.53 s |
| Assignment 5 | Maintained ROS 2 answer | 100%, 7/7 | PASS | Real Jazzy Docker grader, 79 messages at about 10 Hz |
| Assignment 6 | Maintained ROS 2 answer | 100%, 9/9 | PASS | Real Jazzy Docker grader, 44 settled messages at about 9.2 Hz |
| Incorrect code | Assignment 2 wrong value | Graded failure | PASS | 200 response, `pass=false` |
| Syntax error | Invalid Python | Safe syntax classification | PASS | 200 response, `syntax_error` |
| Runtime error | Division by zero | Safe runtime classification | PASS | 200 response, `runtime_error` |
| Infinite loop | Non-terminating code | Bounded timeout | PASS | `timeout` after 5.39 s |
| Excessive output | 200,000-character print | Output bounded | PASS | Returned output limited to about 20,000 characters |
| Unsafe import | `import os` | Sandbox rejection | PASS | `rejected` in 0.45 s |
| Oversized submission | More than 50,000 characters | Request rejected | PASS | HTTP 413 in 0.01 s |
| Student browser | Login, six assignments, editor, run, opt-in tutor, question | Complete without hang or console error | PASS | Manual Flutter web QA on `127.0.0.1:8180` |
| Demo browser | Temporary student capabilities | Student tools available without permanent study data | PASS | Manual demo flow plus persistence regressions |
| Instructor browser | Login, six-assignment studio, student accounts, research dashboard | Authorized management views render | PASS | Manual Flutter web QA |
| Responsive design | 390 x 844 viewport | No clipped dashboard controls/data | PASS | Manual mobile-width screenshot and widget tests |
| Keyboard/accessibility | Ctrl+Enter, labels, live error regions, narrow results | Operable and readable | PASS | Flutter widget tests |
| Backend regression | Entire backend suite | No failures | PASS | 166 pytest tests |
| Frontend regression | Analyze and all Flutter tests | No issues/failures | PASS | Analyzer clean; 48 Flutter tests |
| Release build | Flutter web release compilation | Successful | PASS | OneDrive-safe release build completed |
| Dependencies | Python environment consistency | No broken requirements | PASS | `pip check` clean |
| Service health | Managed API and sandbox | Healthy | PASS | Verification script health checks |
| OpenAI live semantic quality | Real provider answer against approved cases | Correct, pedagogical, non-revealing answers | BLOCKED | Provider returned `429 insufficient_quota`; no provider answer existed to score |
| External-device/network | Separate physical computer/network | Complete browser workflow | NOT RUN | Current SQA was local to this Windows machine |

## Bugs found and resolved

| ID | Problem | Fix | Verification |
|---|---|---|---|
| AI-01 | Flutter discarded most structured tutor fields after decoding the submit response | Preserve the complete `tutor_feedback` map in the feedback DTO | DTO and rendered-card tests pass |
| AI-02 | A returned tutor response could render without keeping the question form available if the local toggle state changed | Treat returned tutor feedback as authoritative tutor availability | Regression test and manual browser flow pass |
| AI-03 | Question retries could lose context or produce duplicate requests | Keep the typed question, show a recoverable error, and disable duplicate sends while loading | Retry and duplicate-request widget tests pass |
| AI-04 | A free-form model response could violate the expected response contract | Require strict JSON schema validation and apply output solution-leakage checks | Malformed and unsafe-output tests fall back safely |
| AI-05 | Question text could have entered general learning-event storage | Persist only interaction type and question length in research events | Privacy regression test passes |
| QA-01 | Port 8080 showed an older cached Flutter service worker during manual QA | Repeated the test on clean local origin 8180 and verified the compiled source/API response | Current tutor form and response rendered correctly |

## Verification commands

```powershell
.\scripts\verify-local.ps1 -ApiBaseUrl http://127.0.0.1:5000
.\scripts\check-ros2-local.ps1

Set-Location .\backend
..\venv\Scripts\python.exe -m pytest tests\test_tutor_evaluations.py tests\test_tutor.py -q
```

Results:

- complete backend suite: 166 passed;
- focused tutor suite: 31 passed;
- Flutter suite: 48 passed;
- Flutter analyzer: no issues;
- release web build: passed;
- Assignment 1-4 maintained answers: all 100%;
- Assignment 5-6 maintained answers: both 100% in the real ROS 2 grader.

## Release decision

**Staging implementation decision: PASS with one external limitation.** The
feature is safe and usable with the deterministic tutor today. Do not claim
that real OpenAI responses are pedagogically certified until API credit is
available and the 24 instructor cases are evaluated with actual provider
responses and instructor review. Production promotion still requires owner
approval and a separate production SQA cycle.

## Workbook status

The Markdown SQA record is current. Updating
`Robotics_Programming_Lab_Master_SQA_Checklist.xlsx` was blocked in this runtime
because the required workspace spreadsheet dependency loader was unavailable.
The workbook was left unchanged rather than edited through an unsupported
library.
