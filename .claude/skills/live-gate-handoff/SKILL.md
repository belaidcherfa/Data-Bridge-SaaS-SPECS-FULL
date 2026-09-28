---
name: live-gate-handoff
description: Prepare a live gate (behaviour marked TO VERIFY LIVE, DEV/STAGING Snowflake or AWS proof, credit-costing benchmark) or a human gate so it can be executed in minutes by the owner, a CI live job or a later agent with DEV access — exact commands, expected results, budget, evidence path. Use whenever a packet lists live_gates or human_gates.
---

# Live and human gate hand-off

Agents without cloud credentials cannot close live gates; they make them trivial to close.

## Live gate file
Create `tests/live/<TASK-ID>/<gate-id>.md` (and the executable test next to it, `tests/live/<TASK-ID>/test_<gate_id>.py`, marked `@pytest.mark.live`):
```markdown
---
gate: <TASK-ID>-LG<n>
kind: vendor-behavior | isolation | performance | cost | recovery
environment: dev | staging            # never prod
estimated_credits: <n>                  # Snowflake credits, within D-32 budgets
estimated_aws_cost_usd: <n>
requires: [snowflake-dev-admin | aws-dev-readonly | test-estate]
status: PREPARED
---
## Claim being verified
Spec reference (ADR/decision/backlog section) and the exact behaviour, e.g. "row access policy evaluates CURRENT_ROLE() only; secondary roles cannot widen".
## Setup
Idempotent commands (migration IDs, fixture loader, make targets). No secrets inline: credentials come from the CI OIDC role or the operator's SSO session.
## Run
`make validate-task TASK=<ID> ENV=dev GATE=<gate-id>` (or the exact pytest command).
## Expected result
Machine-checkable assertions and thresholds.
## Evidence
Where the runner writes the manifest (`docs/evidence/<TASK-ID>/<sha>/live-<gate-id>.json`) and which fields are redacted.
## Teardown
Commands that remove everything created.
```
- The live test must be runnable by the `live-gates` CI workflow on a self-hosted runner in the VPC (OIDC role, DEV only) — prefer this over a human run.
- Put the gate in the PR "Gates" section and in `delivery/state.json` via the orchestrator (`live_gates_pending`).

## Human gate checklist
For `human_gates` (legal text, pricing, security sign-off, design approval, production apply, customer communication): add a checklist to the PR body and to `delivery/human-gates/<TASK-ID>.md` — what to look at (links), the decision needed (approve / choose option), time estimate (target ≤ 15 min), and what happens after approval. Never mark it passed yourself.

## After execution
The verifier (or the owner) updates the gate `status: PASSED|FAILED` with the evidence path; a FAILED vendor-behavior gate becomes an escalation (`kind: vendor-behavior`) with the observed behaviour and options.
