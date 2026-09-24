# Implementation task tree

All implementation work remains NOT_STARTED. Use the [topological task index](../../TASK_INDEX.md) or [machine index](../00-project/task-index.json), not file-number order, to select ready work.

| Domain / epic | Canonical contract | Tasks |
|---|---|---|
| FND / E-FND-01 — Engineering foundation and local development | [Engineering foundation and local development](../01-architecture/engineering.md) | 6 |
| INF / E-INF-01 — AWS platform, networking and deployment foundation | [AWS platform, networking and deployment foundation](../17-devops/platform.md) | 8 |
| SEC / E-SEC-01 — Identity, authorization, isolation and privacy | [Identity, authorization, isolation and privacy](../02-security/security.md) | 8 |
| CTL / E-CTL-01 — PostgreSQL control plane, transactional APIs and Redis | [PostgreSQL control plane, transactional APIs and Redis](../03-control-plane/control-plane.md) | 7 |
| CON / E-CON-01 — Snowflake WIF, discovery and capability onboarding | [Snowflake WIF, discovery and capability onboarding](../04-snowflake-connectivity/connectivity.md) | 6 |
| ING / E-ING-01 — Source contracts and durable immutable ingestion | [Source contracts and durable immutable ingestion](../05-ingestion/ingestion.md) | 12 |
| ORC / E-ORC-01 — Dagster OSS orchestration and data publication | [Dagster OSS orchestration and data publication](../06-dagster/orchestration.md) | 6 |
| DBT / E-DBT-01 — dbt Core deterministic transformation framework | [dbt Core deterministic transformation framework](../07-dbt/transformation.md) | 6 |
| FIN / E-FIN-01 — Canonical FinOps ledger, pricing and reconciliation | [Canonical FinOps ledger, pricing and reconciliation](../08-finops-ledger/ledger.md) | 21 |
| API / E-API-01 — Semantic metric registry and analytical API | [Semantic metric registry and analytical API](../09-api/semantic-api.md) | 6 |
| UX / E-UX-01 — Premium product experience and cost exploration | [Premium product experience and cost exploration](../10-frontend/product.md) | 8 |
| WRK / E-WRK-01 — Workload intelligence and execution hierarchies | [Workload intelligence and execution hierarchies](../10-frontend/workloads.md) | 5 |
| ALC / E-ALC-01 — External tags, allocation, usage groups, showback and chargeback | [External tags, allocation, usage groups, showback and chargeback](../11-allocation/allocation.md) | 8 |
| GOV / E-GOV-01 — Budgets, forecasting, monitors and notification delivery | [Budgets, forecasting, monitors and notification delivery](../12-budgets-monitoring/governance.md) | 8 |
| INS / E-INS-01 — Evidence-backed insights, actions and verified savings | [Evidence-backed insights, actions and verified savings](../13-insights/intelligence.md) | 7 |
| RPT / E-RPT-01 — Reporting, rendering and secure scheduled distribution | [Reporting, rendering and secure scheduled distribution](../14-reporting/reporting.md) | 5 |
| OPS / E-OPS-01 — Operational quality, security qualification and recovery | [Operational quality, security qualification and recovery](../16-observability/operations.md) | 11 |
| REL / E-REL-01 — Production readiness and release qualification | [Production readiness and release qualification](../19-production-readiness/readiness.md) | 4 |
| ONB / E-ONB-01 — Customer onboarding and first-value acceptance | [Customer onboarding and first-value acceptance](../18-customer-onboarding/onboarding.md) | 5 |
| LCH / E-LCH-01 — Commercial activation, first release and post-launch validation | [Commercial activation, first release and post-launch validation](../20-launch/launch.md) | 4 |

Each task follows domain → named epic → feature → user story → implementation task → micro-tasks → validation → Definition of Done. The canonical contract owns shared formulas/interfaces; task files own concrete changes and proof. See [delivery methodology](../../DELIVERY_METHODOLOGY.md).
