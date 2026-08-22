# Robotics Programming Lab: Product Vision, Architecture, and Delivery Plan

## Document purpose

This document is the shared reference for product ideas, architectural decisions,
team communication, delivery priorities, and release quality. It should be
updated whenever the platform scope, technology, assignment model, or release
criteria changes.

The companion [master SQA workbook](../sqa/Robotics_Programming_Lab_Master_SQA_Checklist.xlsx)
is the execution checklist for verifying every release.

## Product vision

Build a configurable robotics-programming learning platform where students can
learn by writing code, running safe simulations, receiving evidence-based
feedback, and progressing through increasingly sophisticated assignments.
Instructors should be able to create, validate, publish, version, and improve
assignments without requiring a new Flutter screen or backend route for every
lesson.

### North-star outcome

A student can move from an assignment description to a tested, understood
solution while an instructor can see that the assignment, grader, feedback, and
simulation are pedagogically correct, secure, reproducible, and versioned.

## Primary users

| User | Main goals | Required experience |
| --- | --- | --- |
| Student | Understand a robotics concept, write code, run tests, interpret evidence, request progressive help, and track progress | Clear instructions, responsive editor, fast grading, actionable evidence, protected solutions, persistent progress |
| Instructor | Create and revise assignments, configure grading and tutoring, validate content, publish versions, and review quality | Secure access, structured forms, validation-before-publish, stable IDs, version history, reusable graders |
| SQA reviewer | Verify functionality, correctness, security, accessibility, resilience, and release readiness | Repeatable checklist, expected results, evidence fields, severity/status controls, release gates |
| Platform maintainer | Extend graders, simulations, storage, workers, and deployment without breaking existing assignments | Modular interfaces, automated tests, configuration-driven content, observability, documented decisions |

## Product principles

1. Assignment content is configuration, not application code.
2. Every assignment has a stable ID and immutable version history.
3. Every submission records the exact assignment version it used.
4. Hidden tests, grader expectations, and official solutions stay server-side.
5. Student feedback is based on sanitized grader evidence.
6. AI tutoring is optional enhancement, not a dependency for grading.
7. The platform must remain usable when OpenAI, Redis, object storage, or a
   background worker is unavailable.
8. Simulation and code-only assignments use the same assignment lifecycle.
9. An assignment cannot be published until its reference solution and grader
   pass automated validation.
10. Release claims must be supported by reproducible evidence.

## Current implemented platform

### Student experience

- Required student or instructor sign-in with an opaque server-side session.
- Default local prototype student and instructor accounts.
- Forgot-password flow using a one-time email link.
- Assignment catalog containing four versioned robotics assignments.
- Progress summary and assignment state badges.
- Responsive desktop workspace with editor, instructions, and results panels.
- Responsive mobile workspace with Code, Instructions, and Results tabs.
- Python starter code editor and keyboard test execution.
- Public run and graded submission workflows.
- Structured score, pass/fail counts, terminal output, and per-test evidence.
- Optional AI tutoring toggle, disabled by default.
- Deterministic built-in tutoring fallback.
- Progressive hint levels 1 through 4.
- Worked-solution protection until a current-version submission exists.
- Persistent drafts, attempts, latest score, best score, submission ID, and
  solution-reveal state.
- Actionable loading, empty, and backend-error states.

### Instructor experience

- Instructor assignment studio protected by the authenticated instructor role.
- Student-account creation with instructor-entered or generated credentials.
- Optional email activation without sending a reusable password.
- Student email and participant-code editing.
- Password reset by generated credential or one-time email link.
- Student deactivation and reactivation while preserving study records.
- Server-controlled JSON account import for manually managed prototype cohorts.
- Assignment creation and editing.
- Stable assignment IDs and server-controlled version increments.
- Learning objectives, instructions, starter code, language, rubric,
  misconceptions, tutoring rules, simulation configuration, grader
  configuration, and official solution fields.
- Draft state after content changes.
- Server-side assignment validation.
- Publish action blocked until validation succeeds.
- Duplicate stable-ID prevention.
- Protection against client-forced version or publish-state changes.

### Backend and grading

