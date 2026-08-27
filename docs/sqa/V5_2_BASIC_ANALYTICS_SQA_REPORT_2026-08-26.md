# V5.2 Basic Research Analytics SQA Report

**Date:** 2026-08-26

**Repository:** `CS-Ponkoj/Robotics-Programming-Lab-Staging`

**Branch:** `main`

**Base commit:** `0865c8c961baed58e0d14a876ff3ca80ae97f5ba`
**Environment:** `PONKOJ-PC`, Windows x64, Python 3.14, PostgreSQL 17,
Docker Desktop Linux containers, Flutter web, AI disabled

## Decision

**PASS for the V5.2 Basic Analytics implementation in local staging.** The
application now calculates and displays the 55 implemented Phase 1 metric
definitions while preserving deterministic test-case grading. Students see
only their own versioned progress and safe attempt history. Instructors see
participant-code, assignment, classroom, and data-health summaries.

Promotion is not approved by this report. No commit, push, or production change
was performed. The repository-level release check remains **BLOCKED** by
untracked database backup files outside this implementation, and the Excel
checklist remains **BLOCKED** by the unavailable approved spreadsheet runtime.

## Implementation verification

| Feature or issue | Change made | Test performed | Result | Remaining limitation |
| --- | --- | --- | --- | --- |
| Three-phase metric plan | Assigned all 161 candidate metrics to Basic, Moderate, or Advanced and exposed only the 55 implemented Basic definitions | Metric-catalog count assertion, API test, PDF reconciliation | PASS | Moderate and Advanced remain roadmap only |
| Versioned activity | Added one activity record per student, assignment ID, and exact version | Fresh migration and populated-schema migration tests | PASS | Pre-V5.2 time remains unavailable by design |
| Active-time capture | Heartbeat counts only visible, recently interactive use within 15 minutes | Controlled-clock active, idle, and multi-session tests | PASS | Browser timing is observational, not biometric attention measurement |
| Completion definitions | First valid passing Run or Submit freezes active and elapsed completion time | Formula and first-success tests | PASS | Historical completion time is null when no activity record exists |
| Student analytics | Added overview, assignment/version summaries, safe attempt history, and metric definitions | Widget tests plus rendered desktop QA | PASS | Student class comparisons intentionally excluded |
| Instructor analytics | Added classroom, participant, assignment, hidden aggregate, and data-health catalogs | API authorization tests plus rendered desktop/mobile QA | PASS | Current restored dataset has nine historical instructor-owned submissions flagged as orphan research records |
| Attempt pagination | Added student-self and instructor-authorized paginated endpoints | Pagination, cross-student denial, and unauthorized-access tests | PASS | Compatibility payload still retains its existing non-paginated attempt field |
| Privacy | Excluded login IDs, credentials, source snapshots, hidden-test identities/content, and official solutions | API response scans and role-boundary tests | PASS | Instructors receive only hidden-test aggregate percentages |
| Demo boundary | Protected password accounts from the obsolete demo flag; kept `/auth/demo` ephemeral | New account-file regression test, restart, database inspection, and rendered instructor QA | PASS | Old demo-tagged records remain historical data but no longer contaminate current aggregates |
| Exports | Added participant-assignment and class-assignment datasets to CSV/Excel exports | Dataset reconciliation and formula tests | PASS | Manual workbook download was not repeated in the browser because it creates a local download artifact |
| Data health | Added missing-version, duplicate, orphan, timestamp, demo, and export checks | API tests and rendered dashboard inspection | PASS | Nine historical instructor submissions are correctly reported for later governed cleanup |
| AI boundary | Counted optional AI interactions without using them in scores | Backend analytics tests and existing tutor tests | PASS | Paid-provider response quality is outside Phase 1 and was not invoked |

## Assignment and execution QA

| Scenario | Evidence | Result |
| --- | --- | --- |
| Assignments 1-4 maintained answers | Classroom readiness suite executed every maintained Python answer | PASS |
| Assignments 5-6 maintained answers | Real pinned ROS 2 Docker grader returned Assignment 5 `7/7` and Assignment 6 `9/9` | PASS |
| Incorrect Python submission | Structured non-passing grader evidence | PASS |
| Syntax error | Safe `syntax_error` classification | PASS |
| Runtime error | Safe `runtime_error` classification | PASS |
| Infinite loop | Bounded execution returned `timeout` | PASS |
| Unsafe import | Safety policy rejected the submission without executing it | PASS |
| Excessive output | Output was capped and marked truncated | PASS |
| Oversized submission | HTTP 413 plus a safe size-limit analytics record | PASS |
| Incorrect ROS behavior | ROS assignment tests rejected nonconforming observable behavior | PASS |

