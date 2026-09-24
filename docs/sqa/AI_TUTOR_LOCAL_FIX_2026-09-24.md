# Local AI tutor repair — 2026-09-24

Environment: Windows staging checkout, base commit `2252bcf` plus uncommitted
repair; managed local frontend `127.0.0.1:8180`, API `127.0.0.1:5100`, and
sandbox `127.0.0.1:5101`. Production was not changed. The API checks used a
temporary demo session, not a persistent student account.

## Confirmed causes

1. The ordinary local launchers cleared `OPENAI_API_KEY` before starting the
   backend. The assignment switch could request AI, but the backend had no key.
2. With the key available, submission feedback sometimes fell back because the
   420-token response limit truncated the required structured JSON. A tutor
   question using the same key succeeded.

The launchers now keep the server-side key available while the assignment
switch stays off by default. The optional `-EnableAi` / `--enable-ai` flags
validate key presence at startup. The tutor now requests concise fields with a
1000-token output limit. Neither change makes AI part of grading.

## Checks

| Requirement | Exact check / user flow | Expected | Actual | Result |
|---|---|---|---|---|
| Ordinary launch | `run-local.ps1` with no AI flag | Three services healthy; AI available but off | All services ready; AI available `True`, off until assignment switch | PASS |
| AI off | Demo `POST /assignments/1/submit`, `use_ai_tutor=false` | No tutor feedback | No tutor feedback | PASS |
| AI on | Same demo submission with `use_ai_tutor=true` | OpenAI feedback; grading still returns | Tutor source `openai` | PASS |
| Follow-up question | Demo `POST /assignments/1/tutor` | Nonempty OpenAI answer | Source `openai`; answer nonempty | PASS |
| Tutor regressions | `python -m pytest tests/test_tutor.py tests/test_tutor_evaluations.py -q` | Tests pass | 31 passed | PASS |
| Windows launcher syntax | PowerShell parser | No parse errors | No parse errors | PASS |
| Ubuntu launcher syntax | Git Bash `bash -n scripts/run-local.sh` | No parse errors | No parse errors | PASS |
| Manual Flutter click-through | Log in, toggle AI, run and ask in browser | OpenAI result visible | Not performed; API flow and UI wiring checked instead | NOT RUN |
| Physical Ubuntu run | Launch and exercise on Ubuntu | Same behavior | No Ubuntu machine used | NOT RUN |

The two NOT RUN checks need a manual browser pass on this build and an Ubuntu
device respectively before claiming those environments were exercised. OpenAI
availability also depends on the configured key, account credit, network, and
service status; deterministic grading remains usable when AI is unavailable.

`AGENTS.md` was reviewed. No durable repository or release rule changed, so it
did not need an edit. This was a staging-only repair; production was not changed.
