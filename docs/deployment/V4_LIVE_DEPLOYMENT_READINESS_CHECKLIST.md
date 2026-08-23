# Robotics Programming Lab v4 Live Deployment Readiness Checklist

Last audited: 2026-08-04

Target repository: `CS-Ponkoj/Robotics-Programming-Lab`

Target release: v4 live professor-review prototype

Checklist owner: project developer / SQA reviewer
Current release decision: **CLASSROOM CANDIDATE LOCALLY; deploy and complete the live sandbox/restart/restore gates before giving the URL to students.**

This is the release gate for putting the current v3 application online without removing working functionality. The existing [master SQA checklist](../sqa/Robotics_Programming_Lab_Master_SQA_Checklist.xlsx) remains the general feature checklist; this document adds the v4 hosting, security, persistence, and live-parity gates.

## How to use this checklist

- `[x]` means the item was verified with evidence.
- `[ ]` means the item is not yet verified or implemented.
- P0 is a release blocker. P1 is required for v4. P2 is a documented improvement that may follow the professor demo.
- Do not approve v4 while any P0 or P1 row is open.
- Test a focused change immediately after it is made. Run the full integrated checks again only after all focused checks pass.
- Record the command, URL, date, tester, and result in the Evidence/notes column or the final SQA report.

## 1. Approved v4 scope and architecture

The recommended v4 deployment keeps the existing Flutter/FastAPI stack:

```text
Professor or student browser
        |
        v
Flutter Web static site - Vercel Hobby
        |
        v
FastAPI application - Render Free Web Service
        |
        +---- PostgreSQL - Neon Free
        +---- OpenAI API - optional, backend secret only
        |
        v
Dedicated grading container - Render Docker Web Service
        +---- no database or OpenAI secrets
        +---- authenticated requests and restricted workers
```

Initial assignment images and reference files will be bundled with the backend deployment. Instructor-uploaded files should use object storage in a later release; the Render filesystem must never be treated as persistent storage. Redis/background workers are intentionally deferred until grading or simulation jobs exceed the current short synchronous request window. Self-service password reset and email delivery are also deferred for the professor demo. Their existing code will be preserved, but the live demo will hide/disable those entry points and use instructor-managed demo accounts.

| ID | Priority | Check | Requirement / decision | Acceptance evidence |
|---|---|---:|---|---|
| V4-SCOPE-001 | P0 | [ ] | Approve v4 as a controlled professor-review prototype, not an unrestricted public code-execution service. | Written approval; public indexing is disabled and credentials are shared privately. |
| V4-SCOPE-002 | P0 | [ ] | Confirm that all current student and instructor features listed in Section 7 must remain available online. | Feature-parity matrix approved before implementation. |
| V4-SCOPE-003 | P0 | [ ] | Approve Vercel + Render + Neon as the free-host plan. No email provider is required for the professor demo. | Accounts can be created and provider terms are acceptable for an academic prototype. |
| V4-SCOPE-004 | P0 | [ ] | Keep demo login IDs `student` and `instructor`, but never display either account's credentials on the login page. | UI, page source, and compiled asset search contain no demo credential text. |
| V4-SCOPE-005 | P0 | [ ] | Use strong deployment-only demo passwords supplied as secrets; do not use `student` or `instructor` as live passwords. | Both live logins work with privately stored passwords; defaults do not work online. |
| V4-SCOPE-006 | P1 | [ ] | AI tutoring is present but OFF by default for every clean login and every newly opened assignment. | UI test and request-log evidence show no OpenAI call until the user opts in. |
| V4-SCOPE-007 | P1 | [ ] | The local application remains runnable after live deployment. | Local backend + Flutter instructions and tests still pass using local environment values. |

### Required local/live dual-mode support

V4 must use the same source code and approved Git SHA locally and online. Hosting configuration may change through environment variables, but live deployment must not replace or break the v3-style local workflow.

| ID | Priority | Check | Requirement | Acceptance evidence |
|---|---|---:|---|---|
| V4-LOCAL-001 | P0 | [ ] | Preserve the local FastAPI command on `127.0.0.1:5000` and Flutter Chrome command with `--dart-define=API_BASE_URL=http://127.0.0.1:5000`. | A clean local start opens the login page and passes the complete student/instructor smoke test. |
| V4-LOCAL-002 | P0 | [ ] | Keep SQLite as the zero-setup local database while production uses Neon PostgreSQL through `DATABASE_URL`. | Local startup creates/uses only the ignored local database; live startup creates no SQLite file. |
| V4-LOCAL-003 | P0 | [ ] | Keep local demo IDs `student` and `instructor`; do not display credentials in either local or live login UI. | Both local accounts work and compiled/text scans contain no visible credential instructions. |
| V4-LOCAL-004 | P1 | [ ] | Keep AI optional and OFF by default locally and online. A local ignored `.env` may provide an OpenAI key without changing source. | Local and live no-AI tests pass; opt-in tests are separate. |
| V4-LOCAL-005 | P1 | [ ] | Do not require Vercel, Render, Neon, or internet connectivity for the normal local no-AI assignment workflow. | With external-provider settings absent, local login, assignments, grading, hints, progress, and instructor screens work. |
| V4-LOCAL-006 | P1 | [ ] | Keep production-only URLs, passwords, and secrets out of local source/configuration examples. | `.env.example` contains names/placeholders only; secret and compiled-asset scans pass. |
| V4-LOCAL-007 | P1 | [ ] | Document two clearly labeled procedures in the README: `Run locally` and `Use the live application`. | A second tester follows each procedure successfully without undocumented commands. |
| V4-LOCAL-008 | P0 | [ ] | Run the final full SQA suite twice from the same release SHA: once locally and once on the deployed URLs. | The final report records both environments, versions, URLs, and results with no unexplained behavior difference. |

