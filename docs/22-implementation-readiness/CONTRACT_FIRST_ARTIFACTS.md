# Contract-first artifacts to author before coding

The existing specification has canonical *prose* contracts but no executable ones ([AUDIT X-06](AUDIT_CROSS_CUTTING.md)). The domain audits specified **233 contract artifacts** — schemas, DDL, registries, state machines, ADR amendments, catalogs — each with its exact required content and the micro-task that produces it. This page indexes them; the full content requirements are in section 3 of each [backlog](backlog/) file.

Rule: an artifact is authored, reviewed by the owners of every consuming domain and merged **before** the first implementation step that depends on it. Changing a merged artifact follows its versioning rule (schema version bump, ADR amendment or registry version), never an in-place edit.

## 1. Cross-domain artifacts to author first (phase P0)

These gate several lanes at once. Author them in this order; items on the same line can proceed in parallel.

| # | Artifact | Why first | Owner task / source |
|---|---|---|---|
| 1 | ADR-005 amendment — tenant WIF user + per-profile role, `CURRENT_ROLE()`-only row policies, secondary roles disabled (D-02) | Every serving query, cache key and export depends on it | SEC-005 · [SEC Appendix A](backlog/SEC.md) |
| 1 | ADR-014 — analytical revisions and publication (revisioned materialization, SCD2 publication map, `PUBLISH_BATCH`, pins, GC) (D-05, D-06) | Every dbt model, serving view, API pin and recovery snapshot depends on it | DBT-101 · [DBT §3](backlog/DBT.md), [ORC §3](backlog/ORC.md) |
| 1 | ADR amendments for D-04 (config publisher), D-07 (extraction launcher), D-26 (retention) | Change accepted ADR-007/008/009 behavior | CTL-005, ORC/ING, OPS-005 |
| 2 | Control-plane kernel DDL (outbox, idempotency, leases, consumed events) + PostgreSQL RLS standard | Hidden SEC↔CTL cycle is broken only by this kernel (G-SEC-11) | CTL-101 · [CTL §3](backlog/CTL.md), [SEC §3](backlog/SEC.md) |
| 2 | Scope grammar (canonical JSON, PG predicate and Snowflake entitlement compilation) + capability × role matrix with maker-checker rules | Authorization everywhere; approvals for close, rules, prices | SEC-101, SEC-102 · [SEC Appendices B–C](backlog/SEC.md) |
| 3 | Source registry JSON Schema + one contract per activated source, including the widened QUERY_HISTORY projection requested by INS/ALC/WRK and numeric maturity horizons | Irreversible: fields not extracted now are lost for backfilled history | ING-001, FIN-104 · [ING §3](backlog/ING.md), [INS §3](backlog/INS.md) |
| 3 | Landing key grammar, manifest schema, file-receipt contract | S3 prefix-escape defense and batch acceptance | INF-003, ING-005, ING-007 · [INF §3](backlog/INF.md), [ING §3](backlog/ING.md) |
| 3 | Workload metadata allowlist (dbt comment keys, Power BI tag keys) parsed inside the sanitizer | Irreversible loss otherwise (G-WRK-01) | WRK-101 · [WRK §3](backlog/WRK.md) |
| 4 | `fct_charge` schema, family-bucket supersession rules, attribution bridge, service authority map, money library contract | The financial kernel's shape | FIN-001, FIN-106 · [FIN §3](backlog/FIN.md) |
| 4 | Semantic registry schemas + v1 metric/dimension catalog (incl. `attributed_cost`, sketches for percentiles) | API, UX, GOV, RPT, INS all bind to metric IDs | API-001 · [API §3](backlog/API.md) |
| 5 | OpenAPI conventions, error-code catalog, Decimal-as-string codegen | Every endpoint and generated client | FND-103 · [FND §3](backlog/FND.md) |
| 5 | State-machine catalog: connection, batch attempt, backfill, onboarding, rule lifecycle, monitor episode, insight, action, period/statement, subscription | Each state machine is shared by API, workers and UI | CON, ING, ONB, ALC, GOV, INS, FIN, LCH backlogs |
| 5 | Telemetry log/trace/metric schema, alert catalog | Needed from M1 (G-OPS-01) | OPS-001 · [OPS §3](backlog/OPS.md) |
| 6 | Environment, service and IAM policy catalogs; test-estate specification; cost baseline and budgets | Infrastructure and live gates | INF-001, INF-005, INF-101, INF-103, INF-105 · [INF §3](backlog/INF.md) |

