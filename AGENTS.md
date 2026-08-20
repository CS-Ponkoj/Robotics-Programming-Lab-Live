# AGENTS.md

## Purpose and scope

This file is the engineering contract for every human contributor and coding
agent working in this repository. It applies to the entire repository unless a
more specific `AGENTS.md` exists in a subdirectory. A nested file may add local
rules but must not weaken the security, privacy, testing, or release gates in
this file.

When instructions conflict, follow this order:

1. Explicit user or project-owner direction.
2. Security, privacy, research-integrity, and data-loss prevention requirements.
3. The nearest applicable `AGENTS.md`.
4. Existing repository conventions and documentation.

If a requested change would weaken a higher-priority requirement, stop and
explain the conflict before modifying the repository.

## Product mission

Robotics Programming Lab is a classroom and research platform for versioned
robotics-programming assignments. It provides student and instructor Flutter
interfaces backed by FastAPI, PostgreSQL, a dedicated code-execution sandbox,
and an optional OpenAI tutoring enhancement.

The platform must remain useful when AI is unavailable. Deterministic grading,
built-in hints, assignment access, submissions, and research capture are core
functionality and must never depend on OpenAI.

## Non-negotiable product invariants

- Preserve existing working functionality unless the approved task explicitly
  changes it.
- Use one generic assignment workflow; do not add assignment-specific screens or
  one-off public routes when configuration or a grader module is sufficient.
- Give every assignment a stable ID and immutable version identity.
- Save the assignment version with every attempt and submission.
- Keep hidden tests, official solutions, reference answers, grader secrets, and
  sandbox credentials exclusively on the server.
- Never reveal hidden-test contents or official solutions through an API, UI,
  export, log, exception, or AI response.
- Keep AI available but disabled by default unless a study configuration
  explicitly enables it.
- Do not display demo credentials on the login page.
- Public student-demo access must use a server-issued ephemeral session. Demo
  authentication, code attempts, hints, solution unlocks, drafts, and progress
  must remain memory-only; a browser refresh must return to login and reset the
  demo. Demo activity must not create auth-session, submission, hint, audit, or
  research rows. Keep demo authorization student-only and isolate every demo
  browser session from every other session.
- Derive student identity from the authenticated server session. Never trust a
  client-supplied student ID for ownership or authorization.
- Keep student and instructor capabilities separated and tested.
- Preserve local development and production deployment from the same source
  code. Environment values may differ; application logic must not be forked.
- Treat research integrity, reproducibility, accessibility, and participant
  privacy as release requirements.

## Repository and environment roles

| Repository or environment | Role | Policy |
|---|---|---|
| `C:\Users\cspon\OneDrive - University of Nevada, Reno\Robotics-Programming-Lab-Staging` | Canonical Windows staging checkout | Run ordinary local development, local execution, SQA, and staging Git work from this folder. It must track `CS-Ponkoj/Robotics-Programming-Lab-Staging`; do not treat temporary worktrees or `IUSE_Project-2026` as the canonical staging checkout. |
| `CS-Ponkoj/Robotics-Programming-Lab-Staging` | Development, local execution, SQA, and release candidates | Make changes on focused branches and merge into staging `main` only after verification. |
| `CS-Ponkoj/Robotics-Programming-Lab` | Live Vercel and Render deployment | Production `main` receives only an approved, tested staging commit. Do not patch production directly. |
| Local SQLite | Fast developer feedback | May be used for ordinary local work; it is ignored and disposable. |
| Staging PostgreSQL | Production-parity SQA | Must be separate from production and contain no live research records. |
| Production Neon PostgreSQL | Live mutable data | Schema changes require Alembic migrations and recovery planning. |

Promote production-ready changes by reviewed Git commits, never by copying files
between repositories. Staging may contain unreleased features such as ROS
Assignments 5 and 6 while production intentionally remains on Assignments 1-4. While
that difference exists, do not merge staging wholesale into production. Apply
only the reviewed common change to a production branch, verify the production
assignment inventory contains exactly 1-4 and no ROS artifacts, then run the
same complete gate on both resulting commits. Promote ROS only after its hosted
sandbox architecture and release are explicitly approved.

