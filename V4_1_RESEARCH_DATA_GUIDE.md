# V4.1 Research Study Data Guide

## Purpose

V4.1 adds classroom-study evidence without changing assignment grading,
solution protection, authentication, or the optional AI tutor. PostgreSQL is
the live source of truth; local development uses the same models with SQLite
unless `DATABASE_URL` points to PostgreSQL.

## Data flow

```text
Student login
    -> study session
    -> visible-page heartbeat (30 seconds)
    -> assignment/version events
    -> run/submit evidence
    -> PostgreSQL
    -> student progress view
    -> instructor dashboard and exports
```

## Stored records

| Record | Important fields | Purpose |
|---|---|---|
| `study_sessions` | user, participant-code snapshot, start/end, active seconds | Measures active study time without counting hidden tabs |
| `learning_events` | session, assignment/version, event type, UTC time, limited metadata | Reconstructs the learning sequence |
| `submissions` | user/session links, assignment/version, score, result evidence | Connects intentional runs to the research session |

The platform records assignment open, run/submit, hint request, worked-solution
reveal, AI tutor toggle, and mobile workspace-tab changes. It does not record
keystrokes. Student code remains part of the protected submission record for
grading but is excluded from research dashboards and exports.

## Viewing data

- Student: account menu -> **My study progress**
- Instructor: instructor studio -> **Research study dashboard**
- Raw database: Neon SQL Editor for authorized technical inspection
- Export: student summary CSV, assignment attempts CSV, learning events CSV,
  or a three-sheet Excel workbook

## Privacy and data quality

- Research screens and exports use unique participant codes, not login IDs.
- Password hashes, temporary passwords, auth tokens, API keys, hidden tests,
  official solutions, and submitted source code are never exported.
- Missing participant codes receive a stable `UNASSIGNED-XXXXXXXX` label.
- Timestamps are UTC; assignment versions are stored with attempts and events.
- Raw learning events are append-only through the public API.
- Event types are allowlisted, event metadata is size limited, heartbeat time is
  capped at 60 seconds per request, and students can access only their own data.

## Instructor checklist before a study

1. Assign a unique participant code to every study account.
2. Confirm staging and live use separate databases.
3. Run the SQA workbook checks for research capture and export privacy.
4. Export a small test dataset and verify the participant codes.
5. Define the retention/deletion period in the approved study protocol.

## Research endpoints

```text
POST /research/sessions
POST /research/sessions/{session_id}/heartbeat
POST /research/sessions/{session_id}/events
POST /research/sessions/{session_id}/end
GET  /research/me

GET  /admin/research/summary
GET  /admin/research/students/{student_id}
GET  /admin/research/export
```