- FastAPI application with OpenAPI documentation.
- SQLAlchemy persistence with local SQLite and PostgreSQL configuration.
- Argon2id password hashing, opaque hashed session tokens, expiry, and logout.
- Login throttling and generic forgot-password responses.
- One-time expiring password-reset tokens that revoke existing sessions.
- User, session, reset-token, and audit-event persistence.
- Role-based instructor authorization with temporary legacy token compatibility.
- Generic assignment endpoints:
  - `GET /assignments`
  - `GET /assignments/{assignment_id}`
  - `POST /assignments/{assignment_id}/run`
  - `POST /assignments/{assignment_id}/submit`
  - `POST /assignments/{assignment_id}/hint`
  - `POST /assignments/{assignment_id}/solution`
- Compatibility routes for the earlier frontend contract.
- Modular `AssignmentGrader` protocol and Python variable grader.
- Structured, student-safe grading evidence.
- Submission-size, execution-time, and output-size controls.
- Local subprocess sandbox for development.
- Docker sandbox adapter for production.
- Server-side solution reveal and assignment-version enforcement.
- Seed synchronization that upgrades existing local assignment records only
  when a newer seed version exists.
- Optional OpenAI Responses API integration with bounded timeout, no automatic
  retry, privacy rules, and deterministic fallback.

### Infrastructure

- Flutter web/mobile frontend.
- FastAPI/Python backend.
- PostgreSQL production database.
- Redis configuration for future background work.
- Docker Compose development/production topology.
- Dedicated Docker sandbox image.
- Managed backend asset storage with a future object-storage abstraction.
- Environment-based secrets and configuration.

## Target configurable assignment model

Every assignment should be represented by the following logical structure:

```text
Assignment
├── Stable ID
├── Version and publication status
├── Title, description, and instructions
├── Learning objectives
├── Starter code and managed assets
├── Language and execution settings
├── Public tests
├── Hidden grading tests
├── Rubric
├── Common misconceptions
├── AI tutoring rules and hint policy
├── Simulation configuration
├── Reference solution
└── Validation and publication history
```

### Assignment lifecycle

```text
Instructor draft
    ↓
Automated reference-solution and grader validation
    ↓
Published immutable assignment version
    ↓
Student run or submission
    ↓
Assignment-specific modular grader
    ↓
Structured student-visible evidence
    ↓
Built-in progressive tutoring
    ↓
Optional AI enhancement using sanitized evidence
    ↓
Progress, attempt, and feedback history
```

## Architecture direction

### Frontend

Keep Flutter for a shared web/mobile student and instructor interface. New
assignments should render from backend configuration through reusable workspace,
instruction, editor, simulation, result, and rubric components.

### Backend

Keep FastAPI as the orchestration boundary for:

- assignment CRUD and publication;
- synchronous runs and submissions;
- modular grading;
- hint and tutor orchestration;
- simulation job orchestration;
- progress and attempt APIs;
- instructor analytics;
- authentication and authorization;
- managed asset access.

### Persistence

Use PostgreSQL for:

- assignment identities and versions;
- publication state and validation results;
- student submissions and attempts;
- structured test evidence;
- hint interactions and tutor feedback;
- progress and mastery;
- instructor and course ownership;
- simulation job metadata;
- audit events.

Use object storage for:

- starter projects;
- images and lesson assets;
- hidden test packages;
- simulator worlds and configurations;
- large execution artifacts;
- student-generated files where required.

Use Redis and background workers for:

- long-running grading;
- simulation jobs;
- result polling and cancellation;
- retryable storage work;
- rate limiting;
- transient job status.

### Execution isolation

Production submissions must run in short-lived Docker containers with:

- no host filesystem access;
- no unrestricted network access;
- CPU, memory, process, time, and output limits;
- read-only assignment packages;
- generated temporary workspaces;
- guaranteed cleanup;
- structured result transport.

The subprocess executor remains development-only.

## AI tutoring plan

Phase 1 is implemented behind an opt-in switch. Deterministic grading remains
the authority and the built-in tutor remains the required fallback.

### Non-AI baseline

The platform must always provide:

- deterministic grading;
- student-safe evidence;
- progressive built-in hints;
- misconception mapping;
- clear next actions;
- predictable latency;
- no dependency on API quota.

### Phase 1 AI feedback tutor

The current tutor:

