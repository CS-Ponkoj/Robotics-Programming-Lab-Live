# V5 Staging SQA Report

**Test date:** 2026-08-21

**Repository:** `CS-Ponkoj/Robotics-Programming-Lab-Staging`

**Release branch:** `data-standardization-stage1`

**Base commit:** `da68786`

**Scope:** Local staging and staging repository publication only. The production
repository and live deployment were intentionally untouched.

## Release decision

**PASS for staging `main`.** No release-blocking defect remains in the tested
local staging scope. The backend and Flutter application report version
`5.0.0`.

## Manual application checks

| Area | Result | Evidence |
|---|---:|---|
| Cold local startup | PASS | Managed launcher waited for the Flutter compiler before printing the ready URL; a fresh browser reached the login screen without the earlier entrypoint error |
| Login page | PASS | Login ID/password controls and student-demo option rendered; default credentials were not displayed |
| Student demo | PASS | Six assignments opened; demo banner was present; refresh cleared the temporary session |
| Student account login | PASS | Default local student account authenticated and showed the ordinary six-assignment catalog without a demo label |
| Student progress | PASS | `My study progress` displayed participant-only attempts, completion, best score, and active time |
| Instructor login | PASS | Default local instructor account authenticated and exposed role-authorized management |
| Assignment studio | PASS | All six versioned assignments rendered and the Assignment 1 editor opened without changing content |
| Student-account management | PASS | Existing student account and new-student control rendered; no account was changed or deleted during QA |
| Research dashboard | PASS | Participant-code overview, attempts, completion, and active time rendered without login IDs, passwords, or code |
| Assignment 1 grading | PASS | Starter code completed through the dedicated sandbox and returned structured failing-test evidence without hanging |
| Optional AI control | PASS | AI was off by default; enabling the UI control did not interrupt deterministic grading while server-side AI remained disabled |
| Mobile layout | PASS | At 390 x 844, login, catalog, workspace tabs, results, and ROS project tree remained usable without visible overflow |
| Assignment 5 starter run | PASS | ROS grader completed and returned 2/7 checks with meaningful feedback |
| Assignment 6 starter run | PASS | ROS grader completed and returned 1/9 checks with meaningful feedback |
| Docker unavailable recovery | PASS | Executor regression test converts the Windows Docker pipe failure into an actionable `Start Docker Desktop` message without exposing pipe details |

## Automated and integration checks

| Check | Result | Evidence |
|---|---:|---|
| Backend tests | PASS | 127 pytest tests passed |
| Python dependency integrity | PASS | `pip check` found no broken requirements |
| Flutter analysis | PASS | No issues found |
| Flutter tests | PASS | 43 tests passed |
| Flutter release web build | PASS | Production-style release compilation completed |
| Backend health | PASS | `/health` returned `status: ok`, API version `5.0.0`, SQLite, and remote sandbox mode |
| Sandbox health | PASS | Dedicated local sandbox returned `status: ok` |
| Assignment 5 official solution | PASS | 7/7 ROS 2 checks passed in `robotics-lab-ros2-grader:jazzy-v1` |
| Assignment 6 official solution | PASS | 9/9 ROS 2 checks passed in `robotics-lab-ros2-grader:jazzy-v1` |
| Data migration | PASS | Alembic schema migration and fresh/upgrade/downgrade tests passed |
| Data contracts | PASS | Assignment, attempt, execution-status, rubric, and learning-event contracts passed validation tests |
| Git whitespace | PASS | `git diff --check` found no whitespace errors |

## Boundaries and follow-up

| Item | Status | Reason |
|---|---:|---|
| Production/live deployment | NOT RUN | This release was authorized only for the separate staging repository |
| Paid OpenAI response | NOT RUN | AI remains optional and disabled by default; deterministic tutoring/grading paths were verified |
| Separate staging PostgreSQL | NOT RUN | Local QA used the repository's ignored SQLite staging database; PostgreSQL parity remains a promotion check |
| Destructive instructor operations | AUTOMATED ONLY | Account deactivation, password reset, and assignment publication are covered by automated tests but were not manually performed against retained local study data |

## Defects corrected during manual QA

1. **Flutter startup race:** the launcher previously returned after `index.html`
   became reachable, before Flutter finished compiling. It now waits for the
   compiler-ready log marker and generated entrypoint before reporting ready.
2. **Raw Docker error leakage:** a stopped Docker daemon previously exposed its
   Windows named-pipe error. The ROS executor now returns a concise recovery
   instruction and has a focused regression test.
