# Assignment Content Local SQA Report

**Date:** 2026-08-21

**Repository:** `CS-Ponkoj/Robotics-Programming-Lab-Staging`

**Local checkout:** `Robotics-Programming-Lab-Staging`

**Branch:** `assignment-content-quality`

**Scope:** Local Windows staging only. Live deployment and Android were
intentionally excluded.

## Outcome

The corrected local application passes its automated release-style gate and
manual browser smoke test. Assignments 1-4 now use explicit, internally
consistent mathematical models and instructor-authored learning metadata. The
maintained answers pass the dedicated sandbox at 100 percent, and the existing
ROS 2 Assignments 5-6 continue to pass their real Docker grader checks.

The only incomplete priority is the existing Excel master checklist. The
required spreadsheet runtime loader was unavailable in this desktop session,
so the workbook was preserved rather than edited with an unsupported library.
This Markdown report is the current evidence source until the workbook can be
updated safely.

## Priority results

| Priority | Finding | Result | Resolution and evidence |
|---|---|---:|---|
| P0 | Assignment 4 was under-specified | PASS | Version 3 now defines every LIDAR reading, inverse-square density, the inclusive 80-100 degree search, and tie behavior. Focused classroom tests pass. |
| P0 | Assignment 2 had conflicting geometry | PASS | Version 3 now defines O, G, H, L, all rectangle corners, and the right-turn H-A-B-L route. Maintained answer passes 4/4 with a 12-unit total. |
| P1 | Assignment 3 was mathematically incomplete | PASS | Version 4 now defines both floor-5 routes, both floor-10 routes, wait/ride times, and the complete comparison. Maintained answer passes 8/8. |
| P1 | Assignment 1 used an invalid Bug2 leave point | PASS | Version 4 now uses H(4,11/3) and L(23/4,6), both on the S-to-G m-line, with L closer to G. Maintained answer passes 4/4. |
| P1 | Assignments 1-4 used generated generic learning metadata | PASS | Each assignment now has tailored objectives, a 100-point rubric, misconception tags, execution settings, and non-solution tutor rules. Metadata regression tests pass. |
| P2 | Excel SQA workbook was behind Markdown | BLOCKED | The required spreadsheet dependency loader was unavailable. The `.xlsx` was left unchanged to prevent corruption; this report records current results. |
| P2 | Obsolete Monaco editor files and dependency remained | PASS | Removed the unused iframe widget, JS bridge, CDN page, loader script, stale web code copies, and `code_editor` dependency. Flutter analyzer and 48 tests pass. |
| P3 | README contained a command typo | PASS | The AI-enabled local command is now `.\scripts\run-local.ps1 -EnableAi`. |

## Maintained-answer integration results

| Assignment | Published version | Result | Sandbox evidence |
|---:|---:|---:|---:|
| 1 | 4 | PASS | 100%, 4/4 checks |
| 2 | 3 | PASS | 100%, 4/4 checks |
| 3 | 4 | PASS | 100%, 8/8 checks |
| 4 | 3 | PASS | 100%, 2/2 checks |
| 5 | 1 | PASS | ROS 2 Jazzy Docker grader, 7/7 checks |
| 6 | 1 | PASS | ROS 2 Jazzy Docker grader, 9/9 checks |

## Complete verification

| Gate | Result | Evidence |
|---|---:|---|
| Backend regression suite | PASS | 171 pytest tests passed |
| Python dependency integrity | PASS | `pip check` found no broken requirements |
| Python compilation | PASS | Backend `compileall` completed |
| Flutter analysis | PASS | No issues found |
| Flutter tests | PASS | 48 tests passed |
| Flutter web release build | PASS | OneDrive-safe release build completed |
| Git whitespace | PASS | `git diff --check` completed without defects |
| Backend health | PASS | API 5.0.0, SQLite, remote dedicated sandbox mode |
| Sandbox health | PASS | Dedicated service returned `status: ok` |
| Manual demo student flow | PASS | Login page, temporary demo, six-assignment catalog, corrected Assignment 1 instructions, starter run, structured 0/4 feedback, and AI-off default rendered correctly |
| Manual instructor flow | PASS | Instructor login and six published assignment versions rendered in the assignment studio |
| Assignment 2 notebook consistency | PASS | Stale perimeter name and retired route description were replaced; notebook JSON validates |

## Defects found during this cycle

| ID | Defect | Correction | Retest |
|---|---|---|---:|
| QA-CONTENT-01 | Four API tests expected retired answer/version values | Updated assertions to the new published assignment versions and 12-unit Assignment 2 result | PASS, 44/44 focused API tests |
| QA-CONTENT-02 | Seven edited teaching files failed whitespace validation | Removed trailing spaces and extra EOF blank lines | PASS, complete verification gate |
| QA-CONTENT-03 | Assignment 2 notebook still described a full-perimeter route | Added hit/leave points and aligned the variable/route with H-A-B-L | PASS, JSON and stale-text scan |

## Verification commands

```powershell
.\scripts\run-local.ps1 -FrontendPort 8180 -BackendPort 5100 -SandboxPort 5101
.\scripts\verify-local.ps1 -ApiBaseUrl http://127.0.0.1:5100
.\scripts\check-ros2-local.ps1
```

## Release boundary

This result approves the current working tree for continued local staging work.
It is not a production or Android certification, and no live repository or
deployment was changed. The branch has not been committed or pushed in this
cycle.
