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
settings directly from the ignored repository-root `.env`. Submission
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

An instructor can create student or instructor accounts, generate a temporary
password, reset access, and deactivate or reactivate accounts. The API prevents
self-deactivation and disabling the last active instructor. Accounts should be
deactivated instead of deleted so study records remain attributable.

The password-free prototype roster is tracked at `data/study_accounts.json`.
It may contain login IDs, roles, email fields, participant codes, and active
flags, but every `temporary_password` must remain `null`. Import it from the
instructor screen or `POST /admin/accounts/import`. The database is
authoritative: a missing JSON row does nothing, while `"active": false`
deactivates an existing account.

Create new accounts and set or reset passwords in Instructor Studio. Passwords
are hashed and stored in Neon, never in the tracked roster or Git history. To
rename a login ID safely, create the replacement account in Instructor Studio
and deactivate the old ID.

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

The root launcher uses the dedicated Neon `robotics_lab_staging` database when
`NEON_DATABASE_URL` exists in the ignored handoff `.env`. It runs Alembic before
the API starts, and every authorized computer sees the same committed accounts,
attempts, and analytics. The older Neon `neondb` database is separate.

The local application runtime supports Neon PostgreSQL only. Backend unit tests
may still use temporary SQLite databases for fast, isolated test fixtures; that
is not a supported application runtime mode.

On an empty database, the existing `assignments/assignment_*.json` files are
imported with their declared versions. A newer bundled assignment version may
upgrade an older database seed; otherwise instructor edits remain authoritative
and are never overwritten at startup. Instructor changes automatically increase
the assignment version when teaching, execution, grading, tutoring, or
simulation content changes.

## Tests

From the repository root, run `scripts/verify-local.ps1`. It resolves the
device-local Python environment and performs the complete backend, frontend,
Neon-configuration, sandbox, and repository checks.
