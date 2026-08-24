# Local PostgreSQL OneDrive Handoff SQA Report

**Date:** 2026-08-24
**Repository:** `CS-Ponkoj/Robotics-Programming-Lab-Staging`
**Branch:** `feature/local-postgres-onedrive-handoff`
**Base commit:** `c36a9da1b6391393d9fc60294af54ce75cd9814d`
**Environment:** `PONKOJ-PC`, Windows x64, Python 3.14.7, PostgreSQL 17,
Docker Desktop Linux containers, Flutter web, AI disabled

## Decision

**PASS for local staging use on the primary desktop.** The default launcher now
uses PostgreSQL in a computer-local Docker volume and creates a verified logical
backup in the OneDrive project on clean shutdown. Existing SQLite files were
preserved. The latest repeatable migration copied the canonical SQLite
database's 183 current application rows into an empty PostgreSQL database. The
data survived backup, volume destruction, clean-device restore, application
restart, and integrated assignment submissions.

This is a sequential desktop/laptop handoff workflow. It does not support
simultaneous use. A physical laptop and real OneDrive transfer remain to be
rehearsed before treating cross-device operation as fully verified.

## Database behavior

| Requirement | Evidence | Result |
| --- | --- | --- |
| PostgreSQL default | `run-local.ps1` started PostgreSQL 17 and `/health` reported `database=postgresql` | PASS |
| Active files stay out of OneDrive | PostgreSQL used Docker volume `robotics-lab-local_robotics_postgres_data` | PASS |
| First-run migration | Alembic upgraded a fresh PostgreSQL database through `0003_standardize_existing_data` | PASS |
| Existing data preserved | Read-only transfer copied all 183 current application rows from `robotics_lab_staging.db` | PASS |
| No unsafe merge | Transfer code rejects a non-empty target; idempotent first-start mode skips it | PASS |
| Complete backup | `pg_dump --format=custom` produced `latest.dump`; `pg_restore --list` validated it | PASS |
| Copy integrity | SHA-256 of the copied dump matched `latest.json` | PASS |
| Damaged-copy rejection | A deliberately modified test dump was rejected before restore | PASS |
| Recovery point | The preceding successful dump and manifest are retained as `previous.*` | PASS |
| Device exclusion | A simulated second computer was rejected while the first device lock existed | PASS |
| Clean-device restore | An isolated Docker volume was destroyed and recreated; the synchronized dump restored | PASS |
| Same-device volume-loss restore | The isolated volume was destroyed while retaining the original device sync marker; missing schema forced a verified restore | PASS |
| Row-count reconciliation | All nine application-table counts matched after restore | PASS |
| Restart persistence | The real local stack restarted with PostgreSQL and retained all 62 submissions | PASS |
| SQLite fallback | Explicit `-UseSqlite` behavior is retained for disposable troubleshooting | PASS |
| Secrets and generated data | Dumps, manifests, locks, local databases, and `.env` remain ignored by Git | PASS |

## Latest verified legacy-source row counts

| Table | Rows |
| --- | ---: |
| `assignments` | 6 |
| `users` | 2 |
| `submissions` | 40 |
| `hint_interactions` | 5 |
| `study_sessions` | 4 |
| `learning_events` | 31 |
| `auth_sessions` | 44 |
| `password_reset_tokens` | 0 |
| `audit_events` | 51 |
| **Total** | **183** |

## Application QA against PostgreSQL

