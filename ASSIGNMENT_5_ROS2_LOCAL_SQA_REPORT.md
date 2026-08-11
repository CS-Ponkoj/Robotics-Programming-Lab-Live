# Assignment 5 ROS 2 Local SQA Report

**Test date:** 2026-08-11

**Branch:** `codex-ros-local-assignment` based on staging `main` at `522dd745`

**Decision:** PARTIAL - code and local platform checks pass; real ROS container execution is blocked until Docker Desktop is explicitly installed.

| Area | Result | Evidence |
|---|---:|---|
| Pre-change recovery point | PASS | `backup-version-4.1-pre-ros` pushed to staging at `522dd745` |
| Assignment configuration | PASS | Stable ID `ros2-drive-forward`, version 1, seven public behavior checks, simulation disabled |
| Student workspace data | PASS | Seven project files returned; exactly one editable `controller.py` |
| Private data boundary | PASS | Student API omits `grader_config` and `reference_solution_path` |
| Maintained answer | PASS | `manual_sqa_answers/assignment_5_ros2_drive_forward/controller.py` is tracked for instructor checks |
| Grader unit and API tests | PASS | Correct, partial, unsafe-import, missing-Docker and injected-API paths pass |
| Full backend regression | PASS | 100 tests passed in a clean declared-dependency environment |
| Python dependency integrity | PASS | `pip check` reports no broken requirements |
| Python compilation | PASS | Backend `compileall` succeeds |
| Flutter static analysis | PASS | No issues found |
| Flutter regression | PASS | 39 tests passed, including project tree and read-only editor checks |
| Flutter release web build | PASS | Release build completed with local API base URL |
| Local launcher | PASS | Corrected to use web-server mode and an IPv4 health probe |
| Local service health | PASS | Frontend 200; backend and dedicated Python sandbox report `ok` |
| Authenticated Assignment 5 API | PASS | Demo student loads Assignment 5 and its safe project-file payload |
| Missing runtime behavior | PASS | Run returns the Docker Desktop recovery message in about 0.04 seconds; no indefinite spinner |
| Real ROS 2 Jazzy image build | BLOCKED | Docker Desktop is not installed on this computer |
| Correct answer in real ROS runtime | BLOCKED | Requires the versioned ROS 2 Docker image |
| Incorrect/runtime behavior in real ROS runtime | BLOCKED | Requires the versioned ROS 2 Docker image |
| Rendered browser interaction | BLOCKED | Codex browser control could not start because of a Windows sandbox helper failure; widget behavior remains covered by Flutter tests |

## Required completion gate

After explicitly approving and installing Docker Desktop, start its Linux engine and run:

```powershell
.\scripts\check-ros2-local.ps1 -Build
```

Then run the maintained correct controller plus incorrect and unsafe submissions through Assignment 5. Do not publish this feature to live until those real-container checks pass.

## Repository-answer limitation

The answer is not returned through the student API or Flutter application. It is intentionally committed because the instructor requested it. Anyone with read access to the Git repository can still read it, so students should receive only the application link.
