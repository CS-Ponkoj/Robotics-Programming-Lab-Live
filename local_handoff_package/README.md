# Local handoff package

Copy this entire folder into the root of a fresh staging Git clone. The normal
Windows PowerShell or Ubuntu Bash setup and run commands detect it
automatically.

A populated copy contains the private configuration and account-import data:

```text
local_handoff_package/
├── .env                    private backend and optional AI configuration
├── study_accounts.json     editable account-import data
├── study_accounts_import_report.json  generated import result
└── legacy dump files       optional recovery archives from local PostgreSQL
```

The application reads `.env` and `study_accounts.json` here directly. When
Neon is configured, accounts, attempts, and analytics live in the shared
`robotics_lab_staging` database rather than in a synchronized local dump.
Generated contents are intentionally ignored by Git and may contain database
credentials, API keys, or temporary passwords. Never commit, email, or publicly
share a populated package.

The Python virtual environment is not included. It contains device-specific
paths and compiled packages. On the destination computer, normal setup rebuilds
the exact pinned environment in that operating system's local user-data
directory. PostgreSQL custom-format dumps are shared by the supported Windows
and Ubuntu launchers.

Copy only this complete private folder to another authorized computer. The
former `local_database_backups` folder is obsolete. Old dump files in this
folder are retained for recovery but are not updated during Neon-backed runs.
