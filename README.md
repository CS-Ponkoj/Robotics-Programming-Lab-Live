# Robotics Programming Lab

A configurable robotics-education platform with a Flutter student/instructor
interface and a FastAPI assignment, grading, simulation, and tutoring API.

## Live application

Open the classroom-ready web application: [Robotics Programming Lab](https://robotics-programming-lab.vercel.app/)

## What is implemented

- Versioned, database-backed assignment definitions
- Stable assignment IDs and automatic version capture on every submission
- Generic student endpoints for run, submit, hints, and protected solutions
- Modular `AssignmentGrader` implementations
- Server-only hidden grader configuration and reference solutions
- Progressive deterministic tutoring with an optional OpenAI enhancement
- Assignment-specific objectives, rubrics, misconceptions, tutor policies, and
  simulation configuration
- Instructor assignment studio with validation-before-publish
- Student and instructor login with server-side sessions and role checks
- Instructor student-account creation, manual password reset, and deactivation
- Optional `study_accounts.json` import for manually managed prototype cohorts
- PostgreSQL and Redis production services through Docker Compose
- Dedicated secret-free sandbox service for live grading, plus Docker and
  restricted-subprocess local adapters
- Legacy `/grade/{id}` and `/assignments/` compatibility routes
- Persistent Flutter drafts, scores, attempts, submission IDs, and solution state
- Privacy-safe study sessions, active-time capture, learning events, participant
  analytics, and authenticated CSV/Excel research exports

## Repository layout

- `backend/`: FastAPI application, database models, graders, tutor, sandbox, and tests
- `frontend/`: Flutter web/mobile student and instructor interface
- `course_materials/`: controlled reference solutions and course source files
- `manual_sqa_answers/`: instructor-only answer files for manual grader checks
- `docker-compose.yml`: PostgreSQL, Redis, FastAPI, and persistent storage

## Local development

The default local backend uses an ignored SQLite database so the project remains
easy to run without Docker. Production and team environments should set
`DATABASE_URL` to PostgreSQL.

The project now uses a two-repository release workflow. All changes and SQA are
performed in `Robotics-Programming-Lab-Staging`; the live
`Robotics-Programming-Lab` repository receives only the exact approved commit.
See [`STAGING_AND_RELEASE_WORKFLOW.md`](STAGING_AND_RELEASE_WORKFLOW.md).

### Install

```powershell
python -m venv venv
.\venv\Scripts\python.exe -m pip install -r .\backend\requirements.txt
Set-Location .\frontend
flutter pub get
Set-Location ..
```

### Run

Run the complete local staging stack from the repository root:

```powershell
Set-Location "C:\Users\cspon\OneDrive - University of Nevada, Reno\Robotics-Programming-Lab-Staging"
.\scripts\stop-local.ps1
.\scripts\run-local.ps1 -FrontendPort 8180 -BackendPort 5100 -SandboxPort 5101
```

This starts the dedicated sandbox, FastAPI backend, and Flutter web application
while keeping AI off by default. It runs Flutter from a generated copy under
`LocalAppData`, preventing OneDrive from locking Flutter build files. Keep the
PowerShell window open and use the frontend URL printed by the script (with the
ports above, `http://127.0.0.1:8180/app`).

The launcher defaults to frontend port `8080`, backend port `5000`, and sandbox
port `5001` when the port parameters are omitted. Stop only the processes
managed by the launcher with:

```powershell
.\scripts\stop-local.ps1
```

To troubleshoot the explicit-port example, check each managed service:

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8180/app
Invoke-RestMethod http://127.0.0.1:5100/health
Invoke-RestMethod http://127.0.0.1:5101/health
```

Do not use the retired `backend/run.py` command, and do not run `flutter run`
directly inside the OneDrive checkout. Those older commands omit the dedicated
sandbox and can trigger OneDrive build-directory locks.

The backend seeds the configured assignments (including staging-only ROS
Assignments 5 and 6) and two prototype accounts into the database on first
start:

```text
Student:    student / student
Instructor: instructor / instructor
```

The login page does not display these credentials. Override both passwords with
server-side environment variables before sharing a live URL beyond the approved
professor demo.

The v4 deployment and local-parity instructions are in
[`V4_LIVE_DEPLOYMENT.md`](V4_LIVE_DEPLOYMENT.md).
The V4.1 research dataset and dashboard are documented in
[`V4_1_RESEARCH_DATA_GUIDE.md`](V4_1_RESEARCH_DATA_GUIDE.md).

## PostgreSQL, Redis, and Docker

Copy `backend/.env.example` to the ignored `backend/.env` file and add database,
email, and optional OpenAI settings. Compose loads this server-only file
automatically. Then:

```powershell
docker compose --profile build build sandbox-image
docker compose up --build postgres redis backend
```

Compose defaults to `SANDBOX_BACKEND=docker`, executing every submission in a
short-lived container with no network, capped memory/CPU, and a process limit.
For ordinary zero-Docker development of Assignments 1 through 4, use
`scripts/run-local.ps1`; it launches the dedicated local sandbox service with
the restricted subprocess executor. Assignments 5 and 6 require Docker Desktop
and the ROS 2 grader image.

### Local ROS 2 assignments

The staging catalog contains two ROS 2 Jazzy code-only exercises:

- Assignment 5 publishes timed `geometry_msgs/Twist` movement and stop commands
  on `/cmd_vel`.
- Assignment 6 subscribes to synthetic `sensor_msgs/LaserScan` messages on
  `/scan`, stops for a nearby obstacle or invalid scan, and resumes when the
  path clears.

Students can inspect each package tree but can edit only that package's
`controller.py`. The grader builds the package and checks observable topic
behavior without launching a simulator.

Docker Desktop with Linux containers must be installed and running. Build the
versioned grader image once, and rebuild it after changing either ROS worker:

```powershell
docker compose --profile build build ros2-grader-image
docker image inspect robotics-lab-ros2-grader:jazzy-v1
```

Then use the normal local command:

```powershell
.\scripts\run-local.ps1
```

Assignments 1 through 4 still run when Docker is unavailable, but Assignments 5
and 6 return an actionable Docker Desktop error instead of waiting
indefinitely. Run `scripts/check-ros2-local.ps1` to verify the image and both
maintained answers. The controller answers are stored at
`manual_sqa_answers/assignment_5_ros2_drive_forward/controller.py` and
`manual_sqa_answers/assignment_6_ros2_obstacle_stop/controller.py`. They are not
returned by the student API or bundled into Flutter. Because they are committed
as requested, anyone who can read this Git repository can read the answers; do
not give students repository access if they must remain private.

The live classroom deployment uses a second Render Docker web service defined
in `render.yaml`. The main API sends only student code, requested result names,
and an execution timeout to that service. The sandbox has no database or OpenAI
credentials, and its short-lived worker environment excludes the service token.
Production startup rejects the local subprocess backend.

## Assignment API

```text
GET  /assignments
GET  /assignments/{assignment_id}
POST /assignments/{assignment_id}/run
POST /assignments/{assignment_id}/submit
POST /assignments/{assignment_id}/hint
POST /assignments/{assignment_id}/solution
```

Authentication routes live under `/auth`. Instructor routes under `/admin`
require an authenticated instructor account. A legacy `X-Admin-Token` remains
available temporarily for older API clients, but the Flutter interface no
longer asks for it.

The student assignment endpoints never return `grader_config`, expected values,
misconceptions used internally by the tutor, reference-solution paths, or the
worked solution. A solution can be retrieved only using a submission ID for the
current assignment version.

## Study accounts

Instructors can create, edit, reset, deactivate, and reactivate students from
the instructor studio. Deactivation preserves attempts and study records.
The v4 professor demo uses instructor-managed passwords. Self-service reset and
email-delivery controls remain implemented but disabled by default.

If those deferred features are enabled later, real email delivery requires the
`SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`,
`SMTP_PASSWORD`, and `SMTP_FROM` values supplied by the chosen mail provider in
the ignored `backend/.env` file. Restart the backend after changing them. The
Student Accounts screen can report whether delivery is configured and provide a
**Send test** action. Invitation and instructor-initiated email reset actions
are blocked when SMTP is missing, so the interface never reports a development
outbox message as a delivered email.

For small prototype cohorts, copy
`backend/data/study_accounts.example.json` to the ignored
`backend/data/study_accounts.json`, edit it in VS Code, and use **Import
study_accounts.json** on the Student Accounts screen. The database remains the
login source of truth. Setting `"active": false` deactivates an account;
removing a row from JSON does not delete it. Any `temporary_password` is hashed
and cleared from the JSON file after import.

Participant codes must be unique for student accounts. They are the identifiers
shown in the research dashboard and exports; login IDs are intentionally
excluded from those datasets.

## Research study data

PostgreSQL (or the local SQLite fallback) is the authoritative store for study
sessions, active time, assignment attempts, hint/solution use, and learning
events. The Flutter application sends a heartbeat every 30 seconds only while
the page is visible. Code is saved only with an intentional run/submit and is
not included in research dashboards or exports.

Students can open **My study progress** from the account menu. Instructors can
open **Research study dashboard** from the instructor studio, inspect a
participant timeline, and download summary, attempt, or event CSV files plus a
complete Excel workbook. All timestamps are stored in UTC and every assignment
record includes its version.

## AI tutoring

Without an API key, the tutor produces deterministic progressive hints from
sanitized grader evidence. With `OPENAI_API_KEY` in an ignored backend environment
file, the same tutor boundary can enhance that feedback. Hidden tests, expected
values, and official solutions are never included in the model input.

## Verification

Run the complete OneDrive-safe verification gate from the repository root:

```powershell
Set-Location "C:\Users\cspon\OneDrive - University of Nevada, Reno\Robotics-Programming-Lab-Staging"
.\scripts\verify-local.ps1 -ApiBaseUrl http://127.0.0.1:5100
```

This runs backend tests, dependency and compilation checks, Flutter analysis and
tests, a release web build from a safe `LocalAppData` copy, Git whitespace
validation, and managed-service health checks when the local stack is running.

Native Android builds additionally require Android Studio and the Android SDK.
Windows desktop builds require the Visual Studio C++ desktop workload.
