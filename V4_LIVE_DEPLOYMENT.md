# V4 live and local operation

V4 keeps one codebase for both modes:

- Local: Flutter web + FastAPI + ignored SQLite database.
- Live: Vercel static Flutter web + Render FastAPI + Neon PostgreSQL.
- AI tutoring: visible but off by default in both modes. The OpenAI key exists
  only in the backend environment.
- Password reset and email delivery: disabled for the professor demo.

## Local mode

From the repository root, start the backend in one PowerShell terminal:

```powershell
Set-Location .\backend
..\venv\Scripts\python.exe -m alembic -c alembic.ini upgrade head
..\venv\Scripts\python.exe run.py
```

Start Flutter in a second terminal:

```powershell
Set-Location .\frontend
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:5000
```

The local default remains SQLite. Do not set `ENVIRONMENT=production` locally.

## Live backend on Render

Create the service from the root [`render.yaml`](render.yaml). Supply these
values in Render without committing them:

| Variable | Value |
|---|---|
| `DATABASE_URL` | Neon pooled connection string |
| `OPENAI_API_KEY` | Existing key; optional runtime enhancement |
| `ALLOWED_ORIGINS` | Exact Vercel URL, such as `https://project.vercel.app` |
| `PUBLIC_APP_URL` | The same exact Vercel URL |
| `DEMO_STUDENT_PASSWORD` | Password shared privately with the professor |
| `DEMO_INSTRUCTOR_PASSWORD` | Password shared privately with the professor |

Render runs `alembic upgrade head` before starting FastAPI. The health check is
`/health`. Mutable state is stored in Neon, never Render's ephemeral filesystem.

## Live frontend on Vercel

Import the GitHub repository and leave the root directory at the repository
root. The root [`vercel.json`](vercel.json) runs the pinned Flutter build and
serves `frontend/build/web`.

Add one Vercel environment variable before deploying:

| Variable | Value |
|---|---|
| `API_BASE_URL` | Exact Render HTTPS service URL, without a trailing slash |

No database password or OpenAI key belongs in Vercel. After Vercel assigns the
final URL, update `ALLOWED_ORIGINS` and `PUBLIC_APP_URL` in Render to that exact
origin and redeploy the backend.

### Browser entry and session behavior

- Opening the public live URL at `/` always clears an old local session and
  shows the login page.
- Successful login changes the browser entry to `/#/app`. Refreshing that URL
  restores the current authenticated session.
- Signing out returns the browser to `/`, so the next person sees login first.
- Demo credentials remain private and are never printed on the login page.

## Release verification

Before promoting a commit:

```powershell
Set-Location .\backend
..\venv\Scripts\python.exe -m pytest tests -q
..\venv\Scripts\python.exe -m pip check

Set-Location ..\frontend
flutter analyze
flutter test
flutter build web --release --dart-define=API_BASE_URL=https://api.example.test
```

Then verify on the live URL:

1. The public root always opens at login; student and instructor logins work,
   but credentials are absent from the page.
2. All four assignments load, including Assignment 1's image.
3. Run and submit complete once, errors stop correctly, and repeated clicks are bounded.
4. Hidden grader data and solutions are absent from assignment responses.
5. AI is initially off; enabling it produces either OpenAI-enhanced or clearly
   labeled deterministic feedback without revealing hidden tests.
6. Instructor assignment and student-account actions persist after a Render restart.
7. The same repository still passes the local SQLite workflow above.

## Free-tier limitations

- Render free web services sleep after 15 idle minutes and can take about one
  minute to wake. The Flutter UI must tolerate that first slow response.
- Render storage is ephemeral; Neon is required for all mutable study data.
- The restricted subprocess runner is acceptable only for this controlled
  professor prototype. Before broad student or anonymous use, move grading to a
  dedicated network-disabled container or microVM execution service.
- Vercel Hobby is for personal/non-commercial use and applies usage limits.
- Monitor Neon storage and compute usage and export study data regularly.

Provider references: [Render free limitations](https://render.com/docs/free),
[Vercel Hobby](https://vercel.com/docs/plans/hobby), and
[Vercel project configuration](https://vercel.com/docs/project-configuration/vercel-json).
