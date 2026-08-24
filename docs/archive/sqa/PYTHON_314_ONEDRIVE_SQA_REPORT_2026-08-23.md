# Python 3.14 and OneDrive Local SQA Report

## Scope

- Repository: `CS-Ponkoj/Robotics-Programming-Lab-Staging`
- Checkout: `Robotics-Programming-Lab-Staging` in University of Nevada,
  Reno OneDrive
- Branch: `upgrade-python314-onedrive`
- Baseline commit: `22ab79a2c160af7c6ac26d6e83a0904b3f306c75`
- Test date: 2026-08-23
- Host: Windows 64-bit (`PONKOJ-PC`)
- Runtime: CPython 3.14.7
- AI: disabled
- Database: local SQLite

This report covers the staging-only Python 3.14 upgrade, the single shared
OneDrive `venv/`, simplified setup/run documentation, Python assignment
metadata, Docker images, and local application regression testing. It does not
promote or change the live repository.

## Results

| ID | Requirement or risk | Check and evidence | Result |
| --- | --- | --- | --- |
| PY314-001 | Official Python 3.14 is installed | `py -3.14 --version` returned `Python 3.14.7`. | PASS |
| PY314-002 | Shared environment uses Python 3.14 | `venv/Scripts/python.exe` returned Python 3.14.7, AMD64. | PASS |
| PY314-003 | New-device setup is repeatable | `scripts/setup-local.ps1 -Repair` recreated `venv/`; a second normal setup detected the valid signature without rebuilding. | PASS |
| PY314-004 | Device switch is detected | Environment signature includes requirements hash, computer name, base interpreter path/version, and architecture; the setup helper rebinds and reinstalls when these change. | PASS |
| PY314-005 | Python dependencies support 3.14 | Clean pinned install completed; native imports for Pydantic Core, CFFI, NumPy, SciPy, and psycopg succeeded. | PASS |
| PY314-006 | Dependency graph is consistent | `python -m pip check` returned `No broken requirements found.` | PASS |
| PY314-007 | Backend regression suite | `python -m pytest tests -q`: 171 passed with no warnings after adding the supported `httpx2` test-client dependency. | PASS |
| PY314-008 | Python source compiles | `python -m compileall -q .` completed without error. | PASS |
| PY314-009 | Assignment runtime metadata is current | Assignments 1–4 declare `python3.14`; their versions are 5, 4, 5, and 4. ROS assignments retain `ros2-jazzy-python`. | PASS |
| PY314-010 | Maintained Python answers grade correctly | Local authenticated submissions for Assignments 1–4 returned 100%, completed execution, and all test checks true. | PASS |
| PY314-011 | Incorrect and hostile submissions are bounded | Incorrect, syntax-error, runtime-error, infinite-loop, unsafe-import, excessive-output, and oversized cases returned safe controlled outcomes; oversized input returned HTTP 413. | PASS |
| PY314-012 | Local services start through one command | `run-local.ps1` migrated SQLite and started frontend 8180, API 5100, and sandbox 5101. All health checks passed. | PASS |
| PY314-013 | Flutter static analysis | OneDrive-safe `flutter analyze`: no issues found. | PASS |
| PY314-014 | Flutter regression tests | 48 tests passed. | PASS |
| PY314-015 | Flutter release web build | Release build completed from the LocalAppData verification copy. | PASS |
| PY314-016 | Browser desktop flow | Login page rendered; temporary student demo opened; catalog displayed all six assignments. No browser errors were recorded. | PASS |
| PY314-017 | Browser mobile-width flow | 390 x 844 viewport displayed responsive single-column cards with readable controls and no visible overflow. | PASS |
| PY314-018 | ROS 2 maintained answers | Assignment 5 passed 7/7 grader checks; Assignment 6 passed 9/9 grader checks. | PASS |
| PY314-019 | Python sandbox image | `python:3.14-slim` sandbox image built with NumPy 2.5.2 and SciPy 1.18.1. | PASS |
| PY314-020 | Dedicated sandbox service | Python 3.14.7 image built; health passed, missing token returned 401, authorized execution returned answer 4. | PASS |
| PY314-021 | Backend container compatibility | Backend image built; direct imports reported Python 3.14.7, FastAPI 0.141.1, NumPy 2.5.2, SciPy 1.18.1, and psycopg 3.2.13. | PASS |
| PY314-022 | Repository safety | `venv/`, secrets, databases, logs, and generated Flutter output remain ignored; `git diff --check` passed. | PASS |
| PY314-023 | README is usable on a new device | README begins with setup/start/stop, then documents Python 3.14, Flutter, optional Docker, OneDrive switching, repair, and environment limitations. | PASS |
| PY314-024 | Master Excel SQA workbook | The required standalone spreadsheet authoring runtime was unavailable in this session, so the workbook could not be edited using the mandated verified workflow. | BLOCKED |
| PY314-025 | Repair cannot corrupt a running environment | With the local stack running, `setup-local.ps1 -Repair` stopped before changing files and instructed the user to run `stop-local.ps1`; backend and sandbox remained healthy. | PASS |

## Defects found and corrected incrementally

| Defect | Cause | Correction | Focused verification |
| --- | --- | --- | --- |
| `psycopg-binary==3.2.9` would not install | No Python 3.14 wheel | Upgraded to 3.2.13 | Clean install and direct import passed |
| Python 3.14 dependency compatibility | NumPy/SciPy and FastAPI pins were from the Python 3.11 baseline | Upgraded to NumPy 2.5.2, SciPy 1.18.1, and FastAPI 0.141.1 | Full backend suite passed |
| FastAPI test-client deprecation warning | Starlette 1.6 expects the maintained HTTPX2 client | Added pinned `httpx2==2.10.0` | Focused test passed without warnings |
| Assignment seed tests failed after versioning | Expected versions still described the pre-upgrade assignments | Updated repository, API, auth, sandbox, and tutor-evaluation expectations | Focused suites and 171-test regression passed |
| Old shared `venv/` could not be upgraded | OneDrive placeholder/read-only attributes retained Python 3.11 content | Removed only the ignored generated environment and rebuilt it with Python 3.14 | Setup and complete verification passed |
| Helper returned installation output as a path | PowerShell pipeline output polluted the function return value | Sent status and pip output to the host; returned only the executable path | Setup script passed twice |
| Repair could start while Python modules were locked | The setup script did not inspect the managed-process state | Added a preflight that blocks setup/repair while the application is running | Guard rejected repair and both services remained healthy |

## Limitations

- A shared virtual environment is supported only for compatible Windows
  computers using Python 3.14 and comparable 64-bit architecture. It is not a
  portable cross-platform artifact.
- OneDrive must finish syncing before switching computers. The checkout must
  not run on two devices simultaneously.
- Docker Desktop emits host cgroup/blkio capability warnings. Both ROS graders
  and all tested containers completed successfully; the warnings are not test
  failures.
- The Flutter dependency resolver reports newer packages outside the validated
  lockfile constraints. This upgrade intentionally did not combine a Flutter
  dependency migration with the Python change.
- The master Excel workbook remains blocked as recorded in PY314-024. This
  Markdown report is the authoritative evidence for this upgrade until the
  workbook runtime is available.

## Release state

Local staging only. The changes are not committed, pushed, or promoted to the
live repository.
