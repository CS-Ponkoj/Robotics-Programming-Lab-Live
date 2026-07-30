# Robotics Programming Lab FastAPI backend

## Services

- FastAPI provides student, instructor, grading, tutoring, and asset endpoints.
- SQLAlchemy stores assignments, versions, submissions, evidence, and hint history.
- PostgreSQL is the production database; SQLite is the zero-setup local fallback.
- Redis/RQ adapters are available for future long-running simulations and grading.
- Submission execution can use a restricted local worker or per-run Docker sandbox.
- Server-side sessions authorize student and instructor roles.
- Instructor tools manage study accounts without exposing password hashes.

Docker Compose loads secrets and instructor settings from the ignored
`backend/.env` file and defaults submission execution to the Docker sandbox.
Direct local development can keep `SANDBOX_BACKEND=subprocess`.

## Run locally

```powershell
..\venv\Scripts\python.exe run.py
```

OpenAPI documentation is available at `http://127.0.0.1:5000/docs`.

## Accounts and instructor access

The local prototype seeds `instructor / instructor` and `student / student`.
The Flutter application signs in through `/auth/login` and sends an opaque
Bearer session token. Instructor APIs verify the instructor role. The
`ADMIN_API_TOKEN` option is retained only for compatibility with older API
clients and is not used by the current Flutter instructor interface.

An instructor can create students, generate a temporary password, send an email
activation link, reset access, and deactivate or reactivate accounts. Accounts
should be deactivated instead of deleted so study records remain attributable.

For manual prototype management, copy
`data/study_accounts.example.json` to the ignored
`data/study_accounts.json`. Import it from the instructor screen or
`POST /admin/accounts/import`. The database is authoritative: a missing JSON
row does nothing, while `"active": false` deactivates an account.
`temporary_password` values are hashed and removed from the JSON file after a
successful import.

Configure SMTP settings in `.env` to deliver one-time activation and reset
links. When SMTP is not configured, development messages stay in the in-memory
test outbox and no email is delivered. `GET /admin/email/status` reports the
configuration without exposing credentials, and `POST /admin/email/test` sends
a real test message. Instructor invitation/reset actions return an explicit
configuration error until SMTP is ready instead of claiming that an outbox
message was delivered.

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
