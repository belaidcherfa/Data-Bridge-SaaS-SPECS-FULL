<!-- Title: `<TASK-ID>: <title>` or `<TASK-ID> [slice n/m]: <title>` (AGENTS.md §7). Keep ≤ ~800 changed lines excluding generated files. -->

## Task
- Packet: `delivery/packets/<TASK-ID>.md` · Backlog: <link> · Tier: A | B | C · Lane: <lane>
- Slice: n/m (micro-steps Sxx–Syy) · Depends on: <IDs> (contract-only deps: <IDs>, integration pending: yes/no)

## Micro-steps
| Step | Done when (oracle) | Commit | Result |
|---|---|---|---|
| <ID>-S01 | … | abc1234 | ✅ expected = observed |

## Oracle results
Expected vs observed for each oracle (fixture IDs, numbers, screenshots for UI states).

## Tests added or changed
- Unit / contract / integration / security (tenant isolation) / financial golden / e2e / a11y
- No test skipped, weakened, xfailed or deleted: ☐ confirmed

## Contracts
- Consumed (must be ACCEPTED): …
- Changed (owner lane, `contract-change` label, consumers impacted): …

## Security, privacy, money
- Tenant-scoped? isolation tests: … · Secrets/PII in logs: none · Money: decimals only, unknown ≠ 0

## Gates
- Live gates prepared (`tests/live/<TASK-ID>/…`): …
- Human gates (checklist `delivery/human-gates/<TASK-ID>.md`): …

## Evidence
`docs/evidence/<TASK-ID>/<short-sha>/index.json`

## Risks and follow-ups
…

## Agent metadata
Model: … · Attempt: n · Turns: … · Cost (USD): … · Escalations: …