The focused classroom, execution-safety, and ROS regression group passed all 31
tests. Python-only syntax/import/output cases are not applied to locked ROS
package files as if they were equivalent; ROS behavior is checked by its
containerized build, node, topic, timing, and stop-condition harness.

## Full automated gate

| Gate | Result |
| --- | --- |
| Backend regression after final fix | PASS, 179 tests |
| Python dependencies | PASS, no broken requirements |
| Python compilation | PASS |
| Fresh PostgreSQL migration | PASS through `0004_basic_research_analytics` |
| Populated database migration | PASS; existing attempts unchanged |
| PostgreSQL backup/checksum/restart restore | PASS; all application table counts reconciled |
| Real ROS 2 Docker answers | PASS, Assignments 5 and 6 |
| Flutter analysis | PASS, no issues |
| Flutter tests | PASS, 50 tests |
| Flutter release web build | PASS |
| Git whitespace check | PASS |
| Repository source-safety check | PASS after the owner-approved backup-folder consolidation; legacy dumps are preserved inside ignored `local_handoff_package/history` |

## Rendered manual QA

| Flow | Actual result | Result |
| --- | --- | --- |
| Login and six-assignment catalog | Student and instructor password accounts opened the current six-assignment application | PASS |
| Student overview | Completion, attempts, best score, and active time rendered | PASS |
| Student assignment analytics | All six current assignment versions plus historical versions rendered separately | PASS |
| Student attempt history | Safe statuses and visible attempt numbers rendered newest first | PASS |
| Student metric catalog | Exactly 55 implemented definitions and catalog version 1.1 rendered | PASS |
| Instructor overview | Persistent student appeared by participant code with aggregate totals | PASS |
| Instructor assignment catalog | All six current versions rendered with completion summaries | PASS |
| Data health | Zero missing versions, duplicates, timestamp errors, and demo contamination; export reconciliation PASS | PASS |
| Credential-free demo | Opened Assignment 1 and ran its tests; authentication sessions, study sessions, learning events, and submissions remained exactly `76/16/38/63` before and after | PASS |
| Desktop layout | Student and instructor pages rendered without visible overflow | PASS |
| Mobile layout | Instructor home and analytics rendered at 390 x 844 without visible overflow | PASS |
| Browser console | No application errors during final student/instructor QA | PASS |

## Defect found and fixed during QA

| Defect | Root cause | Fix | Verification | Result |
| --- | --- | --- | --- | --- |
| Password-authenticated default accounts were excluded as demo users after startup | The tracked account example and local account file reapplied `demo=true` after startup seed logic removed the obsolete flag | Force the two password-account IDs to `demo=false` during JSON synchronization and correct the safe account templates | New regression test, 22 focused auth/research tests, full 179-test backend suite, PostgreSQL restart, and rendered instructor dashboard | PASS |

## Known limitations and blockers

| Item | Status | Reason and next action |
| --- | --- | --- |
| Existing orphan research records | PARTIAL | Nine old submissions belong to the instructor account. They are excluded from student/class calculations and surfaced by Data Health. Decide on a governed archive or cleanup separately; this implementation did not delete research history. |
| Master Excel SQA checklist | BLOCKED | The approved spreadsheet artifact package is unavailable in the bundled runtime. The workbook was not edited with an unsupported library. Copy this report's V5.2 rows into the workbook when the required runtime is restored. |
| Legacy local database backup folder | RESOLVED | Four older files were preserved under ignored `local_handoff_package/history/legacy-2026-08-25`; the unused duplicate folder was removed and is now ignored if recreated. |
| Physical second-device browser QA | NOT RUN | Clean-device PostgreSQL restore was automated, but this session did not operate a second physical computer/network. |
| Production/live deployment | NOT RUN | Work is staging-only and no promotion authorization was provided. |
| OpenAI provider quality | NOT RUN | AI remained disabled and Phase 1 analytics do not depend on paid AI responses. |

## Files intentionally left untouched

- `error_laptop.txt`
- Existing PostgreSQL research rows, including the nine records flagged by Data Health

## Conclusion

V5.2 Basic Analytics is implemented and locally workable. Its code, migration,
formulas, permissions, exports, PostgreSQL recovery, six-assignment grading,
desktop UI, and mobile UI passed the available acceptance checks. Before a
commit or release decision, update the Excel master checklist with the approved
spreadsheet runtime.