1. Receive only student code, published instructions, learning objectives,
   tutoring policy, misconceptions, and sanitized visible evidence.
2. Never receive hidden tests, expected values, grader configuration, or the
   official solution.
3. Provides a diagnosis, short answer, debugging steps, guiding question, hint,
   and next action without writing a replacement solution.
4. Accepts a student's question about their latest owned submission and adapts
   support to the selected hint level.
5. Clearly label whether feedback came from OpenAI or the built-in tutor.
6. Enforce timeouts, token limits, rate limits, logging, and fallback behavior.
7. Require strict structured output, disable OpenAI response storage, and reject
   suspicious output before display.
8. Record privacy-safe interaction metadata without storing raw questions in
   general learning events.

### Later AI phases

- Compare current and prior attempts to explain meaningful code changes.
- Add prompt-policy/model version metadata for controlled research analysis.
- Run approved instructor evaluation cases against the real provider and score
  pedagogical quality before classroom rollout.
- Add instructor review, quality flags, and aggregate tutor-effectiveness
  reporting.
- Adapt support to demonstrated mastery without changing deterministic grades.

## Simulation plan

Simulation assignments should reuse the same run, submit, evidence, tutoring,
and versioning model.

### Simulation configuration should define

- simulator type and version;
- world or map asset;
- robot model;
- starting state and goal;
- sensors and noise configuration;
- runtime limits;
- deterministic seed policy;
- success and failure metrics;
- artifact capture policy;
- visual replay configuration;
- grader adapter.

### Simulation phases

1. Deterministic lightweight server-side numerical simulations.
2. Containerized robotics simulations producing structured metrics and
   screenshots.
3. Background simulation jobs with progress updates and cancellation.
4. Interactive browser visualization and replay.
5. Optional ROS/Gazebo/Webots integration after security and infrastructure
   capacity are validated.

## Delivery roadmap

### Phase 1: Stabilize the generic assignment engine

- Finalize assignment schema and migration strategy.
- Separate public test packages from hidden grader packages.
- Add assignment-version history and rollback.
- Add reusable language/executor configuration.
- Expand assignment validation and publication reports.
- Add automated tests for every published assignment.
- Remove tracked virtual environments and generated files from Git history in a
  dedicated cleanup change.

### Phase 2: Course and identity model

- Add users, courses, roles, enrollments, and instructor ownership.
- Replace shared instructor token with authenticated role-based access.
- Add course assignment ordering, due dates, prerequisites, and visibility.
- Add student submission history and instructor review.
- Add database migrations and seed strategy for team environments.

### Phase 3: Durable execution platform

- Make Docker execution the only production grader path.
- Add job queue, workers, cancellation, retries, and status polling.
- Add object storage for managed assignment packages and artifacts.
- Add resource quotas, audit logs, and observability.
- Add CI validation for Compose and sandbox images.

### Phase 4: Simulation engine

- Define the common simulation adapter.
- Add one numerical simulation assignment as the reference implementation.
- Add structured simulation evidence and replay artifacts.
- Add background job UI.
- Add deterministic repeatability and performance tests.

### Phase 5: AI tutor evaluation

- Define tutoring quality rubrics and safety test sets.
- Create offline evaluations using stored sanitized evidence.
- Compare built-in and AI-assisted tutoring outcomes.
- Add per-course and per-assignment AI policies.
- Add budget controls and instructor-visible AI quality reports.

### Phase 6: Analytics and learning research

- Add mastery and misconception tracking.
- Add assignment difficulty and test-failure analytics.
- Add instructor dashboards.
- Add privacy-preserving research export.
- Define learning-outcome experiments and evaluation methodology.

## Communication plan

### Source-of-truth artifacts

| Artifact | Purpose | Owner |
| --- | --- | --- |
| This document | Product vision, architecture, decisions, roadmap, and communication | Product/technical lead |
| Master SQA workbook | Feature verification, release evidence, defects, and sign-off | SQA lead |
| Assignment configuration | Published learning content and grader policy | Instructor |
| Automated tests | Executable regression protection | Developers |
| GitHub issues | Work items, bugs, acceptance criteria, and discussion | Assignee |
| Pull requests | Code review, evidence, migration notes, and release impact | Author/reviewer |
| Decision records | High-impact technical or product decisions | Decision owner |