| Flow | Actual result | Result |
| --- | --- | --- |
| Health | Backend and sandbox returned healthy; backend named PostgreSQL | PASS |
| Demo catalog | Temporary demo opened and displayed all six assignments | PASS |
| Demo grading | Assignment 1 starter ran to a controlled 0%, 0/4 result | PASS |
| Demo reset | Browser refresh returned to login and cleared demo work | PASS |
| Student authentication | Login and `/auth/me` returned the student role | PASS |
| Instructor authentication | Login and `/auth/me` returned the instructor role | PASS |
| Role authorization | Student request to instructor research summary returned HTTP 403 | PASS |
| Student progress | Student research/progress endpoint returned HTTP 200 | PASS |
| Instructor analytics | Instructor research summary returned HTTP 200 | PASS |
| Assignment inventory | Authenticated API returned six assignments | PASS |
| Maintained answers, Assignments 1-4 | Every maintained Python answer returned 100%; every starter/incorrect answer returned 0% | PASS |
| Maintained answers, Assignments 5-6 | Real Docker ROS graders returned 7/7 and 9/9; integrated maintained answers returned 100% | PASS |
| Incorrect ROS answers | Assignment 5 starter returned 20%; Assignment 6 starter returned 10%; neither was accepted as complete | PASS |
| Syntax and runtime errors | Syntax failure and controlled runtime failure returned structured non-passing results | PASS |
| Infinite loop | Execution stopped after the five-second limit with `timeout` status | PASS |
| Unsafe import | `import os` was rejected without executing student code | PASS |
| Excessive output | Public run completed but output was capped at 20,019 characters and marked `[output truncated]` | PASS |
| Oversized request | A 100,001-character submission was rejected with HTTP 413 | PASS |
| Student response safety | Student assignment JSON excluded `grader_config` and `reference_solution_path` | PASS |
| Built-in tutor fallback | Two progressive hints and a student question returned structured fallback guidance without the official result | PASS |
| Demo persistence boundary | Demo submission and authentication left PostgreSQL submission and auth-session counts unchanged | PASS |
| Versioned browser drafts | Same-profile mobile QA initially reproduced an older Assignment 1 draft; after the fix, v5 opened the corrected m-line starter code | PASS |
| Mobile-width UI | Login, catalog, assignment workspace tabs, and instructor research dashboard rendered at 390 x 844 without visible overflow | PASS |
| Submission persistence | PostgreSQL retained all 62 submissions after a clean backup and restart | PASS |
| AI default | Launcher reported AI disabled | PASS |

## Automated regression gate

| Gate | Result |
| --- | --- |
| Focused database-transfer tests | PASS, 3 tests |
| Backend regression | PASS, 174 tests |
| Python dependency integrity | PASS, no broken requirements |
| Python compilation | PASS |
| PowerShell parser checks | PASS, five database/run/verification scripts |
| Docker Compose configuration | PASS |
| Isolated handoff integration | PASS, migrate/backup/checksum/lock/reset/same-device restore/clean-device restore/reconcile |
| Flutter analysis | PASS, no issues |
| Flutter tests | PASS, 49 tests |
| Flutter web release build | PASS |
| Git whitespace check | PASS |
| Managed API and sandbox health | PASS |

## Defect found and corrected during manual QA

| Defect | Root cause | Fix | Verification | Result |
| --- | --- | --- | --- | --- |
| Older Assignment 1 code appeared in the v5 workspace | Browser drafts were stored only by assignment ID, so a v4 draft could be loaded after the assignment advanced to v5 | Persist the draft's assignment version and load it only for an exact ID/version match; preserve but ignore legacy unversioned drafts | Focused six-test state suite, full 49-test Flutter suite, analyzer, release build, and same-profile browser restart showed the corrected v5 starter code | PASS |

## Limitations and required follow-up

| Item | Status | Reason and next action |
| --- | --- | --- |
| Physical laptop handoff | NOT RUN | Stop on desktop, wait for OneDrive, start on laptop, verify accounts/submissions, then return through the same procedure |
| Simultaneous device use | UNSUPPORTED | This design intentionally permits one active device; use managed PostgreSQL for concurrent access |
| Backup encryption | BLOCKED FOR REAL STUDY | Prototype dump is not encrypted; approve encrypted storage or managed PostgreSQL before collecting real participant data |
| OneDrive availability/merge guarantee | PARTIAL | Checksums detect incomplete/tampered copies, but OneDrive itself cannot provide a database transaction protocol; always wait for **Up to date** |
| Master Excel SQA workbook | BLOCKED | The required standalone spreadsheet artifact runtime was unavailable in this session; it cannot be safely edited with the mandated workbook tooling. This Markdown report is the current evidence and the workbook still needs the same PostgreSQL and versioned-draft rows added |
| Production/live repository | NOT RUN | This change is staging-only; no production authorization was given |

## Conclusion

The local PostgreSQL and OneDrive backup-handoff implementation is working on
the canonical desktop and is protected against the tested corruption, stale
target, checksum, same-device volume-loss, and simultaneous-device cases. The
next acceptance step is a real laptop handoff after OneDrive completes
synchronization.
