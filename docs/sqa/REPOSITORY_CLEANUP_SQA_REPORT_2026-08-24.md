# Repository cleanup SQA report

**Date:** 2026-08-24
**Repository:** `CS-Ponkoj/Robotics-Programming-Lab-Staging`
**Working branch:** `maintenance/repository-cleanup`
**Protected baseline:** `5ef8f8e2211821e87286e96cf9d418e4782da307`

## Outcome

The structured cleanup is a staging release candidate. Rebuildable local
artifacts and Git garbage were removed, unused tracked duplicates were deleted,
and historical evidence was moved into labeled archives. Assignment content,
instructor answers, environments, databases, PostgreSQL backups, generated PDF
outputs, Flutter platform projects, and production configuration were preserved.

## Cleanup evidence

| Area | Evidence | Result |
|---|---|---:|
| Recovery point | `backup-v5-pre-cleanup-2026-08-24` published at baseline commit | PASS |
| Generated artifacts | Fixed allow-list removed approximately 133.42 MB across initial and final passes | PASS |
| Git object store | Integrity checked; 174.35 MB temporary garbage removed; one 137.53 MB pack remains | PASS |
| Unused tracked files | Removed unreferenced `frontend/code.txt` and the unused duplicate `backend/files/` assets | PASS |
| Course material | Source paths retained; seven unreferenced screenshots moved from `ss/` to `archive/screenshots/` | PASS |
| Documentation | Current documents remain active; superseded SQA and v4 deployment records moved to `docs/archive/` | PASS |
| Markdown links | All repository Markdown files scanned; zero broken relative links | PASS |
| Ignore rules | Root `.gitignore` deduplicated and verified against databases, output, runtime, and caches | PASS |
| Legacy SQLite data | Seven different databases inspected, totaling 10-340 rows each; all preserved because their data differs | PASS |
| Protected paths | `venv`, databases, backups, output, course sources, and instructor answers excluded from cleanup | PASS |

## Regression evidence

| Check | Evidence | Result |
|---|---|---:|
| Backend regression | 174 tests passed | PASS |
| Python dependencies | `pip check` found no broken requirements | PASS |
| Python compilation | Backend compilation completed without error | PASS |
| PostgreSQL handoff | Migration, checksummed backup, lock, same-device recovery, and clean-device restore passed with 183 rows | PASS |
| Flutter static analysis | No issues found | PASS |
| Flutter regression | 49 tests passed | PASS |
| Flutter release build | OneDrive-safe release web build passed | PASS |
| Assignment content | 15 focused repository/classroom-readiness tests passed after file cleanup | PASS |
| Assignment image | Active image and JSON 404 behavior passed after duplicate removal | PASS |
| ROS 2 Assignment 5 | 7/7 checks; 78 Twist messages at approximately 10.0 Hz | PASS |
| ROS 2 Assignment 6 | 9/9 checks; 44 settled Twist messages at approximately 9.2 Hz | PASS |
| Git integrity | Full object integrity check passed before and after maintenance | PASS |

## Manual browser QA

| Flow | Evidence | Result |
|---|---|---:|
| Login | Clean root displayed the study login and temporary demo option | PASS |
| Demo catalog | Six assignments displayed and demo mode was clearly labeled temporary | PASS |
| Demo execution | Assignment 1 starter code ran once and returned the expected structured 0% result | PASS |
| Demo reset | Refresh returned to login after Flutter initialization | PASS |
| Student account | Default student login displayed persisted progress and all six assignments | PASS |
| Student analytics | `My study progress` displayed attempts, completion, score, time, and recent attempts | PASS |
| Instructor studio | Six versioned assignments and instructor controls rendered | PASS |
| Student management | Default student account rendered with active status | PASS |
| Research dashboard | Participant-safe aggregate dashboard rendered | PASS |
| Responsive layout | Login, catalog, workspace, and instructor dashboard had no page-width overflow at 390 x 844 | PASS |
| Browser console | No application errors; only the known Flutter debug tooling warning appeared | PASS |

## Remaining limitations

- The master Excel SQA workbook is retained as historical evidence and was not
  edited because the approved spreadsheet runtime was unavailable. Current
  evidence is in this Markdown report and the PostgreSQL handoff report.
- The seven ignored SQLite databases contain different historical records.
  They remain in place until an owner-approved archival or import decision is
  made; deleting them would risk losing data.
- Flutter reported newer package releases that are outside current dependency
  constraints. Dependency upgrades were not part of this cleanup.
- Production and Android deployment were not tested or changed.

## Release decision

**PASS for staging.** The cleanup may be promoted to the staging repository's
`main` branch after final diff, secret, and generated-file review. Production
must remain unchanged unless separately authorized.
