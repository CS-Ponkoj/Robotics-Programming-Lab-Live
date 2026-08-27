# First-time run on any Windows computer

Use the OneDrive staging folder on the main desktop. On a laptop or lab
computer, clone the staging Git repository into a normal local folder. Both run
the same source code.

## 1. Install the required software

Install [Git for Windows](https://git-scm.com/download/win), Python 3.14,
[Docker Desktop](https://docs.docker.com/desktop/setup/install/windows-install/)
with Linux containers, and
[Flutter](https://docs.flutter.dev/get-started/install/windows/web) with web
support. Add Git, Python, and Flutter to `PATH` when their installers request
it. Reopen PowerShell, start Docker Desktop, and verify:

```powershell
git --version
py -3.14 --version
docker version
docker compose version
flutter --version
flutter doctor
```

Resolve any command-not-found error before continuing.

If PowerShell blocks project scripts, allow signed/local scripts for your user
once, then reopen PowerShell:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## 2. Open or clone the project

On the main desktop, open the canonical folder:

```text
C:\Users\cspon\OneDrive - University of Nevada, Reno\Robotics-Programming-Lab-Staging
```

On another computer, clone into a local folder outside OneDrive:

```powershell
$projectParent = Join-Path $env:USERPROFILE "Projects"
New-Item -ItemType Directory -Force -Path $projectParent | Out-Null
Set-Location $projectParent
git -c core.longpaths=true clone https://github.com/CS-Ponkoj/Robotics-Programming-Lab-Staging.git
Set-Location .\Robotics-Programming-Lab-Staging
git config core.longpaths true
```

If you want the same accounts, attempts, analytics, and private settings, stop
the source app and copy its complete `local_handoff_package` folder into the
root of the clone. Otherwise the clone starts with fresh demo data.

## 3. Prepare the computer

From the repository root:

```powershell
.\scripts\setup-local.ps1
```

This creates the Python environment and generated caches under this computer's
`LocalAppData`, installs `backend/requirements.txt`, and reports the active
package paths. Use `-Repair` only if normal setup reports an incomplete Python
environment.

## 4. Build the ROS 2 grader once

```powershell
docker compose --profile build build ros2-grader-image
```

Rebuild after its Dockerfile or ROS grading dependencies change.

## 5. Start and stop

```powershell
.\scripts\run-local.ps1 -FrontendPort 8180 -BackendPort 5100 -SandboxPort 5101
```

Open `http://127.0.0.1:8180/app`. Stop safely with:

```powershell
.\scripts\stop-local.ps1
```

The managed launcher backs up changed PostgreSQL data every 10 minutes while
the stack is running. Closing the browser does not close the backend or create a
device handoff. Before changing computers, always run `stop-local.ps1` and wait
for `local_handoff_package` to finish copying or synchronizing.

A clean stop validates and saves PostgreSQL directly to:

```text
local_handoff_package/
├── .env
├── latest.dump
├── latest.json
├── previous.dump
├── previous.json
├── history/              optional older recovery files
└── package.json
```

The live PostgreSQL Docker volume remains computer-local. The files above are
the portable backup and configuration used directly by the app. Do not edit
the dump or manifest, and never run the same copied package on two computers at
once. Stop first, wait for file copying or OneDrive synchronization to finish,
and then start on the other computer.

## Optional verification

```powershell
.\scripts\verify-local.ps1 -ApiBaseUrl http://127.0.0.1:5100
.\scripts\check-ros2-local.ps1
```

## Common problems

| Message or symptom | Correct action |
| --- | --- |
| `git`, `py`, `docker`, or `flutter` is not found | Install that prerequisite, reopen PowerShell, and verify its version. |
| Docker is unavailable | Start Docker Desktop and select Linux containers. |
| A port is in use | Run `stop-local.ps1`, or choose unused port parameters. |
| Database is assigned to another device | Stop it there and wait for the package to finish copying or syncing. |
| Only one of `latest.dump` or `latest.json` exists | Restore the complete pair from a known-good package copy. |
| An old `local_database_backups` folder exists | It is obsolete. Preserve unique old files under `local_handoff_package/history`, then use only the complete handoff package. |
| Python environment is incomplete | Stop the app, then run `setup-local.ps1 -Repair`. |
| ROS grading image is missing | Run the ROS image build command from step 4. |
| Flutter reports a locked build directory | Use `run-local.ps1`; do not run Flutter directly in the OneDrive source folder. |

The package is ignored by Git and is not encrypted. It may contain API keys,
password hashes, student work, analytics, and research records. Do not commit,
email, publicly share, or leave it on an untrusted computer.