The production repository `main` branch is the live branch watched by Vercel and
Render. Publication, production promotion, tags, releases, and destructive
operations require explicit project-owner approval.

Before every repository action, verify the checkout with
`git rev-parse --show-toplevel`, the current branch, `git remote -v`, and
`git status --short`. The canonical local staging checkout and staging Git
repository must resolve to the intended matching commit before handoff. Preserve
unrelated local work with a named, recoverable stash when a clean synchronized
checkout is required. Never fetch, merge, push, or deploy the `production`
remote unless the project owner explicitly authorizes a live promotion.

## Architecture map

```text
frontend/                         Flutter student and instructor application
  lib/screens/                    Pages and workspaces
  lib/services/                   Typed API clients and web/native adapters
  lib/state/                      Local learner-progress state
  lib/models/                     Transport and UI models

backend/                          FastAPI application
  app.py                          HTTP routes and application composition
  models.py                       SQLAlchemy persistence models
  schemas.py                      Pydantic API schemas
  auth_service.py                 Authentication and password/session behavior
  assignment_repository.py       Assignment loading and persistence
  graders/                        Modular AssignmentGrader implementations
  sandbox.py                      Sandbox client and execution policies
  sandbox_service.py              Dedicated execution service
  ros2_worker.py / ros2_*_harness.py  Isolated ROS package build and behavior checks
  tutor.py / hinter.py            Deterministic and optional AI tutoring
  research_service.py             Study sessions, events, summaries, and exports
  migrations/                     Alembic production schema history
  assignments/                    Controlled assignment configuration
  tests/                          Backend regression and security tests

manual_sqa_answers/               Instructor-only manual verification answers
scripts/                          Local run, verification, and release automation
.github/workflows/ci.yml          Continuous-integration release gates
render.yaml                       API and sandbox hosting configuration
vercel.json                       Flutter web deployment configuration
```

Read `README.md`, `STAGING_AND_RELEASE_WORKFLOW.md`,
`V4_1_RESEARCH_DATA_GUIDE.md`, and the current SQA report before making a broad
architectural, research-data, or release change.

## Working method

Use an incremental, evidence-driven workflow:

1. Inspect the current behavior, relevant tests, working tree, branch, and
   remotes before editing.
2. State the smallest safe change and its acceptance check.
3. Preserve unrelated user changes in a dirty working tree.
4. Implement one focused change.
5. Run the closest focused check immediately.
6. Fix failures before beginning the next change.
7. Run the proportional regression suite.
8. Run the complete release gate when behavior, dependencies, data, deployment,
   authentication, grading, or shared UI changes.
9. Record evidence and remaining limitations honestly.
10. At the beginning and end of each task, check whether durable repository
    facts or engineering rules have changed enough to require an `AGENTS.md`
    update. Update it in the same verified staging workflow when needed; do not
    create documentation churn for ordinary implementation details.

Do not claim a feature works because it compiles. Verify observable behavior at
the appropriate API, test, browser, database, or deployed-service boundary.

## Local setup and execution

The supported developer shell is PowerShell on Windows.

Install dependencies:

```powershell
python -m venv venv
.\venv\Scripts\python.exe -m pip install -r .\backend\requirements.txt
Set-Location .\frontend
flutter pub get
Set-Location ..
```

Start the complete local stack:

```powershell
.\scripts\run-local.ps1
```

Stop only the processes managed by the launcher:

```powershell
.\scripts\stop-local.ps1
```

Run the full local verification gate:

```powershell
.\scripts\verify-local.ps1
```

Use `-EnableAi` only for an intentional AI test. Use `-DatabaseUrl` with a
separate staging PostgreSQL connection for final database-parity checks.

OneDrive can lock Flutter build artifacts. Use the supplied run and verification
scripts, which build from a safe generated copy under LocalAppData. Do not solve
locking problems by committing generated build output or deleting broad folders.

