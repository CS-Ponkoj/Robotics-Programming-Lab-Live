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
| `id` | Internal numeric assignment ID. It is the identity in every attempt, event, and export. From 2026-11-19 students may instead see a course number (`backend/assignments/catalog.json` `course_numbers`, for example Assignment 7 shown as 1 and Assignment 8 as 2); that number is presentation only and is never stored |
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
| `simulation_config` | Optional simulation settings; `diagram` describes the playground drawing, and `provider: ros2_2d` with a `world` (walls, robot start, duration, optional `wall_move`) enables the ROS 2 robot replay. An assignment whose `grader_config` sets `flbr_topic` (Assignment 8) receives the course's four-sector summary (`rse_msgs/Flbr`) computed from the same simulated scan |
| `asset_manifest` | Project files and which file may be edited |
| `grader_type`, `grader_config` | Server-side grader selection and protected settings |

### `code_drafts`

One row stores the latest unfinished code for one authenticated student and one
exact assignment version. Saving a newer draft updates that row. Demo sessions
never write to this table.

The editor saves each change on the device at once and to this table about a
third of a second later, and again when the student leaves the workspace. A
device copy the server has not confirmed is restored and sent the next time the
student opens that assignment on that device. The student assignment list
reports `has_saved_draft` (computed from this table, never stored) so the home
page shows **Continue assignment** on any computer.

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
| `feedback_mode` | Feedback mode the account had when this attempt ran (`traditional`, `tdd`, `tdd_ai`); null for attempts before migration 0010 |
| `created_at` | UTC attempt time |

Standard `execution_status` values are:

| Value | Simple meaning |
|---|---|
| `completed` | The program ran and grading completed |
| `syntax_error` | Python could not parse the code (including `IndentationError` and `TabError`, classified this way from 2026-11-22) |
| `runtime_error` | The code started but failed while running |
| `timeout` | Execution exceeded its limit |
| `rejected` | A safety or request rule rejected the code |
| `grader_unavailable` | The isolated grader could not be reached or started |
| `internal_error` | The grader returned an invalid/internal response |
| `execution_error` | A legacy failure without enough detail to classify safely |

`evidence.error_frames` lists the student's own call stack when their code
raised, outermost call first: each entry is a `line` number and a function
`name` (`<module>` for top-level code). When a grading scenario's call into
the student's function raised, only frames within the student's own lines are
kept; the grader's call line is dropped. It never holds values, source text,
or worker internals, is capped at 20 entries, and is always empty for syntax
errors, rejected code, and records saved before it existed. The editor
terminal uses it to print a Python-style traceback; research exports do not
include it.

For a grading-scenario crash, `execution_error` names the exception class and
adds Python's message only when it cannot echo a hidden input: a `NameError`
or `UnboundLocalError` naming an identifier the student wrote, or a fixed
`ZeroDivisionError` or `RecursionError` message. Records saved before
2026-10-14 name only the class.

