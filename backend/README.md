# Robotics Programming Lab FastAPI backend

## Services

- FastAPI provides student, instructor, grading, tutoring, and asset endpoints.
- SQLAlchemy stores assignments, versions, submissions, evidence, and hint history.
- PostgreSQL is the production database; SQLite is the zero-setup local fallback.
- Redis/RQ adapters are available for future long-running simulations and grading.
- Submission execution can use a restricted local worker or per-run Docker sandbox.

Docker Compose loads secrets and instructor settings from the ignored
`backend/.env` file and defaults submission execution to the Docker sandbox.
Direct local development can keep `SANDBOX_BACKEND=subprocess`.

## Run locally

```powershell
..\venv\Scripts\python.exe run.py
```

OpenAPI documentation is available at `http://127.0.0.1:5000/docs`.

## Instructor configuration

Set a long random `ADMIN_API_TOKEN` in the ignored `backend/.env` file. The
instructor interface sends it as `X-Admin-Token`; it is never compiled into
Flutter.

Instructor publishing runs the server-side reference solution through the hidden
grader. Invalid assignments remain drafts.

## Database lifecycle

On an empty database, the existing `assignments/assignment_*.json` files are
imported as version 1. After import, instructor edits are persisted in the
database and automatically increase the assignment version when teaching,
execution, grading, tutoring, or simulation content changes.

## Tests

```powershell
..\venv\Scripts\python.exe -m pytest -q
..\venv\Scripts\python.exe -m pip check
```