## 2. Current baseline evidence

### Live deployment evidence added 2026-08-03

| Area | Result | Live evidence |
|---|---:|---|
| Release identity | [x] PASS | Render deploys the unchanged `v4-live` backend; Vercel production tracks `v4-live` and serves the public-entry application release `a16292c`. GitHub `v4 verification` passed for the final application release. |
| Live frontend | [x] PASS | `https://robotics-programming-lab.vercel.app` returns HTTP 200 over HTTPS with the SPA rewrite and configured security headers. |
| Live backend | [x] PASS | `https://robotics-programming-lab-api.onrender.com/health` returns HTTP 200 with API `4.0.0`. |
| Exact-origin CORS | [x] PASS | Preflight from the production Vercel origin returns the exact `Access-Control-Allow-Origin` value and permits the required methods/headers. |
| Student smoke | [x] PASS | The login page shows no demo credentials or password-reset link; the student demo logs in, exactly four assignments load, Assignment 1's image loads, AI is OFF, and Run Tests stops with structured evidence (`0 passed`, `4 failed`) for the starter placeholders. |
| Instructor smoke | [x] PASS | The instructor demo logs in; the assignment studio lists four published versioned assignments; the student-account screen loads the active demo student and exposes the instructor management controls. |
| Student API contract | [x] PASS | Authenticated live assignment listing returns four assignments and contains none of `hidden_tests`, `official_solution`, or `reference_solution`. |
| Hosting defect 1 | [x] FIXED | The first Flutter deployment compiled but Vercel could not find the configured artifact. `vercel.json` was corrected from `frontend/.flutter_build/web` to the clean-run output `frontend/build/web`; the next production build passed. |
| Hosting defect 2 | [x] STABILIZED | One login attempt during the Render redeploy transition received a failed preflight. After the service became healthy, exact-origin preflight and a clean student login passed. The free-tier cold-start/redeploy disclosure remains required. |
| Demo-password exception | [ ] ACCEPTANCE REQUIRED | The live demo currently preserves the previously requested simple passwords (`student` and `instructor`). Credentials are not displayed, but these passwords are not suitable for an unrestricted public service. Replace them with private strong Render secrets before any real participant study. |
| Remaining SQA | [ ] OPEN | Full correct-solution coverage for Assignments 1-4, mutation/persistence after restart, mobile/accessibility, hostile-submission live probes, AI-on provider behavior, rollback/restore, and an independent clean-device round remain open. |

### V4 implementation evidence added 2026-08-03

| Area | Check | Current evidence |
|---|---:|---|
| Clean release branch | [x] PASS | `v4-live` is based exactly on active `origin/main` SHA `3cc641d3`; the retired IUSE history is not used. |
| Login/reset demo scope | [x] PASS | Credentials and Forgot password are absent by default; public reset and SMTP endpoints return 404; instructor manual password reset remains. |
| Assignment authorization | [x] PASS | Assignment list/detail/run/submit/hint/solution and legacy grade require a valid session; student identity is server-derived and ownership tests pass. |
| Abuse controls | [x] PASS | Request-size, per-user/IP rate, `Retry-After`, and two-slot global execution limits are implemented and tested. |
| Restricted executor | [x] CONTROLLED DEMO | AST/private-attribute and unsafe NumPy file APIs are blocked; child environment is scrubbed; Linux resource limits apply; all four official solutions pass. A dedicated microVM/container grader remains required before broad public use. |
| Neon persistence layer | [x] PASS | TLS pooled Neon connection succeeds, Alembic baseline applied, production health returns PostgreSQL, both demo logins seed, and four assignments load. Restart persistence remains a post-deploy test. |
| Migration compatibility | [x] PASS | Alembic tests pass for both a fresh schema and adoption of an existing v3 schema. SQLite remains the local default. |
| Production configuration | [x] PASS | Production rejects SQLite, automatic schema creation, and wildcard CORS. Public health is minimal and OpenAPI/docs are disabled. |
| Render configuration | [x] LIVE | `render.yaml` deployed from `v4-live`; migrations, startup, health, Neon, exact-origin CORS, auth, and assignment APIs passed the live smoke. |
| Vercel configuration | [x] LIVE | `vercel.json` and the pinned Flutter 3.32.8 script produced the corrected production artifact and the final Vercel domain serves v4. |
| CI | [x] IMPLEMENTED | GitHub Actions verifies backend tests/dependencies/PostgreSQL migration plus Flutter dependencies/analyzer/tests/release build. First hosted run remains pending. |
| Local automated gate | [x] PASS | 59 backend tests, `pip check`, 30 Flutter tests, analyzer, and release web build pass. The OneDrive-safe script also completes outside the synced build directory. |
| Local browser SQA | [x] PASS | Student/instructor login, four assignments, Assignment 1 image, Run Tests completion/error, AI-off default, logout, assignment studio, and email-free student account UI pass with zero browser console warnings/errors. |
| Public entry policy | [x] LIVE PASS | Opening `/` with a saved student session shows login; student and instructor demos both authenticate into `/app`; refreshing `/app` restores the signed-in assignment page. Credentials remain absent from login. Focused tests, all 32 Flutter tests, analyzer, release build, GitHub CI, Vercel deployment, and live browser SQA pass. |
| Secret audit | [x] PASS | No tracked environment folders/files and no OpenAI/Neon credential patterns in tracked files or active `origin/main` history. Ignored `.env` remains untracked. |
| Remaining go-live gates | [ ] PENDING | Use strong private live demo passwords, complete the remaining live feature matrix, cold-start/restart persistence, hostile-execution checks, independent SQA, rollback/restore, and the final Excel/SQA report. |

