# Public Student Demo Session SQA Report

Date: 2026-08-12

Scope: credential-free student demo access with memory-only state

Branch under test: `codex-public-demo-staging`

## Acceptance result

The public demo provides the same assignment workspace, grading, feedback,
hint, solution-unlock, AI-toggle, and navigation capabilities as a student
account. Demo authentication, submissions, hints, drafts, scores, and solution
state are not written permanently. Refreshing `/app` returns to the login page
and starts a clean demo.

The login page does not display the student or instructor credential values.

## SQA results

| ID | Check | Expected | Actual evidence | Result |
|---|---|---|---|---|
| DEMO-001 | Public demo entry | A visitor can start without credentials | Rendered login shows **Try the student demo** and no credential values | PASS |
| DEMO-002 | Student capability parity | Demo can list, open, edit, run, submit, request hints, and unlock solutions | API workflow and rendered Assignment 2 run completed normally | PASS |
| DEMO-003 | Assignment inventory | Staging retains Assignments 1–5, including ROS Assignment 5 | Rendered catalog and backend inventory matched | PASS |
| DEMO-004 | Authentication persistence | No demo token is stored in browser preferences | Flutter policy test passed; restore rejects legacy demo tokens | PASS |
| DEMO-005 | Learning-progress persistence | Demo drafts, scores, attempts, submission IDs, and solution state stay in memory | Flutter store test proved saved student data is unchanged and demo data disappears on reload | PASS |
| DEMO-006 | Server persistence | Demo creates no auth-session, submission, hint, research-session, or audit rows | Focused API test compared all five database table counts before and after a run/hint/solution workflow | PASS |
| DEMO-007 | Browser refresh | Refresh resets the demo | Rendered `/app` refresh returned to login with no restored attempt | PASS |
| DEMO-008 | Cross-session isolation | One demo session cannot access another session's submission | Foreign hint returned 404 and foreign solution returned 403 | PASS |
| DEMO-009 | Logout | Logout revokes the in-memory token and session data | Logout returned 200; subsequent `/auth/me` returned 401 | PASS |
| DEMO-010 | Research integrity | Demo activity is excluded from permanent study capture | Demo research-session creation returned 409; frontend does not start the tracker | PASS |
| DEMO-011 | AI default | AI is available but off by default | Rendered assignment toolbar showed the AI toggle off | PASS |
| DEMO-012 | Backend regression | Existing backend behavior remains green | 104 backend tests passed | PASS |
| DEMO-013 | Frontend regression | Analyzer, all Flutter tests, and release web build pass | Zero analyzer findings, 41 Flutter tests passed, release build succeeded | PASS |
| DEMO-014 | Dependency integrity | Installed backend dependencies are consistent | `pip check` reported no broken requirements | PASS |

## Runtime notes

- The local API and dedicated sandbox health endpoints returned `status: ok`.
- AI was intentionally disabled for this SQA run; deterministic tutoring remains
  available and the application did not depend on a paid OpenAI request.
- The initial direct Flutter test command encountered the known OneDrive build
  lock. The repository's LocalAppData verification path completed analyze,
  tests, and the release build successfully.

## Remaining release work

| Item | Status | Reason / next action |
|---|---|---|
| Excel master SQA workbook update | BLOCKED | The required bundled spreadsheet authoring runtime was not available in this Codex session. This Markdown report records the complete evidence without modifying the workbook through an unsupported library. |
| Git commit and remote push | PENDING | Perform only after final diff, secret, generated-file, and assignment-separation review. |
| Deployed production smoke test | NOT RUN | Run after the live repository commit is intentionally pushed and Render/Vercel finish deployment. |

No functional blocker was found in the implemented demo session.