Each item in `evidence.tests` describes one grading check: `test_id`, `label`,
`passed`, `message`, and `visibility`. Function-assignment checks may also
store `weight` (the check's rubric points) and `reason`, a stable failure
category that never exposes protected cases. ROS 2 checks also store `weight`
from 2026-10-05. Two further optional fields were added on 2026-10-05:
`earned_weight` records points actually counted when they differ from
`passed` times `weight` (a ROS check whose supplied-scaffold credit is held
back until a behavior check passes stores `0`; otherwise it is null), and
`misconception_tag` names the assignment's configured misconception tag for a
function-assignment check that returned a wrong value (null when the check
passed, crashed, or has no tag). Older records omit these fields; analyses
must treat a missing value as not collected.

From 2026-11-18, a failed Assignment 7 behavior check may also store
`hint_key`, the pattern the grader observed in the student's own published
commands (`speed-too-high`, `speed-too-low`, `infinity-treated-as-obstacle`,
`stops-too-early`, `stops-too-late`, `wrong-threshold-direction`,
`must-drive-first`, `does-not-resume`, `turns-while-driving`,
`publishes-too-rarely`, or `build-node-returns-none`), and its `message` ends
with one sentence stating that observation (for example the `linear.x` the
robot published). `hint_key` selects the built-in hint ladder; it is not a
research label. Only a `hint_key` that is also one of the assignment's
configured misconception tags is copied into `misconception_tag` for a ROS 2
check. Null or missing means no pattern was recognised.

From 2026-11-19, a failed Assignment 8 (turn toward the open side) behavior
check may store one of these `hint_key` values in the same way:
`turns-while-clear`, `forward-speed-wrong`, `front-check-reversed`,
`turn-direction-swapped`, `no-turn-when-blocked`, `same-turn-every-time`,
`threshold-boundary`, `tie-goes-left`, `nan-side-chosen`,
`open-side-no-resume`, `not-wired`, `silent-callback`, or
`skips-clear-messages`. The Assignment 8 harness also reports `started`,
`subscribed`, and `alive` (booleans) in its observations; they are not stored.

From 2026-11-22 the observation sentence added to a check `message` states
only what the robot or node did; advice on how to fix it moved to the hint
ladders, which only the `tdd_ai` mode receives. Records saved earlier may end
with advice. New `hint_key` values from that date: `never-drives` (Assignment
7: the robot published `linear.x` 0.0 in every situation, which earlier
records may label `stops-too-early`, `must-drive-first`, or
`does-not-resume`), `stop-distance-at-boundary` (Assignment 7: stopped with
the wall 0.2 m away but not 0.3 m away), `sensor-ignored` and `main-modified`
(Assignment 7: the `reads-ranges` or `main-unchanged` source check failed;
`sensor-ignored` is also set on stop checks of a publishing node that never
reads `scan.ranges`), and for Assignment 8 `drives-when-blocked` (kept driving
with the front 0.5 m away) and `never-moves` (published only zero commands).
`one-command-contract` (both assignments) marks a failed one-command-per-
callback check (`one-command-per-scan`, `flbr-response`) and, when the node
also published from outside its callback, the behaviour checks whose
commands were mixed by it.
`publisher-queue-depth` (both assignments) is used instead when the /cmd_vel
publisher's queue depth is not the required 10, and `extra-axes` (Assignment
8) marks failed behaviour checks of a node that set linear.y, linear.z,
angular.x or angular.y.
`sensor-ignored` and `main-modified` are configured Assignment 7 tags, so they
now also reach `misconception_tag`. Interpretation changes from the same date:
no behaviour `hint_key` is stored when no command was observed during the
checked situations (crash, hang); `publishes-too-rarely` is stored on
behaviour checks when the node published below 5 commands per second;
`does-not-resume` requires that the robot drove with the wall 1.2 m away; and
Assignment 8 checks the reversed front comparison first, so
`front-check-reversed` replaces the earlier `turns-while-clear` and
`no-turn-when-blocked` labels for that pattern. Checks the grader marks as not
run never store a `hint_key`.

For a ROS 2 assignment whose `grader_config` lists `gate_tests` and
`pass_tests` (Assignment 7 onward), `score` is 0 whenever any gate check
fails, and `passed` means every gate check and every listed pass check passed;
other checks (code contract and code quality) add to `score` but do not decide
`passed`. For every other assignment, `passed` still means every check passed.
Assignment 7 also records read-only source checks of the submitted code
(allowed imports, `build_node()` present, reads `scan.ranges`, no blocking
loop or `sleep()`, unchanged `main()`, named constants, no unused imports) as
ordinary `evidence.tests` items. They are computed in the grader container and
store only the pass/fail result and a fixed message, never source text.

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
- `simulation_run`

Each event type has a small approved metadata shape. Extra fields are rejected,
which prevents passwords, source code, or arbitrary browser data from being
stored accidentally.