## 2. Full index by domain

Artifact names and producing micro-steps, extracted from section 3 of each backlog file. Follow the domain link for the exact required content.

### FND (12 artifacts) — [details](backlog/FND.md)

| Artifact | Produced by |
|---|---|
| `docs/development/packages.yaml` + `layout.md` | FND-001-S01 |
| `.importlinter` + `apps/web/eslint.config.js` boundaries | FND-001-S04/S05 |
| `docs/development/versions.md` + `infra/images.lock.json` | FND-002-S01/S05 |
| `compose.yaml` topology + `docs/development/ports.md` | FND-003-S01/S02 |
| `data/fixtures/manifest.schema.json` (fixture v1) | FND-004-S01 |
| `tools/validation/manifest.schema.json` | FND-005-S01 |
| `docs/evidence/schema/evidence.schema.json` + index line format | FND-005-S04/S06 |
| Required-checks list (`docs/development/ci-checks.md`) | FND-006-S01/S03 |
| `AGENTS.md` | FND-006-S08 |
| `docs/development/snowflake-dev-access.md` | FND-101-S01 |
| `data/fixtures/recorded/meta.schema.json` | FND-102-S01 |
| `contracts/.spectral.yaml` + API conventions doc | FND-103-S01/S02 |

### INF (14 artifacts) — [details](backlog/INF.md)

| Artifact | Produced by |
|---|---|
| `infra/environments/<env>.json` + schema | INF-001-S01 |
| Org and SCP set | INF-001-S02..S04 |
| Terraform state layout | INF-001-S08/S09 |
| CIDR/subnet/SG matrix | INF-002-S01/S06 |
| Egress publication format | INF-002-S03/S13 |
| Storage/messaging catalog | INF-003-S01 |
| Landing key grammar | INF-003-S04 |
| IAM policy templates | INF-103-S01..S05, INF-005-S06/S08 |
| Service catalog `infra/services.yaml` | INF-005-S01 |
| PG pool budget manifest | INF-004-S04 |
| Release manifest schema | INF-007-S01 |
| Snowflake object/role/grant manifest | INF-008-S01/S07/S08 |
| Test-estate specification | INF-101-S01 |
| Cost baseline and budgets | INF-105-S01 |

### SEC (12 artifacts) — [details](backlog/SEC.md)

| Artifact | Produced by |
|---|---|
| ADR-005 amendment (D-02) | SEC-005-S01 |
| Scope grammar spec + JSON Schema | SEC-101-S01/S02 |
| Capability catalog + role matrix | SEC-004-S02 |
| Approval (maker-checker) state machine | SEC-102-S01 |
| Session & auth OpenAPI | SEC-002-S01 |
| Identity DDL | SEC-004-S01, SEC-002-S02, SEC-003-S01 |
| RLS standard | CTL-101 / SEC-004-S03 |
| Revocation contract | SEC-006-S01 |
| Privacy policy file | SEC-007-S01, SEC-103-S01 |
| Attack catalog | SEC-001-S05, SEC-008-S07 |
| Audit event taxonomy | SEC-008-S01 |
| Data inventory | SEC-001-S03 |

### CTL (11 artifacts) — [details](backlog/CTL.md)

| Artifact | Produced by |
|---|---|
| Kernel DDL | CTL-101-S05…S07, CTL-002-S02 |
| "Add a tenant table" template | CTL-101-S11 |
| Event catalog | CTL-004-S01 |
| Error catalog | CTL-003-S03 |
| Control OpenAPI | CTL-003-S01, CTL-001-S09, CTL-007-S03 |
| Pool budget manifest | CTL-002-S08 |
| Expand/contract protocol | CTL-002-S01 |
| Redis key/value contract | CTL-006-S01 |
| Config snapshot contract | CTL-005-S01/S02 |
| Tenant and subscription state machines | CTL-102-S01, CTL-007-S07 |
| Control ERD | CTL-001-S10 |