These checks describe the current local version. They do not by themselves approve the live release.

| ID | Check | Current result | Evidence from 2026-08-03 audit |
|---|---:|---|---|
| V4-BASE-001 | [x] | PASS | Backend tests: `46 passed` from `backend` using `..\venv\Scripts\python.exe -m pytest tests -q`. |
| V4-BASE-002 | [x] | PASS | Python environment: `pip check` reported no broken requirements. |
| V4-BASE-003 | [x] | PASS | Flutter static analysis completed with no issues. |
| V4-BASE-004 | [x] | PASS | Flutter tests: `29 passed`. |
| V4-BASE-005 | [x] | PASS | Flutter release web build completed successfully. Output was 41 files / 26.3 MiB. |
| V4-BASE-006 | [x] | PASS | `/health` returned `status=ok`, API `2.0.0`, SQLite, and subprocess sandbox. |
| V4-BASE-007 | [x] | PASS | API smoke: student and instructor logins succeeded; four published assignments and four admin assignments loaded; starter code executed successfully; one managed student loaded. |
| V4-BASE-008 | [x] | PASS | Browser smoke: student login, assignment list, Assignment 1 editor, Run Tests, results, instructor login, assignment studio, and student-account page rendered and responded. |
| V4-BASE-009 | [x] | PASS / FIXED | Sign-out now waits for the popup route to close; widget regression and browser-console tests pass. |
| V4-BASE-010 | [x] | PASS / FIXED | The login page and default compiled UI contain no displayed demo credentials. |
| V4-BASE-011 | [x] | PASS / FIXED | Assignment execution, grading, hints, solutions, and legacy grade now require authentication and enforce submission ownership. |

## 3. Source-control and release identity gates

| ID | Priority | Check | Requirement | Acceptance evidence |
|---|---|---:|---|---|
| V4-SRC-001 | P1 | [ ] | Keep the project in OneDrive and use active `CS-Ponkoj/Robotics-Programming-Lab` `origin/main` as the v4 base. The retired local branch does not need to be rewritten or deployed. | `git remote -v`, `git status`, and `git rev-parse origin/main` show the expected repository and approved base SHA. |
| V4-SRC-002 | P1 | [ ] | Create the v4 implementation branch from active `origin/main`. Recommended branch: `v4-live`. | Branch has a merge base with `origin/main`; initial diff contains only the approved checklist/implementation. |
| V4-SRC-003 | P0 | [ ] | Ensure no virtual environment, database, Flutter cache, build output, `.env`, study account file, or editor setting is tracked. | `git ls-files env venv` returns zero; generated-file audit is clean. |
| V4-SRC-004 | P0 | [ ] | Copy this reviewed checklist into the clean v4 branch before implementation. | File is present in the v4 branch and retains reviewer decisions. |
| V4-SRC-005 | P1 | [ ] | Set a consistent release identity: Flutter `4.0.0+1`, API version `4.0.0`, and build commit SHA. | Version is visible in build metadata/health output and SQA report. |
| V4-SRC-006 | P0 | [ ] | Run a tracked-file and Git-history secret scan before the first deployment. Rotate any exposed key rather than only deleting it. | Scan report contains no API keys, passwords, tokens, connection strings, or real participant data. |
| V4-SRC-007 | P1 | [ ] | Pin direct Flutter dependencies instead of `any`, retain `pubspec.lock`, and record Python 3.14. | Clean CI install resolves the same versions twice. |
| V4-SRC-008 | P1 | [ ] | Record the final v4 commit SHA before deployment. Do not tag or publish until the user explicitly approves it. | Approved SHA appears in the release report. |

## 4. Confirmed blockers and required solutions