For `hint_requested`, `interaction_type` distinguishes a progressive hint from
a `student_question`. Question events store only the question length, hint
level, and tutor source. The student's question text is not written to the
learning-event record; from 2026-11-24 it is kept in `hint_interactions`
instead (see below).

`assignment_run` and `assignment_submitted` also store `feedback_mode`, the
account's mode at that moment, so moving a student to another mode never
changes the meaning of earlier events.

From 2026-11-22 study student accounts can no longer reveal an assignment's
solution approach in any mode (owner decision), so new `solution_revealed`
events come only from instructor accounts; the public demo never records
events. Earlier `solution_revealed` rows remain valid history.

### Feedback modes (`users.feedback_mode`)

An instructor assigns each student account one study condition on the Accounts
page. New and existing accounts start as `tdd`. Instructors always see
`tdd_ai`, and the public demo is always `tdd`. The server enforces each mode;
grading is identical in all three.

| Value | Label | What the student receives |
|---|---|---|
| `traditional` | Traditional | Score, pass state, and how many checks passed (from 2026-11-22 the per-check pass list is returned passed-first and the assignment payload omits the public check labels, so the order cannot name a failed check). Build and runtime errors at the student's own line still show. Plain simulation replay (since 2026-11-20) without the beam probe, printed output, or links from failed checks. No check names or messages, printed output, hints, or tutor |
| `tdd` | TDD | Everything above plus check names and messages, printed output, and the full simulation replay (beam probe and links from failed checks). No hints (since 2026-11-20; the server switch `TDD_BUILT_IN_HINTS` restores the built-in hint ladder), no tutor questions or AI. The public demo is `tdd` but keeps built-in hints |
| `tdd_ai` | TDD + AI | Everything in `tdd` plus hints: the AI tutor and Ask the tutor, still subject to the AI policy gates, with the built-in hint ladder as the fallback |

Each change is an append-only `student.feedback_mode_changed` audit event with
the previous and new mode, the instructor, and the time. Research exports carry
`feedback_mode` on each attempt row and the current mode on the student summary.
The app shows each mode in its own theme colour for students (Traditional blue,
TDD green, TDD + AI teal, each as a gradient); instructors use bronze.

`simulation_run` is recorded when a signed-in student in a study session presses
Simulate on an assignment with a `ros2_2d` simulation. It stores only `outcome`
(`collided`, `never_moved`, `stopped`, `stopped_and_resumed`, `kept_driving`, or
`error`), `duration_seconds`, and from 2026-11-24 `feedback_mode` (the account's
mode at that moment; empty on earlier rows). The replay is visual only: it creates no
submission, score, or test evidence, and the trace and source code are not stored.
Demo sessions record nothing.

### `hint_interactions`

Connects a structured tutor response and hint level to one submission. The
response may contain a diagnosis, short answer, debugging steps, guiding
question, next action, source, and solution-protection flag. Demo sessions do
not create persistent hint rows.

| `data_schema_version` | What the `feedback` JSON adds |
|---|---|
| 1 (until 2026-11-23) | `interaction_type` only on `student_question` rows; the question text was not stored |
| 2 (from 2026-11-24) | `interaction_type` on every row: `run_hint` (automatic hint after a run), `progressive_hint` (Hint button), or `student_question` (Ask the tutor). `student_question` rows also keep `student_question`, the exact text the student typed (3-500 characters), by owner decision so instructors can review it beside the answer shown |

Questions typed before 2026-11-24 were never stored and cannot be recovered;
only their length is in the `hint_requested` event. The question text is free
student writing, so the consent form should say it is kept.
From 2026-11-18 the daily AI quota counts a student's rows from the current
UTC day whose stored `source` is `openai`; built-in (`fallback`) answers are
never counted.

### Instructor Study data page (from 2026-11-24)

