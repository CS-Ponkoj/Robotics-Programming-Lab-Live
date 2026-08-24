# V5 Python 3.14 Full Local SQA Report

**Date:** 2026-08-23

**Repository:** `CS-Ponkoj/Robotics-Programming-Lab-Staging`

**Candidate branch:** `upgrade-python314-onedrive`

**Candidate base:** `22ab79a2c160af7c6ac26d6e83a0904b3f306c75`

**Tested content:** the Git commit containing this report; the exact pushed SHA is
recorded in the release handoff

**Environment:** Windows x64, Python 3.14.7, Flutter web, SQLite, PostgreSQL 17,
Docker Desktop Linux containers, AI disabled by default

## Decision

**PASS for staging `main`.** All applicable local application, assignment,
security, browser, persistence, migration, sandbox, and container checks passed.
No application defect was found during this cycle. The optional paid OpenAI
provider path, public hosting, a second physical computer/network, Android, and
the master Excel-workbook edit were not part of this local release decision.

## Assignment answer matrix

Each maintained instructor answer was submitted through the running authenticated
API. Each starter program was then submitted as a deliberately wrong answer.
Assignments 5 and 6 used the real ROS 2 Jazzy Docker grader.

| Assignment | Version | Correct answer | Wrong answer | Result |
| --- | ---: | --- | --- | --- |
| 1, Bug2 m-line route | 5 | 100%, 4/4 checks | 0%, 0/4 checks | PASS |
| 2, Bug2 rectangular detour | 4 | 100%, 4/4 checks | 0%, 0/4 checks | PASS |
| 3, multi-floor route | 5 | 100%, 8/8 checks | 0%, 0/8 checks | PASS |
| 4, VFH safe sector | 4 | 100%, 2/2 checks | 0%, 0/2 checks | PASS |
| 5, ROS 2 drive and stop | 1 | 100%, 7/7 checks | 20%, 2/7 checks | PASS |
| 6, ROS 2 obstacle stop | 1 | 100%, 9/9 checks | 10%, 1/9 checks | PASS |

All responses used structured status/score evidence and were scanned for hidden
test, reference-solution, and private grader-field leakage. No leak was found.

## Hostile and invalid submission matrix

| Case | Expected controlled outcome | Actual outcome | Result |
| --- | --- | --- | --- |
| Syntax error | Safe syntax status | HTTP 200, `syntax_error` | PASS |
| Runtime exception | Safe runtime status | HTTP 200, `runtime_error` | PASS |
| Infinite loop | Bounded timeout | HTTP 200, `timeout` | PASS |
| Unsafe import | Rejected before unsafe execution | HTTP 200, `rejected` | PASS |
| Excessive output | Bounded, non-passing result | HTTP 200, non-passing `completed` result | PASS |
| Oversized submission | Request rejected | HTTP 413 | PASS |
| Missing code | Request rejected | HTTP 400 | PASS |
| Unknown assignment | Not found | HTTP 404 | PASS |

Client responses were checked for stack traces, local filesystem paths, hidden
test labels, grader configuration, and reference-solution paths. None appeared.

## Student, instructor, demo, and research checks

| Requirement | Evidence | Result |
| --- | --- | --- |
| Student authentication and session restore | `/auth/login` and `/auth/me` returned the student role | PASS |
| Instructor authentication and session restore | `/auth/login` and `/auth/me` returned the instructor role | PASS |
| Invalid login | Invalid account returned HTTP 401 | PASS |
| Role authorization | Student and demo tokens returned HTTP 403 for instructor routes | PASS |
| Instructor access | Assignment, student, and research endpoints returned HTTP 200 | PASS |
| Logout revocation | Logout returned 200; reused token returned 401 | PASS |
| Deferred password/email features | Local default returned HTTP 404 | PASS |
| Instructor assignment validation | Assignments 1-6 returned `valid=true` with zero errors | PASS |
| Demo learning tools | Demo submission, hint, and tutor question returned HTTP 200 | PASS |
| Demo restrictions | Research persistence returned 409; admin access returned 403 | PASS |
| Demo memory-only behavior | Submission, auth-session, audit, study-session, and learning-event database counts were unchanged | PASS |
| AI disabled fallback | Requested tutor help returned built-in `fallback`, progressive debugging steps, and no solution | PASS |
| Research CSV privacy | Three CSV datasets returned 200 and excluded passwords, login IDs, source code, secrets, and grader fields | PASS |
| Research Excel export | Combined XLSX returned 200, valid ZIP signature, and 14,487 bytes | PASS |