| ID | Priority | Check | Confirmed gap | Best v4 solution and focused proof |
|---|---|---:|---|---|
| V4-FIX-001 | P0 | [ ] | Demo credentials are hardcoded in backend seeding and printed on the login page. | Remove the login-page credential block. Seed fixed IDs with deployment-only password secrets. Test that credentials are absent from source/build and both accounts still exist. |
| V4-FIX-002 | P0 | [ ] | Student run, submit, hint, and solution endpoints allow anonymous access. | Require an authenticated student/instructor on all attempt routes; retain public assignment reading only if intentionally approved. Add 401, ownership, and instructor-access tests. |
| V4-FIX-003 | P0 | [ ] | Anonymous or non-owning users can address a submission if they learn its UUID. | Bind every submission/hint/solution read to the authenticated user; permit instructor access through a separately tested role rule. |
| V4-FIX-004 | P0 | [x] | The production API previously executed student code in its own subprocess. | A separate authenticated Docker sandbox service now contains no database/OpenAI credentials; worker environments are scrubbed and CPU/memory/file/process/output/time limits plus the AST allowlist remain. Contract and secret-exclusion tests pass. Live deployment proof remains required. |
| V4-FIX-005 | P0 | [x] | Execution limits previously relied on client-IP buckets that could be changed with forwarding headers. | Run/submit quotas now follow the authenticated account, cannot be bypassed with `X-Forwarded-For`, return `429` + `Retry-After`, and retain global API/sandbox concurrency and request-size ceilings. |
| V4-FIX-006 | P0 | [ ] | SQLite and local JSON/files would be lost on Render restarts or idle spin-down. | Use Neon PostgreSQL for users, sessions, assignments, attempts, feedback, and progress. Keep only immutable bundled assets on disk. Verify persistence after redeploy/restart. |
| V4-FIX-007 | P0 | [ ] | The backend uses `Base.metadata.create_all` and has no versioned production migrations. | Add Alembic baseline and forward migration. Test a fresh database, upgrade from the v3 schema, rollback procedure, and idempotent assignment/demo-account seed. |
| V4-FIX-008 | P2 | [ ] | Self-service password reset and email delivery are deferred for the professor demo. | Preserve the existing reset/email code for a future release. Add a production feature flag that hides the Forgot password and email-status/test UI and disables public reset endpoints while instructor-managed password reset remains available. |
| V4-FIX-009 | P0 | [ ] | Sign-out triggers a Flutter deactivated-widget ancestor assertion. | Allow the popup route to close before the root authentication state/navigation changes. Add widget and browser-console regression tests. |
| V4-FIX-010 | P0 | [ ] | Assignment 1 stores `http://localhost:5000/images/1` in HTML. | Store server-relative/structured asset references and resolve them through the configured backend URL. Reject localhost/127.0.0.1 in published content and release assets. |
| V4-FIX-011 | P1 | [ ] | The old Monaco page/app script is shipped but appears unused; it defaults to localhost and loads code from a third-party CDN. | Prove it is unused, then exclude it from production assets, or fully configure/authenticate it and add CSP/SRI. Release scan must find no unintended localhost dependency. |
| V4-FIX-012 | P0 | [ ] | Production CORS currently defaults to `*`. | Set `ALLOWED_ORIGINS` to the exact production Vercel origin. Use separate explicit preview origins; do not let arbitrary preview sites call production. Test allowed and rejected preflights. |
| V4-FIX-013 | P1 | [ ] | `/health` exposes database/sandbox details and `/docs` is public. | Make public health minimal (`status`, version, commit); protect or disable detailed diagnostics/OpenAPI in production. |
| V4-FIX-014 | P1 | [ ] | Login throttling is in memory and resets on restart. | Store failed-login windows in PostgreSQL for v4 or explicitly use a database-backed limiter. Test restart behavior and successful-account recovery. |
| V4-FIX-015 | P1 | [ ] | Browser bearer tokens are stored in web local storage. | Keep the short-lived token model for the prototype, add strong CSP/XSS controls, revoke on logout/password changes, avoid token logging, and document HttpOnly cookies as a future production upgrade. |
| V4-FIX-016 | P1 | [ ] | Admin API token can bypass instructor login if configured. | Leave the legacy admin token unset in production or replace it with a separately scoped, rotated maintenance mechanism. Instructor UI must use role authentication. |

## 5. Hosting and environment checklist

### Vercel frontend

| ID | Priority | Check | Requirement | Acceptance evidence |
|---|---|---:|---|---|
| V4-WEB-001 | P0 | [ ] | Add a reproducible CI build for Flutter Web; do not depend on a manual OneDrive build folder. | GitHub Actions installs the pinned Flutter version and produces the same release artifact from a clean runner. |
| V4-WEB-002 | P0 | [ ] | Compile the production backend URL using `--dart-define=API_BASE_URL=https://<render-service>`. | Search built assets and network requests; no request targets localhost. |
| V4-WEB-003 | P1 | [ ] | Add Vercel SPA rewrite/fallback and security/cache headers. | Root load, browser refresh, assets, manifest, and service worker pass. CSP is tested with Flutter/CanvasKit. |
| V4-WEB-004 | P1 | [ ] | Use cache-safe versioning so a new deployment cannot retain an old backend URL. | Upgrade test from build N to N+1 shows the new version/API without manual cache clearing. |
| V4-WEB-005 | P1 | [ ] | Keep static upload below Vercel Hobby's 100 MB limit. | Current output is 26.3 MiB; CI reports size and fails before 90 MiB. |
| V4-WEB-006 | P1 | [ ] | Confirm Vercel Hobby's personal/non-commercial fair-use terms fit this academic prototype. | Owner records confirmation; move to an institution-approved plan/host if the study becomes production/commercial. |
| V4-WEB-007 | P1 | [ ] | Add a clear `Waking up the server...` state with retry for Render cold starts. | First request after 15+ idle minutes recovers without a permanent error or endless spinner. |

### Render backend

| ID | Priority | Check | Requirement | Acceptance evidence |
|---|---|---:|---|---|
| V4-API-001 | P0 | [ ] | Add `render.yaml` or equivalent documented settings with Python 3.14, root/build/start commands, health path, and environment variables. | A clean Render deployment succeeds from the approved SHA without dashboard-only mystery steps. |
| V4-API-002 | P0 | [ ] | Bind Uvicorn to `0.0.0.0:$PORT`; do not hardcode port 5000 for the live process. | Render health check and public HTTPS URL succeed. |
| V4-API-003 | P0 | [ ] | Keep all secrets in Render environment variables, never Vercel/Dart or Git. | Backend receives secrets; compiled frontend and repository scans are clean. |
| V4-API-004 | P1 | [ ] | Use one worker for the initial free service and enforce execution concurrency limits. | Parallel run test returns controlled responses without exhausting memory. |
| V4-API-005 | P1 | [ ] | Add structured, redacted logs with request ID, user ID, action, latency, result, and release SHA. | Logs contain no password, reset token, bearer token, API key, full code, or hidden grader data. |
| V4-API-006 | P1 | [ ] | Handle free-instance cold start and unexpected restart. | Sessions/data survive; frontend retries; no local-file dependency breaks. |
| V4-API-007 | P1 | [ ] | Add graceful OpenAI timeouts and error mapping. | Provider failures return a bounded, useful response and do not leave UI spinners running. |

