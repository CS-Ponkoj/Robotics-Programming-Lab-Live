# V5.4 Assignment and Progress SQA Report

**Date:** 2026-08-30  
**Scope:** Local staging application only  
**AI tutor:** Disabled by design for this test run

## Result

The improved content for Assignments 1–6 is present in the application. The
student analytics failure was repaired, and percentage-based progress and score
colors were added. Automated backend and frontend gates pass.

## Verification matrix

| Area | Check | Result | Evidence |
|---|---|---:|---|
| Assignment content | Improved Assignments 1–6 load from the backend | PASS | Current assignment API and full backend suite |
| Assignment visuals | Instruction images 1–6 are available as PNG responses | PASS | `/images/1` through `/images/6` returned HTTP 200 |
| Student analytics | Multiple attempts no longer cause `/research/me` to return HTTP 500 | PASS | Regression test plus local `student` session returned HTTP 200 |
| Student analytics UI | Study progress page renders summary cards, assignment analytics, and attempt history | PASS | Manual local browser check |
| Progress color | Home progress percentage and bar interpolate from red through amber to green | PASS | Flutter widget tests and manual browser check |
| Score color | Assignment badges and result score use the same percentage color scale | PASS | Flutter widget tests and manual browser check |
| Empty results layout | Desktop Results panel stays collapsed before the first run, allowing Instructions to use the full right side; Results opens when a run starts | PASS | Focused workspace and keyboard-run widget tests |
| Backend regression | Entire backend suite | PASS | 185 tests passed |
| Python dependencies | Installed dependency compatibility | PASS | `pip check` reported no broken requirements |
| Flutter static analysis | Dart/Flutter analyzer | PASS | No issues found |
| Flutter regression | Entire Flutter test suite | PASS | 52 tests passed |
| Flutter release | Production-style web compilation | PASS | Release web build completed |
| ROS 2 runtime | Real Docker execution for Assignments 5–6 during this run | BLOCKED | Docker Desktop 4.86.0 crashed while starting its Linux engine because its internal `dockerInference` socket could not be accessed |

## Confirmed bug and fix

The analytics service paired a list of active-time snapshots with a list that
was intentionally one item shorter, but requested strict equal-length pairing.
Any student with multiple timed attempts could therefore trigger a server
exception. The pairing now uses normal adjacent-item behavior, with a regression
test covering two attempts and the calculated 60-second active gap.

## Limitation

The ROS 2 application code and automated tests pass, but the maintained answers
for Assignments 5–6 could not be rerun through the real local Docker engine in
this session because Docker Desktop failed before the engine became available.
This is a local Docker Desktop runtime problem, not an application test failure.
Restarting Windows (or repairing Docker Desktop) is required before repeating:

```powershell
.\scripts\check-ros2-local.ps1
```

Do not describe the real ROS runtime check as passed until that command succeeds.
