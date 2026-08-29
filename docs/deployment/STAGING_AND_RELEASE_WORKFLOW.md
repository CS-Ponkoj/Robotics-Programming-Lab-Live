# Staging and Production Workflow

## Repository roles

| Repository | Role | Change policy |
|---|---|---|
| `CS-Ponkoj/Robotics-Programming-Lab-Staging` | Development, local execution, SQA, and release candidates | Feature branches merge into `main` only after focused checks. |
| `CS-Ponkoj/Robotics-Programming-Lab` | Live Vercel and Render deployment | No direct editing. It receives only an approved staging commit. |

Both repositories share Git history. A release is promoted by commit SHA, never
by copying files. Source, tests, dependency locks, assignment content, and
deployment configuration are therefore identical. URLs, database connections,
and secrets remain external environment values.

## Local staging workflow

Install once with the command for the current operating system:

```powershell
.\scripts\setup-local.ps1
```

```bash
./scripts/setup-local.sh
```

Python 3.14 is required. Setup creates an ignored device-local environment
under Windows LocalAppData or the Ubuntu XDG user-data directory. A laptop or
lab computer should clone the staging repository outside OneDrive and run its
operating-system setup command. Use `-Repair` on Windows or `--repair` on Ubuntu
only when normal setup reports an incomplete environment.

Run the complete application:

```powershell
.\scripts\run-local.ps1
```

```bash
./scripts/run-local.sh
```

This connects to the dedicated Neon `robotics_lab_staging` database and starts
the sandbox, API, and Flutter web application. Python and Flutter generated
files stay outside the clone. The ignored repository-root `.env` supplies the
Neon connection and optional AI configuration. Git supplies the password-free
account roster at `backend/data/study_accounts.json`.
AI is off. To test AI deliberately, use `-EnableAi`. To use an external staging
The launcher refuses to reuse ports already owned by an older project process;
stop that process or provide different `-FrontendPort`, `-BackendPort`, and
`-SandboxPort` values.

Stop the managed processes:

```powershell
.\scripts\stop-local.ps1
```

```bash
./scripts/stop-local.sh
```

Closing the browser is not enough; use the stop command to end the managed API,
sandbox, and Flutter processes. Neon keeps the shared data independently of the
local processes.

Run the full automated SQA gate:

```powershell
.\scripts\verify-local.ps1
```

```bash
./scripts/verify-local.sh
```

The Windows and Ubuntu workflows use the same source and handoff-package
contract. A physical Ubuntu 22.04 or 24.04 lab-computer smoke test is required
before an Ubuntu classroom release is declared hardware-compatible.

## Change workflow

1. Create a feature branch from staging `main`.
2. Make one focused change.
3. Run the closest backend or Flutter check.
4. Record the evidence in the SQA workbook.
5. Merge only after the focused check passes.
6. Run the application locally and complete the full SQA gate from staging
   `main`.
7. Keep the working tree clean and record the approved commit SHA.

## Release gate

Before production promotion:

- backend tests, dependency validation, and Python compilation pass;
- Flutter analysis, tests, and release web build pass;
- the sandbox container builds in GitHub Actions;
- correct and incorrect submissions behave as expected;
- older browser drafts are not reused after an assignment version changes;
- dangerous imports remain blocked;
- instructor-created student login and student data isolation pass;
- Neon persistence/restart testing and database-health checks pass;
- the workbook records zero open release blockers;
- staging `main` is clean and pushed; and
- the user explicitly approves the production release and release tag.

The guarded promotion command is:

```powershell
.\scripts\promote-release.ps1 -ReleaseTag v4.0.0 -ConfirmProduction
```

The script refuses dirty trees, wrong remotes, non-`main` branches, non-fast-
forward history, unpushed commits, and reused tags. It runs SQA again and sends
the approved commit and immutable tag to production atomically.

## Live validation and rollback

Vercel and Render must watch the production repository `main` branch. After a
promotion, confirm the backend health release SHA and test login, instructor
student creation, assignment loading, correct/incorrect grading, unsafe-code
rejection, persistence, and browser console behavior.

If a live gate fails, redeploy the preceding production tag. Fix the defect in
staging and repeat the complete release process; do not patch production.
