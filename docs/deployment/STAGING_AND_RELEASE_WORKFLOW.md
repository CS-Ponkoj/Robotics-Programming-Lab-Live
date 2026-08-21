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

Install once:

```powershell
python -m venv venv
.\venv\Scripts\python.exe -m pip install -r .\backend\requirements.txt
```

Run the complete application:

```powershell
.\scripts\run-local.ps1
```

This starts the dedicated sandbox, API, and Flutter web application. Flutter is
run from a generated LocalAppData copy to avoid OneDrive build-directory locks.
The default database is the ignored `backend/robotics_lab_staging.db`, and AI is
off. To test AI deliberately, use `-EnableAi`. To run final PostgreSQL parity
testing, pass the separate staging Neon connection string through `-DatabaseUrl`.
The launcher refuses to reuse ports already owned by an older project process;
stop that process or provide different `-FrontendPort`, `-BackendPort`, and
`-SandboxPort` values.

Stop the managed processes:

```powershell
.\scripts\stop-local.ps1
```

Run the full automated SQA gate:

```powershell
.\scripts\verify-local.ps1
```

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
- dangerous imports remain blocked;
- instructor-created student login and student data isolation pass;
- PostgreSQL persistence/restart testing passes;
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
