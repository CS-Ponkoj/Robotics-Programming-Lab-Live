# Local database handoff files

This OneDrive-synchronized directory receives verified PostgreSQL logical
backups created by `scripts/stop-local.ps1`.

- `latest.dump` is the newest complete database backup.
- `latest.json` records its checksum, source computer, schema revision, and UTC
  creation time.
- `previous.dump` and `previous.json` preserve the preceding successful backup.
- `active-device.json` prevents ordinary use on two computers at the same time.

These generated files are deliberately ignored by Git. Never place a live
PostgreSQL data directory or Docker volume here. Wait for OneDrive to report
**Up to date** before starting the application on another computer.
The launcher also uses `latest.dump` to recover when the same computer's Docker
volume has been recreated and the PostgreSQL application schema is missing.

The current prototype backups are not encrypted. Before collecting real
student or research data, move to approved managed storage or add an approved
encrypted-backup procedure.
