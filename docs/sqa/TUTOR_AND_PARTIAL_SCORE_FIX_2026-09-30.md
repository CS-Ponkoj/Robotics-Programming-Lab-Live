# Tutor explanation and partial-score verification

Date: 2026-09-30. Canonical Windows staging checkout, base main `73a122f`,
working branch `fix/tutor-code-grounding`. Scope: function-grader feedback and
AI response grounding. Existing account/reference file moves are excluded.

## Screenshot findings

The submitted Assignment 2 function reads `start_point`, `hit_point` and
`leave_point` from module-level variables rather than using all its arguments.
Those variables exist before the function is called. The shown output is
`4.0 4.0 0.0 0.0`. Execution succeeds, but those fixed calculations fail on
other inputs, so none of the four criteria passes every scenario. The 0% score
is consistent with the assignment rules; it is not a missing partial-credit bug.
Completing the same two calculations using the function parameters earns 50%.

The AI response incorrectly called the module-level variables undefined.
The prompt now explains Python's module-level name lookup and makes grader
execution evidence authoritative. A response claiming undefined variables or a
NameError after successful execution is rejected and replaced by the existing
built-in feedback. This check covers common wording; it is not a proof that all
possible AI explanations are correct. No additional provider call or retry is
made when an explanation is rejected.

Failed function criteria now explicitly explain that they must work for every
input scenario and that the printed example alone is insufficient. Scoring,
criterion weights, assignment versions, and test cases are unchanged.

## Verification

| Check | Result | Evidence |
|---|---|---|
| Screenshot-style globals and partial code | PASS | Executes, prints 4.0 4.0 0.0 0.0; score 0%; explanatory feedback |
| Same two components using parameters | PASS | Same example output; score 50%, two passed criteria |
| Contradictory AI output | PASS | Four name-error phrasings across diagnosis, answer, hint and debugging steps fall back safely |
| Grounded explanation / actual NameError | PASS | Valid global-input explanation and actual failed-execution NameError remain accepted |
| Focused tutor, instructor-case and function-grader tests | PASS | 56 passed |
| API and authentication regressions | PASS | 67 passed |
| Running local API with temporary demo session | PASS | At API 5100, both variants returned 0% / 50%, successful execution and the new explanatory message; AI off |
| Paid OpenAI model validation | NOT RUN | Injectable fake responses exercised the request and response checks; no paid request authorized |
| Professor's computer / physical Ubuntu / live deployment | NOT RUN | Local staging repair only |

Commands used the managed Python 3.14 environment from `backend`:

```text
python -m pytest tests/test_tutor.py tests/test_python_function_grader.py tests/test_tutor_evaluations.py -q
python -m pytest tests/test_app.py tests/test_auth.py -q
```

`AGENTS.md` now records the execution-grounding invariant. Secrets and database
records were not changed. No frontend source changed; a separate Flutter build
was not necessary for this backend response repair. The owner authorized
publication of this repair to staging main on 2026-09-30. Production is outside
this publication scope.

The managed local stack was restarted successfully at http://127.0.0.1:8180/app
with API 5100 and sandbox 5101. Demo smoke-test submissions remain temporary.
