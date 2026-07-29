# IUSE Flask backend

## Install

From the repository root on Windows:

```powershell
python -m venv venv
.\venv\Scripts\python.exe -m pip install -r .\backend\requirements.txt
```

## Run

```powershell
Set-Location .\backend
..\venv\Scripts\python.exe run.py
```

The Waitress server listens on `http://0.0.0.0:5000`.

## Test

```powershell
..\venv\Scripts\python.exe -m pytest -q
..\venv\Scripts\python.exe -m pip check
```

## Configuration

- `OPENAI_API_KEY`: enables generated hints for failed submissions
- `OPENAI_HINT_MODEL`: optional model override; defaults to `gpt-4.1-mini`

Without an API key, assignment grading still works and the API returns a fallback hint.
