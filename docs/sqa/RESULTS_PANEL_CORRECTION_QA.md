# Isolated Results Panel Correction

Date: 2026-09-29. Scope: staging only; no backend, grading, account or database changes.

The v6.2 desktop bottom dock conflicted with the owner's requested isolated
results panel. Results now uses the existing right-side overlay on all widths.
Instructions retain their full height. Opening before a run, automatic opening
after a run, minimize/reopen, distinct results colors and AI-off defaults remain.

| Check | Result |
|---|---|
| Desktop overlay, no bottom dock; instructions retain original size | PASS: browser at 1280x720; widget test compares instruction size before/after opening |
| Minimize/reopen and AI off by default | PASS: widget regression and browser; retained 0% score, terminal output and four failed-check details after reopening |
| Automatic opening after Run tests | PASS: instructor preview, untouched Assignment 1 starter returns 0%; panel opens for loading and results |
| Narrow-screen panel and existing workspace shortcuts | PASS: browser at 390x844; responsive workspace and shortcut widget regressions |
| Flutter analysis | PASS: no issues |
| Flutter tests | PASS: all 89 tests |
| Release web build | PASS: API_BASE_URL=http://127.0.0.1:5100 |

Source: staging main base `27d883487ec4fe58ad7a15c4de27c090ac1356da`,
with the isolated-results correction on `ui/isolated-results-panel`.
Automated checks used a dependency-equipped frontend copy outside OneDrive;
the changed source and tests were copied from the canonical staging checkout.
Manual checks used the canonical launcher at http://127.0.0.1:8180/app with
API 5100 and sandbox 5101. Instructor preview avoided persistent submissions.

An initial widget size assertion ran before asynchronous loading settled; adding
the initial pumpAndSettle fixed the test setup. The final complete run passed.
One initial browser load encountered a transient debug-script loading error;
reloading after frontend startup restored rendering and the subsequent flows
passed. No application-startup change was made for that transient observation.

Not run: paid OpenAI requests, production deployment, physical Ubuntu checks,
and full six-assignment/backend regression. This is a frontend layout correction;
backend, grading and persistence code did not change. Desktop/mobile widget
coverage and browser smoke testing are the validation scope, not a claim that
the entire application has no bugs.

Unrelated answer/reference moves and the content-builder edit are excluded.
The existing V6.2 Excel sheet remains historical evidence, not a claim that
the bottom dock is the current approved design. No paid AI call is required.