Instructors see every table above in the app (Instructor Studio, Study data)
and can download each filtered table as CSV
(`GET /admin/study-data/{table}?format=csv`). Tables: participants, AI questions
and hints, attempts, check results, learning events, time per assignment,
assignment summary, study sessions, sign-ins, quiz and pre-test attempts, quiz
answers, course learning per topic, instructor actions, and page feedback.
Rows use participant codes, never login IDs. The owner's test logins
(`traditional`, `tdd`, `ai`, and the seeded `student` / `DEMO` row) are hidden
unless "Include test accounts" is on. Submitted code is never in a table or
CSV; an instructor can open one attempt's code in the app, which writes a
`study_data.code_viewed` audit event. Each CSV download writes a
`study_data.exported` audit event with the table and filters (no participant
identity). Instructor-action rows drop login IDs and emails from audit details,
and name the table or attempt they concern.

Table rules (2026-11-24 data review):

- Participants count help apart: `tutor_questions`, `hint_button` (requested),
  `automatic_hints` (shown after a run; exposure, not a request),
  `hints_type_not_recorded` (before 2026-11-24), and `ai_answers` (answers
  whose source was the AI; the rest were built-in).
- Check results: `points_earned` is the credit the check gave (its weight when
  passed, 0 when failed, not run, or held back); `reason` is the grader's
  structured reason.
- Learning events: `mode_source` says whether the mode was recorded with the
  event, taken from its attempt, or is the account's current mode (for events
  that never stored one, such as `assignment_opened`).
- Quiz answers carry the stored `question_id` and the quiz `attempt_id`.
- Assignment summary shows this course's assignments (those with a course
  number) unless an assignment is chosen, so old assignments do not inflate
  "not started" counts.
- Participants, assignment summary, and course learning are whole-study
  summaries; the date filter does not apply to them.
- Assignment summary help counts come from learning events:
  `built_in_hint_count` is Hint button requests answered by built-in hints
  (automatic run hints and tutor questions are not counted), and
  `ai_interaction_count` is runs made with the AI switch on plus hints the AI
  answered. For every help row, use AI questions and hints.
- Quiz attempts carry `attempt_id`, which joins to quiz answers.
- Every `*_at` value in every table is UTC ISO 8601 to the second with an
  offset (for example `2026-11-24T09:41:59+00:00`).
- A CSV larger than 200,000 rows is refused with a message to narrow the
  filters; it is never cut short.

### `course_quiz_attempts`

One row stores one complete course-quiz or pre-test submission by a
persistent student account. The server grades it against the server-only
answer key in `backend/course_content/quiz_answers.json`. A quiz page never
carries the answers; after a complete quiz submit the response names each
correct option and, where the topic provides one, an explanation from
`quiz_explanations.json`. A pre-test response returns only the score. Scores
are kept separate from coding-assignment `submissions`.

**Scoring rule.** A topic's quiz score is the student's first submitted
attempt of the current quiz version, taken before any correct answers were
shown; later attempts are practice and never replace it. The pre-test is one
attempt per student and topic, taken before the lesson (a second submit is
rejected with 409). The learning gain for a topic is the first-attempt quiz
score minus the pre-test score.

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
| `assessment` | `quiz` (after the lesson) or `pretest` (one attempt, before the lesson); rows from before migration `0011` are `quiz` |
| `feedback_mode` | The student's feedback mode (`traditional`, `tdd`, `tdd_ai`) at submission; null on rows from before migration `0011` |
| `answers` | JSON list in question order: `{"question_id", "choice", "correct"}`; null on rows from before migration `0011` |
| `data_schema_version` | Version of the `answers` format; currently `1` |

Every question must be answered before the server grades the quiz or
pre-test.

Demo sessions and instructor previews are graded but return `saved: false` and
never create rows; demo quiz progress lives only in the server's in-memory demo
session. Students can read their own 20 most recent quiz attempts per topic,
each marked `scored` when it is the first attempt of its version, and the
current `learning_score`, through `GET /contents/{topic_id}/quiz/attempts`;
`GET /contents/{topic_id}/pretest` reports whether they have taken the
pre-test and its score.