### CON (10 artifacts) — [details](backlog/CON.md)

| Artifact | Produced by |
|---|---|
| PG DDL `connection.*` | CON-001-S01, CON-004-S01, CON-005-S01, CON-006-S01 |
| IAM templates | CON-001-S03 |
| Install and revoke scripts | CON-003-S02…S06 |
| Privilege map | CON-003-S01 |
| Credit estimator | CON-101-S01 |
| Lifecycle machine | CON-006-S01 |
| Probe contract | CON-005-S01…S03 |
| OpenAPI | CON-001-S07, CON-003-S07, CON-004-S09, CON-005-S11, CON-006-S09…S11, CON-102-S01 |
| Error codes | CON-002-S05, CON-005-S03 |
| Egress IP publication | CON-102-S01 |

### ING (10 artifacts) — [details](backlog/ING.md)

| Artifact | Produced by |
|---|---|
| Registry JSON Schema | ING-001-S01 |
| R1 source contracts | ING-101…104 |
| Transport schema | ING-001-S05, ING-004-S01 |
| Key grammar | ING-005-S01 |
| Manifest v1 JSON Schema | ING-005-S05 |
| PG DDL `sync.*` | ING-002-S05, ING-005-S07, ING-007-S01, ING-010-S01, ING-011-S01, ING-106-S01 |
| Snowflake DDL | ING-006-S01…S05, ING-007-S01 |
| Decision tables | ING-007-S05, ING-008-S03, ING-009-S02, ING-012-S01 |
| APIs | ING-010-S01, ING-011-S01, ING-012-S03, ING-106-S02 |
| Metrics catalog | per task |

### ORC (11 artifacts) — [details](backlog/ORC.md)

| Artifact | Produced by |
|---|---|
| `services/orchestrator/dagster.yaml` + `workspace.yaml` | ORC-001-S01, ORC-003-S06 |
| Launcher contract | ORC-001-S05/S07 |
| PostgreSQL `sync.account_cycles`, `sync.lane_budget`, `sync.tenant_weight` | ORC-003-S01 |
| Error-class catalog | ORC-003-S07 |
| `data/contracts/dagster_metadata.json` | ORC-002-S10 |
| Processing-ledger DDL | ORC-101-S02 |
| Publication DDL + procedure | DBT-101-S03, ORC-005-S01/S04/S13, ORC-105-S01 |
| `data/contracts/publication.json` | ORC-005-S06/S09 |
| `data/contracts/py_outputs.json` | ORC-103-S01 |
| `data/contracts/recovery_plan.json` | ORC-006-S01 |
| Query-tag schema | ORC-104-S01 |

### DBT (11 artifacts) — [details](backlog/DBT.md)

| Artifact | Produced by |
|---|---|
| ADR-014 analytical revisions and publication | DBT-101-S01/S11 |
| `data/contracts/datasets.yaml` | DBT-101-S02 |
| Revision table DDL template | DBT-101-S03 |
| `PARTITION_REVISION` DDL | DBT-101-S03 |
| `revisioned` materialization spec | DBT-101-S04 |
| Serving view template | DBT-101-S05/S08 |
| `data/contracts/dbt_meta.schema.json` | DBT-001-S04 |
| `data/contracts/checks.yaml` | DBT-005-S01 |
| Lint rule catalog | DBT-102-S07, DBT-005-S04 |
| `data/contracts/lineage.json` | DBT-006-S06/S07 |
| CONFIG source contract (D-04) | DBT-103-S01 (with CTL-005) |

### FIN (13 artifacts) — [details](backlog/FIN.md)

