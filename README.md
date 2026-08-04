# Robotics Programming Lab

A configurable robotics-education platform with a Flutter student/instructor
interface and a FastAPI assignment, grading, simulation, and tutoring API.

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

## Repository layout

- `backend/`: FastAPI application, database models, graders, tutor, sandbox, and tests
- `frontend/`: Flutter web/mobile student and instructor interface
- `course_materials/`: controlled reference solutions and course source files
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

Recommended one-command local staging run:

```powershell
.\scripts\run-local.ps1
```

This starts the dedicated sandbox, backend, and Flutter web application while
keeping AI off by default. Stop them with:

```powershell
.\scripts\stop-local.ps1
```

The manual commands below remain available for troubleshooting.

Backend terminal:

```powershell
Set-Location .\backend
..\venv\Scripts\python.exe run.py
```

Flutter terminal:

```powershell
Set-Location .\frontend
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:5000
```

The backend seeds the four existing assignments and two prototype accounts into
the database on first start:

```text
Student:    student / student
Instructor: instructor / instructor
```

The login page does not display these credentials. Override both passwords with
server-side environment variables before sharing a live URL beyond the approved
professor demo.

The v4 deployment and local-parity instructions are in
[`V4_LIVE_DEPLOYMENT.md`](V4_LIVE_DEPLOYMENT.md).

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
For zero-Docker local development, run `backend/run.py` directly; it uses the
restricted subprocess fallback from `backend/.env`.

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

## AI tutoring

Without an API key, the tutor produces deterministic progressive hints from
sanitized grader evidence. With `OPENAI_API_KEY` in an ignored backend environment
file, the same tutor boundary can enhance that feedback. Hidden tests, expected
values, and official solutions are never included in the model input.

## Verification

```powershell
Set-Location .\backend
..\venv\Scripts\python.exe -m pytest -q
..\venv\Scripts\python.exe -m pip check

Set-Location ..\frontend
flutter analyze
flutter test
flutter build web --dart-define=API_BASE_URL=http://127.0.0.1:5000
```

Native Android builds additionally require Android Studio and the Android SDK.
Windows desktop builds require the Visual Studio C++ desktop workload.
