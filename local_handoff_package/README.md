# Private staging configuration

This ignored folder contains only the local secrets used by the Neon-backed
staging application:

```text
local_handoff_package/
├── .env                    private backend and optional AI configuration
├── .gitignore              secret-safety rule
└── README.md               this file
```

The application reads `.env` directly. The password-free account roster is
tracked at `backend/data/study_accounts.json`. Accounts, password hashes,
attempts, and analytics live in the shared Neon `robotics_lab_staging` database.
Local database dumps, manifests, device locks, and backup history are not part
of the current architecture.

The private contents are intentionally ignored by Git and may contain database
credentials or API keys. Never commit or publicly share them. For a future
no-copy multi-computer workflow, use a hosted staging backend
whose secret environment is configured once; Git clones then need only its
public HTTPS URL.