## Required verification

### Backend

Run backend tests from the `backend` directory so backend-local imports resolve
the same way as CI:

```powershell
Set-Location .\backend
..\venv\Scripts\python.exe -m pytest tests -q
..\venv\Scripts\python.exe -m pip check
..\venv\Scripts\python.exe -m compileall -q .
Set-Location ..
```

Run a focused test first when possible, then the entire backend suite before
completion of a cross-cutting change.

### Frontend

```powershell
Set-Location .\frontend
flutter analyze
flutter test
flutter build web --release --dart-define=API_BASE_URL=https://api.example.test
Set-Location ..
```

For OneDrive checkouts, prefer `scripts/verify_frontend_onedrive.ps1` or the
complete `scripts/verify-local.ps1` gate.

### Repository hygiene

```powershell
git diff --check
git status --short
```

The release gate also requires migration validation, sandbox image build/smoke,
correct and incorrect assignment solutions, unsafe-code rejection, browser SQA,
persistence checks, and an updated SQA evidence record.

## Definition of done

A change is complete only when:

- the requested behavior is implemented;
- the closest focused tests pass;
- relevant regression tests pass;
- error, empty, loading, timeout, and authorization states are handled;
- no secrets or generated artifacts are added;
- documentation and SQA evidence are updated when behavior or operations change;
- the working-tree diff contains only intended changes; and
- known limitations are reported instead of hidden.

Compilation alone is not sufficient. Manual browser testing alone is not
sufficient when an automated test can reasonably protect the behavior.

## Backend engineering rules

- Keep routes thin. Put reusable domain behavior in services, repositories,
  graders, or dedicated modules.
- Use Pydantic schemas at HTTP boundaries and SQLAlchemy models for persistence.
- Validate request size, types, identifiers, and state transitions server-side.
- Use explicit authorization checks on every student, instructor, research, and
  administrative endpoint.
- Return structured, stable errors suitable for Flutter to display.
- Preserve existing public API contracts unless an approved versioned migration
  is provided.
- Keep legacy compatibility routes working until their removal is explicitly
  approved and documented.
- Do not expose stack traces, SQL details, filesystem paths, tokens, or provider
  responses to clients.
- Bound network calls with short timeouts and controlled retries.
- Keep health responses minimal in production.
- Keep production API documentation disabled unless explicitly required.

## Database and migration rules

- PostgreSQL is authoritative for production mutable data.
- SQLite is a local-development convenience, not a production fallback.
- Every production schema change requires an Alembic migration.
- Test migrations against a fresh PostgreSQL database and the supported previous
  schema state.
- Make seeds idempotent. Never overwrite instructor edits or student records on
  application startup.
- Never use `Base.metadata.create_all` as the production migration strategy.
- Never silently drop, truncate, rename, or reinterpret research data.
- Destructive migrations require an explicit backup, rollback plan, owner
  approval, and restoration rehearsal.
- Store UTC timestamps and assignment versions with attempts and events.
- Avoid N+1 queries and unbounded result sets; paginate growing collections.

## Authentication and authorization rules

- Store passwords only as strong salted hashes.
- Never log passwords, temporary passwords, tokens, password hashes, session
  headers, or reset secrets.
- Enforce server-side roles; hiding a Flutter control is not authorization.
- Revoke sessions after logout, account deactivation, or password change where
  the current session model supports it.
- Rate-limit login, execution, tutor, and sensitive administrative actions.
- Keep self-service password reset and email features behind explicit feature
  flags while they are outside the approved demo scope.
- Instructor account creation or removal must not be possible through a student
  session.
- Add tests for unauthenticated, wrong-role, cross-student, deactivated-account,
  and expired-session cases when modifying protected behavior.

## Assignment and grader rules

Each assignment configuration must support:

- stable assignment ID and version;
- instructions and learning objectives;
- starter code;
- language and execution settings;
- public tests;
- server-only hidden tests;
- rubric;
- common misconceptions;
- tutoring and hint policy;
- optional simulation configuration; and
- publication state.

