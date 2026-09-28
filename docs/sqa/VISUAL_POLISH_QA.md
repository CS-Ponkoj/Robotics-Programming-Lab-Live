# Local visual polish QA — 2026-09-28

Scope: staging checkout, `feature/course-content-library`, base `831f5cd`
plus uncommitted working changes. No production change or publication.
Normal app: http://127.0.0.1:8180/app; API 5100; sandbox 5101; existing
Neon staging configuration. No paid AI calls.

## Implementation

- Preserve the common branded header and Assignment/Contents navigation.
- Shared accessible text, error, warning, success, results-surface colors.
- Consistent form focus borders, outlined buttons, tooltips and table headings.
- Equal-height content cards per responsive row, without truncating descriptions.
- Wrap score badges under enlarged text; all six cards keep attempt/best/latest
  values, including not-attempted state.
- Constrain lesson prose to 880 pixels and improve paragraph/heading spacing.
- Use the same readable instruction font as the application.
- Preserve the results drawer, editor shortcuts, light/dark editor palettes,
  and AI-off default. Form styling must not override the editor background.
- Use bordered white analytics cards with complete labels and a one-column
  layout on very narrow screens; instructor/account status colors match.
- No grading, analytics formula, auth, database schema or API changes in this task.

## Confirmed issues found and fixed

| Issue | Evidence | Fix |
|---|---|---|
| Score badges overflow with 150% text scaling | New widget checks failed at tablet/desktop widths | Flexible badge text wraps; all three width checks pass |
| Form fill overrides dark code-editor background | Browser screenshot during incremental QA | Do not globally fill input decorations; regression assertion added |
| Partial-status orange was inconsistent with accessible shared palette | Code inspection | Shared amber foreground/container |
| Analytics card labels could be truncated | Code inspection | Remove two-line ellipsis; retain complete labels |

## Verification

| Check | Result | Evidence / limit |
|---|---|---|
| Shared normal text contrast | PASS | At least 4.5:1 for primary/surface/secondary/status combinations |
| Score badges, every integer percentage 0–100 | PASS | Contrast measured on actual 12%-tinted white badge background |
| Catalog at 390, 768, 1440 width with 150% text | PASS | No layout exceptions; all six progress summaries render |
| Full Flutter widget/unit suite | PASS | 85 tests, including roles, analytics, editor palettes, retry/loading, instructions, results and AI-off behavior |
| Flutter analysis | PASS | No issues |
| Release web build | PASS | OneDrive-safe copy, API_BASE_URL points to local 5100 |
| Student browser: catalog toggle, account/header, saved quiz summary | PASS | Existing 30% quiz summary remains visible at normal 8180 URL |
| Lesson reading at desktop and portrait phone width | PASS | Screenshot inspection: wrapping, headings, navigation |
| Keyboard Home and catalog toggle | PASS | Enter activation and Tab focus inspected |
| Results open before run; AI off | PASS | Distinct blue-tinted drawer; switch false; no request sent |
| Final editor light/dark and drawer minimize | PASS | Both palettes visually inspected after repair; minimize returns to editor without changing code |
| Instructor browser/account studio | NOT RUN | Role/dashboard widget coverage passed; separate instructor browser session not exercised |
| New quiz submissions and six-assignment grading sweep | NOT RUN | Presentation-only change; avoid adding persistent study attempts |
| Physical Ubuntu / other device / all screen-reader combinations | NOT RUN | This session is Windows desktop; not an accessibility certification |

`AGENTS.md` checked: no new environment, architecture, security or release rule
introduced by visual polish, so no additional governance edit was needed.
Existing unrelated course/backend changes, moved reference PDFs and answer-folder
rename were preserved. Earlier full backend QA reported missing old
`manual_sqa_answers` paths; that independent rename is not repaired here and
remains a publication concern. No secrets, generated builds, or screenshots
were added to Git. Screenshot evidence is in the local safe QA directory.

## v6.1 publication gate

The owner authorized staging `main` publication with commit message `v6.1`.
The existing remote cleanup commit `b15efff` was retained. The commit excludes
the unrelated local answer-folder rename, reference-PDF moves and content-build
script cleanup; those files remain local user work.

- Full backend suite on an export of the exact staged Git contents: **215 passed**.
  This export retains the tracked `manual_sqa_answers` folder, so the earlier
  local-only missing-answer-path failures do not apply to the published snapshot.
- Focused course/migration suite: **13 passed**; `pip check`: no broken requirements.
- Frontend final revision: **85 passed**, analyzer clean, release web build passed.
- Staged secret-pattern scan, forbidden tracked-path scan and diff whitespace
  check: **PASS**. Private configuration and generated artifacts remain excluded.
- Instructor manual browser and physical Ubuntu QA remain not run in this gate;
  automated role/dashboard coverage passed. No production deployment authorized.