| Artifact | Produced by |
|---|---|
| `data/contracts/ledger/fct_charge.schema.json` + dbt contract `fct_charge.yml` | FIN-001-S01/S02 |
| `data/contracts/ledger/supersession.md` | FIN-001-S03 |
| `data/contracts/ledger/bridge_charge_attribution.schema.json` | FIN-001-S04 |
| `data/contracts/service-authority.json` | FIN-001-S05 |
| `data/dbt/seeds/ref_service_crosswalk.csv` (versioned) | FIN-001-S06 (v0), FIN-108 (v1 from live evidence) |
| `data/dbt/seeds/ref_source_maturity_policy.csv` (versioned) | FIN-104-S01 |
| `data/contracts/reconciliation/controls.yaml` | FIN-009-S01 |
| `data/contracts/finance/period_state_machine.md` + PG DDL `finance.*` | FIN-010-S01, FIN-107-S01 |
| `packages/bridge_money` API + `data/contracts/money.schema.json` | FIN-106-S01…S04 |
| OpenAPI: `/v1/pricing/*`, `/v1/billing-references/*`, `/v1/reconciliation/*`, `/v1/periods/*`, `/v1/statements/*` | FIN-105-S05, FIN-101-S06, FIN-009-S12, FIN-010-S11 |
| UX screen specs `/settings-pricing`, `/reconciliation-close`, `/reconciliation-references` | UX owner, before FIN-105-S08 / FIN-010-S12 / FIN-101-S09 |
| Fixture pack `data/fixtures/finance/` | FIN-001, per-task fixture steps |
| Capability catalog additions (SEC) | FIN-010-S02 with SEC-005 |

### API (16 artifacts) — [details](backlog/API.md)

| Artifact | Produced by |
|---|---|
| `packages/semantic_metrics/schema/{metric,dimension,relation,join_path}.schema.json` | API-001-S01 |
| `packages/semantic_metrics/relations/*.yaml` | API-001-S03 (names agreed with DBT-006) |
| v1 metric catalog (§3.1) | API-001-S04…S06 |
| Dimension catalog (§3.2) | API-001-S07 |
| QueryPlan IR `schema/query_plan.schema.json` | API-002-S03, S06 |
| OpenAPI 3.1 `docs/api/openapi.yaml` | API-003-S01 (skeleton), extended by API-004/005/102/104/006 |
| Response meta JSON Schema `packages/api_contracts/meta.schema.json` | API-003-S01 |
| Value encoding | API-003-S01/S02 |
| Problem catalogue `packages/api_contracts/problems.yaml` | API-003-S01 |
| Sealed-token spec `docs/09-api/tokens.md` | API-003-S05 |
| `planner_limits.yaml` | API-002-S05, API-004-S03, API-102-S02 |
| PG DDL `ops.serving_partition_stats`, `ops.serving_dimension_ndv`, `analytics.analysis_job`, `analytics.export_job`, `identity.machine_client` | API-002-S05, API-003-S08, API-004-S02, API-102-S01, API-006-S01 |
| Snowflake DDL `SERVING_JOBS.JOB_RESULT` | API-004-S04 (with SEC-005) |
| Analysis job state machine | API-004-S01 |
| Explain node schema `data/contracts/explain.json` | API-005-S01 |
| Machine-client and rate-limit policy | API-006-S01, S05, S07 |

### UX (10 artifacts) — [details](backlog/UX.md)

| Artifact | Produced by |
|---|---|
| Canonical route map `apps/web/src/routes/route-map.ts` + doc | UX-001-S10 |
| URL-state schema `apps/web/src/state/url-schema.ts` (zod) | UX-002-S05 |
| Query-key factory spec | UX-002-S04 |
| Screen-contract template `docs/10-frontend/screen-contracts/_template.md` | UX-001-S15 (template); each page task S01 |
| Money/number/date formatting spec `apps/web/src/format/README.md` | UX-001-S04 |
| i18n conventions | UX-001-S03 |
| Component inventory (production) | UX-001-S01 |
| Budgets file `apps/web/.size-limit.json` + performance SLOs | UX-001-S12 |
| Accessibility test matrix | UX-008-S01 |
| MSW handlers from OpenAPI examples | UX-002-S01 |

### WRK (11 artifacts) — [details](backlog/WRK.md)