Use `AssignmentGrader` implementations for grading differences. Keep result
evidence structured and normalize non-native scalar values before JSON
serialization. A feedback string is not a pass/fail boolean.

Before publishing or changing an assignment, verify:

- the maintained answer passes its versioned grader;
- starter code produces the expected instructional failure;
- an incorrect answer fails;
- syntax and runtime errors are reported safely;
- infinite loops, excessive output, unsafe imports, and oversized submissions
  are bounded; and
- hidden tests and solutions are absent from student responses.

`manual_sqa_answers/` is controlled instructor material. Do not ship its contents
to the frontend, public API, learner export, or AI context.

## Sandbox and untrusted-code rules

Treat every submission as hostile input.

- Production execution must use the dedicated sandbox service.
- The API and sandbox authenticate with a strong secret stored only in provider
  environment settings.
- Send the sandbox only the minimum code and result-name data it needs.
- Do not send database credentials, OpenAI keys, hidden tests, auth secrets, or
  research records to the sandbox.
- Preserve execution time, output size, request size, concurrency, and import
  limits.
- Keep network and filesystem access denied unless an assignment has an
  explicitly reviewed requirement and isolation design.
- Never replace isolation with `eval`, `exec`, or an in-process restriction and
  call it production-safe.
- Test timeout, memory/output abuse, malformed payload, missing token, invalid
  token, dangerous import, and concurrent execution behavior.

## AI tutor rules

- AI is an optional enhancement and remains off by default.
- Never place an OpenAI API key in Flutter, source control, logs, screenshots,
  exports, or assignment configuration.
- Send only sanitized assignment context and grader evidence.
- Never send hidden tests, official solutions, secrets, unrelated student data,
  or raw research exports.
- Prompts must prohibit solution disclosure and hidden-test inference.
- Apply timeouts, quotas, and a deterministic built-in-hint fallback.
- Clearly label AI-generated feedback in the UI.
- AI failure must not leave grading stuck or block submission.
- Add evaluation cases for correctness, hallucination, prompt injection,
  solution leakage, unsafe advice, and quota/provider failure before expanding
  AI use in a study.

## Research data and privacy rules

- Use participant codes in research screens and exports, not login IDs.
- Never export passwords, hashes, temporary credentials, auth tokens, API keys,
  hidden tests, official solutions, or submitted source code.
- Preserve event allowlists, metadata size limits, heartbeat caps, and
  student-self-only access.
- Escape spreadsheet-formula prefixes in CSV/XLSX exports.
- Keep raw learning events append-only through public APIs.
- Record protocol/cohort/configuration changes as versioned metadata rather than
  rewriting historical events.
- Define consent, retention, deletion, anonymization, backup, and withdrawal
  procedures before enrolling research participants.
- Use separate staging and production databases.
- Treat any suspected research-data leak as a release blocker and incident.

## Flutter engineering rules

- Keep networking in `lib/services`, shared state in `lib/state`, transport data
  in `lib/models`, and screens focused on presentation and interaction.
- Use the configured `API_BASE_URL`; do not hardcode localhost or production URLs
  in application logic.
- Preserve web and mobile-width behavior.
- Provide explicit loading, empty, retry, offline, timeout, and permission-denied
  states.
- Prevent double submissions and endless loading indicators.
- Keep keyboard navigation, focus order, semantics, labels, contrast, and touch
  target sizes usable.
- Avoid exposing protected data in client storage or debug output.
- Update widget tests when UI state or navigation behavior changes.
- Test at desktop and mobile widths when changing layout.

## Secrets and configuration

- Store secrets only in ignored local `.env` files or deployment-provider secret
  settings.
- Track only safe examples such as `backend/.env.example`.
- Never commit `.env`, database files, credentials, API keys, private connection
  strings, auth tokens, generated environments, logs, or build output.
- Never print secret values while diagnosing configuration.
- Production must reject wildcard CORS, SQLite, automatic schema creation, and
  missing required secrets.
