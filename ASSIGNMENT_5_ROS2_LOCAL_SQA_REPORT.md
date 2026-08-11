# Assignment 5 ROS 2 Local SQA Report

**Test date:** 2026-08-11

**Environment:** `C:\Users\cspon\OneDrive - University of Nevada, Reno\Robotics-Programming-Lab-Staging`

**Branch and tested commit:** staging `main` at `3ab909b7b6b7ecd6977e14ccb1e98f878fe76e17`

**Decision:** PASS for the local staging implementation, automated release gate, authenticated functional QA and staging-Git synchronization. Rendered browser inspection is still BLOCKED by the Codex Windows browser-control sandbox and must be completed by a human before production promotion. Live was not touched and remains a separate future step because it requires a hosted ROS worker.

| Area | Result | Evidence |
|---|---:|---|
| Pre-change recovery point | PASS | `backup-version-4.1-pre-ros` pushed to staging at `522dd745` |
| Assignment configuration | PASS | Stable ID `ros2-drive-forward`, version 1, seven public behavior checks, simulation disabled |
| Student workspace data | PASS | Seven project files returned; exactly one editable `controller.py` |
| Private data boundary | PASS | Student API omits `grader_config` and `reference_solution_path` |
| Maintained answer | PASS | `manual_sqa_answers/assignment_5_ros2_drive_forward/controller.py` is tracked for instructor checks |
| Grader unit and API tests | PASS | Correct, partial, syntax-error, unsafe-import, isolation-policy, missing-Docker and injected-API paths pass |
| Full backend regression | PASS | 100 tests passed from the synchronized staging folder in 31.27 seconds |
| Python dependency integrity | PASS | `pip check` reports no broken requirements |
| Python compilation | PASS | Backend `compileall` succeeds |
| Flutter static analysis | PASS | No issues found |
| Flutter regression | PASS | 39 tests passed, including project tree and read-only editor checks |
| Flutter release web build | PASS | OneDrive-safe release build completed using API base URL `http://127.0.0.1:5100` |
| Local launcher | PASS | Uses web-server mode and an IPv4 health probe |
| Local service health | PASS | Frontend 200; backend and dedicated Python sandbox report `ok` |
| Authenticated Assignment 5 API | PASS | Demo student loads Assignment 5 and its safe project-file payload |
| Docker readiness | PASS | Docker Desktop 4.86.0; Linux engine 29.7.2; project readiness script locates PATH or standard Windows installation |
| Real ROS 2 Jazzy image build | PASS | Pinned official Jazzy base built as `robotics-lab-ros2-grader:jazzy-v1` |
| Correct answer in real ROS runtime | PASS | Seven of seven tests pass; approximately 58 messages at 10 Hz |
| Authenticated real ROS API | PASS | Correct controller returns execution success, score 100 and seven passing evidence rows in 9.03 seconds |
| Adversarial real ROS matrix | PASS | Wrong velocity, syntax error, runtime crash, unsafe import, infinite loop, excessive output and oversized code all produced the expected bounded result |
| Container isolation | PASS | Non-root worker, network disabled, read-only root, capability drop, no-new-privileges, resource limits, executable workspace and non-executable `/tmp` |
| Manual functional QA | PASS | Exact staging-folder run passed health, invalid login, both roles, role isolation, instructor validation, seven-file safe project tree with one editable file, correct score 100 with seven evidence rows in 9.03 seconds, and wrong velocity rejected at score 80 in 8.98 seconds |
| Student solution boundary | PASS | The compatibility `solution_html` field is empty (length 0); no grader configuration, reference-solution path or private project file is returned |
| AI default | PASS | Managed local state records `aiEnabled: false` |
| Local/staging Git consistency | PASS | Local staging `main` and `origin/main` both resolve to `3ab909b7`; pre-existing local lockfile and generated import report remain excluded from this release |
| Rendered browser interaction | BLOCKED | Browser control failed before connecting with `windows sandbox failed: helper_unknown_error: setup refresh had errors`; UI behavior remains covered by 39 Flutter tests but is not represented as manually passed |

## Staging decision and live limitation

The feature is synchronized to staging Git `main` and is ready for local classroom evaluation. Recheck the local ROS image at any time with:

```powershell
.\scripts\check-ros2-local.ps1
```

Do not promote Assignment 5 to the current live Render service yet. Render cannot run this local Docker-in-Docker grader design. A separate hosted ROS worker or container-job service must be designed, secured and SQA-tested before live publication.

Before production promotion, open `http://127.0.0.1:8180` and visually confirm: login layout, Assignment 5 file tree, lock icons on six files, editable `controller.py`, correct-result presentation, wrong-result presentation, narrow/mobile layout and keyboard navigation.

## Repository-answer limitation

The answer is not returned through the student API or Flutter application. It is intentionally committed because the instructor requested it. Anyone with read access to the Git repository can still read it, so students should receive only the application link.
