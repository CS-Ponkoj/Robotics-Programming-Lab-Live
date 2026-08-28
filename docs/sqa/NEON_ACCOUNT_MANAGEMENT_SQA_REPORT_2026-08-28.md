# Neon and Account Management SQA Report

**Date:** 2026-08-28
**Repository:** `Robotics-Programming-Lab-Staging`
**Branch:** `main`
**Implementation commit:** `573375a` (`v5.3`) on staging `origin/main`
**Final QA follow-up:** local until separately authorized for publication

## Result

The requested staging changes passed the available Windows local QA. The
application now uses the dedicated Neon database `robotics_lab_staging`, supports
student and instructor account management in Instructor Studio, and isolates
browser progress by authenticated user. The earlier local PostgreSQL study
records were migrated to Neon and reconciled by table counts. The subsequent
Neon-only architecture removed the local PostgreSQL fallback.

This report does not claim production deployment or physical Ubuntu validation.

## Verified data state

| Check | Result | Evidence |
|---|---|---|
| Dedicated Neon database | PASS | The launcher selected `robotics_lab_staging`; the older Neon `neondb` database was not overwritten. |
| Local-to-Neon migration | PASS | 376 application rows migrated across users, assignments, submissions, activities, events, sessions, hints, audits, and auth records. |
| Core analytics reconciliation | PASS | Neon contains 3 users, 6 assignments, 65 submissions, 2 assignment-activity rows, 44 learning events, and 22 study sessions before and after restart. |
| Dave account retained | PASS | Dave remains active with 0 submissions and 0 completed assignments. |
| Default student account restored | PASS | The active default student password hash verifies against the required prototype password. No password is recorded in this report. |
| Versioned account roster | PASS | `backend/data/study_accounts.json` contains password-free account metadata and is eligible for Git tracking. Password hashes remain in Neon. |

## Functional and regression QA

| Area | Change or test | Result | Remaining limitation |
|---|---|---:|---|
| Account isolation | Added user-ID-scoped browser storage and tested two persistent students plus the temporary demo session | PASS | Existing legacy browser progress migrates only to the default prototype student once. |
| Dave fresh progress | Verified zero database attempts/completions and isolated browser state | PASS | A browser that still shows an old page must sign out or refresh after receiving the new frontend build. |
| Instructor Studio | Create, list, edit, reset, activate, and deactivate student/instructor accounts | PASS | Passwords are intentionally shown only once when manually generated. |
| Instructor safety | Prevent self-deactivation and disabling the last active instructor | PASS | Deletion is intentionally replaced by deactivation to preserve research history. |
| File-based management | Import role, active, email, and participant-code changes from the tracked password-free roster | PASS | New accounts and password changes must use Instructor Studio. |
| Neon restart persistence | Stopped and restarted the full local stack; row counts and Dave state remained unchanged | PASS | Availability still depends on internet access and the Neon service. |
| Neon-only transition | The former local PostgreSQL fallback was verified before retirement; current launchers now require the authorized Neon staging database | SUPERSEDED | See the Neon-only architecture SQA report for the current runtime gate. |
| Backend suite | 183 tests | PASS | None observed. |
| Python dependencies | `pip check` | PASS | None observed. |
| Python compilation | `compileall` | PASS | None observed. |
| Flutter analysis | Static analyzer | PASS | None observed. |
| Flutter tests | 51 tests | PASS | None observed. |
| Flutter web release | Release web build with staging API URL | PASS | This was a local build, not a public deployment. |
| Service health | Frontend HTTP 200; backend and sandbox report healthy | PASS | Authenticated browser mutation was covered by API/widget tests rather than changing the shared staging data manually. |
| PowerShell launcher syntax | Parser check | PASS | None observed. |
| Legacy database recovery | Migrated the pre-V5.2 SQLite schema without `assignment_activities` into the current PostgreSQL schema and reconciled every table count | PASS | The missing historical table is correctly treated as empty; current targets must still contain it. |
| Ubuntu Bash validation | `bash -n` and ShellCheck on this Windows host | NOT RUN | WSL/Bash and ShellCheck are unavailable on this computer; existing Ubuntu support tests were not repeated. |

## Security and privacy checks

- Neon credentials remain only in ignored private configuration.
- The private account JSON and migration report remain ignored.
- No plaintext password, API key, database URL, dump, environment, or generated
  build artifact is included in the tracked changes.
- Existing submissions and analytics are not deleted when an account is
  deactivated.
- The application still treats test-case grading as authoritative; AI remains
  optional and disabled by default.

## Final status

**PASS for the requested Windows local staging scope.** Publication, production
deployment, and physical Ubuntu-machine validation require separate approval or
execution.
