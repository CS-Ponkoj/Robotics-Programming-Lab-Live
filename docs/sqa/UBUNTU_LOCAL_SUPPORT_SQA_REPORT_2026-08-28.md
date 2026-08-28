# Ubuntu Local Support SQA Report

**Date:** 2026-08-28

**Repository:** `CS-Ponkoj/Robotics-Programming-Lab-Staging`

**Source branch:** `main`

**Protected baseline:** remote branch `backup-v5` at `7976caa8eb764c3452ab9f3021ddc875a5631e36`

**Scope:** Ubuntu local-run support and regression coverage; no application API, grader, schema, assignment, analytics, or production changes

## Result

The Ubuntu implementation passes the automated Ubuntu 22.04/24.04 container checks and the existing Windows verification gate. The same PostgreSQL custom-format handoff package was restored successfully from a Windows-created dump on Ubuntu. A physical Ubuntu lab-computer smoke test is still required before hardware-level compatibility can be claimed.

## Verification matrix

| Area | Evidence | Result | Remaining limitation |
|---|---|---:|---|
| Source backup | Remote `backup-v5` resolves exactly to `7976caa8eb764c3452ab9f3021ddc875a5631e36` | PASS | None |
| Bash syntax | Every maintained `.sh` file parsed with Bash on Ubuntu | PASS | None |
| ShellCheck | ShellCheck completed with no findings | PASS | None |
| Ubuntu 22.04 setup | `uv` installed managed Python 3.14.7; all 53 pinned backend packages installed and passed compatibility checks | PASS | Docker and Flutter prerequisite discovery used controlled command stubs in this setup-only container |
| Ubuntu 24.04 setup | Real Docker client and Flutter 3.32.8; managed Python 3.14.7 and all pinned packages installed | PASS | None |
| Local stack startup | PostgreSQL, sandbox, FastAPI, Flutter web, and backup worker became healthy on isolated test ports | PASS | None |
| Frontend | `/app` returned HTTP 200 from the Ubuntu runtime; Flutter widget and release-build checks passed | PASS | No physical Ubuntu browser was used |
| Authentication and authorization | Persistent student and instructor logins passed; unauthenticated assignment access returned 401; instructor assignment access passed | PASS | None |
| Assignments 1-6 | Maintained answers passed at 100%; incorrect submissions failed for all six assignments | PASS | None |
| Error and safety handling | Syntax error, unsafe import, infinite loop, and oversized submission paths behaved as expected | PASS | None |
| ROS assignment 5 | Seven grader checks passed; expected Twist stream observed | PASS | Container-based ROS execution only |
| ROS assignment 6 | Nine grader checks passed; settled Twist stream observed | PASS | Container-based ROS execution only |
| Backup worker | Changed database saved; unchanged database skipped; checksum and device lock verified | PASS | None |
| Final shutdown backup | Stop produced and validated a final dump before stopping PostgreSQL | PASS | None |
| Windows-to-Ubuntu restore | A real Windows-created `latest.dump` restored on Ubuntu with 2 users, 63 submissions, and 0 activity rows reconciled | PASS | Counts describe the current local research package; no private row content was printed |
| Ubuntu stop/restart | Data survived volume removal and clean-device restore; 16 isolated SQA submissions reconciled before and after | PASS | None |
| Process ownership | Ubuntu stop left an unrelated control process running | PASS | None |
| Backend regression | 179 tests passed; dependency compatibility passed | PASS | None |
| Flutter regression | Analyzer passed, 50 tests passed, and release web build passed | PASS | None |
| Repository safety | Required-clone and release checks passed; secrets, dumps, environments, logs, caches, and build outputs remain untracked | PASS | GitHub Actions will run only after a later authorized push |
| Physical Ubuntu 22.04/24.04 lab computer | Not executed on institution hardware | NOT RUN | Required before claiming lab hardware compatibility; lab IT may need to install prerequisites and grant Docker access |

## Supported workflow

- Windows uses the existing PowerShell scripts.
- Ubuntu x86-64 22.04/24.04 uses the new Bash scripts.
- Generated Python environments, Flutter build files, logs, and process state stay outside the Git clone on Ubuntu.
- Both operating systems use the same private `local_handoff_package` structure and PostgreSQL custom-format dump.
- Only one device may hold the database handoff lock or run the shared package at a time.
- AI remains available but disabled by default.

## Publication status

Implementation and local QA are complete. The implementation is intentionally not committed or pushed. A separate authorization is required to publish it. After publication, GitHub Actions and a physical lab-computer smoke test remain the final external checks.
