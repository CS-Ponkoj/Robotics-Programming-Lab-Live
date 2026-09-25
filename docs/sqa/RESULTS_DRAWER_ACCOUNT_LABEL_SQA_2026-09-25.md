# Results drawer and account-label SQA

Date: 2026-09-25
Environment: local staging checkout, Flutter web, FastAPI, Neon staging, AI off

| Check | Evidence | Result |
|---|---|---|
| Account label | Refreshed local browser shows `Demo` beside the account icon; student, instructor, demo, and long-name widget tests pass | Pass |
| Instructions space | Mobile browser shows Instructions filling its workspace tab without an embedded Results section; desktop layout widget test passes | Pass |
| Results before first run | Browser Results button opens the differently colored drawer, with an empty state and AI switch off | Pass |
| Minimize and reopen | Browser minimization restores the workspace; Results button remains available | Pass |
| Run opens Results | Local demo starter-code run automatically opens the drawer and returns 0%, four failed tests, and their feedback | Pass |
| AI-off safety | Browser showed test details without an AI question form; backend unit test confirms built-in progressive hints do not call OpenAI when AI is off | Pass |
| Automated frontend | Flutter analysis, 67 widget/unit tests, and release web build | Pass |
| Focused backend | Tutor and API tests, 57 passed | Pass |
| Complete local gate | 206 backend tests, dependency and Python checks, 67 Flutter tests, analysis, release web build, fresh-clone source check, and managed service health | Pass |

The first full-gate run stopped after a successful private-config check because
its PowerShell wrapper read a stale Git exit code. The wrapper now checks the
script result directly; the complete gate then passed.

Limitations: Persistent student and instructor account names were checked by
widget tests, not a manual credentialed browser session. The existing tutor
question endpoint requires a prior submission, so the drawer can open before
the first run but questions become available after that run. Production was
not changed or tested by this staging check.
