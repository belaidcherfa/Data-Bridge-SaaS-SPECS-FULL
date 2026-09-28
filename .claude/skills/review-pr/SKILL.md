---
name: review-pr
description: Review an agent PR against its task packet with the Bridge rubric (scope, contracts, oracle, tests, tenant isolation, money, security, observability, UX, docs, evidence) and return APPROVE, REQUEST_CHANGES or ESCALATE. Use as reviewer or specialized reviewer.
---

# Review an agent PR

Inputs: PR number, task packet. Rubric: docs/23-agentic-delivery/ORCHESTRATION.md §7.

1. `gh pr view <n> --json title,body,files,labels,headRefName`; `gh pr diff <n>`; read the packet and the contracts in `contracts_read` that the diff touches.
2. Scope: every changed path matches `writes`; no unrelated refactor; generated files regenerated, not hand-edited.
3. Contracts: types, fields, enums, error codes, events and state transitions match; contract tests updated; ACCEPTED contracts changed only by their owner with a `contract-change` label.
4. Oracle: re-run the micro-step oracles and `checks` (or confirm the verifier did from a clean checkout). Evidence manifest complete and consistent with the run.
5. Tests: failing-first evidence (commit order), negative/edge cases, no skipped tests, coverage threshold.
6. Lenses: tenant isolation, money, security, privacy, observability, UX states, performance budgets, docs/runbooks — as applicable.
7. Verdict block:
```
VERDICT: APPROVE | REQUEST_CHANGES | ESCALATE
BLOCKING:
1. path:line — problem — why it matters — required change
NITS:
- …
SPECIALIZED REVIEW STILL REQUIRED: security|finops|data|frontend|none
HUMAN GATES: …
```
Post it with `gh pr review <n> --approve|--request-changes --body-file <file>` (reviewers never push commits).
