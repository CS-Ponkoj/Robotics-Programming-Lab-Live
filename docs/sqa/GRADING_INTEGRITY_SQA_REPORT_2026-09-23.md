# Assignment Grading Integrity SQA Report

Date: 2026-09-23
Branch: fix/grading-integrity
Release state: Local staging only; not committed or pushed

## Outcome

All confirmed grading issues from the partial-answer QA were repaired. Assignments 1–4 now grade reusable functions across deterministic server-only scenarios. Assignments 5–6 retain their ROS 2 behavior graders, and their displayed rubrics now match the implemented test weights.

## Repaired issues

| ID | Confirmed issue | Repair | Verification | Result |
|---|---|---|---|---|
| GI-001 | The Run endpoint awarded 100% to any executable Python submission | Run and Submit now use the same assignment-specific grader | API contract tests | Pass |
| GI-002 | Assignments 1–4 could pass with hardcoded displayed values | Added the modular PythonFunctionGrader and multiple hidden parameter scenarios | Official, partial, hardcoded, syntax, and runtime tests | Pass |
| GI-003 | Python-assignment feedback was too generic | Added criterion-specific failure guidance without exposing hidden inputs or answers | Grader feedback tests | Pass |
| GI-004 | Assignment 4 allowed only 0%, 50%, or 100% | Expanded the rubric to five independently checked 20% criteria | Mixed answer scored 60% | Pass |
| GI-005 | Assignment 3 used 12.5% criteria but displayed integer scores without explanation | Instructions now state that the final total is rounded to the nearest whole percent | Instruction and score tests | Pass |
| GI-006 | ROS rubrics did not match the behavior-harness weights | Aligned Assignment 5 to 20/20/30/30 and Assignment 6 to 15/20/20/35/10 | Derived rubric-to-harness regression test | Pass |
| GI-007 | Instructor validation rejected the new function grader | Added configuration validation for function name, criteria, cases, arguments, and expected outputs | Assignment Studio validate/edit/publish tests | Pass |

## Assignment scoring checks

| Assignment | Official answer | Mixed answer | Copied displayed values | Runtime grader |
|---|---:|---:|---|---|
| 1: Bug2 route | 100% | 25% | Rejected | Python sandbox |
| 2: Bug route | 100% | 25% | Rejected | Python sandbox |
| 3: Elevator routes | 100% | 50% | Rejected | Python sandbox |
| 4: VFH | 100% | 60% | Rejected | Python sandbox |
| 5: ROS 2 drive and stop | 100%; 7/7 checks | Weighted by passed behaviors | Not applicable | Real Docker ROS 2 grader |
| 6: ROS 2 obstacle stop | 100%; 9/9 checks | Weighted by passed behaviors | Not applicable | Real Docker ROS 2 grader |

## Final verification

| Gate | Evidence | Result |
|---|---|---|
| Backend regression | 200 pytest tests passed | Pass |
| Dependency integrity | pip check reported no broken requirements | Pass |
| Flutter static analysis | No issues found | Pass |
| Flutter automated tests | 52 tests passed | Pass |
| Flutter release web build | Release build completed in the OneDrive-safe build directory | Pass |
| ROS 2 Assignment 5 | Real Docker grader passed 7/7 checks; 78 Twist messages at about 10.0 Hz | Pass |
| ROS 2 Assignment 6 | Real Docker grader passed 9/9 checks; 44 settled Twist messages at about 9.2 Hz | Pass |

## Security and research safeguards

- Hidden parameter scenarios remain in server-side assignment configuration and are excluded from student API responses.
- Student output generated during hidden function calls is discarded.
- The grader reports criterion-level guidance without returning hidden inputs or official solution code.
- AI remains optional and does not affect test-driven scores.
- Assignment versions were increased so future submissions retain the exact content and grading version used.

## Remaining limitations

- Docker Desktop with Linux containers is required to grade Assignments 5 and 6 locally.
- The code is ready for review, but no commit, push, merge, deployment, or production change was performed.
