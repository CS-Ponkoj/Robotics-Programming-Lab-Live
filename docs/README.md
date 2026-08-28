# Project documentation

This directory keeps long-form project material out of the repository root
while preserving a predictable place for engineering, research, deployment,
and verification records.

## Architecture and planning

- [Project vision, architecture, and delivery plan](architecture/PROJECT_VISION_ARCHITECTURE_AND_DELIVERY_PLAN.md)

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

- [Master SQA checklist](sqa/Robotics_Programming_Lab_Master_SQA_Checklist.xlsx)
- [Ubuntu local support SQA report](sqa/UBUNTU_LOCAL_SUPPORT_SQA_REPORT_2026-08-28.md)
- [Automatic local database backup SQA report](sqa/AUTOMATIC_LOCAL_DATABASE_BACKUP_SQA_REPORT_2026-08-26.md)
- [V5.2 Basic Analytics SQA report](sqa/V5_2_BASIC_ANALYTICS_SQA_REPORT_2026-08-26.md)
- [Historical PostgreSQL OneDrive handoff SQA report](sqa/LOCAL_POSTGRES_ONEDRIVE_HANDOFF_SQA_REPORT_2026-08-24.md)
- [Copyable local handoff package SQA report](sqa/COPYABLE_LOCAL_HANDOFF_PACKAGE_SQA_REPORT_2026-08-25.md)
- [Repository cleanup SQA report](sqa/REPOSITORY_CLEANUP_SQA_REPORT_2026-08-24.md)

Earlier dated reports remain available through the
[historical documentation archive](archive/README.md). They are evidence from
their recorded versions, not the current release decision.

## Placement rule

- Keep only essential entry-point and governance documents in the repository
  root, currently `README.md` and `AGENTS.md`.
- Put architecture and forward-looking plans in `docs/architecture/`.
- Put local setup and operator instructions in `docs/guides/`.
- Put hosting, promotion, rollback, and environment procedures in
  `docs/deployment/`.
- Put research schemas, collection guidance, and data definitions in
  `docs/research/`.
- Keep the current test checklist and latest dated evidence in `docs/sqa/`.
- Move superseded release evidence and deployment snapshots to `docs/archive/`
  without rewriting their historical results.
