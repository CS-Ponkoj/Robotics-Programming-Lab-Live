# Robotics Programming Lab FastAPI backend

## Services

- FastAPI provides student, instructor, grading, tutoring, and asset endpoints.
- SQLAlchemy stores assignments, versions, submissions, evidence, and hint history.
- PostgreSQL is the default local and production database; SQLite is an explicit
  disposable troubleshooting fallback.
- Redis/RQ adapters are available for future long-running simulations and grading.
- Submission execution can use a restricted local worker or per-run Docker sandbox.
- Server-side sessions authorize student and instructor roles.
- Instructor tools manage study accounts without exposing password hashes.
- Research sessions and learning events use participant codes in dashboards and
  exports; submitted code and login IDs are excluded from research datasets.
- Phase 1 analytics keep assignment versions separate, preserve null historical
  time, expose paginated attempt history, and provide privacy-safe classroom,
  participant, assignment, and data-health summaries.

Docker Compose and the supported local launcher load secrets and instructor
settings directly from ignored `local_handoff_package/.env`. Submission
execution defaults to the Docker sandbox.
Direct local development can keep `SANDBOX_BACKEND=subprocess`.

## Run locally

From the repository root, use the supported launcher so the backend and its
dedicated sandbox start together:

```powershell
.\scripts\setup-local.ps1
.\scripts\run-local.ps1 -FrontendPort 8180 -BackendPort 5100 -SandboxPort 5101
```

OpenAPI documentation is available at `http://127.0.0.1:5100/docs` in local
development. Use the root launcher for normal work because it resolves the
device-local Python environment, database, sandbox, and API together.

## Accounts and instructor access

The local prototype seeds `instructor / instructor` and `student / student`.
The Flutter application signs in through `/auth/login` and sends an opaque
Bearer session token. Instructor APIs verify the instructor role. The
`ADMIN_API_TOKEN` option is retained only for compatibility with older API
clients and is not used by the current Flutter instructor interface.

These password accounts are persistent prototype accounts and may use the
analytics catalog. The credential-free `/auth/demo` session is the only
ephemeral demo identity; it cannot create persistent research records.

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

You can edit `data/study_accounts.json` directly in VS Code or Notepad. Add a
row to create an account, enter a new `temporary_password` to change its
password, or set `"active": false` to remove its login access while preserving
its study records. To rename a login ID safely, add the new ID and deactivate
the old ID. Do not commit this ignored file because it can briefly contain
plain-text temporary passwords.

Email/reset features are disabled by default for the v4 professor demo. If they
are enabled in a later release, configure SMTP settings in `.env` to deliver one-time activation and reset
links. When SMTP is not configured, development messages stay in the in-memory
test outbox and no email is delivered. `GET /admin/email/status` reports the
configuration without exposing credentials, and `POST /admin/email/test` sends
a real test message. Instructor invitation/reset actions return an explicit
configuration error until SMTP is ready instead of claiming that an outbox
message was delivered.

Instructor publishing runs the server-side reference solution through the hidden
grader. Invalid assignments remain drafts.

## Phase 1 research analytics

`GET /research/me` returns a student's own overview and version-specific
assignment summaries. `GET /research/me/attempts` is the paginated history.
Instructor equivalents are available under `/admin/research/`, and exports now
include participant-assignment and class-assignment datasets. Authenticated
clients can read the 55 implemented definitions from `GET /research/metrics`.

The browser heartbeat remains 30 seconds and is sent only while visible and
recently interactive within the 15-minute idle window. New submissions store a
nullable active-time snapshot. Old attempts are never backfilled with invented
time and display as `Not available`.

## Database lifecycle

The root launcher starts PostgreSQL 17 in a computer-local Docker volume. It
runs Alembic before the API starts. On the first PostgreSQL setup, if no
synchronized backup exists and the target is empty, the launcher copies every
row from the canonical ignored `robotics_lab_staging.db` without modifying that
SQLite source.

While the managed stack is running, `scripts/backup-local-database.ps1` creates
a PostgreSQL custom-format dump every 10 minutes when the database change
position advances. It validates the dump with `pg_restore --list` and verifies
its SHA-256 checksum. `scripts/stop-local.ps1` always writes the final dump to
`local_handoff_package`, keeps the preceding successful backup, releases the
device lock, and then stops PostgreSQL. A new computer restores the verified
dump before the API starts. The same dump is restored if the current computer's
Docker volume is recreated and the application schema is missing. This is a
sequential device handoff, not simultaneous database use.

On an empty database, the existing `assignments/assignment_*.json` files are
imported with their declared versions. A newer bundled assignment version may
upgrade an older database seed; otherwise instructor edits remain authoritative
and are never overwritten at startup. Instructor changes automatically increase
the assignment version when teaching, execution, grading, tutoring, or
simulation content changes.

## Tests

From the repository root, run `scripts/verify-local.ps1`. It resolves the
device-local Python environment and performs the complete backend, frontend,
database-handoff, sandbox, and repository checks.
