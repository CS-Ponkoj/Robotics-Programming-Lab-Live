# Local handoff package

Copy this entire folder into the root of a fresh staging Git clone. The normal
`setup-local.ps1` and `run-local.ps1` commands detect it automatically.

A populated local copy contains one flat set of active private files:

```text
local_handoff_package/
├── .env                    private backend and optional AI configuration
├── latest.dump             active PostgreSQL handoff backup
├── latest.json             checksum and backup metadata
├── previous.dump           optional recovery copy
├── previous.json           optional recovery manifest
└── package.json            package metadata
```

Create or refresh it only while the application is stopped:

```powershell
.\scripts\stop-local.ps1
.\scripts\create-local-handoff-package.ps1 -IncludePrivateConfig
```

The application reads `.env` here directly and restores/saves PostgreSQL here;
these are not duplicate copy-only files. The generated contents are
intentionally ignored by Git. They may contain API
keys, password hashes, student attempts, analytics, and research data. Never
commit, email, or publicly share a populated package.

The Python virtual environment is not included. It contains device-specific
paths and compiled packages. On the destination computer, normal setup rebuilds
the exact pinned environment safely under LocalAppData.
