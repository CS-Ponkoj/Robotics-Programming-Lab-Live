# Automatic Local Database Backup SQA Report

Date: 2026-08-26

Environment: canonical Windows staging checkout on `PONKOJ-PC`

Scope: managed local PostgreSQL backup lifecycle only

## Result

The local launcher now starts a managed backup worker. It creates a verified
PostgreSQL dump immediately after startup and every 10 minutes thereafter when
the database has changed. The explicit stop command terminates that worker
before creating the final handoff backup and releasing the device lock.

Closing a browser tab does not stop local services. Therefore, automatic
backups continue while the managed stack remains running, but a clean
`stop-local.ps1` remains mandatory before changing computers.

## QA evidence

| Check | Evidence | Result | Remaining limitation |
| --- | --- | --- | --- |
| PowerShell syntax | Database module, launcher, worker, and stop scripts parsed without errors | PASS | None |
| Managed worker startup | Runtime state recorded `database-backup`; worker produced a verified dump | PASS | Requires Docker PostgreSQL mode |
| Scheduled cycle | One-minute test interval produced a second worker log entry | PASS | Normal default is 10 minutes |
| Unchanged database | Consecutive cycle reported `Database unchanged; automatic backup skipped` | PASS | PostgreSQL-only optimization |
| Changed database | Controlled temporary-table change produced a new dump and SHA-256 manifest | PASS | Temporary probe was removed before final backup |
| Backup validation | Dump creation ran `pg_restore --list`; manifest recorded checksum, schema, system ID, and WAL position | PASS | None |
| Clean shutdown | Worker stopped first; final verified dump was saved; state and device-lock files were removed | PASS | User must run the stop command before device handoff |
| Active services | Backend, sandbox, frontend, and PostgreSQL started successfully; backend health returned `ok` | PASS | Browser-close detection is intentionally not used |
| Folder consolidation | Four older August 25 backups were preserved under `local_handoff_package/history/legacy-2026-08-25`; duplicate folder removed | PASS | History remains private and ignored by Git |
| Isolated handoff regression | Automated backup, unchanged skip, checksum rejection, device lock, same-device recovery, and simulated clean-device restore preserved all table counts | PASS | Physical second-device operation was not repeated |
| Complete local gate | 179 backend tests, dependency check, migrations, database handoff, Flutter analysis, 50 Flutter tests, release web build, and source-safety check | PASS | Existing unrelated V5.2 working-tree changes remain uncommitted |

## Operator rule

For another computer, copy only the complete `local_handoff_package` folder.
Do not copy a Python environment, Docker volume, cache, or an obsolete
`local_database_backups` folder. Stop the source stack and wait for OneDrive or
the copy operation to finish before starting on the destination device.
