# Secure Grader Reliability SQA Report

**Test date:** 2026-08-17

**Change:** Retry transient hosted-sandbox startup failures, distinguish configuration and temporary-service errors, and allow the slowest maintained production assignment to finish on Render.

**Staging behavior commit:** `925f43f00665bd60ca34bb4b1c634492b71703d8`

**Production behavior commit:** `9fa6c2482c7ac66f30bc658a876c68b017eb1b5d`

**Decision:** PASS for the reported Assignment 1 execution-error repair in staging and production.

## Results

| Requirement | Environment | Check | Expected | Actual | Status |
|---|---|---|---|---|---:|
| Transient sandbox startup recovery | Automated unit test, both repositories | Sandbox returns HTTP 503 before succeeding | Client retries within its bounded deadline | Request retried and succeeded | PASS |
| Invalid sandbox credentials | Automated unit test, both repositories | Sandbox returns HTTP 401 | No retry; instructor-facing configuration message | Correct safe message returned once | PASS |
| Persistent sandbox outage | Automated unit test, both repositories | Sandbox remains HTTP 503 | Bounded retry; temporary/busy message | Retries stopped at deadline with safe message | PASS |
| Portable timeout contract | GitHub-hosted Linux CI | Deadline-derived timeout is marginally below 20 seconds | Test accepts clock precision without weakening the limit | Tolerance-based assertion passed | PASS |
| Backend regression | Staging local | `pytest tests -q` | All tests pass | 107 passed | PASS |
| Backend regression | Production local | `pytest tests -q` | All tests pass | 98 passed | PASS |
| Frontend regression | Staging local | Flutter analyzer, tests, release web build | All gates pass | Analyzer clean; 41 tests passed; release build passed | PASS |
| Frontend regression | Production local | Flutter analyzer, tests, release web build | All gates pass | Analyzer clean; 38 tests passed; release build passed | PASS |
| Hosted CI gate | Staging GitHub Actions run `32011216945` | Backend, frontend, repository safety, sandbox image | All jobs pass | Four jobs passed | PASS |
| Hosted CI gate | Production GitHub Actions run `32011217908` | Backend, frontend, repository safety, sandbox image | All jobs pass | Four jobs passed | PASS |
| Exact production deployment | Render API health | Release identifies approved production behavior commit | `9fa6c2482c7a` | `9fa6c2482c7a` | PASS |
| Production assignment inventory | Live authenticated API | Only approved live assignments are exposed | IDs 1-4; no ROS Assignment 5 | IDs 1, 2, 3, 4 | PASS |
| Official answers | Live demo API | Maintained answers for Assignments 1-4 pass hidden grading | 100% for each | All four returned 100% | PASS |
| Reported Assignment 1 flow | Live Vercel UI | Paste maintained answer and select **Run tests** | Completed result; no execution error | 100%, 4/4 passed | PASS |
| Incorrect answer | Live `/submit`, Assignment 2 | Hidden grader rejects `total_path_length = 0` | Failing score | 0%, 4/4 hidden checks failed | PASS |
| Public-versus-hidden test boundary | Live `/run` and `/submit`, Assignment 2 | Public run may provide partial evidence; submission enforces hidden tests | Incorrect code rejected at submission | Public check passed; hidden submission failed | PASS |
| Syntax error | Live sandbox | Invalid Python is reported safely | SyntaxError; no stuck request | Safe SyntaxError returned | PASS |
| Runtime error | Live sandbox | Division by zero is reported safely | ZeroDivisionError; no stuck request | Safe ZeroDivisionError returned | PASS |
| Infinite loop | Live sandbox | Execution is bounded | Timeout near assignment limit | TimeoutError after about 5.5 seconds | PASS |
| Unsafe import | Live sandbox | `import os` is denied | Safe rejection | ImportError: import not allowed | PASS |
| Oversized submission | Live API | More than 50,000 code characters is rejected | HTTP 413 | HTTP 413 | PASS |
| Demo privacy behavior | Live Vercel UI | Demo work resets on refresh | Return to login; no retained progress | Returned to login after refresh | PASS |
| AI default | Live Assignment 1 UI | AI tutoring remains available but off by default | Toggle off | Toggle off | PASS |
| Staging Assignment 5 separation | Local staging | ROS Assignment 5 remains staging-only | Staging has 1-5; production has 1-4 | Inventory preserved | PASS |

## Local assignment execution evidence

Staging local execution passed maintained answers for Assignments 1-4 and the ROS 2 Assignment 5 Docker grader. Incorrect values, syntax errors, runtime errors, infinite loops, unsafe imports, and oversized submissions were also exercised. Production's dedicated sandbox-service image was built and smoke-tested with Assignment 3 under the new 10-second API execution allowance.

The per-assignment execution limit still takes precedence where configured. Assignment 2 therefore continues to stop infinite loops after 5 seconds. The Linux sandbox CPU limit remains 6 seconds, so increasing the API default from 5 to 10 seconds does not remove the CPU safety boundary.

## Non-blocking items not run

| Item | Status | Reason and follow-up |
|---|---:|---|
| Forced real Render cold-start retry | NOT RUN | Render does not provide a safe command to intentionally suspend the sandbox. The exact 503-to-success sequence is protected by automated tests, and the live grader was exercised after deployment. Recheck after a natural idle period before a classroom session. |
| Paid OpenAI response | NOT RUN | AI is intentionally off by default and no paid call was authorized. Deterministic grading and built-in feedback passed without AI. |
| Physical second computer/network | NOT RUN | The deployed URL and hosted APIs were tested from the current external network and a clean browser tab, but not from a second physical device. Complete this before a classroom-wide release. |
| Hosted restart persistence rehearsal | NOT RUN | No data or persistence code changed. Existing automated persistence coverage passed, but Render/Neon was not deliberately restarted during this repair. |

## Engineering handoff

The implementation uses the same source behavior in both repositories while preserving the intentional assignment difference: staging includes ROS Assignment 5 and production does not. No durable architecture, repository-role, security-boundary, or release-process rule changed, so `AGENTS.md` did not require an update.

