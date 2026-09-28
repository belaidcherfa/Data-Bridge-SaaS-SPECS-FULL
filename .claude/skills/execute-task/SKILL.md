---
name: execute-task
description: Implement one Bridge task packet end to end as a worker — read the packet, implement micro-steps in order with tests first, stay inside writes, run checks, capture evidence and open the PR. Use whenever you are dispatched with a task ID.
---

# Execute a task packet

1. **Load context**: `delivery/packets/<ID>.md` → "Read first" list in order. Confirm dependencies are DONE in `delivery/state.json`. Note the `writes`, `locks`, `checks`, `human_gates`, `live_gates`.
2. **Contracts first**: if a contract your task owns exists as `status: DRAFT`, your first micro-step is to verify it against the backlog, complete it, run `make contracts-check`, and set `status: ACCEPTED` in the same PR (reviewers will check). If a contract you consume is DRAFT, escalate unless the packet says otherwise.
3. **Per micro-step** (in table order):
   - Write the failing test that encodes the *Done when* oracle (fixture values computed independently, not by calling your implementation).
   - Implement the smallest change that passes; then edge cases (nulls, signed amounts, duplicates, empty windows, retries, revocation mid-flight) as listed.
   - Tenant-scoped? add foreign-tenant, missing-context and revoked-scope tests (skill `tenant-isolation-tests`). Money? follow `money-and-ledger`.
   - Add telemetry per `packages/telemetry` registries; no PII or SQL in logs.
   - Run the relevant checks; commit `<type>(<domain>): <ID>-Sxx <summary>`.
4. **Scope guard**: `git diff --name-only origin/main...HEAD` must match `writes`. If not, revert the stray change or escalate.
5. **Full checks**: run every command in `checks`. All green. No skipped/xfail tests added.
6. **Evidence**: skill `evidence-capture`.
7. **PR**: `git push -u origin <branch>`; `gh pr create` with the template: packet link, micro-step checklist with commit SHAs, oracle expected vs observed, tests added, contracts touched, gates to hand off, model and cost. Labels `agent`, `tier-X`, `lane-X`, plus `needs-human` / `contract-change` when applicable.
8. **Hand-off**: live gates you cannot run → describe the exact command/workflow and expected result; human gates → a checklist the human can execute in minutes.
Stop and use `escalate` when blocked. Never exceed the budget or turn limit; report partial progress instead.
