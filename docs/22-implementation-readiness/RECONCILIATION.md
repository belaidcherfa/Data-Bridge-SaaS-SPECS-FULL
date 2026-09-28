# Reconciliation of the domain backlogs

Integration review, 2026-09-28. Inputs: the 20 files in [backlog/](backlog/), [DECISIONS_REQUIRED.md](DECISIONS_REQUIRED.md) (D-01…D-34, authoritative), [AUDIT_CROSS_CUTTING.md](AUDIT_CROSS_CUTTING.md), [RELEASE_PLAN.md](RELEASE_PLAN.md) and the original index `docs/00-project/task-index.json`. Outputs: this file, the machine-readable plan [revised-task-graph.json](revised-task-graph.json) and [REVISED_CRITICAL_PATH.md](REVISED_CRITICAL_PATH.md). No backlog file was edited in the integration pass; where a ruling changes a backlog step, §5 lists the text the owner must update (applied on 2026-09-28 — see §6).

## 0. Method and conventions

- **Scope.** 249 tasks: the 151 original tasks and 98 new tasks (`<DOM>-1nn`) found in the backlogs. Every task keeps its ID. One task is merged (CTL-103 → UX-101; it keeps an entry with zero hours and `merged_into`). No original task is removed.
- **Ownership rule.** When two backlogs specify the same artifact, the owner is the domain whose contract the artifact belongs to (platform mechanism → INF/CTL, security semantics → SEC, money → FIN, source contracts → ING, serving/API → API). The other task keeps a thin integration step (usually 0–1 h) and loses the duplicated steps.
- **Hour de-duplication.** Removed hours are the step hours listed in the losing task's micro-step table. The task's low estimate is reduced by those step hours scaled by (task low ÷ Σ step hours), and the high estimate by (task high ÷ Σ step hours), so each task keeps its own uncertainty ratio. Every changed estimate is listed in §4 with its reason; the JSON keeps the backlog figure in `backlog_estimate_low_h/high_h`.
- **Edge semantics.** An edge X → Y means X cannot be DONE before Y is DONE. Edges a backlog labels "step-level", "contract only" or "soft" are **not** graph edges (they are named in the ruling notes and are schedule risk R-06 in the critical-path document). Edges labelled "live gate", "staging gate" or "before DONE" **are** graph edges (conservative).
- **Releases.** R1, R1\* (in R1 only if the first-customer profile D-20 requires it) and R2, as tagged in each backlog §6. Where §6 splits one task, the task stays R1 and carries `conditional_hours_low/high` (R1\* part: FIN-008 replication) or `r2_hours_low/high` (R2 part: API-102 PNG/PDF, ALC-002 regex operators).
- **Ruling IDs.** `U-nn` = duplicate/overlap ruling (§1); `C-nn` = contradiction ruling (§2). The edge table (§3) tags every integration edge with its ruling ID.

### Outcome in numbers

| Measure | Before (backlog §6 as written) | After reconciliation |
|---|---|---|
| Tasks | 249 (151 original + 98 new) | 249 entries; 248 live, 1 merged (CTL-103) |
| Live tasks by release | — | R1 218 · R1\* 9 · R2 21 |
| R1 hours | 6,949–10,228 | **6,779–9,974** (−170 / −254) |
| R1\* hours (task-level + FIN-008 replication part) | 247–366 | **247–366** (unchanged) |
| R2 hours (task-level + R2 parts of R1 tasks) | 708–1,107 | **663–1,036** (−45 / −71) |
| Dependency edges | 821 if every backlog request is applied literally — with 4 cycles (CON-002/CON-003 ↔ OPS-103), 1 R1→R2 edge (OPS-004 → API-006) and 1 R1→R1\* edge (INS-002 → FIN-004) | **859**, acyclic; 0 R1→R2, 0 R1→R1\*, 0 R1\*→R2 |
| Longest R1 chain | 73 tasks (original index) | **42 tasks**; 1,360–2,003 h (see critical-path file) |

The de-duplication is modest in hours (≈ 2.5 % of R1) because the domain auditors mostly split work cleanly; the larger value of this reconciliation is in the 30 contradictions (§2), five of which would have produced a security or data-loss defect if each backlog had been implemented as written (C-04, C-07, C-10, C-11, C-19).

## 1. Duplicate or overlapping tasks

### U-01 · Dashboards: CTL-103 / RPT-103 / UX-101 (and CTL-007-S12)
- **Evidence.** `CTL.md` CTL-103-S01 "Responsive grid layout engine with drag/resize and keyboard alternatives"; `RPT.md` RPT-103-S03 "Builder UI (drag, resize, configure compatible metrics only)"; `UX.md` UX-101-S03 "Grid editor (drag/resize with keyboard alternatives…)". All three are R2 and all three build the same builder, widget model and sharing.
- **Ruling.** UX-101 owns the dashboards list, builder UI and widget states (R2). RPT-103 owns the backend: dashboard definition as a report layout kind, widget data API evaluated under the **viewer's** scope, sharing and "export dashboard to report" (R2). CTL-103 is **merged into UX-101** (0 h). CTL-007 keeps only the R1 persistence (`report.dashboards`, ≤ 30 widgets, fixed grid, per-widget states in S04/S12).
- **Hours.** CTL-103 24–40 → 0; RPT-103 38–57 → 27–41 (S03/S04 UI removed). **Edges.** UX-101 +RPT-103.

