# Instructor-created AI evaluation data: initial stage

## Purpose

This initial dataset records examples of student mistakes and the kind of
feedback an instructor expects from the AI tutor. It remains an offline
evaluation resource: the student-facing runtime does not load it. The automated
AI safety evaluation harness reads all cases to verify the same strict schema,
privacy boundary, and solution-protection policy used by the runtime tutor.

The dataset helps answer a simple question later: **does the AI respond like a
safe, useful tutor for mistakes that an instructor has already reviewed?**

## Where to see the data

Open this folder in the staging checkout:

```text
backend/ai_evaluation_cases/
```

It contains one readable JSON file for each assignment:

```text
assignment_1.json
assignment_2.json
assignment_3.json
assignment_4.json
assignment_5.json
assignment_6.json
```

The format and validation code are in `backend/instructor_dataset.py`. Dataset
validation is in `backend/tests/test_instructor_dataset.py`; the Phase 1 tutor
evaluation harness is in `backend/tests/test_tutor_evaluations.py`.

## What one case means

Each case contains:

| Field | Simple meaning |
|---|---|
| `case_id` | Permanent name for this example |
| `title` and `case_type` | The kind of mistake or safety request |
| `student_code` / `student_question` | A realistic incorrect attempt or question |
| `expected_execution_status` | Expected deterministic grader category, when applicable |
| `misconception_tags` | Which configured misunderstanding the case represents |
| `expected_feedback` | What a useful tutor must explain, ask, mention, and avoid |
| `hint_ladder` | Three hints from general guidance to more specific guidance |
| `review_status` | `draft`, `approved`, or `rejected` |
| `reviewer` | Required when an instructor approves the case |

The initial inventory has 24 cases: four per assignment. It covers every
misconception tag currently configured for Assignments 1–6 and includes direct
solution-request and prompt-injection cases.

## Current status and important limitation

All initial cases are **drafts generated as a starting point**. They are not
professor-approved labels and must not be treated as research ground truth yet.
An instructor must read each case, correct its educational interpretation and
hint wording, add their name to `reviewer`, and change `review_status` to
`approved` only when satisfied.

This stage does not:

- send data to OpenAI;
- train or fine-tune a model;
- change student feedback;
- add an instructor UI;
- store official solutions, hidden tests, or grader configuration in the
  evaluation files.

## Instructor review workflow

1. Open one assignment JSON file.
2. Compare each example with the assignment instructions and rubric.
3. Confirm that the diagnosis identifies the real learning issue.
4. Confirm that hints become gradually more specific without giving code or the
   final answer.
5. Confirm that `must_avoid` protects solutions, hidden tests, and unsafe advice.
6. Edit inaccurate wording or add missing examples.
7. Add the instructor name in `reviewer` and set `review_status` to `approved`.
8. Run the validator and backend tests before committing.

```powershell
Import-Module .\scripts\local-environment.psm1 -Force
$python = Get-RoboticsPythonExecutable -RepositoryRoot (Get-Location)
Push-Location .\backend
& $python instructor_dataset.py
& $python -m pytest -p no:cacheprovider tests\test_instructor_dataset.py -q
Pop-Location
```

The validator checks schema correctness, assignment IDs and versions, unique
case IDs, hint order, configured misconception coverage, and the absence of
protected fields. An approved case without a named reviewer is rejected.

## How this is used now and later

Phase 1 now runs every case through the tutor's controlled request/response
pipeline using deterministic test responses. This proves assignment coverage,
strict response validation, privacy filtering, and solution-leakage rejection
without spending API credit. It does not prove the educational quality of a
real model response.

After instructor review and when API credit is available, an explicit provider
evaluation can give each approved case to the configured model and compare its
response with `expected_feedback` and `hint_ladder`. The test-case grader
remains the authority for code correctness. The AI remains a feedback tutor,
not a grader.

Runtime integration must be a separate, reviewed stage. It must preserve AI-off
behavior, record the model and prompt version, handle provider failure, and pass
solution-leakage and prompt-injection tests before classroom use.
