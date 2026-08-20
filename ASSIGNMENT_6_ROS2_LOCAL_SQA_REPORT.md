# Assignment 6 ROS 2 Local SQA Report

**Test date:** 2026-08-20

**Environment:** `C:\Users\cspon\OneDrive - University of Nevada, Reno\Robotics-Programming-Lab-Staging`

**Branch:** `assignment-6-ros2-obstacle-stop`

**Decision:** PASS for the local staging implementation and staging feature
branch. Live was not modified. Production promotion remains blocked until the
hosted ROS worker and its deployment SQA are explicitly approved.

## Result summary

| Area | Result | Evidence |
|---|---:|---|
| Assignment identity | PASS | ID `6`, stable ID `ros2-obstacle-stop`, version `1`, published staging seed |
| Learning design | PASS | LaserScan subscription, Twist publisher, clear-path motion, obstacle/invalid-scan stop, and recovery objectives |
| Project workspace | PASS | Seven visible project files; exactly one editable `src/reactive_navigation/reactive_navigation/controller.py` |
| Locked-file content | PASS | Browser QA confirmed selecting `package.xml` displays its XML and read-only state; shared CodeController defect was fixed and regression-tested |
| Student privacy boundary | PASS | Student API omits `grader_config`, `reference_solution_path`, and official solution content |
| Maintained answer | PASS | Rebuilt ROS 2 Jazzy Docker grader returned 9/9 checks, score 100; 44 settled messages at approximately 9.2 Hz |
| Assignment 5 regression | PASS | Existing maintained answer still passes 7/7 checks in the rebuilt image |
| Starter code | PASS | Builds but fails the seven incomplete behavior requirements without hanging |
| Incorrect threshold | PASS | Real grader rejects reversed threshold logic; authenticated API score 40 and `pass=false` |
| Syntax error | PASS | Rejected safely with a bounded syntax error |
| Runtime error | PASS | Node crash is bounded and returned as execution failure |
| Unsafe import | PASS | `import os` rejected before package execution |
| Infinite loop | PASS | Container execution terminated within the configured bound |
| Excessive output | PASS | Execution remained bounded and behavior tests failed without exposing unbounded output |
| Oversized submission | PASS | Assignment 6 API returns HTTP 413 before execution |
| Container isolation | PASS | Reuses the networkless, read-only, non-root Docker executor with CPU, memory, PID, capability, and privilege limits |
| Focused backend tests | PASS | 12 ROS-specific tests passed, including the ROS-discovery readiness regression |
| Full backend regression | PASS | 114 tests passed |
| Python integrity | PASS | `pip check` and backend `compileall` passed |
| Flutter analysis | PASS | No issues found |
| Flutter regression | PASS | 43 tests passed, including complete project-file content replacement and persistent-student analytics access |
| Flutter release build | PASS | OneDrive-safe release web build succeeded with configured API base URL |
| Local services | PASS | Frontend HTTP 200; backend and dedicated sandbox health returned `ok` |
| Authenticated local API | PASS | Catalog returned IDs 1-6; maintained answer score 100 with nine evidence rows; wrong answer failed |
| Instructor publish validation | PASS | Authenticated `/admin/assignments/6/validate` returned `valid=true` with no errors after running the maintained answer |
| Desktop browser | PASS | Card 06, instructions, seven-file tree, read-only files, editable controller, and AI-off state rendered correctly |
| Mobile browser | PASS | Assignment workspace rendered at 390 x 844 without browser errors |
| CI protection | PASS | The fixed harness waits for ROS discovery and one end-to-end response before scoring; the rebuilt image plus four additional consecutive runs passed Assignment 5 at 7/7 and Assignment 6 at 9/9 |
| Master Excel SQA checklist | BLOCKED | The required bundled spreadsheet dependency loader was unavailable in this session; the existing workbook was not modified with an unsupported library |

## Remaining production limitations

| Item | Status | Reason / next action |
|---|---:|---|
| Live deployment | NOT RUN | The owner requested staging only. Production still intentionally contains Assignments 1-4. |
| Hosted ROS worker | BLOCKED | Local Docker execution is not the approved production architecture. Deploy and secure a private Linux ROS worker before promotion. |
| External computer/network | NOT RUN | Localhost was tested in a clean browser session and mobile viewport, not from a second physical device. |
| Physical robot or simulator | NOT RUN | Assignment 6 intentionally uses synthetic LaserScan messages and observable topic grading without simulation. |
| Excel evidence synchronization | BLOCKED | Copy this report into `Robotics_Programming_Lab_Master_SQA_Checklist.xlsx` when the approved spreadsheet runtime is available. |

## Reproduction

```powershell
Set-Location "C:\Users\cspon\OneDrive - University of Nevada, Reno\Robotics-Programming-Lab-Staging"
.\scripts\check-ros2-local.ps1 -Build
.\scripts\verify-local.ps1 -ApiBaseUrl http://127.0.0.1:5100
```

The instructor answer is committed for manual SQA but is never returned by the
student API or Flutter bundle. Anyone with repository access can read it, so
students should receive only the application URL.

## CI readiness defect and correction

The first GitHub pull-request run built the ROS image successfully, but the
Assignment 6 check started scoring before the cold CI runner completed ROS
publisher/subscriber discovery. The node became available after the clear-path
phase, so the otherwise correct maintained answer had no settled clear-phase
sample. The harness now waits for the `/scan` subscriber, `/cmd_vel` publisher,
and one end-to-end scan response, then clears readiness traffic before beginning
the scored phases. Five consecutive rebuilt-image runs produced identical PASS
results for both maintained ROS assignments.
