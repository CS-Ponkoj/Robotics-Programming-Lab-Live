# Assignment 5 ROS 2 Local SQA Report

**Test date:** 2026-08-11

**Branch:** `codex-ros-local-assignment` based on staging `main` at `522dd745`

**Decision:** PASS for staging feature-branch publication; HOLD staging `main` until the rendered-browser visual checklist is completed. The local code-only ROS assignment, real container grader and hands-on API workflow pass. Live deployment remains a separate future step because it requires a hosted ROS worker.

| Area | Result | Evidence |
|---|---:|---|
| Pre-change recovery point | PASS | `backup-version-4.1-pre-ros` pushed to staging at `522dd745` |
| Assignment configuration | PASS | Stable ID `ros2-drive-forward`, version 1, seven public behavior checks, simulation disabled |
| Student workspace data | PASS | Seven project files returned; exactly one editable `controller.py` |
| Private data boundary | PASS | Student API omits `grader_config` and `reference_solution_path` |
| Maintained answer | PASS | `manual_sqa_answers/assignment_5_ros2_drive_forward/controller.py` is tracked for instructor checks |
| Grader unit and API tests | PASS | Correct, partial, syntax-error, unsafe-import, isolation-policy, missing-Docker and injected-API paths pass |
| Full backend regression | PASS | 100 tests passed in a clean declared-dependency environment |
| Python dependency integrity | PASS | `pip check` reports no broken requirements |
| Python compilation | PASS | Backend `compileall` succeeds |
| Flutter static analysis | PASS | No issues found |
| Flutter regression | PASS | 39 tests passed, including project tree and read-only editor checks |
| Flutter release web build | PASS | Release build completed with local API base URL |
| Local launcher | PASS | Corrected to use web-server mode and an IPv4 health probe |
| Local service health | PASS | Frontend 200; backend and dedicated Python sandbox report `ok` |
| Authenticated Assignment 5 API | PASS | Demo student loads Assignment 5 and its safe project-file payload |
| Docker readiness | PASS | Docker Desktop 4.86.0; Linux engine 29.7.2; project readiness script locates PATH or standard Windows installation |
| Real ROS 2 Jazzy image build | PASS | Pinned official Jazzy base built as `robotics-lab-ros2-grader:jazzy-v1` |
| Correct answer in real ROS runtime | PASS | Seven of seven tests pass; approximately 58 messages at 10 Hz |
| Authenticated real ROS API | PASS | Student login to Assignment 5 run returns execution success, score 100 and seven passing evidence rows in 10.68 seconds |
| Adversarial real ROS matrix | PASS | Wrong velocity, syntax error, runtime crash, unsafe import, infinite loop, excessive output and oversized code all produced the expected bounded result |
| Container isolation | PASS | Non-root worker, network disabled, read-only root, capability drop, no-new-privileges, resource limits, executable workspace and non-executable `/tmp` |
| Manual functional QA | PASS | Staging-folder run passed 12 hands-on checks: service health, invalid login, both roles, role isolation, instructor validation, safe project tree, correct score 100 and wrong velocity rejected at score 80 |
| Rendered browser interaction | BLOCKED | Codex browser control could not start because of a Windows sandbox helper failure; widget behavior remains covered by Flutter tests |

## Staging decision and live limitation

The feature is ready on the staging Git feature branch and for local classroom evaluation. Recheck the local ROS image at any time with:

```powershell
.\scripts\check-ros2-local.ps1
```

Do not promote Assignment 5 to the current live Render service yet. Render cannot run this local Docker-in-Docker grader design. A separate hosted ROS worker or container-job service must be designed, secured and SQA-tested before live publication.

Before merging staging `main`, open `http://127.0.0.1:8180` and visually confirm: login layout, Assignment 5 file tree, lock icons on six files, editable `controller.py`, correct-result presentation, wrong-result presentation, narrow/mobile layout and keyboard navigation.

## Repository-answer limitation

The answer is not returned through the student API or Flutter application. It is intentionally committed because the instructor requested it. Anyone with read access to the Git repository can still read it, so students should receive only the application link.
