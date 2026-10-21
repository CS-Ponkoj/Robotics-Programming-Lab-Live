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
- Scope browser code drafts to both assignment ID and assignment version.
  Never load an older-version draft into a newer assignment workspace.
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
- Grade complete course quizzes on the server. Store student scores with the
  exact quiz version, separately from coding-assignment scores. Demo and
  instructor previews must not create persistent quiz-attempt records.
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
| Secondary Windows or Ubuntu laptop/lab checkout | Temporary local clone outside OneDrive | Clone or fast-forward from staging Git. Never copy generated environments or build caches between computers. |
| Repository-root `.env` | Ignored private local configuration | Contains Neon and optional AI settings; it does not contain accounts or the active database. Never commit or publicly share it. |
| Neon `robotics_lab_staging` database | Default staging application data | Shared across authorized devices through ignored private configuration; keep it separate from production `neondb`. |
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
  data_contracts.py               Versioned assignment, grading, and event schemas
  schemas.py                      Pydantic API schemas
  auth_service.py                 Authentication and password/session behavior
  assignment_repository.py       Assignment loading and persistence
  course_content_repository.py   Student-safe course-page and whole-quiz grading
  course_content/                Generated lessons and server-only quiz keys
  graders/                        Modular AssignmentGrader implementations
  sandbox.py                      Sandbox client and execution policies
  sandbox_service.py              Dedicated execution service
  ros2_worker.py / ros2_*_harness.py  Isolated ROS package build and behavior checks
  ros2_callback_audit.py           Container-only callback publication instrumentation
  tutor.py / hinter.py            Deterministic and optional AI tutoring
  research_service.py             Study sessions, events, summaries, and exports
  instructor_dataset.py           Offline instructor AI-evaluation contract and validator
  ai_evaluation_cases/            Server-only, instructor-reviewed tutor evaluation cases
  migrations/                     Alembic production schema history
  assignments/                    Controlled assignment configuration
  tests/                          Backend regression and security tests

assignments_answers/              Instructor-only manual verification answers
course_materials/                 Controlled assignment and course source documents
  archive/                        Historical supporting material, not runtime content
docs/                             Architecture, deployment, research, and SQA records
  archive/                        Superseded evidence retained for traceability
scripts/                          Local run, verification, and release automation
  build_course_content.py         Rebuild web pages after reviewed source changes
  course_quiz_bank.json           Authored questions for topics without a source quiz
