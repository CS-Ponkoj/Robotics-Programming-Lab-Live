# Unified Local Handoff Package SQA Report

**Date:** 2026-08-25

**Repository:** `CS-Ponkoj/Robotics-Programming-Lab-Staging`

**Branch:** `main`

**Tested state:** local staging candidate based on `f3789b2720376e566a0183d9cf22dda4da58df6e`

## Outcome

The project now uses one ignored folder for portable private local state:

```text
local_handoff_package/
├── .env
├── latest.dump
├── latest.json
├── previous.dump
├── previous.json
└── package.json
```

The backend reads `.env` from this folder directly. The local PostgreSQL
launcher restores from it and every clean stop saves back to it. No second
`backend/.env`, nested `database/`, nested `private/`, clone-local database
folder, or shared OneDrive database folder is used.

The active database dump was checksum-verified before consolidation. Obsolete
copies were moved, not destroyed, to:

```text
C:\Users\cspon\AppData\Local\RoboticsProgrammingLab\legacy-data-layouts\2026-08-25-unified-package
```

## Verification results

| Requirement | Test | Result | Evidence or limitation |
| --- | --- | --- | --- |
| One active private-data folder | Resolved database and config paths | PASS | Both equal repository `local_handoff_package` |
| No duplicate active paths | Filesystem inspection after migration | PASS | Old four locations absent; recovery copies are outside OneDrive in quarantine |
| Database integrity | SHA-256 compared with `latest.json` | PASS | Hash matched before and after runtime stop |
| Private config integrity | Root `.env` compared with former backend file before quarantine | PASS | SHA-256 matched; contents were not printed |
| Direct config loading | Focused backend test | PASS | `ROBOTICS_ENV_FILE` selected the requested file |
| Incomplete backup protection | Removed one member of a temporary pair | PASS | Resolver rejected the incomplete pair |
| Fresh-clone handoff | Clone, apply candidate, copy package, setup, detect | PASS | Clone used package directly and did not create `backend/.env` |
| First-time setup | Normal `setup-local.ps1` | PASS | Python 3.14.7, Docker Compose, and Flutter detected |
| Backend regression | Full test suite | PASS | 175 tests passed |
| Dependency integrity | `pip check` | PASS | No broken requirements |
| Database migration and recovery | Isolated Docker handoff test | PASS | All 183 rows preserved across every application table |
| Flutter analysis | Analyzer | PASS | No issues found |
| Flutter regression | Widget and state tests | PASS | 49 tests passed |
| Flutter release build | OneDrive-safe release build | PASS | Web build completed |
| Local runtime startup | Supported launcher | PASS | Frontend, FastAPI, sandbox, and PostgreSQL became ready |
| Runtime service health | HTTP checks | PASS | Frontend 200; backend and sandbox status `ok` |
| Rendered login and student UI | In-app browser at local frontend | PASS | Login card rendered; student login showed six assignment cards and saved progress |
| Rendered instructor UI | In-app browser at local frontend | PASS | Assignment studio showed six published assignments; research dashboard rendered |
| Browser console | Warning/error inspection | PASS | No application error; one known Dart debug-runtime warning only |
| Student and instructor access | Real local API login and role endpoints | PASS | Both demo roles authenticated; wrong password returned 401; student admin access returned 403 |
| Six assignment discovery | Authenticated assignments API | PASS | IDs 1 through 6 returned |
| Clean shutdown | Supported stop script | PASS | Dump refreshed, checksum valid, device lock absent |
| ROS 2 Assignment 5 | Real Jazzy grader image | PASS | 7/7 checks; observed command topic behavior |
| ROS 2 Assignment 6 | Real Jazzy grader image | PASS | 9/9 checks; observed obstacle-stop behavior |
| Docker Compose configuration | `docker compose config --quiet` | PASS | Configuration parsed successfully |
| Physical second computer | Run on an actual laptop or lab computer | NOT RUN | Automated fresh-clone rehearsal passed; physical-device acceptance remains |
| Excel SQA workbook refresh | Required spreadsheet artifact runtime | BLOCKED | Runtime was unavailable in this session; Markdown report is current |

## Defects found and fixed during this pass

| Defect | Root cause | Fix | Retest |
| --- | --- | --- | --- |
| Database lock regression test failed | Updated error wording no longer contained the stable phrase recognized by the test | Restored the stable phrase and kept package-specific recovery guidance | Isolated database handoff test passed |
| Launcher failed after services started | A forced PowerShell module import removed an exported helper before a late status lookup | Resolve the package path once before importing the database module | Full launcher start, health checks, and clean stop passed |

## Security and operating limits

- The package is ignored by Git but unencrypted. It can contain API keys,
  password hashes, student work, analytics, and research records.
- Never commit, email, publicly share, or leave a populated package on an
  untrusted lab computer.
- PostgreSQL's live Docker volume remains computer-local. Copy only the complete
  stopped package between devices.
- Sequential handoff is supported. Simultaneous use of the same synchronized
  package is not supported.
- This local package is not a replacement for encrypted institutional backup or
  approved research-data governance.

## Publication state

The implementation is verified in the canonical local staging checkout but is
not committed or pushed by this report. A Git publication requires separate
explicit authorization.