- Use exact allowed origins for the deployed Flutter application.
- Rotate any credential that is accidentally exposed; deleting it from the
  latest commit is not sufficient.

Forbidden tracked paths include environment directories, `.env`, `.dart_tool`,
Flutter `build`, `.local-run`, local databases, caches, and generated logs.

## Git and change hygiene

- Inspect branch, remotes, status, and diff before modifying or publishing.
- Start work from current staging `main` on a focused feature branch.
- Never use the word `codex` (in any capitalization) in a Git branch name or
  commit message. Use a short project- or feature-based name instead.
- Keep commits focused and use clear imperative commit messages.
- Do not mix formatting, dependency upgrades, feature work, and unrelated fixes
  in one commit.
- Never discard, overwrite, or stage unrelated user changes.
- Do not use destructive history or filesystem commands without explicit owner
  approval and exact target verification.
- Do not commit generated Python environments or Flutter artifacts.
- Do not amend, force-push, tag, publish, promote, or create a release unless the
  owner explicitly requests it.
- Before committing, review the staged diff and run `git diff --check`.
- Before production promotion, require a clean staging `main`, passing CI, an
  updated SQA record, and explicit owner approval.

## Release and rollback rules

Follow `STAGING_AND_RELEASE_WORKFLOW.md` and the guarded scripts.

Before promotion:

- run `scripts/verify-local.ps1`;
- verify PostgreSQL migrations and persistence;
- verify the dedicated sandbox and adversarial execution cases;
- verify student and instructor end-to-end workflows;
- verify research capture and export privacy;
- confirm AI is off by default;
- update the master SQA workbook/report;
- confirm zero open release blockers;
- record the tested commit SHA; and
- obtain explicit approval for production and the release tag.

After promotion, verify that Vercel and both Render services deploy from
production `main`, the API health release matches the approved SHA, and the live
student/instructor smoke tests pass from a clean browser. Perform an external
device/network check for classroom releases.

If live validation fails, redeploy the previous known-good immutable tag. Fix
the problem in staging, rerun the complete gate, and promote a new release. Do
not patch production in place.

## Documentation and SQA evidence

Update documentation whenever a change affects setup, architecture,
configuration, API behavior, assignment authoring, research data, security,
deployment, or recovery.

Treat `AGENTS.md` maintenance as a required handoff check. Update it when the
canonical checkout, repository roles, branch policy, supported commands,
architecture, security boundary, verification gate, or release process changes.
When none of those durable facts changed, record that no `AGENTS.md` update was
needed rather than editing the file unnecessarily.

SQA evidence must state:

- feature or requirement tested;
- environment and commit SHA;
- exact check or user flow;
- expected and actual result;
- PASS, FAIL, PARTIAL, BLOCKED, or NOT RUN;
- reason for every non-PASS result; and
- follow-up owner or action when applicable.

Never convert a blocked or untested item into PASS based on assumption.

## Review checklist

Before handing off a change, ask:

- Is the implementation generic enough for future assignments?
- Did authorization remain server-enforced?
- Could hidden tests, solutions, secrets, credentials, or student data leak?
- Can a timeout or exception leave the UI running forever?
- Are local and deployed paths driven by configuration from the same code?
- Does the database change have a tested migration and rollback path?
- Are untrusted submissions still isolated and bounded?
- Does the feature work with AI disabled?
- Are research records reproducible and privacy-preserving?
- Are desktop, mobile-width, keyboard, and accessibility states covered?
- Are focused tests and proportional regressions passing?
- Is the diff limited to the requested scope?
- Are documentation, SQA evidence, and known limitations accurate?

## Contributor handoff format

End implementation reports with:

1. Outcome: what changed.
2. Files: the important files changed.
3. Verification: exact checks run and their results.
4. Limitations: anything partial, blocked, deferred, or not run.
5. Release state: local only, committed, pushed to staging, or promoted live.

Do not say “everything works perfectly” unless every applicable automated,
manual, deployment, persistence, security, and external-network gate has passed.
