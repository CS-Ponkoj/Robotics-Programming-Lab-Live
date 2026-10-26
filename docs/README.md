# Project documentation

This directory keeps long-form project material out of the repository root
while preserving a predictable place for engineering, research, deployment,
and verification records.

## Architecture and planning

- [Project vision, architecture, and delivery plan](architecture/PROJECT_VISION_ARCHITECTURE_AND_DELIVERY_PLAN.md)
- System architecture blueprint (owner-editable, describes the live app):
  [PRD](system-architecture/PRD.md) ·
  [AppFlow](system-architecture/AppFlow.md) ·
  [UI_Spec](system-architecture/UI_Spec.md) ·
  [TRD](system-architecture/TRD.md) ·
  [Schema](system-architecture/Schema.md) ·
  [Plan](system-architecture/Plan.md)

## Local operation

- [First-time run operating-system chooser](guides/FIRST_TIME_RUN.md)
- [First-time run on Windows](guides/FIRST_TIME_RUN_WINDOWS.md)
- [First-time run on Ubuntu](guides/FIRST_TIME_RUN_UBUNTU.md)

## Deployment and release

- [Staging and release workflow](deployment/STAGING_AND_RELEASE_WORKFLOW.md)
- [Historical documentation archive](archive/README.md)

## Research data

- [Research data dictionary](research/DATA_DICTIONARY.md)
- [V5.2 research analytics phases](research/V5_2_ANALYTICS_PHASES.md)
- [V5.2 three-phase metric dictionary](research/ROBOTICS_PROGRAMMING_LAB_METRIC_DICTIONARY_V1_1.pdf)
- [Original 161-metric candidate dictionary](research/ROBOTICS_PROGRAMMING_LAB_METRIC_DICTIONARY_V1.pdf)
- [V4.1 research data guide](research/V4_1_RESEARCH_DATA_GUIDE.md)
- [Instructor-created AI evaluation data guide](research/AI_INSTRUCTOR_DATASET_GUIDE.md)

## SQA evidence

- [Master QA workbook](sqa/Robotics_Programming_Lab_Master_SQA_Checklist.xlsx)

This is the single maintained QA file. Use **Master Checklist** for current
checks, **Defect Log** for issues, and **Release Sign-off** for release approval.
**QA Run History** contains checks imported from dated reports. **QA Report
Index** locates each report; **QA Report Archive** preserves its complete text
in source-line order. Historical results describe the recorded version and
are not a current release verdict. Future QA evidence belongs in this workbook,
not a new Excel or Markdown report.

## Placement rule

- Keep only essential entry-point and governance documents in the repository
  root, currently `README.md` and `AGENTS.md`.
- Put architecture and forward-looking plans in `docs/architecture/`.
- Put local setup and operator instructions in `docs/guides/`.
- Put hosting, promotion, rollback, and environment procedures in
  `docs/deployment/`.
- Put research schemas, collection guidance, and data definitions in
  `docs/research/`.
- Keep all current and historical QA evidence in the single master workbook
  under `docs/sqa/`; preserve dated results when adding a new run.
- Move superseded deployment snapshots to `docs/archive/`.
