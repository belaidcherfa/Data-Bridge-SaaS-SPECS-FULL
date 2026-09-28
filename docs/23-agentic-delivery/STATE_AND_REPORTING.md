# Delivery state, escalations and reporting

## 1. `delivery/state.json`

Single durable state of the delivery system, validated by [`delivery/state.schema.json`](../../delivery/state.schema.json). Only the orchestrator writes it, in its own commits (`chore(delivery): tick <UTC>`) on the unprotected **`delivery-ledger`** branch ([ADR-018](../architecture/adr/ADR-018-agentic-delivery.md) §5), never inside a feature PR and never on `main` (protected). `main` holds the schema and the initial state; the live copy, reports, escalations, metrics and human-gate checklists live on `delivery-ledger` (checked out by the orchestrator as a separate worktree, e.g. `/srv/bridge/ledger`). A weekly PR snapshots the ledger into `main`.

| Key | Meaning |
|---|---|
| `control.paused` / `pause_reason` | Kill switch. The owner (or the orchestrator on a stop condition) sets it; a paused orchestrator only reconciles and reports. Initial value: paused until the owner checkpoints in [HUMAN_CHECKPOINTS.md](HUMAN_CHECKPOINTS.md) are done. |
| `control.*` | Tick period, worker caps, lease TTL, turn limit, budget parameters, release scope, default models per role. |
| `budget` | Spend counters (USD, reset daily at 00:00 UTC). |
| `locks` | Serialization locks `lock:<name>` → holder task and time. |
| `leases` | Running workers: task, worker ID, branch, worktree, model, start, last commit, budget, attempt. |
| `tasks.<ID>` | `status`, `attempts`, `pr`, `model`, `steps_done`, `evidence`, `blocked_by`. |
| `escalations_open`, `reports` | Pointers to files. |

Task status machine: `NOT_STARTED → READY → IN_PROGRESS → IN_REVIEW → (NEEDS_HUMAN →) DONE`; `IN_REVIEW → AWAITING_INTEGRATION → IN_PROGRESS` when the task started on contract-only dependencies ([PARALLELISM.md](PARALLELISM.md)): its first PR merges the implementation against fakes, and the orchestrator dispatches the remaining integration micro-steps as a new slice once those dependencies are `DONE`; `BLOCKED` from any non-terminal state with `blocked_by` (escalation IDs, missing gates); `MERGED_INTO:<ID>` for merged tasks. `DONE` requires: PR(s) merged, every micro-step in `steps_done` (integration steps included), evidence path recorded, human gates approved, and every dependency `DONE`.

## 2. Escalation file

`delivery/escalations/<UTC-timestamp>-<TASK-ID>.md`:

```markdown
---
id: 2026-10-02T1412Z-FIN-003
task: FIN-003
raised_by: worker|reviewer|orchestrator
kind: decision | contract-change | vendor-behavior | access | budget | failure | security | financial
severity: blocking-task | blocking-lane | blocking-all | info
status: OPEN | ANSWERED | APPLIED | WITHDRAWN
---
## Context
What happened, with links (packet, PR, logs, evidence).
## Options
1. … (consequences, effort)
2. …
## Recommendation
Option N because …
## Owner answer
(to be filled by the owner; one line is enough, e.g. "Option 2")
```

The orchestrator mirrors each escalation as a GitHub issue labelled `escalation` and lists open ones at the top of every report. An answered decision is appended to the decision record as `D-39+`.

## 3. Daily report (for the owner)

`delivery/reports/<UTC-date>.md`, written in French for the owner, also posted as a GitHub issue comment (and optionally to Slack/Linear/Notion). Template (skill `daily-report`):

```markdown
# Rapport de livraison — <date>

## En bref
3–5 phrases : avancement global, faits marquants, ce qui bloque, ce qui est attendu de toi.

## Décisions / actions attendues de toi
- [ESC-…] question courte → options → recommandation (lien)

## Avancement
| Couloir | Terminées (total) | En cours | En revue | Bloquées | Heures estimées livrées / R1 |
Chemin critique : tâche courante, prochaine, avance/retard vs plan.

## Livré depuis hier
- <TASK-ID> — titre — PR #… — preuve (lien) — modèle, coût

## Qualité
CI main (vert/rouge), tests ajoutés, couverture, incidents de revue, tentatives échouées, retours arrière.

## Coûts
Dépense du jour / cumul / budget ; coût par heure estimée livrée.

## Risques et écarts
Nouveaux risques, hypothèses « TO VERIFY LIVE » invalidées, écarts au plan.

## Prochaines 24 h
Tâches prévues par couloir.
```

A weekly report adds: milestone/phase progress vs [RELEASE_PLAN](../22-implementation-readiness/RELEASE_PLAN.md), velocity (estimated hours delivered per day), cost trend, quality trend, and a re-forecast of the critical path.

## 4. Metrics tracked by the orchestrator

Per task: attempts, wall-clock, tokens and USD, model, review findings count by severity, CI reruns, lines changed. Per day: tasks done, estimated hours delivered, spend, escalations opened/closed, main red minutes. Stored as JSON lines in `delivery/metrics/<UTC-date>.jsonl` (no personal data).

## 5. What the owner checks

Daily: the report's "Décisions / actions attendues" section and red flags. Weekly: the weekly report. On demand: `delivery/state.json` (`control.paused` to stop everything), open PRs labelled `needs-human`, open escalations.