The research export adds two sheets built from this table:
`course_assessment_attempts` (one row per attempt: participant code, topic,
assessment, quiz version, attempt number, `scored`, feedback mode, counts,
score, `choices` such as `B,C,A,...`, `correct_pattern` such as `1101...`,
submission time, `data_schema_version`) and `course_learning_summary` (per
participant and topic: `pretest_score`, `quiz_score` from the first attempt,
`learning_gain`, `quiz_attempts`, `best_quiz_score`, and the feedback mode of
the first attempt). From 2026-11-24 `learning_gain` is computed from the
correct counts (quiz percent minus pre-test percent, one decimal), not from the
two rounded percentages; before that a 5/15 to 10/15 change showed 34 instead
of 33.3. The instructor's participant page shows the same summary.
Quiz attempts are not part of the Phase 1 analytics metrics.

### `page_feedback`

One row stores one bug report or suggestion sent from the **Feedback** button
shown on every signed-in page. Instructors read and resolve it from
**Instructor Studio → Feedback** (`GET /admin/feedback`,
`PATCH /admin/feedback/{id}`).

| Field | Meaning |
|---|---|
| `id` | Unique feedback identifier |
| `user_id` | Account that sent it; empty for the public student demo, whose shared seeded account is never credited |
| `sender_role` | `student`, `instructor`, or `demo` |
| `page` | Page the sender was on, such as `Assignment 2: ...` or `Home: Contents` (up to 200 characters) |
| `category` | `bug`, `content`, `suggestion`, or `other` |
| `message` | The sender's text, 1–2000 characters |
| `status` | `new` or `resolved` |
| `created_at` | UTC time it was sent |
| `resolved_at` | UTC time an instructor marked it resolved; cleared when reopened |

Feedback is operational, not research data: it is not part of the Research
dashboard exports or analytics. Instructors can still view and download it as
the Page feedback table on the Study data page. Each sender is limited to five messages per minute.

### `course_settings`

One row per course-wide instructor setting, changed in **Instructor Studio**.
A missing row means the default. Operational configuration, not research data.

| Field | Meaning |
|---|---|
| `key` | `ai_tutor` or `catalog` |
| `value` | `ai_tutor`: `{"enabled": bool, "daily_limit": 1-200}` (defaults `false`, `20`). `catalog`: `{"old_stable_ids": [stable ID] or null}`, the assignments grouped under Old assignments (null uses `backend/assignments/catalog.json`) |
| `updated_by_user_id` | Instructor who changed it last; empty when changed with the admin token |
| `updated_at` | UTC time of the last change |

Each change of the AI tutor setting also writes an `audit_events` row with
action `ai_tutor_settings_changed` and the new values; each change of the
catalog writes `catalog_settings_changed`.

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
- Alembic migration `0007_page_feedback` adds the page-feedback table without
  changing any existing table.
- Alembic migration `0009_course_settings` adds the `course_settings` table
  without changing any existing table.
- Alembic migration `0008_session_device` adds a nullable `device` column
  (`phone`, `tablet`, or `computer`) to `auth_sessions`. Only that category is
  derived from the sign-in browser; the full User-Agent is never stored.
  Instructors see it, with sign-in and sign-out times, by selecting an account
  in Manage accounts. Sessions created before this migration show "Not
  recorded".

## Phase 1 analytics interfaces

| Interface | Purpose |
| --- | --- |
| `GET /research/metrics` | Versioned definitions for the 55 implemented basic metrics |
| `GET /research/me` | Student-self overview and assignment/version summaries |
| `GET /research/me/attempts` | Paginated student-self attempt history |
| `GET /me/assignment-progress` | Student-self progress summary per assignment (attempt count, best and latest score, current-version latest submission ID, solution revealed); read-only, rejected for instructors and demo sessions |
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