### Neon PostgreSQL

| ID | Priority | Check | Requirement | Acceptance evidence |
|---|---|---:|---|---|
| V4-DB-001 | P0 | [ ] | Create a Neon project/branch for v4 and use the pooled runtime URL with TLS. | Render connects after both services have been idle. No SQLite file is created in production. |
| V4-DB-002 | P0 | [ ] | Normalize Neon's URL for SQLAlchemy/psycopg (`postgresql+psycopg://`) or explicitly configure the driver. | Fresh deploy connects without a missing `psycopg2` error. |
| V4-DB-003 | P0 | [ ] | Use a direct/migration-safe connection for Alembic if the pooled URL is unsuitable. | CI/deploy migration completes once and application startup is race-safe. |
| V4-DB-004 | P0 | [ ] | Verify instructor edits, demo accounts, attempts, progress, feedback, and sessions persist after Render restart and redeploy. | Before/after persistence test report. |
| V4-DB-005 | P1 | [ ] | Define export/backup and restore steps within the free tier's retention limits. | Encrypted export restored into a clean test database. |
| V4-DB-006 | P1 | [ ] | Monitor Neon free usage (currently 0.5 GB and 100 CU-hours/project/month) and define an archive threshold. | Warning threshold and owner are documented. |

### Deferred email delivery (not a v4 demo release gate)

The professor demo does not require an email provider or self-service password reset. These P2 items remain for a future student-study release and do not block v4 demo approval.

| ID | Priority | Check | Requirement | Acceptance evidence |
|---|---|---:|---|---|
| V4-MAIL-001 | P2 | [ ] | Select an HTTPS transactional email provider for a future release; do not rely on Render-blocked SMTP. | Provider decision is approved when self-service reset enters scope. |
| V4-MAIL-002 | P2 | [ ] | Verify the sender address/domain required by the future provider. | Delivery succeeds to an address other than the provider account email. |
| V4-MAIL-003 | P2 | [ ] | Store the future provider key only in Render and redact provider responses. | Secret scan/log review passes. |
| V4-MAIL-004 | P2 | [ ] | Test future activation/reset links with the Vercel production URL, single-use token, expiry, and already-used behavior. | End-to-end reset test succeeds and negative cases fail safely. |
| V4-MAIL-005 | P2 | [ ] | Enforce future reset-request throttling and non-enumerating responses. | Existing and unknown emails return the same public response; burst returns 429. |

## 6. Code-execution and grader safety gate

Production grading now crosses an authenticated boundary into a dedicated Docker
service that has no database or OpenAI secrets. The student worker remains a
short-lived restricted subprocess inside that container; this is a controlled
classroom boundary, not approval for anonymous public code execution.

| ID | Priority | Check | Requirement | Acceptance evidence |
|---|---|---:|---|---|
| V4-RUN-001 | P0 | [ ] | Require authentication for every execution and grade request. | Anonymous requests return 401 and create no process/submission. |
| V4-RUN-002 | P0 | [ ] | Parse and validate the AST before execution using an assignment-aware allowlist. | Tests reject dunder/private access, dynamic class traversal, unsafe imports, `eval`/`exec`, filesystem, process, socket/network, reflection, and resource-abuse patterns. |
| V4-RUN-003 | P0 | [ ] | Restrict module and attribute access to the minimum required by each assignment. | Assignments 1-4 official solutions pass; malicious import/attribute suite fails. |
| V4-RUN-004 | P0 | [ ] | Enforce wall time, CPU time, memory, output, file size, and child-process limits on Render Linux. | Infinite loop, memory growth, output flood, and process-spawn tests terminate within limits. |
| V4-RUN-005 | P0 | [x] | Add per-account quotas and global API/sandbox concurrency ceilings. | Burst, capacity, retry, and forwarded-header bypass tests pass. |
| V4-RUN-006 | P0 | [ ] | Never send grader configuration, expected values, official solutions, or reference paths to student APIs. | Contract tests scan every student response for hidden fields. |
| V4-RUN-007 | P1 | [ ] | Validate every assignment's official solution before publish and on every CI run. | All four current assignments and future fixtures pass their versioned grader. |
| V4-RUN-008 | P1 | [ ] | Save stable assignment ID and version with every run/submit. | Database/API test confirms version retention after assignment edit. |
| V4-RUN-009 | P1 | [x] | Before classroom use, move execution outside the API into a dedicated secret-free grading container with hard worker limits. | Remote contract, service authentication, invalid-response, resource, and secret-exclusion tests pass locally; live Render proof remains open. |

## 7. Live functional-parity matrix

Every row must be tested against the final Vercel URL, not localhost. Repeat the critical student and instructor paths in a clean/incognito session.

