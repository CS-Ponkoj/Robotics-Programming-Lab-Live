# Neon-Only Database Architecture SQA Report

**Date:** 2026-08-28
**Repository:** `Robotics-Programming-Lab-Staging`
**Branch:** `main`
**Publication status:** Local working tree; not committed or pushed

## Result

The staging application now has one runtime database architecture: the shared
Neon PostgreSQL staging database. Local PostgreSQL, runtime SQLite, database
dump restore, periodic/final backup workers, package manifests, and device locks
were removed from the supported launch path.

The private configuration is now one ignored `.env` in the repository root.
The password-free account roster is tracked at `backend/data/study_accounts.json`;
passwords and hashes remain outside Git.
Docker remains required for the Python and ROS 2 grading containers; it no
longer hosts the application database.

## QA results

| Area | Check | Result | Remaining limitation |
|---|---|---:|---|
| Windows launcher | Started with the configured Neon staging URL, applied Alembic migrations, and recorded `databaseProvider=neon` | PASS | Internet and Neon availability are required |
| Managed shutdown | Stopped only launcher-owned frontend, backend, and sandbox processes | PASS | None observed |
| Private configuration | Validator confirmed the ignored repository-root `.env`, tracked password-free roster, and absence of obsolete dumps/manifests/history | PASS | The `.env` must be provisioned through a secure channel on each authorized computer |
| Account roster safety | Tracked roster contains no temporary passwords; backend rejects passwords placed in the canonical roster | PASS | Create and reset passwords through Instructor Studio |
| Local fallback removal | PostgreSQL Compose service, transfer module, dump scripts, backup worker, device lock, and runtime fallback switches removed | PASS | No offline database mode remains |
| Account import | Focused authentication/account tests | PASS | 16 tests passed |
| Backend regression | Full backend test suite | PASS | 179 tests passed after adding tracked-roster password protection |
| Dependencies | `pip check` | PASS | No broken requirements |
| Python compilation | `compileall` | PASS | No compilation errors |
| Flutter analysis | Static analyzer | PASS | No issues found |
| Flutter tests | Widget/state/API-client tests | PASS | 51 tests passed |
| Flutter release build | Release web build using the local API URL | PASS | Local build only; no deployment performed |
| Compose configuration | Docker Compose configuration validation | PASS | Compose now defines only build-profile grader images |
| ROS 2 grading | Maintained answers for Assignments 5 and 6 | PASS | Assignment 5: 7/7; Assignment 6: 9/9 |
| Service health | Frontend HTTP 200; backend and sandbox healthy | PASS | Verified on Windows local ports 8180/5100/5101 |
| Persistent student login | Default student authenticated against Neon, `/auth/me` returned the student role, and logout succeeded | PASS | Password value was not recorded in QA output |
| Ubuntu launcher | Source updated to the same Neon-only lifecycle | NOT RUN | This Windows host has no Bash/WSL or ShellCheck; repeat on a physical Ubuntu lab computer |
| Secret safety | `.env` remains ignored; the tracked roster contains metadata only | PASS | Never commit passwords, hashes, or private connection settings |

## Removed private artifacts

The following obsolete local fallback files were permanently removed from the
ignored package: `history/`, `latest.dump`, `latest.json`, `previous.dump`,
`previous.json`, `package.json`, `neon-migration-report.json`, and
`study_accounts_import_report.json`. The migrated study data remains in Neon.

## Decision

**PASS for the tested Windows local scope.** The Neon-only application is ready
for continued local staging work. Physical Ubuntu execution remains an explicit
hardware/environment validation item and is not claimed as tested here.