| Artifact | Produced by |
|---|---|
| Allowlist v1 `packages/workload_meta/allowlist_v1.yaml` | WRK-101-S01 |
| `WorkloadMetaV1` Arrow schema | WRK-101-S05 |
| Evidence and classification DDL | WRK-001-S01 |
| Workload taxonomy enum | WRK-001-S01 |
| Precedence table `classifier_rules_v1.yaml` | WRK-001-S03 |
| Session application map `session_app_map_v1.yaml` | WRK-001-S02 |
| Execution graph DDL | WRK-004-S01 |
| Required source projections (to ING) | WRK-101-S09 (handoff to ING backlog) |
| Comparison contract | WRK-005-S01 |
| Operator evidence artifact schema | WRK-103-S01 |
| Retention contract | WRK-104-S01 |

### ALC (13 artifacts) — [details](backlog/ALC.md)

| Artifact | Produced by |
|---|---|
| `data/contracts/tags.json` | ALC-001-S01 |
| `data/contracts/rule-attributes.json` | ALC-001-S04 |
| `data/contracts/rule-ast.json` | ALC-002-S01/S02 |
| Precedence spec `docs/…/alc-precedence.md` | ALC-002-S04 |
| Snowflake CONFIG DDL | ALC-002-S07, ALC-004-S04, ALC-005-S02 |
| dbt model contracts | ALC-001/002/004/005/006/008, ALC-101 |
| Rounding spec + fixtures | ALC-005-S04, ALC-008-S03 |
| State machines | ALC-003-S01, ALC-008-S01 |
| Access-impact & disclosure spec | ALC-003-S05, ALC-101-S01/S05 |
| OpenAPI | ALC-001…008 |
| Error codes | each task |
| D-15 seed | ALC-103-S06 |
| Golden fixtures | ALC-005, ALC-103, ALC-101 |

### GOV (15 artifacts) — [details](backlog/GOV.md)

| Artifact | Produced by |
|---|---|
| `data/contracts/budget.json` + PG DDL | GOV-001-S01/S02 |
| Budget formula sheet | GOV-001-S06 |
| `packages/bridge_stats` API | GOV-101 |
| `data/contracts/forecast.json` + `py_forecast` DDL | GOV-002-S01 |
| `data/contracts/monitor.json` (JSON Schema 2020-12) | GOV-003-S01/S02 |
| Condition catalog | GOV-003-S02 |
| Observation DDL | GOV-004-S01 |
| Tracker/incident PG DDL + transition table | GOV-004-S05/S06 |
| Planner batching spec + cost model | GOV-003-S08, GOV-103 |
| Destination DDL + adapter interface | GOV-006-S01/S02 |
| Webhook spec | GOV-006-S08, GOV-007-S08 |
| SSRF deny list + validator | GOV-006-S09 |
| Retry and classification table | GOV-007-S03 |
| Templates | GOV-007-S08 |
| Error codes | each task |

### INS (13 artifacts) — [details](backlog/INS.md)

| Artifact | Produced by |
|---|---|
| Source projection change request | INS-001-S02 → ING-001, CON-005 |
| `data/contracts/detector_manifest.schema.json` + `services/intelligence/detectors.v1.yaml` | INS-001-S01/S02 |
| `data/contracts/insight_observation.schema.json` | INS-001-S01 |
| Reason-code enum | INS-001-S01 |
| Snowflake DDL (insert-only, D-05) | INS-001-S08, INS-006-S06, INS-007-S03 |
| PostgreSQL DDL | INS-006-S02 |
| Lifecycle specs | INS-006-S01 |
| Measurement contract | INS-007-S01 |
| Config catalog | INS-001-S04, INS-007-S01 |
| `config/warehouse_credit_rates.v1.json` | INS-002-S06 |
| OpenAPI | INS-101, INS-006, INS-007 |
| Error codes | INS-006-S03 |
| Events | INS-001-S11, INS-006, INS-007 |

### RPT (11 artifacts) — [details](backlog/RPT.md)

| Artifact | Produced by |
|---|---|
| `data/contracts/report-definition.schema.json` | RPT-001-S01 |
| `data/contracts/report-components/*.schema.json` (11) | RPT-001-S02 |
| Narrative grammar v1 | RPT-001-S06 |
| State machines | RPT-002-S01, RPT-004-S01 |
| Schedule schema + resolver spec | RPT-004-S01..S03 |
| CSV serialization spec | RPT-002-S08 |
| S3 layout + lifecycle | RPT-002-S10, RPT-005-S08 |
| IAM | RPT-002-S12, RPT-005-S04 |
| Renderer image spec | RPT-002-S04 |
| OpenAPI | RPT-001, RPT-002, RPT-004, RPT-005 |
| Error codes | all |