| ID | Role | Check | Feature / acceptance result |
|---|---|---:|---|
| V4-FEAT-001 | Public | [ ] | Login page loads over HTTPS with no demo credential text, debug banner, console error, or mixed content. |
| V4-FEAT-002 | Student | [ ] | `student` demo ID logs in with the privately shared live password. |
| V4-FEAT-003 | Instructor | [ ] | `instructor` demo ID logs in with the privately shared live password. |
| V4-FEAT-004 | Auth | [ ] | Invalid login, lockout/rate limit, session restore, logout, expired session, and password change behave correctly. |
| V4-FEAT-005 | Auth | [ ] | Self-service Forgot password is hidden/disabled in the live demo; direct reset requests are disabled, and existing reset/email code remains available for a future release. |
| V4-FEAT-006 | Student | [ ] | Dashboard lists exactly the four current published assignments with titles, versions, descriptions, and progress. |
| V4-FEAT-007 | Student | [ ] | Assignment 1 instructions and robot image load from the live backend. |
| V4-FEAT-008 | Student | [ ] | Each assignment opens with the correct starter code, instructions, objectives, rubric, and current version. |
| V4-FEAT-009 | Student | [ ] | Editor typing, scrolling, copy/paste, syntax highlighting, draft save, refresh restore, and reset behavior work. |
| V4-FEAT-010 | Student | [ ] | Run/submit returns within the timeout; the button stops running on success, failure, timeout, 401, 429, and backend cold start. |
| V4-FEAT-011 | Student | [ ] | Correct solutions for Assignments 1-4 pass with expected scores and evidence. |
| V4-FEAT-012 | Student | [ ] | Incorrect but runnable solutions fail with accurate evidence; syntax/runtime errors are readable and safe. |
| V4-FEAT-013 | Student | [ ] | Progress, attempts, last score, completion, drafts, and submission IDs remain correct after logout, new browser, and backend restart. |
| V4-FEAT-014 | Student | [ ] | Progressive hint levels work and solution reveal stays gated; another student's submission ID cannot be used. |
| V4-FEAT-015 | Student | [ ] | AI toggle is visible and OFF by default; built-in/non-AI behavior remains available. |
| V4-FEAT-016 | Student | [ ] | When AI is enabled, a failing attempt returns a clearly labeled OpenAI tutor response; disabling it stops OpenAI requests. |
| V4-FEAT-017 | Instructor | [ ] | Assignment studio lists the same four assignments and their versions/status. |
| V4-FEAT-018 | Instructor | [ ] | Create draft, edit, validate, publish, archive/remove behavior, stable ID, version increment, hidden grader, rubric, misconceptions, tutoring rules, and simulation configuration work. |
| V4-FEAT-019 | Instructor | [ ] | A failing official solution blocks publish; a passing one permits publish. |
| V4-FEAT-020 | Instructor | [ ] | Student-account list, create, edit, deactivate/reactivate, password reset, and temporary credential workflow work. |
| V4-FEAT-021 | Instructor | [ ] | Account import writes to PostgreSQL and does not depend on a mutable Render JSON file. |
| V4-FEAT-022 | Instructor | [ ] | Email configuration warnings and test controls are hidden in the live demo; instructor-managed student password reset still works without email. |
| V4-FEAT-023 | Authorization | [ ] | Student cannot open instructor pages/APIs; unauthenticated access is rejected; instructor access is explicit and audited. |
| V4-FEAT-024 | Responsive | [ ] | Chrome desktop, narrow mobile viewport, keyboard navigation, focus visibility, semantics, and text scaling pass. |
| V4-FEAT-025 | Reliability | [ ] | Refresh, back/forward, service-worker update, offline/error states, Render cold start, and provider failure do not create endless spinners. |
| V4-FEAT-026 | Diagnostics | [ ] | Browser console and backend logs contain no uncaught exception, Flutter assertion, failed asset, CORS error, or secret. |

## 8. AI tutoring gate

| ID | Priority | Check | Requirement | Acceptance evidence |
|---|---|---:|---|---|
| V4-AI-001 | P0 | [ ] | Keep `OPENAI_API_KEY` exclusively in Render secrets. | Git history, frontend bundle, browser network, and logs contain no key. |
| V4-AI-002 | P0 | [ ] | Add a backend capability/status flag so the UI does not silently call a built-in hint “AI” when OpenAI is unavailable. | Toggle is disabled/clearly explained without a key; configured path reports `source=openai`. |
| V4-AI-003 | P0 | [ ] | Default AI to false in Flutter state and backend schema. | Clean-session UI/API tests prove false; current local defaults are already false. |
| V4-AI-004 | P0 | [ ] | Filter tutor context: do not send hidden test labels/messages, expected values, grader config, official solution, reference path, email, login ID, or participant ID to OpenAI. | Mock-client test captures the exact payload and confirms prohibited fields are absent. |
| V4-AI-005 | P0 | [ ] | Treat student code as untrusted data, not instructions, and test prompt-injection attempts. | Tutor refuses requests to reveal tests/solutions or change role. |
| V4-AI-006 | P1 | [ ] | Enforce per-user AI quotas, timeout, zero/limited retries, model allowlist, and daily cost ceiling. | Quota test and provider usage alert are configured. |
| V4-AI-007 | P1 | [ ] | Keep deterministic built-in feedback available when AI is off or the provider fails, but label the source correctly. | UI clearly distinguishes `OpenAI tutor hint` and `Built-in tutor hint`. |
| V4-AI-008 | P1 | [ ] | Obtain professor/institution approval before sending study submissions to a third-party AI provider. | Data-flow disclosure and approval are recorded. |

## 9. Security, privacy, and study-data checklist