## Manual browser QA

| Flow | Evidence | Result |
| --- | --- | --- |
| Clean login | Login ID, password, sign-in, and temporary-demo controls rendered; credentials were not displayed | PASS |
| Demo entry and reset | Demo opened without credentials; browser refresh returned to login and reset work | PASS |
| Catalog | All six assignment cards rendered with correct titles and states | PASS |
| Python workspace | Assignment 1 instructions/editor/results rendered; starter run completed at 0% without hanging | PASS |
| ROS workspace | Assignment 5 file tree showed only `controller.py` editable; other project files were locked | PASS |
| Long ROS run | Starter run completed at 29%, 2/7 checks, with observed-topic evidence | PASS |
| Responsive layout | Login and catalog rendered at 390 x 844 with readable single-column cards and no visible horizontal overflow | PASS |
| Keyboard/accessibility regression | Flutter tests covered Ctrl+Enter, semantic roles, responsive results, and navigation | PASS |
| Browser console | No application errors; only the known Flutter debug-mode DWDS warning appeared | PASS |

## Automated and infrastructure gates

| Gate | Result |
| --- | --- |
| Backend regression | PASS, 171 tests |
| Python dependency integrity | PASS, `pip check` found no broken requirements |
| Python compilation | PASS |
| Flutter analysis | PASS, no issues |
| Flutter widget/state tests | PASS, 48 tests |
| Flutter web release build | PASS |
| Managed backend and sandbox health | PASS |
| SQLite student-attempt restart persistence | PASS, 75 submissions before and after restart |
| Instructor analytics after restart | PASS, HTTP 200 |
| ROS 2 grader image build | PASS |
| Assignment 5 real ROS behavior | PASS, 7/7; 78 Twist messages at approximately 10.0 Hz |
| Assignment 6 real ROS behavior | PASS, 9/9; 44 settled Twist messages at approximately 9.2 Hz |
| Dedicated sandbox-service image | PASS, Python 3.14.7 |
| Sandbox service authentication | PASS, unauthorized 401 and authorized execution 200 |
| Backend Docker image | PASS, Python 3.14.7 and pinned runtime imports |
| Fresh PostgreSQL migration | PASS, PostgreSQL 17 through Alembic head `0003_standardize_existing_data` |
| Repository whitespace and generated-file safety | PASS |

## QA harness corrections

Two interim red results were investigated before continuing:

1. The first hostile-input script expected excessive output to use a
   `runtime_error` status. The application correctly bounded the output and
   returned a non-passing `completed` execution. The assertion was corrected
   and the full hostile matrix passed.
2. The first sandbox smoke script looked for `namespace.answer`. The documented
   sandbox contract returns `values.answer`. The assertion was corrected and
   the same image passed health, authentication, and execution checks.

Neither was an application defect, and neither required a source-code change.

## Non-blocking limitations and exclusions

| Item | Status | Reason or next action |
| --- | --- | --- |
| Paid OpenAI provider request | NOT RUN | AI is optional and off by default; no paid provider call was authorized or required for deterministic grading |
| Public live deployment | NOT RUN | This task authorizes staging `main` only; the production repository remains untouched |
| Second physical computer/network | NOT RUN | The current task ran on the canonical desktop checkout; use the README device-switch procedure for the laptop rehearsal |
| Android packaging | NOT RUN | Current project priority is the local web application |
| Master SQA workbook edit | BLOCKED | The required standalone spreadsheet artifact runtime was unavailable; this Markdown report is the current authoritative evidence |
| Flutter dependency upgrades | DEFERRED | Flutter reports 80 newer packages outside the validated constraints; upgrading them is separate risk-bearing work |
| Docker host warnings | ACCEPTED | Docker Desktop reported cgroup v1/blkio host warnings; all grader and sandbox behavior passed |

## Release conclusion

The candidate is suitable for staging `main`. Production promotion remains a
separate, explicit decision and must not be inferred from this report.