### OPS (15 artifacts) — [details](backlog/OPS.md)

| Artifact | Produced by |
|---|---|
| `packages/telemetry/schema/log-event.v1.json` | OPS-001-S01 |
| `packages/telemetry/error_taxonomy.py` | OPS-001-S02 |
| `packages/telemetry/metrics-registry.yaml` | OPS-001-S05 |
| `docs/operations/propagation.md` | OPS-001-S03 |
| `infra/observability/slo/slo-catalog.yaml` | OPS-003-S01 |
| `data/quality/gate-catalog.yaml` | OPS-002-S01 |
| DDL `ops.quality_results` (Snowflake) | OPS-002-S02 |
| DDL `privacy.tombstones` (PG) + S3 object schema `tombstone.v1.json` | OPS-104-S01 |
| DDL `privacy.deletion_requests`, `privacy.deletion_stages`, `privacy.legal_holds` (PG) | OPS-005-S01 |
| `data/contracts/recovery-manifest.v1.json` | OPS-007-S01 |
| DDL `ops.processing_ledger` (Snowflake, internal) | OPS-109-S02 |
| DDL `internal_cost.*` (separate Snowflake database, no customer grants) | OPS-009-S01 |
| `support.access_grants` (PG) + ops API OpenAPI `ops-api.v1.yaml` | OPS-106-S01 |
| `docs/operations/oncall-policy.md` | OPS-102-S01 |
| `docs/security/evidence-catalog.yaml` | OPS-108-S01 |

### REL (8 artifacts) — [details](backlog/REL.md)

| Artifact | Produced by |
|---|---|
| `docs/releases/release-manifest.v1.json` (JSON Schema) | REL-001-S01 |
| `docs/releases/migration-policy.md` + linter config | REL-101-S01 |
| `docs/releases/deploy-strategies.md` | REL-002-S02 |
| `docs/releases/evidence-impact.yaml` | REL-001-S06 |
| `docs/releases/deployment-record.v1.json` | REL-002-S13 |
| DDL `control.feature_flags` + `docs/releases/kill-switches.md` | REL-102-S01 |
| `docs/releases/serving-compatibility.md` | REL-103-S01 |
| `docs/production/go-no-go.yaml` | REL-004-S06 |

### ONB (7 artifacts) — [details](backlog/ONB.md)

| Artifact | Produced by |
|---|---|
| `docs/onboarding/state-machine.md` | ONB-001-S01 |
| DDL `onboarding.*` (PG) | ONB-001-S02 |
| OpenAPI onboarding paths | ONB-001-S06 |
| `docs/onboarding/blockers.yaml` | ONB-001-S07 |
| `data/estimates/onboarding-estimate.v1.json` | ONB-101-S01 |
| `docs/onboarding/first-value.md` | ONB-005-S01 |
| Export bundle manifest `tenant-export.v1.json` | ONB-102-S01 |

### LCH (10 artifacts) — [details](backlog/LCH.md)

| Artifact | Produced by |
|---|---|
| DDL `commercial.plans`, `commercial.tenant_entitlements` | LCH-101-S01 |
| `entitlements.check()` interface | LCH-101-S03 |
| `docs/commercial/subscription-state-machine.md` | LCH-001-S02 |
| DDL `commercial.subscriptions`, `commercial.subscription_events` | LCH-001-S02 |
| DDL `commercial.invoice_refs` | LCH-001-S04 |
| DDL `commercial.payment_events` | LCH-001-S04 |
| `docs/commercial/vat-and-invoicing.md` | LCH-103-S02 |
| `docs/legal/dpa-annexes.md`, `docs/legal/subprocessors.md` | LCH-102 |
| `docs/support/support-policy.md` | LCH-104-S01 |
| `docs/releases/go-live-plan.md` | LCH-003-S03 |