.github/workflows/ci.yml          Continuous-integration release gates
scripts/run-live.ps1              Self-hosted live stack on the lab PC (Caddy + Cloudflare Tunnel)
```

Read `README.md`, `docs/README.md`,
`docs/deployment/STAGING_AND_RELEASE_WORKFLOW.md`,
`docs/research/V4_1_RESEARCH_DATA_GUIDE.md`, and the current report under
`docs/sqa/` before making a broad architectural, research-data, or release
change.

## Working method

Act as the project owner's professional software engineer and technical
partner. Prioritize correct, maintainable, secure, and practical code.

- Make the smallest professional change that fully solves the task.
- Follow the existing architecture, conventions, and applicable instructions.
- Preserve existing functionality unless the owner explicitly requests a
  change.
- Do not overengineer, add unnecessary dependencies, or refactor unrelated
  code.
- Work incrementally on one clearly defined change at a time.
- Stop when the requested task is correctly implemented and appropriately
  validated.
- Preserve unrelated user work and files.

For each task:

1. Inspect only the relevant code and current behavior.
2. Understand the confirmed cause or requirement.
3. Implement the smallest clean, practical solution.
4. Run the closest relevant test or validation.
5. Fix failures caused by the change before beginning another change.
6. Report what changed, what was tested, and any meaningful limitation.

Use broader regression testing only when a change is large, risky,
cross-cutting, release-related, or explicitly requested. Add or update tests
when behavior meaningfully changes; do not add unnecessary tests for trivial
changes. Verify affected UI and API behavior when practical. Compilation alone
is not evidence that observable behavior works.

Clearly separate confirmed bugs, possible risks or improvements, untested
items, and external limitations or blockers. Mention directly related problems
encountered during the task, but do not investigate unrelated issues.

When discussing a plan or update, begin each reply with a brief recap of the
relevant decisions already agreed with the owner. Then explain new options,
changes, or next steps. Keep the recap short and distinguish agreed decisions
from proposals; do not ask for approval of an agreed decision again.

Explain technical ideas in simple words and lead with the result or
recommendation. For architecture, stacks, and workflows, explain what each
component does, why it is needed, how components communicate, its advantages
and limitations, and what is needed now versus later. Use a small diagram or
table only when it materially improves understanding. Ask a question only when
the answer would materially change the solution or require new authorization;
otherwise make a safe, reasonable assumption.

The current priority is the complete local staging application. Do not expand
the scope to production, Android packaging, or mobile-store release work unless
the owner explicitly starts that phase.

Update documentation, tests, SQA evidence, or this file only when the change
makes existing material inaccurate or when the task explicitly requires it.
Avoid documentation churn for ordinary implementation details.

## Local setup and execution

The supported local environments are Windows 10/11 with PowerShell and x86-64
Ubuntu 22.04/24.04 LTS with Bash. Use
`docs/guides/FIRST_TIME_RUN_WINDOWS.md` or
`docs/guides/FIRST_TIME_RUN_UBUNTU.md` for first-time setup.

Prepare the single ignored Python 3.14 environment and install pinned
dependencies:

```powershell
.\scripts\setup-local.ps1
```

The main desktop checkout is intentionally inside OneDrive. Secondary laptops
and lab computers must use a Git clone in a normal local folder outside
OneDrive. Setup creates the Python environment under that computer's local
user-data directory and installs the pinned requirements. Generated Python and
Flutter files are never synchronized or committed. Use `-Repair` on Windows or
`--repair` on Ubuntu only when ordinary setup reports an incomplete environment.

Start the complete local stack connected to Neon staging:

```powershell
.\scripts\run-local.ps1
```

The launchers default to `http://127.0.0.1:8180/app` (API 5100, sandbox 5101)
on both operating systems. Document any change to these defaults in
`README.md` and both first-time guides. Signed-in student progress is cached
per browser address and restored at sign-in from `GET /me/assignment-progress`,
which derives everything from the authenticated student's own records.

Ubuntu uses the equivalent commands:

```bash
./scripts/setup-local.sh
./scripts/run-local.sh
./scripts/stop-local.sh
```

Windows stores generated environments and runtime data under LocalAppData.
Ubuntu stores them under the user's XDG data and state directories. Neither
operating system may place generated environments, Flutter builds, or logs in
the Git clone. Both read the same ignored repository-root `.env` format and
connect to the same authorized Neon staging database.

Stop only the processes managed by the launcher:

```powershell
.\scripts\stop-local.ps1
```

The stop command ends only the processes owned by the launcher. Neon preserves
the shared database independently of the browser or local processes. The
ignored root `.env` contains connection settings, not accounts or the active
database. Local dump files, backup manifests, device locks, and the obsolete
`local_database_backups` location are not part of the application.

For an authorized new-device setup, securely provision the ignored repository
root `.env`. The password-free account roster is distributed by Git at
`backend/data/study_accounts.json`. Never create a duplicate `backend/.env`, and
never put secrets or passwords in Git.
Fresh Windows clones must use `git -c core.longpaths=true clone` because tracked
course-material filenames exceed Git's default Windows checkout limit.

Run the full local verification gate:

```powershell
.\scripts\verify-local.ps1
```

On Ubuntu:

```bash
./scripts/verify-local.sh
```

Use `-EnableAi` on Windows or `--enable-ai` on Ubuntu only for an intentional AI
test. Normal application runs require Neon; there are no local-database
troubleshooting flags.

OneDrive can lock Flutter build artifacts. Use the supplied run and verification
scripts, which build from a safe generated copy outside the clone. Do not solve
locking problems by committing generated build output or deleting broad folders.

## Required verification

### Backend

Use the root verification script so it resolves the device-local Python
environment and runs backend checks from the correct directory:

