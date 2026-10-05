# Robotics Programming Lab Data Dictionary

## Purpose

This document explains what the platform stores, where it is stored, and how to
inspect it safely. Data contract version `1` is implemented in
`backend/data_contracts.py`. The application validates structured JSON before
writing it to Neon PostgreSQL. Disposable automated tests may use SQLite.

## Simple mental model

```text
Assignment = what the instructor gives the student
Submission = one intentional Run tests or Submit action
Grader evidence = what the deterministic tests observed
Study session = one period when a student uses the application
Assignment activity = version-specific active time for one student
Learning event = an important action inside that session
Hint interaction = feedback requested for one submission
Quiz attempt = one complete course-quiz submission, graded by the server
```

These records are connected by IDs. For example, a submission contains the
assignment ID and exact assignment version, so results remain interpretable
after an instructor updates the assignment.

## Where data is stored

| Data | Local location | Format | Human-readable? |
|---|---|---|---|
| Assignment source definitions | `backend/assignments/assignment_1.json` through `assignment_6.json` | JSON | Yes, open directly in VS Code |
| Active staging application database | Neon database `robotics_lab_staging` | PostgreSQL | Use the application or authorized Neon SQL Editor |
| Private local configuration | `.env` in the repository root | Ignored environment settings | Read directly by the launcher and backend |
| Historical local databases and dumps | Archived outside the active checkout | SQLite or PostgreSQL dump | Recovery evidence only; never used by the application |
| Student editor draft | Neon PostgreSQL with a browser fallback, keyed by authenticated user, assignment ID, and assignment version | `code_drafts` table plus local JSON preferences | View through the matching assignment workspace; another login and older versions are isolated |
| Password-free prototype account roster | `backend/data/study_accounts.json` | JSON | Yes; tracked by Git, with `temporary_password` always `null` |
| Research exports | Downloaded from the instructor Research Dashboard | CSV or Excel | Yes |
| Data definitions and validation | `backend/data_contracts.py` | Python | Yes; this is the executable contract |
| Database table definitions | `backend/models.py` | Python/SQLAlchemy | Yes |
| Database schema history | `backend/migrations/versions/` | Alembic/Python | Yes |

Neon PostgreSQL is the staging source of truth. Authorized computers connect to
the same database through the ignored `.env`; OneDrive and Git never carry the
live database. Local PostgreSQL dumps are not part of the current architecture.

## How to see local data

1. Start the staging application with `scripts/run-local.ps1`.
2. Use **My study progress** as a student or **Research study dashboard** as an
   instructor.
3. For authorized technical inspection, use the Neon SQL Editor for the
   `robotics_lab_staging` database.

For ordinary study review, the safer option is the application itself:

- Student: account menu, then **My study progress**.
- Instructor: instructor studio, then **Research study dashboard**.
- Instructor export: download summary, attempts, events, or the Excel workbook.

Do not share database credentials or live production access. Authorized production
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
| `simulation_config` | Optional simulation settings; `diagram` describes the playground drawing |
| `asset_manifest` | Project files and which file may be edited |
| `grader_type`, `grader_config` | Server-side grader selection and protected settings |

### `code_drafts`

One row stores the latest unfinished code for one authenticated student and one
exact assignment version. Saving a newer draft updates that row. Demo sessions
never write to this table.

| Field | Meaning |
|---|---|
| `id` | Unique draft identifier |
| `user_id` | Authenticated owner; drafts cannot be read across accounts |
| `assignment_id`, `assignment_version` | Exact assignment content the draft belongs to |
| `code` | The student's unfinished source code |
| `created_at`, `updated_at` | Draft creation and latest-save times |

The browser copy is a fallback for temporary connectivity problems. The
PostgreSQL row is the authoritative cross-device draft for persistent accounts.

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
| `active_seconds_at_attempt` | Phase 1 active-time snapshot; null for attempts recorded before tracking |
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

Each item in `evidence.tests` describes one grading check: `test_id`, `label`,
`passed`, `message`, and `visibility`. Function-assignment checks may also
store `weight` (the check's rubric points) and `reason`, a stable failure
category that never exposes protected cases. Older records omit both fields;
analyses must treat a missing value as not collected.

| `reason` value | Simple meaning |
|---|---|
| `passed` | The check passed for every grading scenario |
| `wrong_all_inputs` | The value was wrong for every grading scenario |
| `wrong_some_inputs` | The value was right for some scenarios but not all |
| `error_on_some_inputs` | The function raised an error during a grading scenario |
| `unsupported_type` | The returned value had a type the grader cannot compare |
| `not_checked` | The code failed before this check could be evaluated |

The **Try inputs** playground (`POST /assignments/{id}/playground`) is
practice only. It never creates submission, attempt, hint, learning-event, or
audit rows, and it never uses protected cases. Its response echoes the parsed
inputs as JSON (`arguments`; tuples become lists and dictionary keys become
text) so the browser can draw them.

An assignment's optional `simulation_config.diagram` block (provider
`diagram`) tells the playground what to draw. A `route` view lists points and
paths by function-argument index and labels each path with a returned-value
index; a `polar` view draws supplied readings, arcs, and rays. Optional
`checks` (`sum`, `min_label`) compare the student's returned values with each
other. Diagrams contain only indices, never expected answers, and the server
rejects inconsistent references when an assignment is saved.