### Suggested cadence

- Weekly product and curriculum planning.
- Weekly engineering/SQA triage.
- Assignment review before publication.
- Release-readiness review before merging to the release branch.
- Monthly architecture and security review.
- Per-semester learning-outcome review with instructors.

### Work-item template

Every issue should include:

- problem or opportunity;
- affected user;
- current behavior;
- desired behavior;
- acceptance criteria;
- assignment/version impact;
- security and privacy impact;
- migration or compatibility impact;
- automated test plan;
- manual SQA checklist IDs;
- screenshots or evidence where relevant.

### Decision-record template

```text
Decision ID:
Date:
Owner:
Status: Proposed | Accepted | Superseded
Context:
Options considered:
Decision:
Why:
Consequences:
Migration plan:
Validation plan:
Related issues/PRs:
```

## Release quality gates

A release is ready only when:

1. Backend automated tests pass.
2. Flutter analysis and tests pass.
3. Web build succeeds.
4. Every published assignment validates.
5. Every official solution passes its complete grader.
6. Every starter program executes without an unintended syntax/runtime error.
7. Hidden test and solution leakage checks pass.
8. Desktop and mobile critical paths pass.
9. Instructor create/edit/validate/publish flow passes.
10. Sandbox abuse, timeout, oversized-input, and output-cap tests pass.
11. AI-disabled and AI-fallback paths pass.
12. Database migration and rollback are verified for production changes.
13. Secrets and generated files are absent from the commit.
14. Known limitations and external dependencies are documented.
15. SQA sign-off is recorded in the master checklist.

## Definition of done

A feature is done when:

- acceptance criteria are explicit;
- implementation is configuration-driven where appropriate;
- unit and integration tests cover normal and failure paths;
- responsive UI and accessibility are checked;
- security, privacy, and hidden-content boundaries are checked;
- documentation and assignment versions are updated;
- SQA checklist rows exist and pass;
- evidence is attached to the release record;
- no unresolved critical or high-severity defects remain.

## Key risks and mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Hardcoded assignment behavior returns | Every new assignment needs application changes | Enforce generic APIs and configuration-driven UI/grader contracts |
| Hidden solution or test leakage | Academic integrity failure | Server-only packages, response allowlists, automated leak scans |
| Unsafe code execution | Host or data compromise | Docker isolation, resource limits, no network, read-only packages |
| AI reveals answers or becomes unavailable | Pedagogical harm or broken workflow | Sanitized evidence, strict tutor policy, evaluation, deterministic fallback |
| Assignment edits invalidate student work | Incorrect grading and progress | Immutable versions and version recorded on every submission |
| Simulation jobs block API workers | Poor availability | Redis queue, background workers, cancellation, status polling |
| Shared instructor token is compromised | Unauthorized content changes | Replace with authentication, RBAC, rotation, and audit logging |
| Local-only SQLite behavior differs from production | Deployment defects | PostgreSQL CI/integration environment and migration tests |
| Large generated files enter Git | Repository bloat and merge noise | Dedicated cleanup, ignores, pre-commit checks, artifact storage |

## Idea backlog

- Course authoring templates and assignment cloning.
- Rubric editor with criterion-level scoring.
- Instructor preview as student.
- Assignment scheduling and prerequisite graphs.
- Multiple programming languages.
- Pair-programming or team submissions.
- Accessibility preferences and keyboard-first navigation.
- Localization.
- Code snapshots and attempt comparison.
- Instructor annotations on submissions.
- Test replay and simulation timeline.
- Mastery paths and personalized assignment recommendations.
- Academic-integrity signals with transparent instructor review.
- LTI integration with learning-management systems.
- Gradebook export.
- Research-consent controls and de-identified datasets.
- Offline-first student drafts.
- Automated assignment quality scoring before publication.
- Tutor evaluation dashboard and prompt-policy version comparison.

## Maintenance instructions

- Update the roadmap when priorities or architectural decisions change.
- Add SQA checklist rows whenever a feature or failure mode is introduced.
- Never delete old assignment-version expectations from release evidence.
- Link issues and pull requests to affected checklist IDs.
- Review all `Deferred` checklist rows during each planning cycle.
- Record significant changes using the decision-record template.
