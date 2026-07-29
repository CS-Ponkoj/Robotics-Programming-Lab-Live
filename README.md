# Robotics Programming Lab

An interactive robotics-education prototype with a Flask API, a Flutter web interface, automated Python assignment grading, and optional AI-generated hints.

## Project layout

- `backend/`: Flask API, assignment data, grading worker, and pytest suite
- `frontend/`: Flutter application for web and other Flutter targets
- `course_materials/`: source documents, exercises, and official solution files

## Prerequisites

- Python 3.10 or 3.11
- Flutter 3.32 or another compatible stable release with web support
- Chrome or Edge for the Flutter web target

Android builds additionally require the Android SDK. Windows desktop builds require Visual Studio with the Desktop development with C++ workload. Neither is required for the web application.

## First-time setup

From the repository root:

### Windows PowerShell

```powershell
python -m venv venv
.\venv\Scripts\python.exe -m pip install -r .\backend\requirements.txt
Set-Location .\frontend
flutter pub get
```

### Linux or macOS

```bash
python3 -m venv venv
./venv/bin/python -m pip install -r ./backend/requirements.txt
cd frontend
flutter pub get
```

## Optional AI hints

The grader works without an API key. Failed submissions return a fallback hint when OpenAI is unavailable.

To enable generated hints, provide `OPENAI_API_KEY` in the backend process environment or in an ignored `backend/.env` file. `OPENAI_HINT_MODEL` is optional and defaults to `gpt-4.1-mini`. Never commit a populated `.env` file.

## Run the application

Open two terminals from the repository root.

Backend on Windows:

```powershell
Set-Location .\backend
..\venv\Scripts\python.exe run.py
```

Backend on Linux or macOS:

```bash
cd backend
../venv/bin/python run.py
```

Frontend:

```powershell
Set-Location .\frontend
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:5000
```

For a backend on another host, replace `API_BASE_URL` with the URL reachable from the device running the frontend.

## Verification

Backend:

```powershell
Set-Location .\backend
..\venv\Scripts\python.exe -m pytest -q
..\venv\Scripts\python.exe -m pip check
```

Frontend:

```powershell
Set-Location .\frontend
flutter analyze
flutter test
flutter build web --dart-define=API_BASE_URL=http://127.0.0.1:5000
```

## Execution safety

Student submissions run in a short-lived isolated Python worker with an import allowlist, execution timeout, output cap, and request-size limit. This protects the Flask server from common mistakes and runaway code. An internet-facing or multi-tenant deployment should add an OS-level sandbox or container with restricted filesystem, network, CPU, and memory access.
