# Project documentation

This directory keeps long-form project material out of the repository root
while preserving a predictable place for engineering, research, deployment,
and verification records.

## Architecture and planning

- [Project vision, architecture, and delivery plan](architecture/PROJECT_VISION_ARCHITECTURE_AND_DELIVERY_PLAN.md)

## Deployment and release

- [Staging and release workflow](deployment/STAGING_AND_RELEASE_WORKFLOW.md)
- [V4 live deployment guide](deployment/V4_LIVE_DEPLOYMENT.md)
- [V4 live deployment readiness checklist](deployment/V4_LIVE_DEPLOYMENT_READINESS_CHECKLIST.md)

## Research data

- [Research data dictionary](research/DATA_DICTIONARY.md)
- [V4.1 research data guide](research/V4_1_RESEARCH_DATA_GUIDE.md)
- [Instructor-created AI evaluation data guide](research/AI_INSTRUCTOR_DATASET_GUIDE.md)

## SQA evidence

- [Master SQA checklist](sqa/Robotics_Programming_Lab_Master_SQA_Checklist.xlsx)
- [Assignment content local SQA report](sqa/ASSIGNMENT_CONTENT_LOCAL_SQA_REPORT_2026-08-21.md)
- [AI Tutor Phase 1 staging SQA report](sqa/AI_TUTOR_PHASE1_SQA_REPORT_2026-08-21.md)
- [V5 staging SQA report](sqa/V5_STAGING_SQA_REPORT.md)
- [Stage 1 data-standardization SQA report](sqa/DATA_STANDARDIZATION_STAGE1_SQA_REPORT.md)
- [V4.1 staging SQA report](sqa/V4_1_STAGING_SQA_REPORT.md)
- [Secure-grader reliability SQA report](sqa/SECURE_GRADER_RELIABILITY_SQA_REPORT_2026-08-17.md)
- [Demo-session SQA report](sqa/DEMO_SESSION_SQA_REPORT_2026-08-12.md)
- [Assignment 5 ROS 2 local SQA report](sqa/ASSIGNMENT_5_ROS2_LOCAL_SQA_REPORT.md)
- [Assignment 6 ROS 2 local SQA report](sqa/ASSIGNMENT_6_ROS2_LOCAL_SQA_REPORT.md)

## Placement rule

- Keep only essential entry-point and governance documents in the repository
  root, currently `README.md` and `AGENTS.md`.
- Put architecture and forward-looking plans in `docs/architecture/`.
- Put hosting, promotion, rollback, and environment procedures in
  `docs/deployment/`.
- Put research schemas, collection guidance, and data definitions in
  `docs/research/`.
- Put test checklists and dated evidence in `docs/sqa/`.
