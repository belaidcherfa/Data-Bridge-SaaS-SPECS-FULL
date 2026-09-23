# Implementation task tree

Product implementation status: NOT_STARTED. Task specifications are being published domain by domain. Do not confuse publication with execution.

Construction order and ownership:

| Prefix | Domain | Primary owner | Canonical documentation |
|---|---|---|---|
| FND | Engineering standards and local environment | Tech lead | docs/01-architecture/engineering.md |
| INF | AWS infrastructure and deployment foundation | DevOps | docs/17-devops/platform.md |
| SEC | Identity, authorization, isolation and privacy | Security | docs/02-security/security.md |
| CTL | Transactional model, APIs and cache | Backend | docs/03-control-plane/control-plane.md |
| CON | WIF, organization discovery and capabilities | Snowflake | docs/04-snowflake-connectivity/connectivity.md |
| ING | Source contracts and immutable ingestion | Data | docs/05-ingestion/ingestion.md |
| ORC | Dagster OSS orchestration | Data platform | docs/06-dagster/orchestration.md |
| DBT | Deterministic transformation framework | Analytics engineer | docs/07-dbt/transformation.md |
| FIN | Services, ledger, prices and reconciliation | FinOps | docs/08-finops-ledger/ledger.md |
| API | Semantic metrics and analytical API | Backend | docs/09-api/semantic-api.md |
| UX | Product shell and cost exploration | Frontend | docs/10-frontend/product.md |
| WRK | Workload intelligence | Data | docs/10-frontend/workloads.md |
| ALC | Tags, allocation, showback and chargeback | FinOps | docs/11-allocation/allocation.md |
| GOV | Budgets, monitors and delivery | Backend | docs/12-budgets-monitoring/governance.md |
| INS | Insights, actions and verified savings | Data science | docs/13-insights/intelligence.md |
| RPT | Reports, exports and schedules | Frontend/backend | docs/14-reporting/reporting.md |
| OPS | Quality, observability, recovery and security qualification | SRE/QA | docs/16-observability/operations.md |
| REL | Production readiness and release machinery | Delivery | docs/19-production-readiness/readiness.md |
| ONB | Self-service and first-customer onboarding | Customer success | docs/18-customer-onboarding/onboarding.md |
| LCH | Commercial activation and post-launch proof | Product | docs/20-launch/launch.md |

Paths in the table are the intended canonical destinations; they become navigable in domain indexes as published. Tasks will live in `docs/tasks/<PREFIX>/<PREFIX>-NNN.md`. The final `task-index.json` and `TASK_INDEX.md` provide exact dependencies and a topological execution order. Every task includes its own objective, contract links, micro-tasks, proof, runbook and acceptance checklist.

See [delivery methodology](../../DELIVERY_METHODOLOGY.md) for the evidence and restart protocol.