```powershell
.\scripts\verify-local.ps1
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

### Browser flows

With the local stack running, `scripts/run-browser-tests.ps1` (Ubuntu:
`scripts/run-browser-tests.sh`) drives the student demo and an instructor
session that changes no course or research data in a real browser. Keep Playwright in its separate
browser-test environment; never add it to the application requirements. Run it
after UI, authentication, grading, or launcher changes.

### Repository hygiene

```powershell
git diff --check
git status --short
.\scripts\clean-local.ps1
```

`scripts/clean-local.ps1` is dry-run by default. Use `-Execute` only after the
managed application is stopped. Its allow-list may contain rebuildable caches
and build output only. Never add `.git`, `.env`, `venv`, databases,
`output`, `course_materials`, or
`assignments_answers` to that cleanup allow-list.

Use Git maintenance commands for repository object cleanup; never delete files
inside `.git` manually. Keep the current operating documents and latest SQA
evidence in their active directories, and preserve superseded evidence under
`docs/archive/` for research traceability.

The release gate also requires migration validation, sandbox image build/smoke,
correct and incorrect assignment solutions, unsafe-code rejection, browser SQA,
persistence checks, and an updated SQA evidence record.

## Definition of done

A change is complete only when:

- the requested behavior is implemented;
- the closest focused tests pass;
- broader regression checks pass when the change's scope or risk requires them;
- no secrets, generated artifacts, or unrelated changes are introduced; and
- meaningful limitations and untested items are reported honestly.

## Backend engineering rules

- Keep routes thin. Put reusable domain behavior in services, repositories,
  graders, or dedicated modules.
- Use Pydantic schemas at HTTP boundaries and SQLAlchemy models for persistence.
- Keep instructor-authored AI evaluation cases server-only and offline until a
  separately reviewed runtime stage is approved. Draft cases are not research
  ground truth. Approval requires a named instructor reviewer, and evaluation
  files must never contain official solutions, hidden tests, grader
  configuration, or answer keys.
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

- Neon PostgreSQL is authoritative for all persistent application data.
- Normal staging launchers, direct backend starts, and Alembic commands must
  resolve the same dedicated Neon database. Missing configuration or connection
  failure must never silently create or switch to a local database.
- SQLite and local PostgreSQL are allowed only as explicitly configured,
  disposable automated-test databases (`ENVIRONMENT=testing`), not app modes.
  The one exception is the owner-approved (2026-10-20) self-hosted live
  instance on the lab PC: `ENVIRONMENT=production` with
  `SELF_HOSTED_DATABASE=true` uses that PC's local PostgreSQL. It never applies
  to development or staging, and that database needs off-machine backups.
- Reconcile legacy records before importing them. Preserve newer Neon accounts,
  assignments, and session state; never restore an old dump over the shared DB.
- Every production schema change requires an Alembic migration.
- Test migrations against a fresh PostgreSQL database and the supported previous
  schema state.
- Make seeds idempotent. Never overwrite instructor edits or student records on
  application startup.
- Never use `Base.metadata.create_all` as the production migration strategy.
- Never silently drop, truncate, rename, or reinterpret research data.
- Never synchronize an active PostgreSQL data directory through OneDrive.
- Treat the repository-root `.env` as protected configuration: never commit it,
  provision it only through an approved secure channel, and require managed
  secret storage before a real study. It is never a release artifact.
- Destructive migrations require an explicit backup, rollback plan, owner
  approval, and restoration rehearsal.
- Store UTC timestamps and assignment versions with attempts and events.
- Version JSON-bearing assignment, submission, hint, and learning-event records
  with `data_schema_version`; update `docs/research/DATA_DICTIONARY.md` whenever
  a stored contract or allowlisted status/event value changes.
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

ROS grading must verify the stated one-command-per-callback contract, not just
an average publication rate. Keep callback instrumentation inside the isolated
Docker image; it is assessment evidence, never a substitute for isolation.
Run `backend/verify_ros2_assignments.py` after rebuilding that image to check
maintained answers and duplicate-publication rejection.

Before publishing or changing an assignment, verify:

- the maintained answer passes its versioned grader;
- starter code produces the expected instructional failure;
- an incorrect answer fails;
- syntax and runtime errors are reported safely;
- infinite loops, excessive output, unsafe imports, and oversized submissions
  are bounded; and
- hidden tests and solutions are absent from student responses.

`assignments_answers/` is controlled instructor material. Do not ship its contents
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
- Ground execution claims in the recorded grader evidence. Successful execution
  must not be described as a NameError; module-level variables may exist even
  when using them instead of function parameters fails other input scenarios.
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

- Keep Results as a separate, minimizable right-side overlay panel. Instructions
  retain their full workspace height; do not dock Results beneath them without
  explicit owner approval. Preserve results when minimizing/reopening and keep
  AI tutoring off by default.
- A collapsible, resizable terminal under the code editor (owner-approved
  2026-10-14) shows each run's printed output, the error with the student's
  own line, and a test summary, like the VS Code terminal. It adds to the
  Results overlay and never replaces it; build its lines only from the run
  result and the student's code, never from protected tests.

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
Flutter `build`, `.local-run`, local databases, database dumps, caches, and
generated logs. A clone must instead contain
the assignment sources, migrations, demo seed logic, tests, and setup scripts
needed to create a safe fresh demo database.

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
- Before an authorized push, verify the branch, working tree, exact staged
  files, and absence of secrets or accidental files.
- If manual QA or a broader regression check is advisable before pushing, tell
  the owner and recommend it, especially for risky or cross-cutting changes.
- After an authorized push, confirm the expected commit exists on the remote.
- Before production promotion, require a clean staging `main`, passing CI, an
  updated SQA record, and explicit owner approval.

## Release and rollback rules

Follow `docs/deployment/STAGING_AND_RELEASE_WORKFLOW.md` and the guarded scripts.

Before promotion:

- run `scripts/verify-local.ps1` on Windows or `scripts/verify-local.sh` on Ubuntu;
- verify PostgreSQL migrations and persistence;
- verify the dedicated sandbox and adversarial execution cases;
- verify student and instructor end-to-end workflows;
- verify research capture and export privacy;
- confirm AI is off by default;
- update the single master SQA workbook;
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

Keep long-form documentation under `docs/` according to `docs/README.md`.
Reserve the repository root for essential entry-point/governance documents and
runtime configuration files.

SQA evidence must state:

- feature or requirement tested;
- environment and commit SHA;
- exact check or user flow;
- expected and actual result;
- PASS, FAIL, PARTIAL, BLOCKED, or NOT RUN;
- reason for every non-PASS result; and
- follow-up owner or action when applicable.

Never convert a blocked or untested item into PASS based on assumption.

Maintain exactly one QA file:
`docs/sqa/Robotics_Programming_Lab_Master_SQA_Checklist.xlsx`.
Update its checklist, defect log, dated run evidence, and release sign-off
instead of creating separate QA Excel, CSV, or Markdown reports. Preserve
historical evidence and its original statuses. Imported reports are indexed
in QA Report Index, with complete text in QA Report Archive. Temporary test
logs may be generated outside tracked files; automated tests and test fixtures
are not QA reports and must remain in the repository.

## Review checklist

Before handing off a change, ask:

- Is the implementation generic enough for future assignments?
- Did authorization remain server-enforced?
- Could hidden tests, solutions, secrets, credentials, or student data leak?
- Can a timeout or exception leave the UI running forever?
- Are local and deployed paths driven by configuration from the same code?
- Does the database change have a tested migration and rollback path?
- Can an older browser draft be mistaken for the current assignment version?
- Do assignment diagrams use version-specific image URLs, and have the actual
  displayed diagrams been checked rather than only the source image files?
- Are untrusted submissions still isolated and bounded?
- Does the feature work with AI disabled?
- Are built-in hints available with AI off, and are misconception labels based
  on explicit grader evidence rather than model guesses or hint levels?
- Do route graders check exact return count and order, equivalent safe math
  methods, valid geometry, and every correct/wrong criterion combination?
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