| ID | Priority | Check | Requirement | Acceptance evidence |
|---|---|---:|---|---|
| V4-SEC-001 | P0 | [ ] | Use HTTPS only for frontend, API, email links, and database TLS. | No mixed content; HTTP redirects to HTTPS. |
| V4-SEC-002 | P0 | [ ] | Never store real student credentials, emails, reset tokens, study data, database exports, or API keys in Git/JSON files in the repository. | Repository/history scan and `.gitignore` audit pass. |
| V4-SEC-003 | P0 | [ ] | Hash passwords with the existing Argon2 path; use random reset/session tokens and store only hashes where applicable. | Auth unit tests and database inspection pass. |
| V4-SEC-004 | P0 | [ ] | Add CSP, `nosniff`, referrer policy, permissions policy, frame policy, and safe cache rules without breaking Flutter. | Header scan and browser smoke pass. |
| V4-SEC-005 | P0 | [ ] | Sanitize instructor-authored HTML and URLs; block scripts, event handlers, dangerous schemes, and mixed content. | Stored/reflected XSS suite passes. |
| V4-SEC-006 | P1 | [ ] | Define data collected, purpose, access, retention, export, deletion, and incident owner before real participant use. | Approved data-management note exists. |
| V4-SEC-007 | P1 | [ ] | Use pseudonymous participant codes where possible and minimize email/PII. | Database and exports contain only approved fields. |
| V4-SEC-008 | P1 | [ ] | Confirm institutional/IRB/FERPA requirements with the professor before a research study; do not treat this checklist as legal approval. | Professor/institutional decision recorded. |
| V4-SEC-009 | P1 | [ ] | Disable search-engine indexing for the controlled demo and avoid publishing credentials in README/issues/screenshots. | `robots.txt`/metadata and repository review pass. |
| V4-SEC-010 | P1 | [ ] | Add dependency/security scans and remediate critical/high findings. | `pip-audit`, Dart dependency review, and secret scan reports are attached. |

## 10. CI/CD and automated release gates

| ID | Priority | Check | Required clean-run check |
|---|---|---:|---|
| V4-CI-001 | P0 | [ ] | Backend: run tests from `backend`; all tests pass. |
| V4-CI-002 | P0 | [ ] | Backend: `pip check` and dependency audit pass. |
| V4-CI-003 | P0 | [ ] | Frontend: `flutter pub get`, `flutter analyze`, and all Flutter tests pass. |
| V4-CI-004 | P0 | [ ] | Assignment validation: official solutions for every published assignment pass; intentionally wrong solutions fail. |
| V4-CI-005 | P0 | [ ] | Security suite: anonymous execution, ownership bypass, sandbox escape, XSS, CORS, rate-limit, hidden-data, and prompt-injection tests pass. |
| V4-CI-006 | P0 | [ ] | Database: fresh Alembic migration and v3-to-v4 upgrade test pass on PostgreSQL. |
| V4-CI-007 | P0 | [ ] | Release build uses the production API URL and contains no secret, demo password, or unintended localhost reference. |
| V4-CI-008 | P1 | [ ] | Release artifact size, source maps/debug banner, service worker, manifest, icons, and license notices are verified. |
| V4-CI-009 | P1 | [ ] | Deploy frontend/backend only from an approved GitHub SHA after tests pass; no manual untested upload. |
| V4-CI-010 | P1 | [ ] | Post-deploy smoke automatically checks frontend 200, API health, CORS, assignment list, and authenticated disposable test account. |
| V4-CI-011 | P1 | [ ] | A failed migration/deploy stops promotion and leaves the previous live version available. |
| V4-CI-012 | P0 | [ ] | The release pipeline verifies both supported modes: local-style SQLite configuration and production-style PostgreSQL configuration. |

## 11. Live SQA execution rounds

| ID | Check | Round / acceptance evidence |
|---|---:|---|
| V4-LIVE-001 | [ ] | Round 1 developer smoke: all P0 feature rows pass on final live URLs. |
| V4-LIVE-002 | [ ] | Round 2 independent SQA: execute every row in Section 7 using clean student and instructor sessions. |
| V4-LIVE-003 | [ ] | Test after 15+ minutes idle to observe Render cold start and frontend recovery. |
| V4-LIVE-004 | [ ] | Test after a Render redeploy/restart; database data and account changes persist. |
| V4-LIVE-005 | [ ] | Test AI off, AI on, invalid key/quota/provider timeout, and cost/rate limit. |
| V4-LIVE-006 | [ ] | Confirm self-service password reset/email UI and endpoints are disabled for the demo; verify instructor-managed student password reset. |
| V4-LIVE-007 | [ ] | Test malicious/oversized/infinite submissions and confirm controlled termination. |
| V4-LIVE-008 | [ ] | Test Chrome desktop plus a narrow mobile viewport; inspect browser console and Render logs. |
| V4-LIVE-009 | [ ] | Professor handoff rehearsal: open the link from a different network/device and use only the supplied instructions. |
| V4-LIVE-010 | [ ] | Update the [master SQA checklist](../sqa/Robotics_Programming_Lab_Master_SQA_Checklist.xlsx) and issue a dated final v4 SQA report. |
| V4-LIVE-011 | [ ] | Check out the exact deployed SHA in OneDrive and repeat the local backend + Flutter browser smoke test; confirm v4 remains locally runnable like v3. |

## 12. Rollback, recovery, and handoff

| ID | Priority | Check | Requirement | Acceptance evidence |
|---|---|---:|---|---|
| V4-OPS-001 | P0 | [ ] | Record previous frontend/backend deploy IDs and approved Git SHA. | One-command/dashboard rollback target is known. |
| V4-OPS-002 | P0 | [ ] | Export/backup the database before migration and test restore. | Restore drill succeeds in a non-production database. |
| V4-OPS-003 | P1 | [ ] | Document rollback order for frontend, backend, and database schema. | Another person can follow the runbook. |
| V4-OPS-004 | P1 | [ ] | Prepare a professor handoff page with live URL, private demo IDs/passwords, expected cold-start delay, AI toggle explanation, and issue contact. | Handoff is tested from a clean device; credentials are not in Git or public chat. |
| V4-OPS-005 | P1 | [ ] | Define who can access Vercel, Render, Neon, OpenAI, and GitHub and how keys are rotated. | Owner/access list is stored privately. |
| V4-OPS-006 | P1 | [ ] | Keep local run instructions valid and include live/local environment examples without secrets. | A clean local setup passes the baseline suite. |

