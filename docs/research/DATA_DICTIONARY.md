# Robotics Programming Lab Data Dictionary

## Purpose

This document explains what the platform stores, where it is stored, and how to
inspect it safely. Data contract version `1` is implemented in
`backend/data_contracts.py`. The application validates structured JSON before
writing it to SQLite or PostgreSQL.

## Simple mental model

```text
Assignment = what the instructor gives the student
Submission = one intentional Run tests or Submit action
Grader evidence = what the deterministic tests observed
Study session = one period when a student uses the application
Learning event = an important action inside that session
Hint interaction = feedback requested for one submission
```

These records are connected by IDs. For example, a submission contains the
assignment ID and exact assignment version, so results remain interpretable
after an instructor updates the assignment.

## Where local data is stored

| Data | Local location | Format | Human-readable? |
|---|---|---|---|
| Assignment source definitions | `backend/assignments/assignment_1.json` through `assignment_6.json` | JSON | Yes, open directly in VS Code |
| Active local application database | Computer-local Docker volume `robotics-lab-local_robotics_postgres_data` | PostgreSQL 17 | Use the application or an authorized PostgreSQL client |
| Cross-device database handoff | `local_database_backups/latest.dump` plus `latest.json` | Verified PostgreSQL logical backup | Restore through `scripts/run-local.ps1` |
| Legacy local source preserved during first migration | `backend/robotics_lab_staging.db` | SQLite | Read-only; not used by the default launcher after migration |
| Student editor draft | Browser storage, keyed by assignment ID and assignment version | Local JSON preferences | View through the matching assignment workspace; older-version drafts are ignored |
| Optional prototype account import | `backend/data/study_accounts.json` | JSON | Yes, but it can contain temporary passwords and is ignored by Git |
| Safe account-import example | `backend/data/study_accounts.example.json` | JSON | Yes |
| Research exports | Downloaded from the instructor Research Dashboard | CSV or Excel | Yes |
| Data definitions and validation | `backend/data_contracts.py` | Python | Yes; this is the executable contract |
| Database table definitions | `backend/models.py` | Python/SQLAlchemy | Yes |
| Database schema history | `backend/migrations/versions/` | Alembic/Python | Yes |

The active PostgreSQL files stay inside Docker and are never synchronized by
OneDrive. `scripts/stop-local.ps1` exports a complete validated dump, checksum
manifest, and previous backup into the ignored OneDrive handoff directory.
The launcher restores the verified dump for a new device, a newer synchronized
backup, or a recreated same-device volume with no application schema.
PostgreSQL is the source of truth. Never edit a dump or live database file.

## How to see local data

1. Start the staging application with `scripts/run-local.ps1`.
2. Use **My study progress** as a student or **Research study dashboard** as an
   instructor.
3. For authorized technical inspection, connect a trusted PostgreSQL client to
   `127.0.0.1:5432`, database `robotics_lab`, while the app is running.

For ordinary study review, the safer option is the application itself:

- Student: account menu, then **My study progress**.
- Instructor: instructor studio, then **Research study dashboard**.
- Instructor export: download summary, attempts, events, or the Excel workbook.

Do not share handoff dumps or live production access. Authorized production
inspection should use the Neon SQL Editor and participant codes.

## Main tables

### `assignments`

One row describes the current form of an assignment.

| Field | Meaning |
|---|---|
| `id` | Internal numeric assignment ID |
| `stable_id` | Permanent readable identity, such as `ros2-obstacle-stop` |
| `version` | Content version shown to students and saved with attempts |
| `data_schema_version` | Version of the JSON structure; currently `1` |
| `title`, `description`, `assignment_html` | Instructor-facing learning content |
| `starter_code` | Code initially shown to the student |
| `learning_objectives` | Structured list of intended learning outcomes |
| `execution_settings` | Runtime, timeout, imports, network, and editable-file settings |
| `public_tests` | IDs and labels safe to show students |
| `rubric` | Criteria, descriptions, and weights |
| `misconceptions` | Known misunderstanding tags and descriptions |
| `tutoring_rules` | Hint limits and solution-protection rules |
| `simulation_config` | Optional simulation settings |
| `asset_manifest` | Project files and which file may be edited |
| `grader_type`, `grader_config` | Server-side grader selection and protected settings |

### `submissions`

One row represents one deliberate code execution.

| Field | Meaning |
|---|---|
| `id` | Unique attempt identifier |
| `assignment_id`, `assignment_version` | Exact assignment attempted |
| `data_schema_version` | Structure version for the stored evidence |
| `user_id`, `study_session_id` | Links to the authenticated student and session |
| `mode` | Standard value: `run` or `submit` |
| `code` | Protected student source code; never included in research exports |
| `execution_succeeded` | Whether execution completed |
| `execution_status` | Standard failure/success category |
| `passed`, `score` | Deterministic grader result |
| `evidence` | Versioned test evidence and safe execution details |
| `created_at` | UTC attempt time |

Standard `execution_status` values are:

| Value | Simple meaning |
|---|---|
| `completed` | The program ran and grading completed |
| `syntax_error` | Python could not parse the code |
| `runtime_error` | The code started but failed while running |
| `timeout` | Execution exceeded its limit |
| `rejected` | A safety or request rule rejected the code |
| `grader_unavailable` | The isolated grader could not be reached or started |
| `internal_error` | The grader returned an invalid/internal response |
| `execution_error` | A legacy failure without enough detail to classify safely |

### `study_sessions`

One row represents a period of active student use. It stores a participant-code
snapshot, start/end times, last activity, and capped active seconds.

### `learning_events`

One row represents an allowlisted learning action. Assignment-related events
must include both assignment ID and version.

Standard event types are:

- `assignment_opened`
- `assignment_run`
- `assignment_submitted`
- `hint_requested`
- `solution_revealed`
- `ai_tutor_toggled`
- `workspace_tab_changed`
- `workspace_file_selected`

Each event type has a small approved metadata shape. Extra fields are rejected,
which prevents passwords, source code, or arbitrary browser data from being
stored accidentally.

For `hint_requested`, `interaction_type` distinguishes a progressive hint from
a `student_question`. Question events store only the question length, hint
level, and tutor source. The student's question text is not written to the
learning-event record.

### `hint_interactions`

Connects a structured tutor response and hint level to one submission. The
response may contain a diagnosis, short answer, debugging steps, guiding
question, next action, source, and solution-protection flag. For student
questions, the stored response also records `interaction_type` but does not
store the raw question. Demo sessions do not create persistent hint rows.

## Assignment JSON fields

Every assignment is normalized into the same fields before database storage.
Older Assignments 1-4 may omit optional fields in their source JSON because the
repository supplies validated defaults. Assignments 5-6 declare the complete
configuration explicitly. All assignment files declare
`"data_schema_version": 1`.

## Version and integrity rules

- Assignment content versions and data-schema versions must be positive.
- Every stored submission receives its assignment version from the server.
- Browser code drafts are loaded only when their saved assignment version
  matches the version currently returned by the server.
- Assignment-related events require assignment ID and version together.
- The server rejects events for a version that is no longer current.
- Submission modes and execution statuses use allowlisted values.
- Alembic migration `0003_standardize_existing_data` adds and backfills the
  standardized columns without deleting existing research rows.

## Privacy boundary

The database contains protected operational data that is intentionally absent
from research exports. Never export or share passwords, password hashes, login
IDs, session tokens, student source code, hidden tests, grader configuration,
official solutions, or API keys. Research views and exports use participant
codes.
