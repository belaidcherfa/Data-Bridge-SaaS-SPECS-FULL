# Bridge Data FinOps — Project master plan

Specification baseline: 2026-09-23. Product implementation has **not started**. This repository is an engineering delivery specification, not a working SaaS or a claim of production validation.

## Authority and outcome

The supplied 159-section PRD is authoritative. It will be preserved verbatim under `docs/00-project/PRD.md`. Architecture decisions resolve omissions and qualify illustrative examples; they do not silently replace the PRD. All specifications are in English for implementation agents.

Deliver a Snowflake-only FinOps SaaS from a clean checkout through AWS production, organization/account onboarding, available historical synchronization, financial reconciliation, complete customer workflows, and a first paying customer. AWS costs are measured only as Bridge Data's internal cost of delivery, not as a customer multi-cloud FinOps product.

## Non-negotiable boundaries

| Component | Owns | Forbidden responsibility |
|---|---|---|
| Customer Snowflake | Source metadata and consumption | Hosting the SaaS control plane |
| AWS IAM / Snowflake WIF | Short-lived workload authentication | Persistent Snowflake passwords, PATs or RSA keys |
| Python | Extraction, parsing and statistical algorithms | A second analytical database |
| Arrow / Parquet / S3 | Typed immutable transport, provenance, replay | Business transformations or analytical serving |
| Snowpipe | File ingestion into central Snowflake | Business ordering or end-to-end exactly-once guarantees |
| dbt Core | Deterministic SQL, ledger, allocation, marts | Orchestration and notification delivery |
| Snowflake | Analytical and financial truth | SaaS transactional workflow state |
| Dagster OSS | Assets, scheduling, retries, lineage, backfills | Cost formulas or duplicated customer pipelines |
| PostgreSQL | Identity, configuration, workflow and operational checkpoints | Query history, cost facts or allocation fact mirrors |
| Redis | Disposable acceleration | Durable locks, progress or financial truth |
| FastAPI / React | Authorized API and premium product experience | Alternative KPI definitions |

## Delivery scope

The critical path is engineering foundation → identity/isolation → connection capabilities → contracts and immutable ingestion → orchestration and transformations → additive ledger and reconciliation → semantic serving → customer exploration → ownership/allocation → governance/reporting → insights/action verification → operational qualification → first customer → release.

Build all account capabilities through configuration. Tenant contains one or more Snowflake organizations; organization contains accounts. Every durable analytical record physically carries `tenant_id`. Organization-level financial items without an account use a documented organization-level scope; never fabricate a real account. Identifiers survive renames and preserve effective-dated organization membership.

## Product domains and deliverables

| Domain | Required completion evidence |
|---|---|
| Engineering and AWS | Reproducible local setup, isolated environments, Terraform, private services, delivery pipeline |
| Identity and control | Cognito/SSO/MFA, scoped RBAC, PostgreSQL RLS, Snowflake isolation, revocation tests |
| Connectivity | Per-account WIF, organization discovery, capability/permission diagnostics, revocation |
| Data acquisition | Verified source contracts, streaming, typed Parquet, manifests, Snowpipe, replay and coverage |
| Orchestration/dbt | Generic Dagster assets, fair queues, deterministic incremental models and publication gates |
| Finance | All observed billing services represented once, pricing provenance, corrections, reconciliation |
| Product/API | Semantic registry, safe queries, asynchronous jobs, complete UX states, explainability |
| Workloads | dbt, Power BI, tasks/procedures, serverless, Cortex, SPCS and uncertain classification |
| Ownership | External tags, versioned rules, simulation, usage group sets, allocation, showback/chargeback |
| Governance | Budgets, forecasting, generic monitors, four notification channels, scheduled reports |
| Optimization | Evidence-backed insights, actions, normalized savings and uncertainty |
| Operations and launch | SLOs, recovery drills, privacy, support, onboarding, commercial entitlement and release evidence |

## Four distinctions that implementations must preserve

1. **Specification complete ≠ implementation complete.** Task status starts `NOT_STARTED`; a document being published never marks its implementation done.
2. **Historical request ≠ available history.** Plan 365 days, record per-source retention/capability limits, never present missing history as zero or fabricate historical object snapshots.
3. **Consumption ≠ attribution.** Query compute, warehouse idle, dynamic-table workload costs and other subdivisions must not be added again to their parent billable amount.
4. **FINAL ≠ invoice final.** Source maturity, reconciliation outcome, and financial close are separate versioned states. Corrections may supersede any open-period result.

## Engineering system

Each domain has a canonical contract, feature specifications and independently reviewable task files. Every task records domain → epic → feature → user story → implementation task → numbered micro-tasks → validation → Definition of Done. Exact dependencies form a directed acyclic graph and a machine-readable execution index.

Canonical definitions own terminology, formulas, schemas and interfaces. Task files reference those contracts and state their specific inputs, outputs, failure modes and test oracles. Templates cannot replace feature-specific analysis.

## Release boundary

The first release includes the PRD's read-only FinOps workflows, customer self-service onboarding and commercial activation. Automated changes to customer Snowflake and an AI copilot remain deliberately future capabilities. Actions in this release track human-performed changes; they do not grant an operator role. Notification destinations are configured by customers; preparing this specification does not send messages or provision infrastructure.

## Evidence and blockers

Official documentation verifies vendor behavior. Live AWS/Snowflake tests must subsequently verify pinned versions, account editions, permissions, region availability, performance and recovery. Mark these `OPEN_VALIDATION`, with a concrete task, owner and release gate. Do not label them passed because documentation exists.

Commercial terms, legal approval, production account identifiers and real customer consent are launch inputs. Choose safe technical defaults and build everything reviewable; do not invent signatures, customer consent, payment or credentials.

## Publication

Publish each completed document through the GitHub API to `main`, immediately. Update progress after each domain, then perform a repository-wide dependency, link, PRD coverage and contradiction audit. Preserve a useful starting point after every checkpoint.