## 13. Known free-tier limitations and disposition

Provider limits were checked against official documentation on 2026-08-03 and must be rechecked immediately before deployment.

| Limitation | Impact | Best available free-plan mitigation | Release disposition |
|---|---|---|---|
| Render sleeps after 15 minutes idle and may take about one minute to wake. | First API request may feel broken or time out. | Add explicit wake/retry UI and rehearse before professor review. Do not use artificial keep-alive traffic as the primary solution. | Acceptable for professor demo only after V4-WEB-007 passes. |
| Render Free filesystem is ephemeral and free services can restart. | SQLite, uploads, mutable JSON, and local study data disappear. | Neon for all mutable data; immutable bundled assets only; future uploads go to object storage. | Not acceptable until V4-FIX-006 passes. |
| Render Free blocks outbound SMTP ports 25/465/587. | Current email/reset delivery cannot work on the free backend. | Email/reset is disabled for the professor demo; use an HTTPS email provider in a future student-study release. | Accepted for the v4 demo because email is out of scope. |
| Render Free does not provide persistent disk, SSH, one-off jobs, scaling, or a nested Docker daemon. Free web services also cannot receive private-network traffic. | The sandbox must be a separate public-HTTPS Docker service and both services can cold-start. | Shared-secret authentication, no application secrets in the sandbox, strict worker controls, bounded 90-second UI wait, and exact URL configuration. | Acceptable for a controlled classroom study after live sandbox verification; not for anonymous public use. |
| Render grants 750 free instance hours/workspace/month and can suspend at limits. | No uptime guarantee; other free services in the workspace share capacity. | One backend service, monitor usage, retain rollback/local demo. | Acceptable for scheduled professor review, not a production SLA. |
| Vercel Hobby is personal/non-commercial and caps CLI static uploads at 100 MB. | Terms or artifact growth may force a plan/host change. | Confirm academic use; current build is 26.3 MiB; enforce size gate. | Acceptable after owner confirmation. |
| Neon Free currently provides 0.5 GB and 100 CU-hours per project/month and can scale to zero. | Cold DB connection and eventual capacity limit. | Pooling/retry, usage alerts, export/archive plan. | Acceptable for prototype volume. |
| OpenAI API usage is funded/billed separately. | Unexpected usage or quota failure can affect the tutor. | AI off by default, per-user quota, cost ceiling, timeout, labeled fallback. | Acceptable only after AI gate passes. |
| OneDrive can lock/read-only Flutter build directories. | Local builds may fail even when source is correct. | Build/deploy in clean GitHub Actions runners; keep source in OneDrive but never deploy a cached local build blindly. | Acceptable with CI release build. |
| Free tiers have no production SLA. | Live link can be unavailable during provider incidents. | Label v4 a prototype, retain local demo and rollback instructions. | Must be disclosed to professor. |

Official references:

- [Render free-instance limits](https://render.com/docs/free)
- [Vercel Hobby plan](https://vercel.com/docs/plans/hobby)
- [Vercel platform limits](https://vercel.com/docs/limits)
- [Neon pricing and free limits](https://neon.com/pricing)

## 14. Checklist coverage double-check

The checklist itself was reviewed against the repository and live-host plan in these areas:

| Review area | Check | Result |
|---|---:|---|
| Current repository, remotes, branches, generated files, and active GitHub default branch | [x] | Branch-history/generated-environment blocker captured. |
| Backend tests, dependency consistency, health, API auth, assignments, grading, and instructor routes | [x] | Current passes and unauthenticated execution gap captured. |
| Flutter analysis, tests, release build, login, student, instructor, and browser console | [x] | Current passes plus credential display and sign-out assertion captured. |
| API URLs, CORS, port binding, service worker, static artifact, and unused web editor assets | [x] | Production configuration gates captured. |
| PostgreSQL persistence, schema migrations, seed behavior, restart, backup, and restore | [x] | Neon and Alembic gates captured. |
| Code sandbox, hidden grading data, rate limits, resource abuse, and ownership | [x] | Controlled-demo restriction and future isolated runner gate captured. |
| AI opt-in, key handling, hidden evidence, prompt injection, privacy, cost, and fallback | [x] | AI gates captured. |
| Login credentials, deferred self-service reset/email, demo feature flags, and instructor-managed account recovery | [x] | Demo scope and future email work are separated. |
| Free-tier cold start, storage, quotas, terms, no-SLA, and OneDrive build locking | [x] | Known limitations and mitigations captured. |
| CI/CD, live SQA, rollback, professor handoff, study privacy, and future scaling | [x] | Release/operations gates captured. |

## 15. Final go-live approval

Do not check this section until implementation and both live SQA rounds are complete.

- [ ] All P0 items are checked with evidence.
- [ ] All P1 items are checked with evidence.
- [ ] Section 7 functional parity is 100% passing on the final Vercel URL.
- [ ] No unresolved critical/high security, privacy, data-loss, or sandbox defect remains.
- [ ] Accepted free-tier limitations are explicitly approved for the professor demo.
- [ ] AI is present, off by default, bounded, and correctly labeled.
- [ ] Demo student/instructor IDs exist; credentials are absent from the login page, repository, build, and logs.
- [ ] Rollback and database restore were tested.
- [ ] The final SQA report and Excel master checklist were updated.
- [ ] User approves the final Git SHA for deployment/push/tag/release.
- [ ] Final decision: **GO for v4 professor review**.

Reviewer: ____________________  Date: __________  Final SHA: ____________________
