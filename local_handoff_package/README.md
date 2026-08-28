# Local handoff package

Copy this entire folder into the root of a fresh staging Git clone. The normal
Windows PowerShell or Ubuntu Bash setup and run commands detect it
automatically.

A populated local copy contains one active private data set and may contain an
optional history subfolder:

```text
local_handoff_package/
├── .env                    private backend and optional AI configuration
├── latest.dump             active PostgreSQL handoff backup
├── latest.json             checksum and backup metadata
├── previous.dump           optional recovery copy
├── previous.json           optional recovery manifest
├── package.json            package metadata
└── history/                optional older recovery files
```

The managed launcher refreshes changed database data every 10 minutes. Create a
final device-handoff backup only while the application is stopped:

```powershell
.\scripts\stop-local.ps1
.\scripts\create-local-handoff-package.ps1 -IncludePrivateConfig
```

On Ubuntu:

```bash
./scripts/stop-local.sh
./scripts/create-local-handoff-package.sh --include-private-config
```

The application reads `.env` here directly and restores/saves PostgreSQL here;
these are not duplicate copy-only files. The generated contents are
intentionally ignored by Git. They may contain API
keys, password hashes, student attempts, analytics, and research data. Never
commit, email, or publicly share a populated package.

The Python virtual environment is not included. It contains device-specific
paths and compiled packages. On the destination computer, normal setup rebuilds
the exact pinned environment in that operating system's local user-data
directory. PostgreSQL custom-format dumps are shared by the supported Windows
and Ubuntu launchers.

Copy only this complete folder to another computer. The former
`local_database_backups` folder is obsolete and is not read by the application.