`simulation_config.playground.parameters` describes each function input in
order: `name`, `kind` (`point`, `number`, `integer`, `list_of_points`,
`angle_map`, or `text`), `label`, `meaning`, `unit`, `example` (an input value
from the instructions' public example), and an optional display `group`. The
browser shows one labelled field per parameter, prefilled with its example.
Before running, the server checks each input's kind and returns HTTP 400 with
`details` entries carrying `parameter_index`, so the message appears on that
field. `playground.hints_enabled` (default true) lets instructors turn
consistency hints off. A v6.3 `sample_arguments` value is accepted and ignored.
`playground.scenarios` lists up to eight instructor-written presets (`id`, `label`,
`description`, and `values` keyed by parameter name). They hold inputs only:
the server requires exactly one valid value per parameter and rejects any other
key, so no expected output can be stored. The browser keeps the last three
successful runs in memory for comparison; they are never saved or sent.
Inputs that cannot be drawn are skipped and named under the diagram.

### `study_sessions`

One row represents a period of active student use. It stores a participant-code
snapshot, start/end times, last activity, and capped active seconds.

### `assignment_activities`

One row stores time for one student, assignment ID, and exact assignment
version. It records first/latest activity, accumulated active seconds, first
successful completion time, and active seconds accumulated before first
completion. The unique key prevents two versions from being mixed.

Historical attempts are not given invented timing. When an older attempt has no
matching activity row, the API returns null time values with
`not_collected`; the interface displays **Not available**.

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

### `course_quiz_attempts`

One row stores the score for one complete course-quiz submission by a
persistent student account. The server grades every quiz against the
server-only answer key in `backend/course_content/quiz_answers.json`; the
browser never receives the correct answers. Quiz scores are kept separate from
coding-assignment `submissions`.

| Field | Meaning |
|---|---|
| `id` | Unique quiz-attempt identifier |
| `user_id` | Authenticated student who submitted the quiz |
| `topic_id` | Course topic whose quiz was taken, such as `locomotion` |
| `quiz_version` | Exact quiz version answered; the server rejects submissions for an outdated version |
| `correct_count` | Number of questions answered correctly (at least `0`, at most `total_questions`) |
| `total_questions` | Questions in that quiz version (at least `10`) |
| `score_percent` | `correct_count / total_questions` as a rounded whole percentage, `0`–`100` |
| `submitted_at` | UTC submission time |

Only scores are stored. The chosen answers for each question are not written
to the database. Every question must be answered before the server grades the
quiz.

Demo sessions and instructor previews are graded but return `saved: false` and
never create rows; demo quiz progress lives only in the server's in-memory demo
session. Students can read their own 20 most recent attempts per topic through
`GET /contents/{topic_id}/quiz/attempts`. Quiz attempts are not currently part
of the research exports or the Phase 1 analytics metrics.

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
- Alembic migration `0004_basic_research_analytics` adds assignment activity
  tracking and nullable active-time snapshots without changing old attempts.
- Alembic migration `0006_course_quiz_attempts` adds the separate quiz-score
  table without changing coding-assignment submissions.

## Phase 1 analytics interfaces

| Interface | Purpose |
| --- | --- |
| `GET /research/metrics` | Versioned definitions for the 55 implemented basic metrics |
| `GET /research/me` | Student-self overview and assignment/version summaries |
| `GET /research/me/attempts` | Paginated student-self attempt history |
| `GET /admin/research/summary` | Classroom, participant, assignment, and data-health summaries |
| `GET /admin/research/students/{student_id}` | Instructor-authorized participant detail |
| `GET /admin/research/students/{student_id}/attempts` | Paginated instructor-authorized participant history |
| `GET /admin/research/assignments` | Filterable current assignment/version summaries |
| `GET /admin/research/export` | Privacy-safe CSV or Excel datasets, including Phase 1 assignment summaries |

The phase mapping and timing rules are in
`docs/research/V5_2_ANALYTICS_PHASES.md`.

## Privacy boundary

The database contains protected operational data that is intentionally absent
from research exports. Never export or share passwords, password hashes, login
IDs, session tokens, student source code, hidden tests, grader configuration,
official solutions, or API keys. Research views and exports use participant
codes.
