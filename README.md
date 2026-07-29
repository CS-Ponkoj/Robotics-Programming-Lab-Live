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
- PostgreSQL and Redis production services through Docker Compose
- Docker submission-sandbox adapter with a local subprocess development fallback
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

### Install

```powershell
python -m venv venv
.\venv\Scripts\python.exe -m pip install -r .\backend\requirements.txt
Set-Location .\frontend
flutter pub get
Set-Location ..
```

### Run

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

The backend seeds the four existing assignments into the database on first start.

## PostgreSQL, Redis, and Docker

Copy `backend/.env.example` to the ignored `backend/.env` file, replace the
instructor token, and add the optional OpenAI key there. Compose loads this
server-only file automatically. Then:

```powershell
docker compose --profile build build sandbox-image
docker compose up --build postgres redis backend
```

Compose defaults to `SANDBOX_BACKEND=docker`, executing every submission in a
short-lived container with no network, capped memory/CPU, and a process limit.
For zero-Docker local development, run `backend/run.py` directly; it uses the
restricted subprocess fallback from `backend/.env`.

## Assignment API

```text
GET  /assignments
GET  /assignments/{assignment_id}
POST /assignments/{assignment_id}/run
POST /assignments/{assignment_id}/submit
POST /assignments/{assignment_id}/hint
POST /assignments/{assignment_id}/solution
```

Instructor routes live under `/admin/assignments` and require `X-Admin-Token`.
The Flutter landing-page shield icon opens the instructor assignment studio.

The student assignment endpoints never return `grader_config`, expected values,
misconceptions used internally by the tutor, reference-solution paths, or the
worked solution. A solution can be retrieved only using a submission ID for the
current assignment version.

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
