# V5.2 Research Analytics Phases

## Current status

Phase 1 Basic Analytics is implemented in staging. Phase 2 and Phase 3 are a
roadmap only and are intentionally absent from the application until their data
and research rules are ready.

The implementation evidence is recorded in the
[V5.2 Basic Analytics SQA report](../sqa/V5_2_BASIC_ANALYTICS_SQA_REPORT_2026-08-26.md).

| Phase | Scope | Application status |
| --- | --- | --- |
| Phase 1: Basic | Direct progress, scores, attempts, time, safe errors, basic tutor use, assignment summaries, and data health | Implemented |
| Phase 2: Moderate | Revisions, recovery, objectives, misconceptions, detailed tutor use, surveys, study conditions, and operations | Documented only |
| Phase 3: Advanced | AI quality, experimental comparisons, effect sizes, confidence intervals, retention, and thesis-level analysis | Documented only |

## Phase 1 metric IDs

- Population: `POP-01`, `POP-03` through `POP-08`
- Outcomes: `OUT-01` through `OUT-05`, `OUT-07` through `OUT-12`, `OUT-15`
- Attempts: `ATT-01` through `ATT-03`
- Time: `TIME-01` through `TIME-05`, `TIME-09`, `TIME-10`
- Errors: `ERR-01` through `ERR-08`, `ERR-16`
- Tutor: `TUT-01`, `TUT-02`, `TUT-04`
- Assignment: `ASG-01` through `ASG-06`
- Data health: `SYS-09` through `SYS-15`, `SYS-18`

The versioned machine-readable definitions are returned by authenticated
`GET /research/metrics`. Only the 55 implemented Phase 1 definitions are
returned. The executable definitions live in `backend/metric_catalog.py`.

## Phase 2 metric IDs

`POP-02`, `POP-09`, `POP-10`; `OUT-13`, `OUT-14`; `ATT-04` through
`ATT-12`; `TIME-06` through `TIME-08`, `TIME-11`, `TIME-12`; `ERR-09`
through `ERR-15`; `LRN-01` through `LRN-08`; `TUT-03`, `TUT-05` through
`TUT-18`; `ASM-01` through `ASM-03`; `SUR-01` through `SUR-04`, `SUR-06`,
`SUR-07`; `ASG-07`, `ASG-09`, `ASG-11`, `ASG-12`; `SYS-01` through
`SYS-08`, `SYS-16`, `SYS-17`.

## Phase 3 metric IDs

`OUT-06`; `AIQ-01` through `AIQ-12`; `ASM-04` through `ASM-06`; `SUR-05`;
`ASG-08`, `ASG-10`; `CMP-01` through `CMP-15`.

Together the three phases account for all 161 candidate metrics in the formal
metric dictionary.

## Phase 1 visibility

| Audience | Can see | Cannot see |
| --- | --- | --- |
| Student | Own overview, assignment/version summaries, and safe attempt history | Other students, class comparisons, hidden-test data, source snapshots, operational data health |
| Instructor | Classroom, participant, assignment, hidden-test aggregate, and data-health summaries | Hidden-test identities/content, passwords, login IDs, API keys, official solutions in analytics |
| Demo student | Temporary in-browser progress | Persistent research analytics or exports |

## Time rules

- The browser sends a heartbeat every 30 seconds only when the page is visible
  and the student has interacted within the previous 15 minutes.
- `assignment_activities` stores one record per student, assignment ID, and
  exact assignment version.
- Active time is accumulated across sessions.
- Completion is the first valid `passed=true` Run or Submit attempt.
- Active completion time freezes the activity counter at first success.
- Elapsed completion time is first success time minus first tracked activity.
- Attempts recorded before Phase 1 have no fabricated timing. The UI displays
  `Not available`, and exports contain a null value plus availability status.

## Research rules

- PostgreSQL submissions remain the grading and attempt authority.
- Infrastructure failures are excluded from valid-attempt score calculations.
- Assignment versions are never combined.
- Current active students are treated as assigned to all current published
  assignments until Phase 2 introduces study/cohort assignment.
- AI interaction metrics describe optional tutor use only. They never affect
  deterministic test-case grades.
