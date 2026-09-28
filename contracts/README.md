# Contracts — index and ownership map

Conventions: [CONVENTIONS.md](CONVENTIONS.md) · Decision: [ADR-017](../docs/architecture/adr/ADR-017-repository-and-contract-layout.md) · Full artifact list with required content: [CONTRACT_FIRST_ARTIFACTS.md](../docs/22-implementation-readiness/CONTRACT_FIRST_ARTIFACTS.md) and section 3 of each [domain backlog](../docs/22-implementation-readiness/backlog/).

Contracts are authored before the code that implements them. Each file has exactly one owning task (header `owner_task`); other tasks consume it and propose changes through a PR that the owner lane reviews. The table below assigns shared namespaces so that several agents can write contracts in parallel without collisions.

## Shared namespaces

| Namespace | Rule |
|---|---|
| `contracts/openapi/paths/<domain>.yaml`, `contracts/openapi/components/<domain>.yaml` | One file per domain (auth, tenancy, connections, sync, analytics, finance, workloads, allocation, governance, insights, reports, onboarding, commercial, platform, ops). |
| `contracts/errors/problems/<domain>.yaml` | Problem codes prefixed by domain (`AUTH_`, `AUTHZ_`, `TENANT_`, `CONN_`, `SYNC_`, `ORC_`, `DBT_`, `FIN_`, `QUERY_`, `WRK_`, `ALLOC_`, `GOV_`, `INS_`, `RPT_`, `ONB_`, `COMM_`, `OPS_`, `PLATFORM_`). |
| `contracts/events/catalog/<domain>.yaml` + `contracts/events/schemas/` | Event types `bridge.<domain>.*`; the domain segment equals the owning catalog file. |
| `contracts/state-machines/<machine>.yaml` | Machine names are globally unique; see the owner column below. |
| `contracts/postgres/<schema>[.<part>].sql` | Schema file ownership below. |
| `infra/snowflake/migrations/<SCHEMA>/V<NNNN>__<desc>.sql` | Version blocks per lane (below) keep migration numbers unique; dbt-managed models are not migrations. |

## Ownership by contract lane

| Lane | Domains | PostgreSQL files | Snowflake migration block / schemas | State machines | OpenAPI / problems / events domains |
|---|---|---|---|---|---|
| K1 Platform | FND, INF | — | V0001–V0099: databases, schemas, warehouses, roles, grants baseline | — | — |
| K2 Identity & control | SEC, CTL | `identity`, `tenant`, `audit`, `platform` (outbox, idempotency, leases, consumed events, config publication) | V0100–V0199: SECURITY, CONFIG (publication tables) | `approval`, `tenant`, `membership`, `invitation`, `session`, `config_publication` | auth, tenancy, platform (`AUTH_`, `AUTHZ_`, `TENANT_`, `PLATFORM_`) |
| K3 Acquisition | CON, ING | `connection`, `sync` | V0200–V0299: RAW, CONTROL | `connection`, `capability_probe`, `batch_attempt`, `backfill_plan`, `account_cycle` | connections, sync (`CONN_`, `SYNC_`) |
| K4 Orchestration & transformation | ORC, DBT | `sync.admission` (admission/lane tables only) | V0300–V0399: PUBLICATION, LINEAGE, PY_OUTPUTS, OPS_META | `build`, `publication` | — (`ORC_`, `DBT_` problems only) |
| K5 Ledger | FIN | `finance` | V0400–V0499: LEDGER support objects, billing references | `period`, `billing_reference`, `reconciliation_run`, `restatement` | finance (`FIN_`) |
| K6 Product API, UX, workloads | API, UX, WRK | `analytics`, `ops.serving` | V0500–V0599: SERVING, SERVING_JOBS, workload evidence | `analysis_job`, `export_job` | analytics, workloads (`QUERY_`, `WRK_`) |
| K7 Allocation & governance | ALC, GOV | `governance`, `allocation`, `monitor` | V0600–V0699: CONFIG (rule/predicate tables), ALLOCATION, SIMULATION, monitor observations | `ruleset`, `simulation`, `chargeback_statement`, `budget`, `monitor`, `incident`, `destination`, `delivery` | allocation, governance (`ALLOC_`, `GOV_`) |
| K8 Optimization & reporting | INS, RPT | `workflow`, `report` | V0700–V0799: insight evidence, savings observations, report snapshots | `insight`, `action`, `savings_study`, `report_job`, `report_schedule` | insights, reports (`INS_`, `RPT_`) |
| K9 Operations, release, onboarding, commercial | OPS, REL, ONB, LCH | `privacy`, `support`, `onboarding`, `commercial`, `platform.flags`, `ops` | V0800–V0899: QUALITY, OPS_INTERNAL, database BRIDGE_INTERNAL_COST | `onboarding`, `deletion_request`, `support_access`, `subscription`, `release` | onboarding, commercial, ops (`ONB_`, `COMM_`, `OPS_`) |
| K10 SaaS surfaces | SAS, PRO (new) | `saas.*` (notifications, lifecycle email, product analytics consent) | V0900–V0999 | `notification`, `lifecycle_campaign` | platform additions (`SAAS_`) |

## Common types (authored)

| File | Purpose |
|---|---|
| [common/money.schema.json](common/money.schema.json) | Money `{amount, currency}` decimal string |
| [common/quantity.schema.json](common/quantity.schema.json) | Quantity `{value, unit}` |
| [common/unknown-reason.schema.json](common/unknown-reason.schema.json) | Null reasons |
| [common/maturity.schema.json](common/maturity.schema.json) | data_status, reconciliation_status, period_state, price_basis, scope_kind |
| [common/event-envelope.schema.json](common/event-envelope.schema.json) | Outbox event envelope |
| [common/problem.schema.json](common/problem.schema.json) | RFC 9457 problem + Bridge extensions |
| [common/namespaces.yaml](common/namespaces.yaml) | UUIDv5 namespaces for deterministic IDs |
| [errors/problems.schema.json](errors/problems.schema.json) | Problem catalog schema |
| [openapi/openapi.yaml](openapi/openapi.yaml) | OpenAPI root, security schemes, shared parameters |
| [.spectral.yaml](.spectral.yaml) | API lint rules |
