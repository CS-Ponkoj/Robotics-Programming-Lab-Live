# Python Editor Upgrade SQA Report

Date: 2026-09-24
Scope: staging local application only; production was not changed.

## Implemented behavior

| Area | Result | Evidence |
|---|---|---|
| Multi-line Tab indentation | Pass | Selected lines are indented without replacing the selection |
| Multi-line Shift+Tab outdent | Pass | Selected lines are outdented as a block |
| Ctrl+Y redo | Pass | Editor history redo is explicitly supported; Ctrl+Shift+Z remains available |
| Draft durability | Pass | Persistent accounts save by user, assignment ID, and exact version in PostgreSQL, with a local fallback |
| Demo isolation | Pass | Demo draft writes never enter PostgreSQL |
| Save status | Pass | Saving, saved, and cloud-save-failed states are visible without blocking local editing |
| Ctrl+S save | Pass | Focused editor saves immediately; the browser test showed a session-save confirmation in demo mode |
| Editor color theme | Pass | Editor tools switches between dark and light syntax themes without changing the code or selection |
| Restore starter code | Pass | Confirmation is required; both server and local draft copies are cleared |
| Error line assistance | Pass | Valid Python traceback lines are highlighted and shown in the file status bar |
| Find and replace | Pass | Manual Find and Replace all actions are available in Editor tools |
| Font controls | Pass | Manual increase/decrease controls are bounded from 12 to 22 points |
| Shortcut help | Pass | The editor lists its supported keyboard shortcuts |
| Python/API help | Pass | Completion uses Python names plus functions, parameters, imports, and visible assignment project APIs |
| Manual Python formatting | Pass | Black formatting runs only when selected and never executes student code; syntax errors return safe feedback |
| ROS Python formatting | Pass | The formatter supports both `python` and `python-ros2` assignments |
| Responsive editor toolbar | Pass | Desktop split view and narrow/mobile layouts render without overflow in widget tests |

## Automated verification

| Check | Result |
|---|---|
| Backend dependency check | Pass — no broken requirements |
| Backend tests | Pass — 205 tests |
| Focused editor and API tests | Pass |
| Flutter analysis | Pass — no issues |
| Flutter tests | Pass — 61 tests |
| Flutter release web build | Pass |
| PostgreSQL migration | Pass — staging Neon upgraded from `0004` to `0005_code_drafts` |

## Manual staging verification

| Check | Result |
|---|---|
| Student login | Pass |
| Assignment 1 editor opens | Pass |
| Editor tools are visible | Pass |
| Manual formatter responds | Pass |
| Restore-starter confirmation and cleanup | Pass |
| Light theme | Pass — selected in the local browser and syntax colors changed while code stayed intact |
| Ctrl+S in focused editor | Pass — showed the demo-session save confirmation; no browser Save dialog appeared |
| Local API, sandbox, frontend, and database startup | Pass |

## Safety and limitations

- Test-case grading, scores, hidden tests, tutoring policy, and assignment
  content were not changed by this editor work.
- Formatting is explicit and server-side; it parses and rewrites Python but
  does not run the submission.
- The browser fallback cannot replace PostgreSQL for cross-device recovery.
- Editor theme selection is currently per open assignment page; it returns to
  dark when the workspace is reopened. Persistence was not requested or tested.
- Hardware-level Ubuntu and a second physical computer were not re-tested in
  this editor pass. Existing cross-platform scripts were left unchanged.
- The repository already contained unrelated Assignment 4 changes on branch
  `fix/assignment-4-starter-score`; those files were preserved and were not
  included as editor work.