### U-02 · Runtime IAM identity provisioning: INF-103 / SEC-105 / CON-001
- **Evidence.** `INF.md` INF-103-S06 "consume `identity.requested` events … idempotent GetRole → compare tag/trust/policy hash → create/update"; `CON.md` CON-001-S04 "Build the outbox-driven `connector-identity-provisioner` worker"; `SEC.md` SEC-105-S02 "`tenant-serving-provisioner` role may `iam:CreateRole/TagRole/DeleteRole` only under path `/bridge/tenant-serving/`". Three IAM-mutating services with three permission models.
- **Ruling.** One runtime IAM provisioner, **INF-103**, for both role kinds (per-connection extractor roles and per-tenant serving roles): names, boundaries, provisioner least privilege, propagation retries, quota guard, reconcile/quarantine, deletion order. **CON-001** keeps the connection-specific inline-policy content (S03), identity immutability, the connection API and revoke = attach `bridge-revoked-deny` (S09, via INF-103's API). **SEC-105** keeps everything Snowflake-side (CREATE USER with `DEFAULT_SECONDARY_ROLES=()`, profile roles, entitlements, GC, Snowflake/PG drift) and requests the IAM role through INF-103. Naming and thresholds: C-11.
- **Hours.** CON-001 40–56 → 28–40 (S04, S05, S10 removed; S06 see U-12); SEC-105 48–76 → 40–63 (S02 and the IAM parts of S07–S09 removed); INF-103 unchanged 30–44. **Edges.** CON-001 +INF-103 (INF), SEC-105 +INF-103 (instead of INF's SEC-005 +INF-103: SEC-005 proves the policy model with scripted fixtures).

### U-03 · Snowflake test estate, canaries and tenant zero: INF-101 / OPS-103 / FIN-108 (with ING-102, FND-102)
- **Evidence.** `INF.md` INF-101-S02 "Provision org T-A … A1 (Enterprise, AWS eu-west-1), A2 … A3"; `OPS.md` OPS-103-S01 "create the synthetic organization with SYN_A (Enterprise, AWS eu-west-1) and SYN_B"; OPS-103-S03 and INF-101-S06 both build a deterministic tagged workload generator; INF-101-S09 and OPS-103-S09 both monitor estate spend. `FIN.md` FIN-108 "Plugs in: after CON-005 and ING-007 connect Bridge's own Snowflake organization (… 'tenant zero')". `ING.md` ING-102 "Coordinate with FIN-108 (billing semantics verification) so the two tasks do not duplicate work."
- **Ruling.** **One** non-production Snowflake estate, owned by **INF-101** (organizations, accounts, generators — including the hourly known-answer canary scenario — spend caps, expiry alarms, provisional install). **OPS-103** keeps only the canary logic: known-answer table, lagged canaries (H+2/H+7/H+10), source-latency measurement and production canary tenants bound to estate accounts. The estate's organization account is **tenant zero** for **FIN-108**, which keeps billing-semantics verification (UICD tuples, crosswalk v1, statement reconciliation, Cortex/marketplace views); per-source DESCRIBE/latency/retention facts are **ING-101…104**'s (not repeated in FIN-108); connector decimal handling is ING-003-S01/S04's acceptance. FND-102 records fixtures from the same estate. Every "OPS-103 account" reference in ING/CON steps means an INF-101 account. Budget: C-24.
- **Hours.** OPS-103 26–40 → 12–18; INF-101 34–52 → 35–54 (+1 h canary scenario); FIN-108 28–44 → 25–39. **Edges.** CON-002/003/005 and ING-101…104 depend on INF-101 instead of OPS-103; OPS-103 → INF-101, CON-003; FIN-108 +ING-102. This also breaks the CON-003 ↔ OPS-103 cycle (C-25).

### U-04 · Privacy transforms in the extraction path: SEC-007 / SEC-103 / ING-107 / WRK-101
- **Evidence.** Comment/tag metadata is extracted twice: `SEC.md` SEC-007-S07 "Extract leading and trailing block comments and QUERY_TAG before sanitizing; … keep allowlisted keys" and `WRK.md` WRK-101-S05 "integrate as the first step of SEC-007 `sanitize()`". The sanitized-text cache is specified twice with the same key: SEC-007-S08 and ING-107-S04 "`(tenant, account, QUERY_PARAMETERIZED_HASH_VERSION, QUERY_PARAMETERIZED_HASH, sanitizer_version)`, LRU 100k". Per-tenant key handling in the extractor is specified twice: SEC-103-S04 "decrypt once per account-cycle, pseudonymize USER_NAME" and ING-107-S03 "decrypt once per task via KMS with encryption context `tenant_id`".
- **Ruling.** Libraries vs integration: **WRK-101** owns the workload-metadata library and allowlist v1 (SEC reviews it; `privacy-policy.json` references it). **SEC-007** owns the SQL/tag sanitizer, its cache and FULL/METADATA_ONLY modes. **SEC-103** owns the pseudonym scheme, key lifecycle, dictionary API and the erasure primitive. **ING-107** owns the in-extractor pipeline: operation order, in-process key handling, throughput budget and failure semantics. Edge SEC-007 +WRK-101 (WRK) is confirmed.
- **Hours.** SEC-007 50–78 → 47–73; ING-107 24–36 → 22–33; SEC-103 40–64 → 35–56 (S04 in-extractor part −2 h; S09 erasure workflow −3 h, see U-11). **Edges.** ING-101 +ING-107 (its S07 validates the privacy path live).

### U-05 · Operator plane and customer-approved support access: CTL-102 / OPS-106 / SEC-104 / LCH-001-S05
- **Evidence.** Three internal consoles: `CTL.md` CTL-102-S02 "Internal console authentication via IAM Identity Center OIDC, operator roles `ops_viewer`, `ops_provisioner`, `finance_operator`, hardware MFA, private ALB listener"; `OPS.md` OPS-106-S02 "Build the internal ops API (private ALB, SigV4 from operator roles only)"; `LCH.md` LCH-001-S05 "Create the internal FinanceOperator capability on the ops API (IAM Identity Center, MFA)". Two support-grant models: `SEC.md` SEC-104-S01 "`identity.support_access_grants` … `expires_at ≤ starts_at+8 h`" vs `OPS.md` OPS-106-S06 "`support.access_grants` … default 4 h, max 24 h".
- **Ruling.** **CTL-102** owns the single ops plane: ops API service, operator authentication (OIDC for the console, SigV4 for the CLI), operator role catalog (ops_viewer, ops_provisioner, finance_operator, support_agent, incident_responder) and tenant lifecycle endpoints. **OPS-106** owns AWS permission sets, `bridge-admin` CLI and its commands, dry-run/approval for mutating recovery actions and break-glass. **SEC-104** owns support-access grants end to end (table, tenant approval incl. OPS-106's `health_read` auto-approve policy, synthetic SUPPORT membership, expiry, audit). **LCH-001** only registers finance-operator capabilities on that plane. Duration/scope rule: C-15.
- **Hours.** OPS-106 40–60 → 25–38; SEC-104 24–40 → 25–42 (+1 h); CTL-102 28–44 → 25–39 (+2 h ops API, −5 h, see U-11); LCH-001 38–56 → 36–53. **Edges.** OPS-106 +CTL-102; CTL-102 +INF-006 (internal ALB listener); LCH-001 +CTL-102; OPS-004 +SEC-104 (support access is in the attack surface).

### U-06 · Cost guardrails, attribution and unit economics: INF-105 / OPS-109 / ORC-104 / OPS-009
- **Evidence.** Tags twice: `INF.md` INF-105-S02 "provider `default_tags` (environment, component, cost_owner, managed_by), org tag policy, activate cost-allocation tags" and `OPS.md` OPS-109-S01 "Enforce AWS tags … via Terraform `default_tags` and an organization tag policy". CUR export twice: INF-105-S05 and OPS-109-S08. Query-tag builder twice: ORC-104-S01 "Set query-tag JSON for dbt …, broker …, Python writer" and OPS-109-S03 "Apply the QUERY_TAG builder in extraction, dbt, broker and reports". Per-tenant build rows twice: OPS-109-S02 "`ops.processing_ledger` and a dbt `on-run-end` hook" and ORC-104-S02 "`OPS_INTERNAL.BUILD_MODEL_TENANT_ROWS` from PARTITION_REVISION row counts". Credit allocation twice: ORC-104-S04 "Allocate credits by rows written per tenant" and OPS-009-S05/S06.
- **Ruling.** **INF-105**: budgets, anomaly detection, tags, CUR export, conftest cost traps. **OPS-109**: one QUERY_TAG JSON format v1 (it absorbs ORC-104's fields `app, env, lane, build_id, model, layer`), serving-user → tenant registry, ECS task usage, extraction bytes, tag-coverage test. **ORC-104**: per-build/per-model central compute capture and per-tenant rows from PARTITION_REVISION. **OPS-009**: ingestion into `INTERNAL_COST`, allocation, margin. OPS-109 no longer creates `ops.processing_ledger`: per-tenant build usage is ORC-104-S02's output, and the name "processing ledger" stays with ORC-101's D-06 batch ledger (U-25).
- **Hours.** OPS-109 20–30 → 13–19; ORC-104 16–24 → 8–12. **Edges.** OPS-009 +INF-105 (CUR), +LCH-001 (revenue references live in `commercial.invoice_refs`, created by LCH-001-S04; OPS asked for LCH-101 — see U-08).

### U-07 · Notification infrastructure and delivery SLIs: INF-006-S11 / GOV-102 / GOV-006 / GOV-007 / OPS-110
- **Evidence.** SES twice: `INF.md` INF-006-S11 "SES: domain identity with Easy DKIM, custom MAIL FROM (MX + SPF), DMARC … configuration set → SNS → SQS bounces/complaints; production access request filed" and `GOV.md` GOV-102-S01…S03 (same identity, configuration set, production-access request). Destination health UI three times: GOV-006-S13 "destinations UI at `/settings/destinations` (configured/verified/degraded, remediation)", `OPS.md` OPS-110-S07 "Show destination health … in Settings › Integrations", `UX.md` UX-103-S05. Error classification twice: GOV-007-S03 and OPS-110-S03.
- **Ruling.** INF-006 owns the SES identity (one sending subdomain `notify.<domain>` in the INF-006-S01 DNS map), configuration set and production-access request; GOV-102 keeps the egress proxy, Slack app, Teams guide and destination secrets. GOV-006/GOV-007 own adapters, classification and the destination-health UI. OPS-110 owns SLI definitions, emission, burn alarms and dashboards only. (Internal target "event → accepted p95 ≤ 2 min" in GOV-007-S13 and the SLO "≤ 10 min, 99 %" in OPS-110-S01 are compatible: target vs objective.)
- **Hours.** GOV-102 21–30 → 14–20; OPS-110 14–22 → 11–17; UX-103 see U-22. **Edges.** UX-103 −GOV-006.

### U-08 · Plans, entitlements and commercial records: CTL-007 / LCH-101 / LCH-001
- **Evidence.** `CTL.md` CTL-007-S07 "Migrate commercial tables (Appendix F): `plans`, `subscriptions` (launch.md states), `entitlement_snapshots`, `invoices_metadata`, `payment_events`", S08 "Subscription state machine", S09 "`entitlements.check(tenant, quota_key, requested)` + admission hooks", S10 "Payment idempotency". `LCH.md` LCH-101-S01 "Create `commercial.plans` and `commercial.tenant_entitlements`", S03 "Implement `entitlements.check()` and wire it into …"; LCH-001-S02 "Implement the canonical subscription state machine …; migrate CTL-007's enum", S04 "Create `invoice_refs` and `payment_events`", S07 payment evidence.
- **Ruling.** **LCH-101** owns plans, entitlements and admission enforcement (early: it gates connection creation and backfill). **LCH-001** owns the subscription state machine (C-08), invoice references and payment evidence. **CTL-007** keeps saved views, shares, R1 dashboards and spec validation. LCH-101 no longer depends on CTL-007.
- **Hours.** CTL-007 48–72 → 31–46 (S07–S10, the commercial tests in S11 and the billing page in S12 removed). **Edges.** LCH-101 −CTL-007 +CTL-102; LCH-001 −CTL-007 +CTL-102; CON-006 +LCH-101 (connection-count quota at admission); ING-010 +LCH-101 (history-days quota at backfill admission).

### U-09 · Statistics library: GOV-101 / GOV-005 / INS-001-S04
- **Evidence.** `GOV.md` GOV-101-S03 "Implement robust_z and impact_floor (max(pct·abs(median), minor unit))"; `INS.md` INS-001-S04 "`impact_floor(currency, tenant)` from config, strict `>` comparison"; GOV-005-S07 "median/MAD implementations outside `packages/bridge_stats` fail the build (INS reuse)".
- **Ruling.** GOV-101 owns every statistical primitive including the monetary impact floor (parameterized per tenant/currency; INS supplies config). GOV-005 is the anomaly *evaluator*; INS-003 Q07 calls it.
- **Hours.** INS-001 −1 h (see U-18 for the rest). **Edges.** INS-001 −GOV-005 +GOV-101 (GOV); INS-003 +GOV-005.

### U-10 · Exports, CSV writer and artifact downloads: API-102 / RPT-002 / RPT-005 / SEC-006 / UX-104 / ONB-102 / FIN-101
- **Evidence.** Three download endpoints: `SEC.md` SEC-006-S08 "`GET /v1/artifacts/{id}/download` rechecks artifact scope ⊆ current scope, then 302 to presigned URL TTL 30 s"; `API.md` API-102-S05 "Download endpoint: re-authorize … → 302 to a 30 s presigned URL"; `RPT.md` RPT-005-S03 "Download broker …", S04 "Presign mode per G-RPT-07 (60 s …)". Two CSV writers: API-102-S03 "type-driven CSV writer … formula injection" and RPT-002-S08 "CSV writer per G-RPT-09 from the snapshot". Two export jobs: API-102-S01/S04 and ONB-102-S02 "Implement the export as an analysis job (API-004) … 7-day expiry; brokered download". FIN-101 lists an "RPT download broker" dependency.
- **Ruling.** **SEC-006-S08** is the single artifact download broker for every artifact kind (reports, exports, evidence bundles, statements, uploaded billing references) — it exists at M1, so FIN-101 does not wait for the reporting lane. RPT-005 plugs a report authorization resolver into it (requester ∈ owner ∪ delivered recipients ∪ report viewers) and keeps the brokered-stream mode for high-sensitivity tenants. **API-102** owns the CSV writer library and the export job kinds; RPT-002 and ONB-102 reuse them (tenant export bundle = an API-102 export kind). TTL: C-12.
- **Hours.** API-102 R1 part 24–34 → 22–31; RPT-005 29–44 → 25–38; RPT-002 44–66 → 42–63; ONB-102 26–40 → 21–32 (with U-11). **Edges.** ONB-102 +API-102.

### U-11 · Tombstones, erasure and tenant deletion: OPS-104 / OPS-005 / SEC-103 / CTL-102 / SEC-105 / CON-006 / ONB-102
- **Evidence.** Three tombstone stores: `SEC.md` Appendix G "`privacy.identity_tombstones`" (PostgreSQL), `OPS.md` OPS-104-S01 "`privacy.tombstones` … INSERT-only" mirrored to an S3 bucket outside restore scope, `CTL.md` CTL-102-S06 "`platform.tenant_tombstones`". Two erasure APIs: SEC-103-S09 "`POST /v1/privacy/erasure-requests`" and OPS-005-S17 "`POST /v1/privacy/requests`". Two deletion orchestrators: CTL-102-S06 "ordered deletion plan (dry-run manifest)" and OPS-005-S09 "tenant-deletion orchestrator with ordered stages". Two pause/disconnect definitions: CON-006-S11 "'Disconnect' = pause + revoke with data retained" and ONB-102-S04 "Define and implement pause …, disconnect account …, offboard tenant".
- **Ruling.** **OPS-104** is the only tombstone registry (kinds SUBJECT, TENANT, CONNECTION; S3 mirror outside restore scope — the D-10 requirement); SEC-103's dictionary suppression and CTL-102's restore guard read it. **OPS-005** owns the privacy-request workflow (access, erasure, tenant deletion) and the deletion orchestrator; SEC-103 provides `erase_subject()`, SEC-105-S07 disables the tenant principal, CON-006/CON-001 revoke — as stage handlers. **CTL-102** owns the tenant state machine and starts offboarding. **CON-006** owns pause/disconnect/revoke semantics; **ONB-102** owns the customer-facing offboarding request, export bundle and reconnection.
- **Hours.** SEC-103 −3 h (S09), CTL-102 −5 h (S06 plan, S06/S07 tombstone table), ONB-102 −3 h (S04). **Edges.** ONB-102 +CTL-102.

### U-12 · Extraction launch path and the account-cycle table: ING-106 / ORC-001 / ORC-002 / ORC-003 / CON-001-S06 / INF-005-S08
- **Evidence.** Launcher defined four times: `ORC.md` ORC-001-S05 "Implement `BridgeEcsRunLauncher(EcsRunLauncher)` … resolve `taskRoleArn` from PostgreSQL"; `ING.md` ING-106-S03 "a generic op (orchestrator role) calls the launcher → `RunTask` … polls ECS until STOPPED"; `CON.md` CON-001-S06 "Restrict the launcher … `services/launcher/resolve.py`"; `INF.md` INF-005-S08 "Extraction launcher IAM". Cycle table twice: ORC-003-S01 "`sync.account_cycles` (unique account_id+lane+cycle_start; lease_token …)" and ING-106-S01 "`sync.cycle_requests` (… kind STEADY/BACKFILL_CHUNK/ANTI_ENTROPY/PROBE/ORG …)". Schedule formula twice (C-03).
- **Ruling (D-07).** **ORC-003** owns the single cycle table (name `sync.account_cycles`, extended with ING-106's `kind`, `due_windows`, `connection_epoch`, `fencing_token`, `deadline_at`), the planner, weighted-fair admission, retry classes and the stuck-cycle reaper. **ING-106** owns the dedicated launcher service (claims ADMITTED cycles, resolves `connection_id → role` from PostgreSQL, calls `RunTask`; absorbs CON-001-S06's `resolve.py` and its negative test), the in-task executor and the `sync-api`. **INF-005-S08** owns the launcher IAM. ORC-001-S05…S07 are retired (C-04). ORC-002-S03's job becomes a sensor that emits `AssetObservation` from sync outcomes.
- **Hours.** ORC-001 38–52 → 31–43; ORC-002 24–36 → 22–33; ING-106 40–58 → 37–54; CON-001 −3 h (in U-02 total). **Edges.** ING-106 +ORC-003; ING's requested ORC-003 +ING-106 is rejected (C-25); INS-102 +ING-106.

### U-13 · Customer credit estimation and consent: CON-101 / ONB-101 / OPS-105-S06 / CON-006-S04, S08
- **Evidence.** `CON.md` CON-101-S01 "Implement `estimate_monthly_credits(cadence, sources, suspend_mode, backfill_profile)`"; `ONB.md` ONB-101-S03 "Implement credit formulas: steady = accounts × cycles/day × billed_seconds_per_cycle/3600 × 30 …; backfill = Σ chunks × seconds_per_chunk/3600"; calibration three times (CON-101-S07, OPS-105-S06, ONB-101-S08).
- **Ruling.** CON-101 owns the estimator (steady and backfill credits) and steady-state calibration; OPS-105-S06 calibrates backfill seconds per day; ONB-101 owns the volume probe, duration/ETA estimate, the backfill consent panel and estimate-vs-actual tracking. CON-006-S08 embeds ONB-101's consent panel; CON-006-S04 records steady-state consent only.
- **Hours.** ONB-101 26–40 → 22–34.

### U-14 · PostgreSQL migration safety: REL-101 / CTL-101 / CTL-002
- **Evidence.** Runner twice: `CTL.md` CTL-101-S01 "one-off ECS migration task (`bridge-migrate`), `pg_advisory_lock(7431001)`, `lock_timeout=3s` with 5 retries" and `REL.md` REL-101-S03 "migration runner as a one-off ECS task: advisory lock, `lock_timeout=5s`". Linter twice (CTL-002-S01, REL-101-S02); backfill framework twice (CTL-002-S03, REL-101-S05); catalog guard twice (CTL-101-S04, REL-101-S07).
- **Ruling.** CTL-101/CTL-002 own the runner, linter, backfill framework and RLS catalog lint. REL-101 keeps the migration policy, the N−1 compatibility job against the previous release tag and the contract-migration gate. Lock timeout: C-16.
- **Hours.** REL-101 20–30 → 10–14.

### U-15 · dbt CI and developer inner loop: FND-101 / DBT-102 / DBT-001-S03
- **Evidence.** `FND.md` FND-101-S07 "PR workflow on in-VPC DEV runner: `dbt build --target ci --select state:modified+ --defer` …; janitor drops `CI_PR_%` older than 48 h"; `DBT.md` DBT-102-S05 "PR job: `state:modified+ --defer --state baseline/`", S06 "TTL janitor dropping `CI_PR*` schemas older than 24 h"; profiles in both FND-101-S05 and DBT-001-S03.
- **Ruling.** DBT-102 owns dbt CI (schema naming, fixture load, baseline, deferral, janitor) and runs on the INF-002-S09 in-VPC runner; DBT-001 owns `profiles.yml`; FND-101 owns the human inner loop only (SSO users, personal schemas and warehouses, the `dev` target, guardrails). Naming/TTL: C-18.
- **Hours.** FND-101 20–30 → 15–22.

### U-16 · Workload classification: DBT-003-S06 / WRK-001
- **Evidence.** `DBT.md` DBT-003-S06 "Implement deterministic workload classification in SQL … retain conflicts in `bridge_query_workload_evidence`"; `WRK.md` WRK-001-S02/S03 "evidence producers in dbt SQL … precedence and conflict resolution".
- **Ruling (D-34).** WRK-001 owns classification (dbt SQL, Python oracle). DBT-003 keeps resource history, membership and the `as_of_join`.
- **Hours.** DBT-003 32–46 → 28–40.

### U-17 · Query-family × day aggregate, retention purge and revision GC: WRK-104 / INS-003-S02 / DBT-006-S01 / ORC-105 / OPS-005-S05
- **Evidence.** Three definitions of the D-11 aggregate: `WRK.md` WRK-104-S02 "`fct_query_family_daily(tenant, account, warehouse, workload_key, query_parameterized_hash, hash_version, day, …, elapsed_tdigest, execution_tdigest, users_hll …)`"; `INS.md` INS-003-S02 "dbt `fct_ins_query_family_day` (extends the D-11 aggregate): … attributed_credits (+QAS), cost, spill_remote_exec_count, spill_remote_bytes, identity tuple counts"; `API.md` G-API-04 "`APPROX_PERCENTILE_ACCUMULATE` … per (tenant, account, warehouse, query_parameterized_hash, day), plus `HLL_ACCUMULATE` states". Three deletion executors: WRK-104-S05 "Purge job for query-level rows older than hot_days", OPS-005-S05 "canonical partition expiry 400 d", ORC-105-S04 "daily GC … deleting eligible revisions".
- **Ruling.** One model `fct_query_family_daily`, owned by **WRK-104**, grain (tenant, account, warehouse_id, workload_key, query_parameterized_hash, hash_version, usage_date UTC) with the union of columns (C-01). INS-003-S02 becomes a view; DBT-006 serves it as `serving_query_family_daily`. **ORC-105**'s GC job is the only physical deleter of revisioned rows (superseded revisions and retention expiry); WRK-104 declares the query-grain retention policy and tier marker; OPS-005 verifies and deletes RAW.
- **Hours.** INS-003 34–50 → 31–46; OPS-005 58–86 → 56–84 (with C-02); ORC-105 22–32 → 23–33. **Edges.** INS-003 +WRK-104; OPS-007 +ORC-105 (recovery-snapshot pins).

### U-18 · Python output landing: ORC-103 / INS-001-S08 / GOV-002-S06 / GOV-005-S02
- **Evidence.** `ORC.md` G-ORC-09 "Remaining Python outputs … use ORC-103 'light acceptance' … No Snowpipe, no receipt poller"; `INS.md` INS-001-S08 "Publish observation/evidence/evaluation batches via the ING-005 batch-commit contract"; `GOV.md` GOV-002-S06 "writing via the Python output contract (immutable batch → accepted)".
- **Ruling.** ORC-103's writer is the only landing path for forecasts, anomaly candidates and insight observations (C-17).
- **Hours.** INS-001 40–60 → 36–54. **Edges.** GOV-002, GOV-005, INS-001 +ORC-103.

### U-19 · Quality gates and check results: OPS-002 / DBT-005 / ORC-005-S03
- **Evidence.** Two result stores: `OPS.md` OPS-002-S02 "`ops.quality_results` (PK tenant, dataset, partition_key, candidate_revision_id, check_id, check_version)" and `DBT.md` DBT-005-S01 "`QUALITY.CHECK_RESULT(build_id, tenant_id, check_id, check_version, dataset_id, partition_start, status …)`". Two eligibility functions: OPS-002-S08 "`eligible(tenant, candidate)`" and ORC-005-S03 "per-tenant gate: all required checks have PASS rows (absence = FAIL)".
- **Ruling.** One store, `QUALITY.CHECK_RESULT` in Snowflake (DBT-005), keyed by candidate revision (add `candidate_revision_id`); ORC-005-S03 is the only eligibility evaluator; OPS-002 owns the gate catalogue (T/X/F/S families), the gate-specific checks, fixtures and dashboards, reusing DBT-005's conservation macro for F03.
- **Hours.** OPS-002 38–58 → 31–47.

### U-20 · Money, rounding and decimal codegen: FIN-106 / ALC-008-S03 / FND-103 / INS-001-S04
- **Evidence.** `FIN.md` FIN-106-S03 "`round_statement_lines` (signed largest remainder) in Python and as a dbt macro, with a property test"; `ALC.md` ALC-008-S03 "Build the shared rounding library and SQL macro parity"; ESLint money rule in both FND-103-S03 and FIN-106-S05; money grammar in both FND-103-S02 and FIN-106-S04 (C-14).
- **Ruling.** FIN-106 owns the money context, rounding, `allocate_exact` contract and JSON money grammar; ALC-008 uses them (its mixed-sign fixtures move into FIN-106's property test). FND-103 owns codegen and the single lint rule and imports FIN-106's `money.schema.json`.
- **Hours.** ALC-008 43–61 → 39–55; FIN-106 16–24 → 15–23. **Edges.** FND-103 +FIN-106.

### U-21 · Cursor and token library: API-003-S05 / SEC-006-S06
- **Evidence.** `API.md` API-003-S05 "sealed-token library (AES-256-GCM, kid ring, purpose AAD)"; `SEC.md` SEC-006-S06 "Signed cursors: HMAC-SHA256 … `exp≤15 min` … `packages/cursors/`".
- **Ruling.** One library, API-003's sealed tokens (C-07). SEC-006 keeps the binding rules and the revocation tests.
- **Hours.** SEC-006 44–68 → 41–64.

### U-22 · Integration Health, connection detail and Bridge-overhead panels: CON-006-S12 / UX-103 / ING-012-S08 / CON-101-S06
- **Evidence.** `CON.md` CON-006-S12 "Build the connection detail page (`/integrations/connection-detail`)"; `UX.md` UX-103-S04 "Connection detail: accounts, sources, schedules, pause/resume/revoke" (UX §2 assumed CON-006 covered "the connection wizard only"). Overhead credits three times: CON-101-S06 "→ Data Health 'Bridge overhead' panel", ING-012-S08 "Build the Bridge overhead panel", UX-103-S03 "Customer footprint panel: BRIDGE_FINOPS_WH credits month-to-date".
- **Ruling.** CON-006 owns the connection detail page; ING-012 renders the overhead panel from CON-101-S06's computation; UX-103 keeps the Integration Health summary, egress-IP and network-policy status and links to the other two.
- **Hours.** UX-103 20–28 → 12–17.

### U-23 · OU.ACCOUNTS source contract: CON-004-S03 / ING-103
- **Evidence.** `CON.md` CON-004-S03 "Write the `OU.ACCOUNTS` contract"; `ING.md` §3.1 row "OU.ACCOUNTS … SNAPSHOT … Feeds CON-004", activated by ING-103.
- **Ruling.** CON-004 authors the contract in the ING-001 registry format (it needs it first; making CON-004 wait for ING-103 would create a cycle through CON-005); ING-103 only activates it for the org cycle.
- **Hours.** ING-103 −1 h (net +2 h with C-10).

### U-24 · Egress IP publication: INF-002-S03 / CON-102-S01, S02 / REL-104-S02
- **Evidence.** `INF.md` INF-002-S03 "NAT per AZ … EIPs `prevent_destroy` … generate `<env>.egress.json` and SSM … document ≥30-day dual-publication change rule"; `CON.md` CON-102-S01 "Publish them via `GET /v1/platform/egress-ips`", S02 "publish ≥ 90 days ahead"; `REL.md` REL-104-S02 "allocate NAT Elastic IPs once (D-09) and publish them".
- **Ruling.** INF-002 allocates the EIPs (production ones in the same module, applied by REL-104); CON-102 owns the customer-facing API and change procedure. Notice period: C-13. No hour change (REL-104 −2 h is for cost guards, U-06).

### U-25 · Name collisions that are not duplicates
- "Processing ledger": ORC-101's `BATCH_PROCESSING` (D-06 accepted-batch ledger) vs OPS-109's `ops.processing_ledger` (cost driver) → the name belongs to ORC-101; OPS uses ORC-104's per-tenant build rows.
- "Invoice references": FIN-101 ingests Snowflake's statements/invoices to reconcile the customer's ledger (`finance.billing_references`); LCH-001 records Bridge's own invoices to its customer (`commercial.invoice_refs`). Different subjects; keep separate schemas and never join them.
- "Tenant zero": RELEASE_PLAN §4 connects Bridge's own DEV/STAGING accounts; U-03 makes the INF-101 estate organization the tenant-zero organization (it has ORGANIZATION_USAGE and a real statement).
- "Launcher": the Dagster run launcher (ORC-001) and the extraction launcher (ING-106) are different components; only the latter may pass connection roles.

## 2. Contradictions between domain backlogs

### C-01 · D-11 query-level retention: what survives after 90 days
- **Evidence.** `ING.md` ING-010-S04 "QUERY_TEXT not projected for windows older than the hot horizon (D-11) … The generated SQL for a day 200 days old lacks QUERY_TEXT". `WRK.md` G-WRK-15 "the extraction SQL projects only the trailing comment, computed in the customer warehouse … as `QUERY_TEXT_TAIL_COMMENT`". `API.md` G-API-04 wants t-digest/HLL states per family-day; `WRK.md` G-WRK-08 "Retain execution-level facts for 400 days"; `INS.md` G-INS-14 "extend the D-11 aggregate with attributed credits, spill counts/bytes and a dominant identity tuple". `ALC.md` ALC-003-S03 simulation "window ≤ 92 d".
- **Ruling (D-11 refinements).** (1) ING-001-S04's tier-aware query builder gets three tiers: HOT (sanitized text, ≤ 90 d), COLD (`QUERY_TEXT_TAIL_COMMENT` only, regex computed in the customer warehouse, truncated to 4,096 chars, parsed by WRK-101 and never persisted as text) and NONE. ING-010-S04's oracle becomes "day 200 lacks QUERY_TEXT and projects QUERY_TEXT_TAIL_COMMENT". The customer-credit cost of the regex is measured in ING-101 and added to CON-101's disclosed estimate (D-08). (2) One aggregate `fct_query_family_daily` (U-17) with columns = WRK-104's list ∪ API's sketches (`elapsed_tdigest`, `execution_tdigest`, `users_hll`, `hashes_hll`) ∪ INS's measures (`executions_success`, `executions_attributed`, `attributed_credits` incl. QAS, `spill_remote_exec_count`, `spill_remote_bytes`, dominant identity tuple counts) ∪ `credits_used_cloud_services` (D-15 driver). (3) Execution-level facts (dbt invocations/model runs, PBI activities, task-graph runs, DT refreshes) are 400-day facts in WRK-104. (4) ALC-003's simulation window is ≤ `hot_days` (90 by default), not 92.

### C-02 · Journal and RAW retention: 90 days everywhere vs 400 days for financial sources
- **Evidence.** `OPS.md` retention matrix "S3 `landing/` journal + manifests | 90 d" and "Snowflake RAW | 90 d from acceptance"; `INF.md` INF-003-S03 "current expiry per ADR-011 journal retention (90 d default)"; vs `ING.md` ING-005-S04 "FINANCIAL moves to Glacier IR at 30 d and expires at 400 d" and `DBT.md` G-DBT-05 "financial/metering/billing sources … RAW 400 days". Time Travel: OPS-005-S05 "(RAW 1, canonical 7)" vs ORC-105-S07 "Set revision tables Time Travel 1 day".
- **Ruling (D-26).** Retention is per registry `retention_class`: FINANCIAL 400 d (journal and RAW), QUERY_GRAIN 90 d. ING-005-S04 generates the lifecycle rules from the registry, INF-003 applies them, OPS-005 enforces RAW deletion per class and verifies. Revisioned fact tables keep Time Travel 1 day (rollback uses retained superseded revisions ≥ 7 days, recovery uses OPS-007 snapshots); OPS-005-S05 must not set 7 days on them. OPS-007's statement that the journal horizon "expires ~60–90 days after first backfill" applies to QUERY_GRAIN sources only.

### C-03 · Freshness and cadence: 15-minute catalog, hourly D-08, 30-minute FRESH-1, two cycle formulas
- **Evidence.** `CON.md` G-CON-01 "At the catalog's 15-minute QH cadence, 96 resumes/day"; `ORC.md` G-ORC-02 "stagger each account's cycle minute by `hash(account_id) mod 60`"; D-08 "hourly batched default cadence"; `OPS.md` G-OPS-02 "FRESH-1 … p95 ≤ 30 min; requires dbt trigger ≤ 15 min"; `ORC.md` ORC-101-S13 "oldest unprocessed ≥ 10 min or ≥ 500 batches"; `ORC.md` ORC-003-S02 "`hash(account_id) mod 60 = minute`" vs `ING.md` ING-106-S08 "cycle minute = `5 + (hash(connection_id) mod 50)`".
- **Ruling.** Extraction is one account-cycle per hour per connection (D-08); the 15-minute catalog cadence is superseded. The cycle minute is `5 + (hash(connection_id) mod 50)` (keyed by connection because the role is per connection; minutes 0–4 and 55–59 stay free), implemented once in ORC-003-S02. FRESH-1 (manifest commit → publication, p95 ≤ 30 min) is the SLO; the build trigger is ORC-101-S13's (≤ 10 min wait). Product copy says query data is typically 1–2 h behind the source. The 15- vs 30-minute build cadence question (ORC Q5, OPS Q6) remains an owner cost question; the trigger-based build answers it for R1 volumes.

### C-04 · Who launches extractor tasks
- **Evidence.** D-07 "a dedicated extraction launcher (not Dagster) resolves `connection_id → role` from PostgreSQL and starts the extractor task; Dagster only enqueues". `ORC.md` G-ORC-01 "one Dagster run = one ECS task per **account-cycle**" and G-ORC-03(a) "`BridgeEcsRunLauncher` subclass … derives `taskRoleArn` … from PostgreSQL"; ORC-001-S04 "daemon role … `iam:PassRole` on `bridge-ext-*`", ORC-001-S05 "`BridgeEcsRunLauncher(EcsRunLauncher)` … inject" the connection role into a Dagster run; ORC-002-S03 "op … calls `extractor.run_cycle(plan)`" (Dagster code under the connection role). `ING.md` ING-106-S03 "a generic op … calls the launcher → `RunTask` … polls ECS until STOPPED" (one Dagster run per cycle, idle while the extractor runs, up to the 45-min STEADY deadline of ING-106-S06).
- **Ruling.** Only the ING-106 launcher holds `iam:PassRole` on connection roles. ORC-003's admission marks cycles (STEADY, BACKFILL_CHUNK, ANTI_ENTROPY, PROBE, ORG) ADMITTED in PostgreSQL; the launcher claims them and calls `RunTask`; an ECS task-state event completes the cycle; a Dagster sensor turns sync outcomes into asset observations. **No Dagster run per account-cycle**: in ORC-001's variant Dagster code runs under the customer's role and the daemon must be able to pass every connection role (G-ORC-03); in ING-106-S03's variant each of the 12,000 daily cycles at the benchmark also holds an idle Dagster run-worker task for up to the 45-minute STEADY deadline. ORC-001-S04's PassRole on `bridge-ext-*` and S05–S07 are removed; extractor tasks carry no Dagster or database credentials (D-07).

### C-05 · Where non-interactive jobs run (D-33)
- **Evidence.** D-33 "A dedicated analysis-worker ECS service claims jobs from PostgreSQL … executes through the query broker". `ORC.md` §3 configures Dagster run-tag limits "lane … report 4"; `RPT.md` RPT-002-S13 "consuming the ORC-003 `report` queue … Dagster/planner only enqueue". `ALC.md` ALC-003-S02 "create an API-004 job and outbox event", S03 "Add the dbt `allocation_sim` selector … writing baseline and candidate into `SIMULATION.*`".
- **Ruling.** Interactive analysis, exports and report snapshot/render jobs run in long-lived workers (analysis-worker, render worker) that read only through the broker; there is no Dagster `report` run lane (remove it from ORC-001-S01/ORC-003-S06). An allocation simulation is a **transform** (a dbt build under the transform identity), which the broker cannot execute: it runs as a Dagster dbt job with the `allocation_sim` selector in the dbt lane (concurrency 1 per tenant), while an API-004 job record gives the user status and cancellation. Edge ALC-003 +ORC-004.

### C-06 · Workload classification engine (D-34)
- **Evidence.** PRD §54 lists `PY_WORKLOAD_CLASSIFICATION` as a Python output; `DBT.md` DBT-003-S06 classifies in SQL; `WRK.md` G-WRK-07 "Classification runs as set-based dbt SQL … The pure Python `classify()` is kept as the reference oracle"; `ORC.md` G-ORC-09 agrees.
- **Ruling.** D-34 as written; WRK-001 is the single implementation (U-16). `PY_WORKLOAD_CLASSIFICATION` is replaced by `fct_query_workload` (revisioned, D-05). The PRD reference needs an erratum.

### C-07 · Cursor format, TTL and publication pins
- **Evidence.** `SEC.md` SEC-006-S06 "HMAC-SHA256 … payload `{t,s,m_epoch,p,q_hash,pub,sort,exp≤15 min}` … stale → 409 `CURSOR_STALE`"; `API.md` G-API-07 "Sealed tokens … AES-256-GCM … exp=iat+3600", "epoch/profile changed → 409 `SCOPE_CHANGED`"; `ORC.md` ORC-105-S03 GC grace "max(cursor TTL + 15 min, 7 d rollback window)".
- **Ruling.** Cursors are API-003's sealed (encrypted) tokens, because a signed-only cursor leaks sort-key values into access logs (G-API-07). TTL 1 h; every page re-checks membership epoch and profile hash, so revocation does not depend on TTL (SEC's goal is met). Error code `SCOPE_CHANGED` (409); SEC's ATK-04 test expects it. Cursors create no pins; ORC-105 reads the TTL from one configuration key `cursor_ttl_seconds` owned by API-003, so the grace window cannot drift from the TTL.

### C-08 · Subscription state machine
- **Evidence.** `CTL.md` CTL-007-S07 "`subscriptions` (launch.md states)", S08 "Subscription state machine with guards"; `LCH.md` §1 "The subscription state names differ between CTL-007 and launch.md", LCH-001-S02 "migrate CTL-007's enum (ACTIVE → ACTIVE_PENDING_PAYMENT/ACTIVE_PAID)".
- **Ruling.** LCH-001's canonical machine (TRIAL → ACTIVE_PENDING_PAYMENT → ACTIVE_PAID; PAST_DUE, SUSPENDED, CANCELLED; `LCH.md` G-LCH-03) with its effect matrix is the only one; CTL-007 creates no subscription table (U-08). `CONTRACT_FIRST_ARTIFACTS.md` row "Tenant and subscription state machines | CTL-102-S01, CTL-007-S07" must read "CTL-102-S01 (tenant), LCH-001-S02 (subscription)".

### C-09 · Identity used to evaluate monitors, budgets and forecasts
- **Evidence.** `GOV.md` G-GOV-05 "Each monitor, budget and forecast runs as its owner's current normalized profile role", GOV-004-S02 "run as the profile role", GOV-002-S06 "Build the Dagster asset `forecast_budgets`: one series query per (tenant, profile role)"; D-22 "the only component allowed to assume tenant serving identities" is the broker.
- **Ruling.** GOV's security intent stands, but no GOV process holds serving credentials: evaluators submit server-signed batch plans keyed (tenant, profile role, dataset, window, input publication) to the broker's JOB class (API-002), which assumes the tenant user and sets the profile role. Forecast series are read the same way; the Python engine writes results through ORC-103 under the central writer identity. The same rule covers report snapshots (RPT-002-S02, already via the broker). Edges: GOV-001/GOV-003 +API-002 (GOV) are sufficient; GOV-002 +ORC-103, GOV-005 +ORC-103.

### C-10 · Source projections requested by INS/ALC/WRK versus what ING activates
- **Evidence.** D-15 "`CREDITS_USED_CLOUD_SERVICES` (and database/schema) … ING-001 adds them" — but ING-001 is the registry framework and `ING.md` never lists these columns for QUERY_HISTORY (the string occurs only in the WMH row). `INS.md` G-INS-01 requires 16 QH columns (hash versions, spill, partitions, compilation/queue times, cluster, warehouse type, cloud-services credits, rows, error code); `ALC.md` G-ALC-11 requires DATABASE_ID/NAME, SCHEMA_ID/NAME, CREDITS_USED_CLOUD_SERVICES, SESSIONS `CLIENT_APPLICATION_ID` and a TAG_REFERENCES snapshot; `WRK.md` §3 requires QAH `PARENT_QUERY_ID`/`ROOT_QUERY_ID`, QH queue/compile times, SESSIONS, TASK_HISTORY and DYNAMIC_TABLE_REFRESH_HISTORY. `ING.md` §3.1 puts "TASK_HISTORY, DYNAMIC_TABLE_REFRESH_HISTORY" in the **R2** families (ING-105) although WRK-004 (R1) needs them.
- **Ruling.** The union is frozen in **ING-101** before the first 365-day backfill (fields not extracted then are lost for history): QH = catalog projection + the 16 INS columns + DATABASE_ID/NAME, SCHEMA_ID/NAME + the COLD-tier tail comment (C-01); QAH + PARENT_QUERY_ID, ROOT_QUERY_ID; a new **AU.SESSIONS** contract (SESSION_ID, CREATED_ON, pseudonymized USER_NAME, CLIENT_APPLICATION_ID/VERSION, CLIENT_ENVIRONMENT:APPLICATION). **ING-103** adds AU.TAG_REFERENCES (daily snapshot, Enterprise-gated). **ING-104** activates TASK_HISTORY and DYNAMIC_TABLE_REFRESH_HISTORY in R1 (moved from ING-105). CON-003's view → database-role map and CON-005's probes cover SESSIONS and TAG_REFERENCES (roles TO VERIFY LIVE). D-15's text must say ING-101.
- **Hours.** ING-101 +4 h (28–40 → 32–46), ING-103 +3 h (−1 h U-23), ING-104 +10/+15 h (20–30 → 30–45), ING-105 −10/−15 h. **Edges.** ING-101 +WRK-101; INS-003 +ING-101; WRK-004 +ING-104; ALC-001 +ING-103.

### C-11 · Runtime IAM role names, paths and quota thresholds
- **Evidence.** `CON.md` CON-001-S04 "`bridge-conn-<env>-<uuid32>` (no path)", CON-001-S10 "alarm at 0.70 (page) and at 0.90 (admission blocked)"; `INF.md` INF-103-S01 "`bridge-<env>-conn-<connection_uuid>`, `bridge-<env>-srv-<tenant_uuid>`, no IAM path", INF-103-S07 "refuse … admission at ≥80%, alarm at 70%"; `SEC.md` SEC-105-S02 "only under path `/bridge/tenant-serving/`", SEC-105-S08 "≥80 % → block"; `ORC.md` ORC-001-S04 "`bridge-ext-*`"; `ING.md` ING-106-S02 maps "`assumed-role/bridge-conn-<env>-<uuid32>/*`".
- **Ruling.** Names `bridge-<env>-conn-<uuid32>` and `bridge-<env>-srv-<uuid32>` (32 lowercase hex, never reused), **no IAM path** (assumed-role ARNs drop the path; Snowflake's matching with paths is TO VERIFY LIVE, `CON.md` G-CON-04). Alarm at 70 %, admission blocked at 80 % of the IAM role quota, one metric `iam_roles_used_ratio` owned by INF-103. ING-106's sync-api mapping, INF-005-S08's PassRole pattern and every policy use these patterns; `bridge-ext-*` disappears.

### C-12 · Presigned download lifetime
- **Evidence.** `SEC.md` SEC-006-S08 "presigned URL TTL 30 s"; `API.md` tokens spec "export link 30 s redirect"; `RPT.md` RPT-005-S04 "Presign mode per G-RPT-07 (60 s …, signer credentials ≥ 15 min remaining)".
- **Ruling.** 30 s everywhere (single broker, U-10), keeping RPT's requirement that the signer's credentials have ≥ 15 min remaining.

### C-13 · Egress IP change notice
- **Evidence.** `INF.md` INF-002-S03 "document ≥30-day dual-publication change rule"; `CON.md` CON-102-S02 "publish ≥ 90 days ahead; both sets are valid during overlap".
- **Ruling.** 90 days: customer network-policy changes go through enterprise change windows; INF-002's runbook adopts CON-102's rule.

### C-14 · Money scale and JSON grammar
- **Evidence.** `FND.md` FND-103-S02 "money … pattern `^-?\d{1,20}(\.\d{1,9})?$`"; `OPS.md` OPS-002-S05 "exact DECIMAL(38,9) sums"; `FIN.md` §3.6 "Internal scale: NUMBER(38,12)" and "JSON money = string matching `^-?(0|[1-9][0-9]{0,25})(\.[0-9]{1,12})?$`"; `DBT.md` DBT-001-S07 "`money(col)` → NUMBER(38,12)".
- **Ruling.** FIN §3.6 governs: NUMBER(38,12) internally, FIN's JSON grammar in APIs; FND-103's Spectral rule and OPS-002's gates use it. A 9-digit pattern would reject valid attribution amounts.

### C-15 · Support access duration and scopes
- **Evidence.** `SEC.md` SEC-104-S01 "`expires_at ≤ starts_at+8 h`", read-only capability set; `OPS.md` OPS-106-S06 "scope `health_read`, `analytics_read`, `config_write`; … default 4 h, max 24 h".
- **Ruling.** Default 4 h, maximum 8 h (D-25: least privilege, reviewable sessions); scopes `health_read` and `analytics_read` in R1; `config_write` is not a support scope in R1 (configuration changes go through the tenant's own users or a break-glass procedure).

### C-16 · Migration lock timeout
- **Evidence.** `CTL.md` CTL-101-S01 "`lock_timeout=3s` with 5 retries"; `REL.md` REL-101-S03 "`lock_timeout=5s`".
- **Ruling.** CTL-101's value (3 s × 5 retries); REL-101's runner step is removed (U-14).

### C-17 · Transport for Python outputs
- **Evidence.** `INS.md` INS-001-S08 "via the ING-005 batch-commit contract"; `ORC.md` G-ORC-09 "Arrow→Parquet→`PUT` to a named internal stage … `COPY INTO … FILES=(…)` … No Snowpipe, no receipt poller".
- **Ruling.** ORC-103 (U-18). The customer journal and its manifests are reserved for customer-sourced data.

### C-18 · dbt CI schema naming, janitor TTL and runner
- **Evidence.** `FND.md` FND-101-S05 "`CI_PR_<n>_<sha7>`", S07 "janitor drops `CI_PR_%` older than 48 h" on an "in-VPC DEV runner"; `DBT.md` DBT-102-S01 "`CI_PR<nr>_<sha7>_<layer>`", S06 "older than 24 h", S02 "GitHub OIDC → AWS → Snowflake WIF CI user; CI role owns only `BRIDGE_CI`".
- **Ruling.** DBT-102's naming and 24 h TTL; database `BRIDGE_CI` in the DEV account; jobs run on the INF-002-S09 in-VPC runner with the WIF CI identity (U-15).

### C-19 · Where deletion tombstones live
- **Evidence.** `SEC.md` Appendix G "`privacy.identity_tombstones`" in PostgreSQL; `OPS.md` G-OPS-07 "deletion tombstones live inside the very stores a restore rolls back", OPS-104 S3 mirror; `CTL.md` CTL-102-S06 "`platform.tenant_tombstones`".
- **Ruling.** OPS-104 only (U-11). A tombstone inside PostgreSQL alone is rolled back by PITR and would resurrect an erased name — the D-10 failure mode.

### C-20 · Privacy request API
- **Evidence.** `SEC.md` SEC-103-S09 "`POST /v1/privacy/erasure-requests` → approval (SEC-102)"; `OPS.md` OPS-005-S17 "`POST /v1/privacy/requests` (preview returns per-store counts)".
- **Ruling.** `/v1/privacy/requests` (typed: SUBJECT_ACCESS, SUBJECT_ERASURE, TENANT_DELETION) owned by OPS-005, approval through SEC-102; UX-102-S05 binds to it.

### C-21 · Schema-breaking changes in serving
- **Evidence.** `REL.md` REL-103-S02 "Generate serving views per version namespace in dbt; keep V<n−1> until all pointers moved" (R1); `DBT.md` DBT-104-S02 "union serving view template mapping v1/v2 columns" (R2).
- **Ruling.** REL-103's version namespaces are the R1 serving contract (the broker selects the namespace from the tenant publication's `serving_schema_version`). DBT-104 (R2) handles storage-level versions of fact tables underneath those views; its union view is internal, never a serving namespace.

### C-22 · Release-tag violations
- **Evidence.** Original OPS-004 depends on API-006, which `API.md` tags "Release: R2"; `INS.md` INS-002 "Keep `FIN-004` (Adaptive flag)" while FIN-004 is "R1\* (D-20)"; FIN-004 dropped its FIN-003 edge and would otherwise lose the billing-normalizer ordering.
- **Ruling.** OPS-004 −API-006 (the public-API attack cases run in API-006 when it is enabled; if API-006 becomes R1\*, OPS-004 regains the edge). INS-002 −FIN-004 (WH detectors read the Adaptive capability flag from CON-005). FIN-004 +FIN-002. The validator reports 0 R1→R2 and 0 R1→R1\* edges.

### C-23 · Quality-check results and publication eligibility
- **Evidence and ruling.** See U-19: the PKs disagree (`candidate_revision_id` vs `build_id`); one store keyed by candidate revision, one evaluator (ORC-005-S03).

### C-24 · Non-production Snowflake budget (D-32)
- **Evidence.** D-32 "≈ 100–150 credits/month" for the test estate; `OPS.md` OPS-103 estimate "(+ ≈ 100 credits/month, ASSUMPTION)" for a second synthetic organization; `INF.md` INF-101-S09 "total 150"; INF-105-S08 "monthly non-prod credit budget 500"; FND-101-S03 "20-credit monthly resource monitor" per developer.
- **Ruling.** One estate (U-03) capped at 150 credits/month (INF-101-S09) including canaries and tenant zero, not 150 + 100. The owner should approve the overall non-production ceiling of INF-105-S08 (500 credits/month: estate + central DEV/STAGING builds + dbt CI + developer sandboxes) plus the one-off benchmarks (DBT-101 ≤ 200, OPS-105 ≤ 100, OPS-008 ≤ 300 credits).

### C-25 · Dependency direction and cycles between backlogs
- **Evidence.** `CON.md` CON-003 "`+OPS-103` (synthetic accounts)" while `OPS.md` OPS-103 "deps INF-008, CON-003" (a two-task cycle). `ING.md` ING-106 "New edge `ORC-003 +ING-106`" while the cycle table and admission live in ORC-003 (U-12).
- **Ruling.** CON-003 depends on INF-101, not OPS-103; OPS-103 depends on CON-003 and INF-101. ING-106 depends on ORC-003 (table and admission contract first; the launcher consumes admitted cycles), not the reverse.

### C-26 · FIN-104's coverage dependency
- **Evidence.** `FIN.md` FIN-104 "Dependencies: `FIN-001`, `ING-001`, `ING-009` (contiguous coverage)"; ING-009 is "Handle schema drift and source BCR changes"; `ING.md` ING-012 "+ING-008 (coverage)"; FIN-104 "Plugs in: … before FIN-002/102/003/009/010".
- **Ruling.** FIN-104 depends on ING-008; FIN-002 +FIN-104 (as FIN-104 states). ING-009 becomes a release prerequisite through OPS-011 (C-29).

### C-27 · Batch-manifest read API for Explain has no owner
- **Evidence.** `API.md` API-005 "Add `+ING` batch-manifest read API (the owner is the ING backlog)"; the API list in `ING.md` §3 has none.
- **Ruling.** ING-012-S03 adds `GET /v1/data-health/batches/{batch_id}` (manifest summary, file set, acceptance evidence; scope-checked), +2 h (42–61 → 44–64). Edge API-005 +ING-012.

### C-28 · AUDIT X-10 text versus the D-02 refinement
- **Evidence.** `AUDIT_CROSS_CUTTING.md` X-10: "row access policies check `CURRENT_USER()` → tenant and `CURRENT_ROLE()`/`IS_ROLE_IN_SESSION()` → profile entitlements; pools keyed by (tenant user, profile role, permission epoch)". D-02 refinement: "Row access policies test `CURRENT_ROLE()` only — not `IS_ROLE_IN_SESSION()`" and "the permission epoch belongs in cursors, jobs, cache keys and download links, not in pool keys".
- **Ruling.** D-02 governs; X-10's resolution paragraph should be corrected so no implementer copies `IS_ROLE_IN_SESSION()`.

### C-29 · R1 work orphaned by backlog edge removals (graph hygiene)
- **Evidence.** After applying every backlog's "Dependency changes" literally, 15 R1 tasks were no longer a prerequisite of any release step, including the Home page and Cost Explorer (UX-005/006 −UX-004, UX-004 −UX-003), the R1 report templates (RPT-004 −RPT-003), the showback portal (ALC-008 −ALC-007), forecasting and anomaly detection (GOV-004 −GOV-002, INS-001 −GOV-005), schema-drift handling (FIN-104 → ING-008), CI gates (INF-001 −FND-006), WRK-005/WRK-102, FND-101/102, OPS-108 and ORC-102. Each backlog's own reasoning was sound; the union silently dropped their qualification.
- **Ruling.** Re-attach them to the step that qualifies them: UX-008 (+UX-003, UX-004, WRK-005, WRK-102, ALC-007, INS-101 — it tests "all R1 routes"), ONB-005 (+RPT-003, UX-004 — its S05 compares a report with the Explorer), GOV-008 (+GOV-002, GOV-005), REL-001 (+FND-006), REL-003 (+OPS-108), OPS-008 (+ORC-102), OPS-011 (+ING-009, INS-105), DBT-001 (+FND-101), CON-005 and ING-003 (+FND-102), all as the FND/INS backlogs describe. Two over-serializations were removed: REL-001 −OPS-011 / REL-004 +OPS-011 (rehearsing the promotion pipeline does not wait for product QA; the release-candidate gate does), and UX-102 −OPS-005 (only its privacy page, S05, needs the OPS-005 API; feature-flagged). Result: every R1 task except LCH-004 (post-launch) is a prerequisite of LCH-002.

### C-30 · Release tags that disagree with RELEASE_PLAN
- **Evidence.** `RELEASE_PLAN.md` puts "005 AI/SPCS detectors" in R1\*; `INS.md` tags INS-005 "R2 (AI01/AI04 → R1 only if D-20 reports Cortex spend)".
- **Ruling.** The domain backlog's finer tag wins: INS-005 is R2 with a `release_note` that AI01/AI04 become R1\* on a D-20 trigger. RELEASE_PLAN §2 should follow the JSON.

## 3. Consolidated edge changes

One row per task whose dependencies differ from the original index (original tasks) or which is new (all its dependencies are listed as additions). "Source" names the backlog that requested the change; `RECONCILIATION` marks integration rulings, tagged with their ruling ID. Step-level, contract-only and soft dependencies are not edges (see §0). The resulting dependency lists are in [revised-task-graph.json](revised-task-graph.json).

| Task | Remove deps | Add deps | Source file(s) | Ruling notes |
|---|---|---|---|---|
| FND-004 | FND-003 | FND-002 | FND.md | fixtures need pinned pyarrow, not Compose |
| FND-005 | FND-004 | FND-002 | FND.md | dispatcher tests use synthetic manifests |
| FND-006 | — | FND-002 | FND.md | deps = FND-002, FND-005 |
| UX-001 | — | FND-002 | UX.md | pinned UI stack |
| INF-001 | FND-006 | FND-001 | FND.md, INF.md | bootstrap needs repo layout only |
| INF-002 | — | INF-102 | INF.md | applied through Terraform pipeline |
| INF-003 | INF-002 | INF-001, INF-102 | INF.md | S3/SQS/KMS need no VPC; S08 step-level on INF-002 |
| INF-004 | — | INF-102 | INF.md | — |
| INF-005 | INF-004 | INF-002, INF-102 | INF.md | cluster/ECR/roles need no DB |
| INF-006 | INF-005 | INF-002, INF-003, INF-102 | INF.md | S13 step-level on INF-005 |
| INF-007 | INF-006 | INF-102 | INF.md | deploy does not need edge |
| INF-008 | INF-007 | INF-001, INF-002, INF-003, INF-102 | INF.md | Snowflake IaC does not need container pipeline |
| SEC-001 | INF-002 | — | SEC.md | uses network design, not deployed VPC |
| SEC-002 | INF-006 | SEC-004, CTL-101 | SEC.md | INF-006 gates only S17 staging evidence |
| SEC-003 | — | SEC-102, CTL-003 | SEC.md | — |
| SEC-004 | SEC-002 | CTL-101, SEC-101 | SEC.md | RBAC/RLS does not need Cognito |
| CTL-001 | — | CTL-101 | CTL.md | — |
| CTL-002 | — | CTL-101 | CTL.md | — |
| SEC-005 | — | SEC-101, INF-104 | SEC.md, INF.md | policy bodies applied by Snowflake migration runner |
| SEC-006 | — | SEC-002, CTL-101, SEC-105 | SEC.md | — |
| SEC-007 | — | WRK-101 | WRK.md | metadata extraction is step (1) of sanitize(); RECON confirms |
| SEC-008 | — | CTL-101, INF-003 | SEC.md | — |
| CTL-003 | SEC-008 | CTL-101, SEC-004 | CTL.md | audit write-path in CTL-101 |
| CTL-004 | CTL-003 | CTL-101, OPS-001 | CTL.md, OPS.md | outbox carries traceparent from day one |
| CTL-005 | — | INF-008, SEC-103, SEC-102, INF-104 | CTL.md, INF.md | CONFIG version tables created by INF-104-S05 |
| CTL-006 | CTL-004 | CTL-101, SEC-101 | CTL.md | — |
| CTL-007 | CTL-005 | API-001 | CTL.md | API-001 registry contract for spec validation; CTL-102 edge dropped by RECON with commercial scope |
| CON-001 | INF-008 | INF-005, INF-003, INF-103 | CON.md, INF.md | roles created by runtime provisioner |
| CON-002 | — | INF-008, INF-002, INF-101 [U-03] | CON.md, INF.md, RECONCILIATION | CON asked +OPS-103; RECON: synthetic accounts are the INF-101 estate (U-03) |
| CON-003 | — | ING-001, CON-101, CON-102, INF-101 [U-03, C-25] | CON.md, RECONCILIATION | CON asked +OPS-103, which itself depends on CON-003 (cycle); estate is INF-101 (C-25, U-03) |
| CON-005 | — | ING-001, CON-101, INF-101 [U-03], FND-102 | CON.md, RECONCILIATION, FND.md | replaces +OPS-103 (U-03); FND-102 recorded fixtures "consumed by ING-001, ING-003, CON-005" (ING-001 kept free of the estate dependency) |
| CON-006 | — | CON-101, CON-102, LCH-101 [U-08] | CON.md, RECONCILIATION | connection-count quota enforced at admission (entitlement engine from LCH-101) (U-08) |
| ING-001 | CON-005 | — | ING.md | inverted: CON-005 depends on ING-001 |
| ING-003 | ING-002 | ING-001, OPS-001, FND-102 | ING.md, OPS.md, FND.md | telemetry library before first worker |
| ING-004 | ING-003 | ING-001 | ING.md | — |
| ING-005 | — | CON-001, CTL-004 | ING.md | — |
| ING-006 | ING-005 | ING-004, INF-003, INF-104 | ING.md, INF.md | — |
| ING-007 | — | ING-005, ING-106 | ING.md | — |
| ING-009 | ING-008 | ING-001, ING-006, CON-005 | ING.md | — |
| ING-010 | ING-009, CON-006 | ING-008, ING-106, ORC-003, CON-101, WRK-101, LCH-101 [U-08] | ING.md, WRK.md, RECONCILIATION | removes implicit cycle with CON-006; cold-window QUERY_TEXT_TAIL_COMMENT projection (WRK-101-S12); history_days / backfill admission entitlement (U-08) |
| ING-011 | ING-010 | ING-007, ING-008, ING-006 | ING.md | — |
| ING-012 | ING-011 | ING-008, CON-005, ING-010 | ING.md | — |
| OPS-001 | CTL-004 | FND-003 | OPS.md | — |
| ORC-001 | CTL-002 | INF-004 | ORC.md | — |
| ORC-002 | ING-008 | ING-001 | ORC.md | — |
| ORC-003 | — | ING-002, CON-001 | ORC.md | — |
| ORC-004 | ING-009 | DBT-001, DBT-002, DBT-101, ORC-101 | ORC.md | — |
| ORC-005 | — | DBT-101, ORC-101, SEC-005 | ORC.md | — |
| ORC-006 | — | ORC-105 | ORC.md | — |
| DBT-001 | ORC-004, ING-008 | ING-001, CON-002, INF-008, FND-004, FND-101 | DBT.md, FND.md | inverted edge with ORC-004; FND-101 "blocks DBT-001 (developer use)" |
| DBT-002 | — | ORC-101, DBT-101 | DBT.md | — |
| DBT-003 | CTL-001 | DBT-103 | DBT.md | — |
| DBT-004 | ORC-005 | DBT-101, ORC-101 | DBT.md | ORC-005 needed only for S08–S11 (step-level) |
| DBT-005 | SEC-008 | DBT-102, FND-004, FIN-001 | DBT.md, FIN.md | reversed: DBT-005 consumes FIN-GOLD fixtures |
| DBT-006 | — | ORC-005 | DBT.md | — |
| FIN-001 | DBT-005, ING-001 | FND-004 | FIN.md | — |
| FIN-002 | — | ING-001, FIN-108, DBT-003, FIN-104 [C-26] | FIN.md, RECONCILIATION | FIN-108 crosswalk v1 before DONE; FIN-104 says "before FIN-002" (C-26) |
| FIN-003 | — | FIN-102, FIN-103, FIN-104 | FIN.md | — |
| FIN-004 | FIN-003 | FIN-103, FIN-104, FIN-002 [C-22] | FIN.md, RECONCILIATION | keeps the billing normalizer ordering previously implied via FIN-003 (C-22) |
| FIN-005 | — | FIN-102, FIN-103 | FIN.md | — |
| FIN-006 | — | FIN-102, FIN-103 | FIN.md | — |
| FIN-008 | FIN-006 | FIN-102, FIN-103 | FIN.md | — |
| FIN-011 | — | FIN-103 | FIN.md | — |
| FIN-012 | — | FIN-103 | FIN.md | — |
| FIN-013 | — | FIN-103 | FIN.md | — |
| FIN-014 | — | FIN-103 | FIN.md | — |
| FIN-015 | — | FIN-103 | FIN.md | — |
| FIN-016 | — | FIN-103 | FIN.md | — |
| FIN-017 | — | FIN-103, FIN-003 | FIN.md | — |
| FIN-007 | FIN-012, FIN-017 | FIN-103 | FIN.md | — |
| FIN-018 | — | FIN-103, FIN-108 | FIN.md | — |
| FIN-019 | — | FIN-103 | FIN.md | — |
| FIN-020 | FIN-019 | FIN-103, FIN-108, ING-001 | FIN.md | — |
| FIN-021 | — | FIN-108 | FIN.md | — |
| FIN-009 | FIN-004, FIN-018, FIN-019, FIN-020 | FIN-003, FIN-101, FIN-104, FIN-106 | FIN.md | — |
| FIN-010 | — | FIN-106, FIN-101 | FIN.md | — |
| OPS-002 | — | OPS-101 | OPS.md | — |
| API-001 | FIN-009, DBT-006 | FIN-001, DBT-001, FND-103 | API.md, FND.md | FND-103 blocks API-001 |
| API-002 | — | INF-005, API-101, SEC-101 | API.md | API-101 = live gate |
| API-004 | ORC-006 | INF-005 | API.md | D-33 analysis-worker, no Dagster |
| API-005 | FIN-010 | DBT-006, ING-012 [C-27] | API.md, RECONCILIATION | ALC-005/FIN-010 only for S05 statement resolvers (step-level); batch-manifest read endpoint added to ING-012-S03 (C-27) |
| API-006 | API-005 | — | API.md | — |
| UX-002 | API-003 | SEC-002, API-001, API-104 | UX.md | builds against API-003-S01 OpenAPI + MSW |
| ONB-001 | — | LCH-101, ONB-101 | ONB.md | — |
| UX-003 | FIN-009 | API-101, API-001 | UX.md | FIN-009 via API-101 staging gate |
| UX-004 | UX-003, API-005 | API-001, API-104, API-102 | UX.md | — |
| UX-005 | UX-004, FIN-004 | UX-002, API-104, WRK-104, FIN-003, API-101 | UX.md | — |
| UX-006 | UX-004 | UX-002, API-104 | UX.md | — |
| UX-007 | UX-004 | UX-002, API-104 | UX.md | — |
| UX-008 | UX-007 | UX-102, UX-103, UX-104, WRK-002, WRK-004, GOV-008, UX-003 [C-29], UX-004 [C-29], WRK-005 [C-29], WRK-102 [C-29], ALC-007 [C-29], INS-101 [C-29] | UX.md, GOV.md, RECONCILIATION | UX-007 only if R1*; inverted edge; UX-008 qualifies all R1 routes; UX-005/006 no longer depend on UX-004 (UX backlog), so Home/Explorer/workload/showback/insights pages lost their qualification edge (C-29) |
| WRK-001 | API-001 | WRK-101 | WRK.md | — |
| WRK-002 | UX-005 | UX-002, API-104, WRK-104 | WRK.md | — |
| WRK-003 | UX-005 | UX-002, API-104, WRK-104 | WRK.md | — |
| WRK-004 | UX-005 | UX-002, API-104, WRK-104, ING-104 [C-10] | WRK.md, RECONCILIATION | TASK_HISTORY / DT refresh contracts pulled into R1 ING-104 (C-10) |
| WRK-005 | WRK-003 | — | WRK.md | — |
| ALC-001 | FIN-009 | FIN-001, DBT-003, ING-103 [C-10] | ALC.md, RECONCILIATION | AU.TAG_REFERENCES snapshot contract (G-ALC-11) (C-10) |
| ALC-003 | — | CTL-005, SEC-006, ORC-004 [C-05] | ALC.md, RECONCILIATION | FIN-010 contract-only (step-level); simulation runs the dbt allocation_sim selector as a Dagster dbt job (not the D-33 analysis-worker) (C-05) |
| ALC-005 | FIN-010 | FIN-009, ORC-005 | ALC.md | — |
| ALC-006 | UX-004 | UX-002, ALC-102 | ALC.md | — |
| ALC-007 | — | ALC-101, ALC-102 | ALC.md | — |
| ALC-008 | ALC-007 | ALC-006, ALC-103, RPT-002, FIN-107 | ALC.md, FIN.md | chargeback corrections after FIN-107 |
| GOV-001 | ALC-007 | API-002, CTL-005 | GOV.md | ALC-102 only for S03 team scope (step-level) |
| GOV-002 | WRK-005 | GOV-101, ORC-005, ORC-103 [U-18] | GOV.md, RECONCILIATION | py_forecast landing via ORC-103 writer (U-18) |
| GOV-003 | API-006 | API-002, CTL-005 | GOV.md | — |
| GOV-004 | GOV-002 | GOV-101, CTL-004 | GOV.md | forecast_breach step gated on GOV-002 |
| GOV-005 | — | GOV-101, ORC-103 [U-18] | GOV.md, RECONCILIATION | py_anomaly_candidate landing via ORC-103 writer (U-18) |
| GOV-006 | GOV-004 | GOV-102, CTL-004 | GOV.md | — |
| GOV-007 | — | GOV-004, SEC-006 | GOV.md | — |
| GOV-008 | UX-008 | UX-002, GOV-002 [C-29], GOV-005 [C-29] | GOV.md, RECONCILIATION | governance E2E acceptance covers forecast and anomaly monitors; GOV-004 −GOV-002 and INS-001 −GOV-005 orphaned them (C-29) |
| RPT-001 | — | CTL-003 | RPT.md | — |
| RPT-002 | — | INF-005, CTL-004, API-004, API-002 | RPT.md | — |
| RPT-003 | GOV-008, WRK-005, UX-007 | ALC-007, GOV-001, GOV-004 | RPT.md | — |
| RPT-004 | RPT-003 | RPT-002 | RPT.md | — |
| RPT-005 | — | SEC-006 | RPT.md | — |
| INS-001 | WRK-005, GOV-005 | CTL-004, CTL-005, GOV-101, ORC-103 [U-18, C-17] | INS.md, GOV.md, RECONCILIATION | observations land via ORC-103, not the ING-005 journal (C-17, U-18) |
| INS-002 | UX-005, FIN-004 [C-22] | FIN-003, INS-102 | INS.md, RECONCILIATION | FIN-004 is R1*; Adaptive handled by capability flag (C-22) |
| INS-003 | WRK-002, WRK-004 | FIN-003, ING-101 [C-10], WRK-104 [U-17], GOV-005 [U-09] | INS.md, RECONCILIATION | projection activated in ING-101 (INS asked ING-001, transitive); family×day base model is WRK-104 (C-10, U-17); Q07 calls the GOV-005 anomaly evaluator (INS-003-S07) (U-09) |
| INS-004 | FIN-011, FIN-012 | — | INS.md | — |
| INS-006 | INS-003, INS-004, INS-005 | INS-101 | INS.md | INS-102 soft (not an edge) |
| OPS-003 | GOV-007, RPT-005 | OPS-101, OPS-102, OPS-103, API-003 | OPS.md | — |
| OPS-004 | API-006 [C-22] | OPS-106, SEC-104 [U-05] | OPS.md, RECONCILIATION | API-006 is R2 (R1 must not wait for it); support access (SEC-104) is in the attack surface (C-22, U-05) |
| OPS-005 | — | OPS-104 | OPS.md | — |
| OPS-006 | OPS-005, INF-003, INF-006 | OPS-104, OPS-102 | OPS.md | — |
| OPS-007 | OPS-005 | OPS-104, DBT-006, ORC-105 [U-17] | OPS.md, RECONCILIATION | recovery snapshot pins via ORC-105-S09 (U-17) |
| OPS-008 | — | OPS-105, ORC-102 [C-29] | OPS.md, RECONCILIATION | capacity qualification includes Dagster metadata guardrails (C-29) |
| OPS-009 | — | OPS-109, ALC-104, GOV-103, ORC-104, LCH-001 [U-06], INF-105 [U-06] | OPS.md, ALC.md, GOV.md, ORC.md, RECONCILIATION | revenue refs live in LCH-001 commercial.invoice_refs (OPS asked LCH-101); CUR export owned by INF-105-S05 (U-06) |
| OPS-010 | — | OPS-106, OPS-110, OPS-102 | OPS.md | — |
| ONB-002 | — | ONB-102 | ONB.md | — |
| OPS-011 | — | OPS-107, INS-105 [C-29], ING-009 [C-29] | OPS.md, RECONCILIATION | detector qualification is release evidence (C-29); schema-drift handling is release evidence (FIN-104 now depends on ING-008, not ING-009) (C-29) |
| REL-001 | OPS-011 [C-29] | REL-101, REL-103, FND-006 [C-29] | REL.md, RECONCILIATION | promotion qualification needs the CI gates (FND-006 orphaned by INF-001 −FND-006); it does not need product QA — OPS-011 moves to REL-004 (C-29) |
| REL-002 | — | REL-102, REL-104 | REL.md | — |
| REL-003 | — | LCH-001, LCH-102, LCH-104, OPS-107, OPS-108 [C-29] | REL.md, RECONCILIATION | readiness pack includes the SOC 2-ready control evidence (D-25) (C-29) |
| LCH-001 | REL-003, CTL-007 [U-08] | LCH-101, LCH-103, CTL-102 [U-05] | LCH.md, RECONCILIATION | reversed; commercial tables and state machine owned by LCH; finance operator on the CTL-102 ops plane (U-05, U-08) |
| REL-004 | — | OPS-011 [C-29] | RECONCILIATION | the release-candidate gate consumes the release evidence matrix (C-29) |
| ONB-003 | — | LCH-003, LCH-102 | ONB.md | — |
| ONB-004 | — | ONB-101, ALC-103, FIN-107, FIN-105 | ONB.md, ALC.md, FIN.md | FIN: restatement and approved rates before ONB-004 |
| ONB-005 | INS-007 | INS-006, RPT-003 [C-29], UX-004 [C-29] | ONB.md, RECONCILIATION | ONB-005-S05 generates a report and checks parity with Explorer; RPT-004 no longer depends on RPT-003 (C-29) |
| LCH-003 | LCH-002 | — | LCH.md | go-live before first real tenant |
| LCH-004 | — | ONB-004 | LCH.md | — |
| ALC-101 (new) | — | SEC-005, SEC-006, ALC-004, ALC-005 | ALC.md | — |
| ALC-102 (new) | — | API-001, ALC-005, ALC-101 | ALC.md | — |
| ALC-103 (new) | — | ALC-005 | ALC.md | — |
| ALC-104 (new) | — | ALC-003, ALC-005 | ALC.md | — |
| API-101 (new) | — | API-001, DBT-006, FIN-009, SEC-005 | API.md | WRK-104 tier bindings step-level |
| API-102 (new) | — | API-003, API-004, INF-003 | API.md | PNG/PDF (R2) steps need RPT-002 |
| API-104 (new) | — | API-002, API-003, API-101 | API.md | — |
| CON-101 (new) | — | CON-002 | CON.md | — |
| CON-102 (new) | — | INF-002, CON-002 | CON.md | — |
| CON-103 (new) | — | CON-102, INF-002 | CON.md | — |
| CTL-101 (new) | — | INF-004, FND-003 | CTL.md | — |
| CTL-102 (new) | — | SEC-004, SEC-105, CTL-004, INF-006 [U-05] | CTL.md, RECONCILIATION | ops API/console on the internal ALB (private listener) (U-05) |
| CTL-103 (new) | — | CTL-007, UX-004 | CTL.md | MERGED into UX-101; edges retired (U-01) |
| DBT-101 (new) | — | INF-008, SEC-005 | DBT.md | — |
| DBT-102 (new) | — | DBT-001, FND-004, FND-005, INF-007 | DBT.md | — |
| DBT-103 (new) | — | CTL-005, ORC-101 | DBT.md | — |
| DBT-104 (new) | — | DBT-004 | DBT.md | — |
| FIN-101 (new) | — | FIN-001, CTL-005, SEC-005, SEC-006, INF-003 | FIN.md | "RPT download broker" = SEC-006-S08 (RECON) |
| FIN-102 (new) | — | FIN-001, FIN-002, FIN-104, DBT-004 | FIN.md | — |
| FIN-103 (new) | — | FIN-001, FIN-106, DBT-005 | FIN.md | — |
| FIN-104 (new) | ING-009 [C-26] | FIN-001, ING-001, ING-008 [C-26] | FIN.md, RECONCILIATION | contiguous coverage is ING-008 (ING-009 is schema drift) (C-26) |
| FIN-105 (new) | — | FIN-002, CTL-005, SEC-005 | FIN.md | — |
| FIN-106 (new) | — | FND-002 | FIN.md | — |
| FIN-107 (new) | — | FIN-009, FIN-010 | FIN.md | — |
| FIN-108 (new) | — | CON-005, ING-007, ING-102 [U-03] | FIN.md, RECONCILIATION | FIN-002-S01..S03 step-level; billing/metering source contracts activated first; ING-102 owns source facts, FIN-108 billing semantics (U-03) |
| FIN-109 (new) | — | FIN-002, FIN-106, FIN-105 | FIN.md | — |
| FND-101 (new) | — | FND-002, FND-004, INF-008 | FND.md | — |
| FND-102 (new) | — | FND-005, INF-101, INF-008 | FND.md | — |
| FND-103 (new) | — | FND-001, FND-002, FIN-106 [U-20] | FND.md, RECONCILIATION | money JSON grammar is FIN-106-S04 (38,12); FND-103 Spectral rule imports it (U-20) |
| GOV-101 (new) | — | FND-004 | GOV.md | — |
| GOV-102 (new) | — | INF-002, INF-003, INF-006 | GOV.md | — |
| GOV-103 (new) | — | GOV-004, GOV-007 | GOV.md | — |
| GOV-104 (new) | — | GOV-001 | GOV.md | — |
| GOV-105 (new) | — | GOV-002, GOV-101 | GOV.md | — |
| INF-101 (new) | — | INF-001, INF-002, INF-008 | INF.md | INF-103 step-level for S10 |
| INF-102 (new) | — | INF-001 | INF.md | — |
| INF-103 (new) | — | INF-003, INF-005 | INF.md | CTL-004 step-level |
| INF-104 (new) | — | INF-008 | INF.md | — |
| INF-105 (new) | — | INF-001 | INF.md | — |
| INF-106 (new) | — | INF-002, CON-006 | INF.md | — |
| ING-101 (new) | — | ING-001, CON-005, CON-002, INF-101 [U-03], WRK-101 [C-10], ING-107 [U-04] | ING.md, RECONCILIATION | ING asked +OPS-103 → INF-101 (RECON); estate; WRK-101-S09 projection handoff; S07 live privacy path needs ING-107 (C-10, U-03, U-04) |
| ING-102 (new) | — | ING-001, CON-005, CON-002, INF-101 [U-03] | ING.md, RECONCILIATION | replaces +OPS-103 (U-03) |
| ING-103 (new) | — | ING-001, CON-005, INF-101 [U-03] | ING.md, RECONCILIATION | replaces +OPS-103 (U-03) |
| ING-104 (new) | — | ING-001, CON-005, INF-101 [U-03] | ING.md, RECONCILIATION | replaces +OPS-103 (U-03) |
| ING-105 (new) | — | ING-101, ING-102, ING-103, ING-104, ING-106 | ING.md | — |
| ING-106 (new) | — | ING-002, ING-003, ING-005, ING-107, CON-001, CON-101, INF-005, ORC-003 [U-12, C-25] | ING.md, RECONCILIATION | cycle table/admission owned by ORC-003-S01..S03; the launcher claims ADMITTED cycles (ING asked the reverse edge ORC-003 +ING-106; rejected) (C-25, U-12) |
| ING-107 (new) | — | SEC-007, SEC-103, ING-001 | ING.md | — |
| ING-112 (new) | — | ING-012, ING-008 | ING.md | — |
| INS-101 (new) | — | INS-001, API-003, UX-002, SEC-006 | INS.md | — |
| INS-102 (new) | — | CON-003, CON-005, ING-005, ING-006, ING-106 [U-12] | INS.md, RECONCILIATION | snapshot runs inside the account-cycle executor (U-12) |
| INS-103 (new) | — | INS-003, WRK-002, WRK-004, WRK-005, ING-105 | INS.md | — |
| INS-104 (new) | — | INS-004, FIN-011, FIN-012, ING-105 | INS.md | — |
| INS-105 (new) | — | INS-002, INS-003, INS-004 | INS.md, RECON | INS: "runs in parallel with INS-002..004; gates enabling" — qualification needs the detectors |
| INS-106 (new) | — | INS-002, INS-102, ING-105 | INS.md | — |
| LCH-101 (new) | CTL-007 [U-08] | SEC-004, CTL-006, CTL-102 [U-08] | LCH.md, RECONCILIATION | plans/entitlements tables created here, not in CTL-007; overrides via ops API (CTL-102) (U-08) |
| LCH-102 (new) | — | SEC-001, OPS-104, OPS-005 | LCH.md | — |
| LCH-103 (new) | — | LCH-101 | LCH.md | — |
| LCH-104 (new) | — | OPS-102 | LCH.md | — |
| ONB-101 (new) | — | ING-010, CON-005, OPS-105, LCH-101 | ONB.md | — |
| ONB-102 (new) | — | OPS-005, API-004, ALC-008, CON-006, API-102 [U-10], CTL-102 [U-11] | ONB.md, RECONCILIATION | export bundle is an API-102 export kind; offboarding state transitions via CTL-102 (U-10, U-11) |
| OPS-101 (new) | — | OPS-001, ING-007, ORC-003 | OPS.md | — |
| OPS-102 (new) | — | OPS-001, INF-006 | OPS.md | — |
| OPS-103 (new) | INF-008 [U-03] | CON-003, INF-101 [U-03] | OPS.md, RECONCILIATION | canaries run on the INF-101 estate (U-03) |
| OPS-104 (new) | — | CTL-002, INF-003, SEC-001 | OPS.md | — |
| OPS-105 (new) | — | ING-008, ORC-003, OPS-101 | OPS.md | part B needs API-003 (step-level) |
| OPS-106 (new) | — | SEC-008, INF-006, ING-007, CTL-102 [U-05] | OPS.md, RECONCILIATION | ops API skeleton and operator authN live in CTL-102 (U-05) |
| OPS-107 (new) | — | OPS-004, REL-104 | OPS.md, REL.md | REL: OPS-107 depends on REL-104 (pentest against production-like stack) |
| OPS-108 (new) | — | INF-007, SEC-008 | OPS.md | — |
| OPS-109 (new) | — | OPS-001, ORC-003, INF-008 | OPS.md | — |
| OPS-110 (new) | — | OPS-003, GOV-007, RPT-005 | OPS.md | — |
| OPS-111 (new) | — | OPS-007 | OPS.md | — |
| ORC-101 (new) | — | ING-007, DBT-101, CTL-005 | ORC.md | — |
| ORC-102 (new) | — | ORC-001 | ORC.md | — |
| ORC-103 (new) | — | DBT-101, CON-002 | ORC.md | — |
| ORC-104 (new) | — | ORC-101, DBT-101 | ORC.md | — |
| ORC-105 (new) | — | ORC-005 | ORC.md | — |
| REL-101 (new) | — | CTL-002, INF-007 | REL.md | — |
| REL-102 (new) | — | CTL-004, CTL-006, OPS-106 | REL.md | — |
| REL-103 (new) | — | DBT-006, API-001, ORC-005 | REL.md | — |
| REL-104 (new) | — | INF-007, INF-008, OPS-102, OPS-103 | REL.md | — |
| RPT-101 (new) | — | RPT-003, WRK-005, UX-007, INS-101, FIN-018 | RPT.md | — |
| RPT-102 (new) | — | RPT-004, RPT-005, GOV-006 | RPT.md | — |
| RPT-103 (new) | — | RPT-001, CTL-007, UX-004 | RPT.md | — |
| SEC-101 (new) | — | FND-004 | SEC.md | — |
| SEC-102 (new) | — | SEC-004, SEC-002, CTL-101 | SEC.md | — |
| SEC-103 (new) | — | INF-003, CTL-101, SEC-001 | SEC.md | — |
| SEC-104 (new) | — | SEC-102, SEC-006, SEC-105, CTL-102 | SEC.md | — |
| SEC-105 (new) | — | SEC-005, CTL-004, INF-005, SEC-101, INF-103 [U-02] | SEC.md, RECONCILIATION | IAM role for tenant serving principal created by the single runtime IAM provisioner (INF says SEC-005; RECON moves the edge to SEC-105 because SEC-005 uses scripted fixtures) (U-02) |
| SEC-106 (new) | — | SEC-101, SEC-105, SEC-103 | SEC.md | — |
| UX-101 (new) | — | UX-002, UX-004, CTL-007, API-102, RPT-103 [U-01] | UX.md, RECONCILIATION | dashboard backend (widget data API, sharing) in RPT-103 (U-01) |
| UX-102 (new) | OPS-005 [C-29] | UX-002, SEC-004, SEC-008, SEC-007, CTL-003 | UX.md, RECONCILIATION | only UX-102-S05 (privacy page) needs the OPS-005-S17 API; step-level, feature-flagged; removes RPT-004→RPT-005→OPS-005→UX-102 from the critical path (C-29) |
| UX-103 (new) | GOV-006 [U-22] | UX-002, CON-005, CON-006, ING-012 | UX.md, RECONCILIATION | destination health panel owned by GOV-006-S13 (U-22) |
| UX-104 (new) | — | UX-002, API-004, API-005, API-102 | UX.md | — |
| WRK-101 (new) | — | SEC-001, FND-004 | WRK.md | — |
| WRK-102 (new) | — | WRK-001, UX-002, API-104 | WRK.md | — |
| WRK-103 (new) | — | API-004, ING-003, SEC-007, CON-005, UX-005 | WRK.md | — |
| WRK-104 (new) | — | WRK-001, DBT-004, ING-001 | WRK.md | — |
| WRK-105 (new) | — | WRK-001, FIN-019, FIN-020, UX-002, API-104 | WRK.md | — |

Original tasks with no dependency change (12): FND-001, FND-002, FND-003, CON-004, ING-002, ING-008, API-003, ALC-002, ALC-004, INS-005, INS-007, LCH-002.

## 4. Estimate changes from de-duplication

Only tasks whose hours changed are listed. Hours are senior engineer-hours including tests, review and evidence (D-19).

| Task | Release | Backlog §6 h | Revised h | Δ low / Δ high | Reason |
|---|---|---:|---:|---:|---|
| SEC-006 | R1 | 44–68 | 41–64 | -3 / -4 | S06 HMAC cursors replaced by API-003-S05 sealed-token library (−3 h); S08 becomes the single artifact download broker |
| SEC-007 | R1 | 50–78 | 47–73 | -3 / -5 | S07 comment/tag metadata extraction → WRK-101 library (−3 h) |
| CTL-007 | R1 | 48–72 | 31–46 | -17 / -26 | S07–S10 commercial tables/subscription/entitlements/payments + commercial tests and billing page removed (owned by LCH-101/LCH-001), −17 step-h |
| CON-001 | R1 | 40–56 | 28–40 | -12 / -16 | S04/S05/S10 (provisioner worker, provisioner IAM, quota monitor) → INF-103; S06 launcher IAM → INF-005-S08 and launcher code → ING-106 (−12 step-h) |
| ING-012 | R1 | 42–61 | 44–64 | +2 / +3 | +2 h: batch-manifest read endpoint for API-005 Explain leaves |
| ORC-001 | R1 | 38–52 | 31–43 | -7 / -9 | S05–S07 BridgeEcsRunLauncher subclass, contract test and in-task guard retired by D-07 dedicated launcher (−7 h) |
| ORC-002 | R1 | 24–36 | 22–33 | -2 / -3 | S03 account_cycle_job body replaced by a sync-outcome observation sensor; launch is ING-106 (−2 h) |
| DBT-003 | R1 | 32–46 | 28–40 | -4 / -6 | S06 workload classification SQL → WRK-001 (D-34) (−4 h) |
| OPS-002 | R1 | 38–58 | 31–47 | -7 / -11 | S02 result table = DBT-005 QUALITY.CHECK_RESULT; S08 eligibility = ORC-005-S03; F03 conservation reuses DBT-005 macro (−8 h) |
| ALC-008 | R1 | 43–61 | 39–55 | -4 / -6 | S03 rounding library = FIN-106-S03 (−4 h) |
| RPT-002 | R1 | 44–66 | 42–63 | -2 / -3 | S08 CSV writer reuses API-102-S03 library (−2 h) |
| RPT-005 | R1 | 29–44 | 25–38 | -4 / -6 | S03/S04 download broker and presign = SEC-006-S08 (−5 h); +1 h report authorization resolver plug-in |
| INS-001 | R1 | 40–60 | 36–54 | -4 / -6 | S08 landing via ORC-103 writer (−3 h); S04 impact_floor from GOV-101 (−1 h) |
| INS-003 | R1 | 34–50 | 31–46 | -3 / -4 | S02 becomes a view over WRK-104 fct_query_family_daily (−3 h) |
| OPS-005 | R1 | 58–86 | 56–84 | -2 / -2 | S03 landing lifecycle rules = ING-005-S04; S05 canonical expiry executed by ORC-105 (−2 h) |
| LCH-001 | R1 | 38–56 | 36–53 | -2 / -3 | S05 operator authentication reuses the CTL-102 ops plane (−2 h) |
| API-102 | R1 | 24–34 | 22–31 | -2 / -3 | S05 download endpoint = SEC-006-S08 artifact broker (−2 h, R1 part) |
| CTL-102 | R1 | 28–44 | 25–39 | -3 / -5 | owns ops API skeleton + operator authN for console and CLI (+2 h); tombstone table/restore loader → OPS-104 (−2 h); ordered deletion plan → OPS-005-S09 (−3 h) |
| CTL-103 | R2 | 24–40 | 0–0 | -24 / -40 | merged into UX-101 (UI) and RPT-103 (widget data API, sharing) |
| FIN-106 | R1 | 16–24 | 15–23 | -1 / -1 | S05 ESLint money rule = FND-103-S03 (−1 h) |
| FIN-108 | R1 | 28–44 | 25–39 | -3 / -5 | S08 decimal end-to-end check = ING-003-S01/S04 acceptance; S06 source-latency part = ING-102-S06 (−3.5 step-h) |
| FND-101 | R1 | 20–30 | 15–22 | -5 / -8 | S04, S07 and the ci profile part of S05 duplicate DBT-102 dbt CI (−7 h) |
| GOV-102 | R1 | 21–30 | 14–20 | -7 / -10 | S01–S03 SES identity/config set/production access = INF-006-S11 (−7 h) |
| INF-101 | R1 | 34–52 | 35–54 | +1 / +2 | +1 h: hourly deterministic canary scenario and known-answer tags absorbed from OPS-103-S03 |
| ING-101 | R1 | 28–40 | 32–46 | +4 / +6 | +4 h: consolidated QH/QAH projection union (INS/ALC/WRK), AU.SESSIONS contract and live verification |
| ING-103 | R1 | 22–32 | 24–35 | +2 / +3 | +3 h AU.TAG_REFERENCES snapshot contract (ALC-001); −1 h OU.ACCOUNTS contract authored in CON-004-S03 |
| ING-104 | R1 | 20–30 | 30–45 | +10 / +15 | +10/+15 h: TASK_HISTORY and DYNAMIC_TABLE_REFRESH_HISTORY contracts pulled from R2 (ING-105) for R1 WRK-004 (≈ 5–7.5 h per source, as for the four existing ING-104 sources) |
| ING-105 | R2 | 80–140 | 70–125 | -10 / -15 | −10/−15 h: TASK_HISTORY and DT refresh contracts moved to R1 ING-104 |
| ING-106 | R1 | 40–58 | 37–54 | -3 / -4 | S01 cycle table = ORC-003-S01 (−3 h); S08 schedule formula = ORC-003-S02 (−2 h); +2 h launcher service (from CON-001-S06) |
| ING-107 | R1 | 24–36 | 22–33 | -2 / -3 | S04 sanitizer cache duplicates SEC-007-S08 (−2 h; process-pool sizing kept) |
| ONB-101 | R1 | 26–40 | 22–34 | -4 / -6 | S01/S03 credit formulas duplicate CON-101-S01 estimator (−4 h) |
| ONB-102 | R1 | 26–40 | 21–32 | -5 / -8 | S02 export bundle reuses API-102 export job (−3 h); S04 pause/disconnect semantics = CON-006-S09/S11 (−3 h) |
| OPS-103 | R1 | 26–40 | 12–18 | -14 / -22 | S01–S04, S09, S10 (org creation, bootstrap, generator, install, spend and expiry monitors) → INF-101 (−16 step-h) |
| OPS-106 | R1 | 40–60 | 25–38 | -15 / -22 | S02 ops API skeleton → CTL-102; S06–S09 support grants/approval/profile/audit → SEC-104 (−16 step-h) |
| OPS-109 | R1 | 20–30 | 13–19 | -7 / -11 | S01 tags → INF-105-S02; S08 CUR export → INF-105-S05; S02 per-tenant build rows → ORC-104-S02 (−8 h) |
| OPS-110 | R1 | 14–22 | 11–17 | -3 / -5 | S03 error classification = GOV-007-S03; S07 destination health UI = GOV-006-S13 (−4 h) |
| ORC-104 | R1 | 16–24 | 8–12 | -8 / -12 | S01 query-tag builder → OPS-109-S03; S04–S06 credit allocation → OPS-009-S05/S06 (−8 h) |
| ORC-105 | R1 | 22–32 | 23–33 | +1 / +1 | +1 h: dataset retention expiry (D-11/D-26) executed by the single GC job |
| REL-101 | R1 | 20–30 | 10–14 | -10 / -16 | S02, S03, S05, S07, S08 duplicate CTL-101-S01/S04 and CTL-002-S01/S03 (−11 h); keeps policy, N−1 compatibility job, contract gate |
| REL-104 | R1 | 22–34 | 20–31 | -2 / -3 | S08 cost guards = INF-105 (−2 h) |
| RPT-103 | R2 | 38–57 | 27–41 | -11 / -16 | S03/S04 builder and viewer UI = UX-101 (−11 h) |
| SEC-103 | R1 | 40–64 | 35–56 | -5 / -8 | S04 in-extractor decrypt/pseudonymize → ING-107-S03 (−2 h); S09 erasure workflow → OPS-005 privacy-request workflow, primitive kept (−3 h) |
| SEC-104 | R1 | 24–40 | 25–42 | +1 / +2 | +1 h: tenant auto-approve policy for health_read (from OPS-106-S07) |
| SEC-105 | R1 | 48–76 | 40–63 | -8 / -13 | S02 IAM role creation and IAM parts of S07/S08/S09 → INF-103 (−8 step-h) |
| UX-103 | R1 | 20–28 | 12–17 | -8 / -11 | S04 connection detail = CON-006-S12; S05 destination health = GOV-006-S13; overhead credits in S03 = ING-012-S08 (−7 step-h) |

Net change on R1 tasks: -170 h (low) / -254 h (high).

Revised totals by domain (live tasks; R1\* includes FIN-008's replication part; R2 includes the R2 parts of API-102 and ALC-002):

| Domain | R1 h | R1* h | R2 h |
|---|---:|---:|---:|
| FND | 189–280 | — | — |
| INF | 379–542 | — | 16–26 |
| SEC | 504–786 | 56–84 | 40–64 |
| CTL | 332–505 | — | — |
| CON | 284–418 | — | 40–80 |
| ING | 608–885 | — | 110–185 |
| ORC | 304–435 | — | — |
| DBT | 260–374 | — | 10–14 |
| FIN | 665–975 | 139–208 | 24–36 |
| API | 262–371 | — | 40–58 |
| UX | 330–459 | 28–40 | 30–44 |
| WRK | 198–276 | 24–34 | 46–66 |
| ALC | 410–584 | — | 8–14 |
| GOV | 345–490 | — | 40–57 |
| INS | 297–440 | — | 158–237 |
| RPT | 179–269 | — | 79–119 |
| OPS | 690–1,047 | — | 22–36 |
| REL | 186–283 | — | — |
| LCH | 162–253 | — | — |
| ONB | 195–302 | — | — |
| **Total** | **6,779–9,974** | **247–366** | **663–1,036** |

## 5. Follow-ups for the lead (text to change; no file was edited here) — all items APPLIED 2026-09-28, see §6

1. **[APPLIED]** **Backlog step text.** Apply the rulings in the losing tasks' step tables: CON-001 (S04–S06, S10), SEC-105 (S02, S07–S09), OPS-103 (S01–S04, S09–S10), OPS-106 (S02, S06–S09), CTL-007 (S07–S10, S12 billing page), ORC-001 (S04–S07), ORC-002 (S03), ORC-003 (S01 columns, S02 formula), ING-106 (S01, S03, S08), ING-010-S04 (COLD tier), SEC-006-S06, SEC-007-S07, SEC-103-S04/S09, ING-107-S04, OPS-109 (S01, S02, S08), ORC-104 (S01, S04–S06), GOV-102 (S01–S03), OPS-110 (S03, S07), OPS-002 (S02, S05 scale, S08), DBT-003-S06, FND-101 (S04, S05 ci target, S07), REL-101 (S02, S03, S05, S07, S08), RPT-005 (S03, S04), API-102-S05, RPT-002-S08, UX-103 (S03–S05), ALC-008-S03, INS-001 (S04, S08), INS-003-S02, WRK-104-S05, OPS-005 (S03, S05), CTL-102 (S06, S07), ONB-101 (S01, S03), ONB-102 (S02, S04), RPT-103 (S03, S04), FIN-108 (S06, S08), CON-004-S03 / ING-103, and every "OPS-103 account" reference in CON/ING steps (→ INF-101 estate).
2. **[APPLIED]** **Contract-first index.** In `CONTRACT_FIRST_ARTIFACTS.md`: subscription state machine → LCH-001-S02 (C-08); landing key grammar → ING-005-S01 (INF-003-S04 consumes it); egress IP publication → INF-002-S03 + CON-102-S01; IAM policy templates → INF-103-S01…S05 (+ CON-001-S03 policy content); quality-check result DDL → DBT-005-S01; money grammar → FIN-106-S04 (FND-103 imports it).
3. **[APPLIED]** **Decisions.** Amend D-07, D-15, D-32 and D-33 as described in C-04, C-10, C-24 and C-05; add the D-11 refinements of C-01; correct AUDIT X-10 (C-28); propagate D-26 into OPS-005/INF-003 (C-02).

## 6. Applied changes (2026-09-28)

All §5 follow-ups are applied. §5.1 and §5.2 were applied in this pass; in §5.3 the decision amendments (D-07, D-11, D-15, D-32, D-33) and the AUDIT X-10 correction were made in [DECISIONS_REQUIRED.md](DECISIONS_REQUIRED.md) and [AUDIT_CROSS_CUTTING.md](AUDIT_CROSS_CUTTING.md), and the D-26 propagation was applied here. Only files under `docs/22-implementation-readiness/` were edited. Step IDs, task headers (and therefore the `backlog_ref` anchors) and table formats are unchanged. A step whose work moved now reads "Moved to <task-step> per RECONCILIATION <ID> — …" (CTL-103: "Merged into …"; ORC-001-S05…S07: "Retired …") with 0 h or the residual hours of the ruling. Absorbed work was added to the receiving steps: INF-101-S06/S09/S12, ING-012-S03, ING-101-S01/S02/S04, ING-103-S01/S05, ING-104-S01/S03–S05, ING-106-S03, ORC-003-S01/S02, ORC-105-S04 and SEC-104-S03.

| File | Steps edited (n) | Task meta / dependency lines and other sections | §6 totals now (R1 unless noted) |
|---|---|---|---|
| `backlog/ALC.md` | ALC-003 S02, S03; ALC-008 S03 (3) | ALC-001, ALC-003, ALC-008 (meta) | 410–584 / R2 8–14 |
| `backlog/API.md` | API-003 S05; API-102 S05, S10 (3) | API-005, API-102 | 262–371 / R2 40–58 |
| `backlog/CON.md` | CON-001 S04, S05, S06, S07, S09, S10, S12; CON-002 S05; CON-003 S01, S02, S05; CON-004 S02, S03, S07; CON-005 S02, S13; CON-006 S04, S08, S12, S15; CON-101 S01, S06, S07 (23) | CON-001, CON-002, CON-003, CON-005, CON-006; §3 identity rules, install-script ARNs, lifecycle guard (C-11) | 284–418 / R2 40–80 |
| `backlog/CTL.md` | CTL-007 S07, S08, S09, S10, S11, S12; CTL-102 S02, S06, S07; CTL-103 S01, S02, S03, S04, S05, S06, S07, S08 (17) | CTL-007, CTL-102, CTL-103 (merged); §3 contract rows; Appendix F marked superseded | 332–505 / R2 0 |
| `backlog/DBT.md` | DBT-001 S03; DBT-003 S06; DBT-005 S01; DBT-006 S01; DBT-104 S02 (5) | DBT-001, DBT-003 | 260–374 / R2 10–14 |
| `backlog/FIN.md` | FIN-101 S08; FIN-106 S03, S04, S05; FIN-108 S06, S08 (6) | FIN-002, FIN-004, FIN-101, FIN-104, FIN-106, FIN-108 | 665–975 / R1\* 139–208 / R2 24–36 |
| `backlog/FND.md` | FND-101 S04, S05, S07; FND-103 S02 (4) | FND-101 (meta), FND-103 | 189–280 |
| `backlog/GOV.md` | GOV-001 S05; GOV-002 S06; GOV-004 S02; GOV-005 S02; GOV-101 S03; GOV-102 S01, S02, S03 (8) | GOV-002, GOV-005, GOV-008, GOV-102; G-GOV-05 resolution (C-09) | 345–490 / R2 40–57 |
| `backlog/INF.md` | INF-002 S03; INF-003 S03, S04; INF-006 S01, S11; INF-101 S02, S06, S09, S12; INF-103 S01, S07 (11) | INF-101, INF-103; cross-domain edge note (SEC-105 +INF-103); §3 contract rows | 379–542 / R2 16–26 |
| `backlog/ING.md` | ING-001 S04; ING-002 S08; ING-003 S04, S12; ING-005 S04; ING-007 S13; ING-010 S04, S06, S12; ING-012 S03, S08; ING-101 S01, S02, S03, S04; ING-103 S01, S02, S05; ING-104 S01, S03, S04, S05; ING-105 S01, S03; ING-106 S01, S02, S03, S08, S12; ING-107 S02, S03, S04 (32) | ING-003, ING-010, ING-012, ING-101, ING-102, ING-103, ING-104, ING-105, ING-106, ING-107; §3.1 source table, `sync.*` list, contract row | 608–885 / R2 110–185 |
| `backlog/INS.md` | INS-001 S04, S08; INS-003 S02 (3) | INS-001, INS-002, INS-003, INS-005 (release note), INS-102, INS-105 | 297–440 / R2 158–237 |
| `backlog/LCH.md` | LCH-001 S02, S05 (2) | LCH-001, LCH-101; milestone table | 162–253 |
| `backlog/ONB.md` | ONB-101 S01, S03, S06; ONB-102 S02, S03, S04 (6) | ONB-005, ONB-101, ONB-102; dependency table | 195–302 |
| `backlog/OPS.md` | OPS-002 S02, S03, S04, S05, S08; OPS-005 S03, S05, S06, S09, S12, S17; OPS-007 S01; OPS-009 S02, S05, S06, S08; OPS-103 S01, S02, S03, S04, S05, S06, S08, S09, S10; OPS-106 S02, S06, S07, S08, S09; OPS-109 S01, S02, S03, S08; OPS-110 S03, S07 (36) | OPS-002, OPS-004, OPS-005 (+ retention matrix, D-26), OPS-007, OPS-008, OPS-009, OPS-011, OPS-103, OPS-104, OPS-106, OPS-109, OPS-110; milestone table; §3 contract rows | 690–1,047 / R2 22–36 |
| `backlog/ORC.md` | ORC-001 S01, S04, S05, S06, S07; ORC-002 S03, S04, S05; ORC-003 S01, S02, S03, S04, S05, S06, S09, S11, S12; ORC-104 S01, S04, S05, S06, S08; ORC-105 S03, S04, S07 (25) | ORC-001, ORC-003, ORC-104, ORC-105; §3 contract rows | 304–435 |
| `backlog/REL.md` | REL-101 S02, S03, S05, S07, S08; REL-104 S02, S08 (7) | REL-001, REL-003, REL-004, REL-101, REL-103, REL-104 | 186–283 |
| `backlog/RPT.md` | RPT-002 S08; RPT-005 S03, S04; RPT-103 S03, S04 (5) | RPT-002, RPT-005, RPT-103; §3 contract rows | 179–269 / R2 79–119 |
| `backlog/SEC.md` | SEC-006 S06, S08; SEC-007 S07, S08; SEC-103 S04, S05, S09; SEC-104 S01, S03; SEC-105 S02, S07, S08, S09 (13) | SEC-006, SEC-007, SEC-103, SEC-104, SEC-105; Appendices A.1/A.6, G.2, I (ATK-04) | 504–786 / R1\* 56–84 / R2 40–64 |
| `backlog/UX.md` | UX-102 S05; UX-103 S01, S03, S04, S05 (5) | UX-008, UX-101, UX-102, UX-103 | 330–459 (R2 incl. UX-007 58–84) |
| `backlog/WRK.md` | WRK-104 S02, S05 (2) | WRK-004, WRK-101, WRK-104; §3 projections row | 198–276 (unchanged) |

Total: 216 step rows in 20 backlog files.

- **Hours.** Each of the 45 changed estimates in §4 (CTL-103 → 0 h) is applied to the task's "Estimate:" meta line, its §6 row and the §6 totals. The domain totals equal the §4 "Revised totals by domain" table: R1 **6,779–9,974 h**, R1\* **247–366 h**, R2 **663–1,036 h**, so no total changed from §4. No hour figure differs from the reconciliation, so `revised-task-graph.json` needed no estimate update. Its `estimate_low_h/high_h` match every backlog §6 row, and `backlog_estimate_low_h/high_h` now record the figures as they stood before this pass. ALC-002's R2 part is its own §6 row ("D-16 regex operators"), which equals `r2_hours_*`.
- **Dependencies.** Every task with a ruling-tagged row in §3 had its "Dependency changes:" or "Plugs in" line rewritten to the final edges with the ruling ID. That covers the U-/C- edge moves, the C-29 re-attachments and the rejected requests: ORC-003 +ING-106; +OPS-103 on CON-002/003/005 and ING-101…104; CTL-007 +CTL-102; OPS-009 +LCH-101; SEC-005 +INF-103; REL-001 +OPS-011; UX-102 +OPS-005; UX-103 +GOV-006; INS-002 +FIN-004; OPS-004 +API-006. The OPS, LCH and ONB milestone/dependency tables were aligned the same way.
- **D-26 (C-02).** OPS-005 now applies per-`retention_class` retention (FINANCIAL = billing/metering/storage sources 400 d, QUERY_GRAIN 90 d) in its retention matrix, S03 and S05, and revisioned fact tables keep Time Travel 1 d. INF-003-S03 applies ING-005-S04's generated lifecycle rules per class. ING-005-S04, OPS-007-S01 and the OPS-007 milestone note were aligned, and ING Q2 and DBT Q1 are marked resolved by D-26.
- **Contract-first index.** In `CONTRACT_FIRST_ARTIFACTS.md` §1 (rows 3–6) and §2, the "Produced by" column was fixed for the subscription state machine, landing key grammar, egress IP publication (INF and CON), IAM policy templates (INF and CON), quality-check result DDL and money grammar (FND and FIN). §2 rows that pointed at moved steps were fixed too: `sync.*` cycle table, launcher contract, query-tag schema, rounding fixtures, CSV spec, RPT IAM and `ops.processing_ledger`. The matching §3 contract tables inside the ALC, CON, CTL, INF, ING, OPS, ORC and RPT backlogs were corrected the same way.
- **Verification.** `validate_graph.py`: PASS (249 tasks, 859 edges, acyclic, 0 R1→R2 / R1→R1\* / R1\*→R2 edges, R1 6,779–9,974 h). Every backlog §6 total equals the sum of its rows. No Markdown table row changed its cell count.
- **Left as is.** (a) Backlog §2 findings and evidence text stay as the audit record; resolutions were annotated only where an implementer would copy them (G-GOV-05, G-RPT-07, SEC G.2, ING `sync.*` and sync-api). (b) SEC-104 and SEC-105 step sums were already below their task low estimates before this pass; the ruled deltas were applied unchanged. (c) WRK-104-S05 and OPS-005-S06 keep 4 h each, now as policy declaration and verification of ORC-105's GC, because §4 did not change those estimates; this may slightly overstate them. (d) `RELEASE_PLAN.md` §2 still lists CTL as "saved views, commercial records"; commercial records are LCH-101/LCH-001 per U-08. That file was not edited in this pass.
