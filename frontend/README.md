# Robotics Programming Lab Flutter frontend

## Supported local run

The repository is inside OneDrive, so use the root automation. It prepares a
safe generated Flutter copy under LocalAppData and starts PostgreSQL, sandbox,
API, and web UI together:

```powershell
Set-Location ..
.\scripts\setup-local.ps1
.\scripts\run-local.ps1 -FrontendPort 8180 -BackendPort 5100 -SandboxPort 5101
```

Open `http://127.0.0.1:8180/app`. Stop cleanly from the repository root with:

```powershell
.\scripts\stop-local.ps1
```

Do not use `flutter run` directly inside the OneDrive source folder for normal
operation; OneDrive can lock generated Flutter files. For a frontend-only
diagnostic outside OneDrive, install packages and point the build at an already
running API:

```powershell
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:5100
```

`API_BASE_URL` must be reachable from the target device. For example, an Android emulator normally needs the host address rather than `127.0.0.1`.

The local prototype login accounts are:

```text
Student:    student / student
Instructor: instructor / instructor
```

The signed-in role controls access to instructor assignment and student-account
management. Session tokens are issued by the backend and restored locally
between authenticated app refreshes. Persistent student code drafts are saved
to PostgreSQL with both assignment ID and version and retain a local browser
fallback; an older-version draft is not loaded into a newer assignment. Demo
drafts remain session-only.

## Verify

From the repository root, run `scripts/verify-local.ps1` for the complete gate
or `scripts/verify_frontend_onedrive.ps1` for the OneDrive-safe Flutter analyzer,
test, and release-build checks.
