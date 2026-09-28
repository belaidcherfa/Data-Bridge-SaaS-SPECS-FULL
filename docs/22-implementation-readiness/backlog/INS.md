# INS — Implementation-readiness review and production backlog

Canonical contract: [intelligence.md](../../13-insights/intelligence.md) (with [governance.md](../../12-budgets-monitoring/governance.md) statistical defaults, [source-catalog.md](../../05-ingestion/source-catalog.md), [workloads.md](../../10-frontend/workloads.md), [ledger.md](../../08-finops-ledger/ledger.md), PRD §97–§108, §112). Tasks reviewed: INS-001, INS-002, INS-003, INS-004, INS-005, INS-006, INS-007. Reviewer: domain audit agent, 2026-09-27. Status of all tasks: NOT_STARTED.

## 1. Verdict

Not implementable as specified, but closer than it looks: the detector registry (41 rows) has precise predicates and fixtures, and the savings formula is sound. What is missing is everything *between* the predicate and a production system. **Only 8 of the 41 detectors run entirely on REQUIRED core projections** (WH01, WH04, Q07, ST03, ST04, ST05, PI03, PI04). **26 need optional columns or extension-family sources that have no finalized contract.** **7 depend on inputs no source provides**: warehouse configuration (WH02, WH05), tenant isolation policy (WH08), customer denominators or quality evaluations (AI02, AI07) and SPCS telemetry (SP01, SP03). One vendor change (Snowpipe per-GB pricing, Dec 2025) removes the monetary basis of PI01–PI04. Fingerprints, observation identity, dismissal expiry, potential-savings formulas, opportunity de-duplication, the impact floor, savings normalizers per action type, window lengths, confidence method and the "Implemented" date source are undefined. The insight and action lifecycles are conflated and contradict the UI spec.

Author first: (1) the detector input matrix in §2 as a projection change request to ING-001/CON-005, including the new warehouse-configuration snapshot source (INS-102); (2) the observation/fingerprint/opportunity-group contract (INS-001-S01..S05); (3) the two lifecycle state machines (INS-006-S01); (4) the savings-measurement contract (INS-007-S01). Ship an **R1 subset of 8 detectors** (WH01 with WH04 folded in as a severity tier, WH02, Q01, Q02, Q03, Q07, ST03, ST04). All of them run on core sources plus cheap projection additions and one new SHOW-based snapshot. 28 detectors move to R2, and 4 are capability-gated until a new input contract exists (AI02, AI07, SP01, SP03).

## 2. Findings

### Detector input availability matrix (evidence for G-INS-01…G-INS-07)

"Required?" refers to the REQUIRED projection in [source-catalog.md](../../05-ingestion/source-catalog.md) Core contracts. That catalog says for QUERY_HISTORY: "Add hash versions and performance fields only through verified optional projection." "Ext" means an extension-family source with no finalized projection ("do not schedule extraction", catalog §Operational defaults). Column names are documented Snowflake fields. Existence per account is still **TO VERIFY LIVE** through the CON-005 schema probe.

| ID | Source view · exact input columns | Required? | Gap raised to | Release |
|---|---|---|---|---|
| WH01 | AU.WAREHOUSE_METERING_HISTORY: START_TIME, WAREHOUSE_ID, CREDITS_USED_COMPUTE, CREDITS_ATTRIBUTED_COMPUTE_QUERIES (via FIN-003 `ledger_warehouse_idle`); rate via FIN-002 | Yes | — | **R1** |
| WH02 | AU.QUERY_HISTORY: START_TIME, END_TIME, WAREHOUSE_ID, WAREHOUSE_SIZE, EXECUTION_TIME (req.) + **CLUSTER_NUMBER, WAREHOUSE_TYPE** (optional); **current AUTO_SUSPEND, AUTO_RESUME, MIN/MAX_CLUSTER_COUNT, SCALING_POLICY, TYPE, SIZE**: no catalog source (only `SHOW WAREHOUSES`) | Partial / **No** | ING-001 (+2 QH cols), **INS-102 new source** | **R1** (needs INS-102) |
| WH03 | AU.WAREHOUSE_LOAD_HISTORY (AVG_RUNNING, AVG_QUEUED_LOAD, AVG_QUEUED_PROVISIONING, AVG_BLOCKED) + QH QUEUED_OVERLOAD_TIME, BYTES_SPILLED_* | Ext / optional | ING-001, CON-005 | R2 |
| WH04 | Same as WH01 (idle share > 50 %) | Yes | — | **R1 as WH01 severity tier** (G-INS-07) |
| WH05 | Config (MIN/MAX_CLUSTER_COUNT, SCALING_POLICY) from INS-102; active clusters from AU.WAREHOUSE_EVENTS_HISTORY (TIMESTAMP, WAREHOUSE_ID, CLUSTER_NUMBER, EVENT_NAME, EVENT_REASON, EVENT_STATE) or QH CLUSTER_NUMBER | No / Ext | INS-102, ING-001 | R2 (redefined, G-INS-07) |
| WH06 | QH QUEUED_OVERLOAD_TIME (optional), TOTAL_ELAPSED_TIME (req.) | Partial | ING-001 | R2 |
| WH07 | AU.WAREHOUSE_EVENTS_HISTORY (as WH05) | Ext | ING-001, CON-005 | R2 |
| WH08 | WMH + QH peak windows + tenant security/SLA isolation policy (no source; tenant input) | Partial / **No** | Tenant config (CTL) | R2 |
| Q01 | QH QUERY_ID, START_TIME, WAREHOUSE_ID, EXECUTION_STATUS, QUERY_PARAMETERIZED_HASH (req.) + **QUERY_PARAMETERIZED_HASH_VERSION** (optional); QAH CREDITS_ATTRIBUTED_COMPUTE, CREDITS_USED_QUERY_ACCELERATION (req.); Adaptive: QMH CREDITS_USED_COMPUTE (req.) | Partial | ING-001 (+hash version) | **R1** |
| Q02 | QH QUERY_PARAMETERIZED_HASH(+_VERSION), START_TIME, USER_NAME (HMAC per D-10), ROLE_NAME, WAREHOUSE_ID, QUERY_TAG | Partial | ING-001 | **R1** |
| Q03 | QH **BYTES_SPILLED_TO_LOCAL_STORAGE, BYTES_SPILLED_TO_REMOTE_STORAGE** | **No** (optional) | ING-001 | **R1** (if projected) |
| Q04 | QH PARTITIONS_SCANNED, PARTITIONS_TOTAL (optional); selectivity from AU.TABLE_QUERY_PRUNING_HISTORY (PARTITIONS_SCANNED, PARTITIONS_PRUNED, ROWS_SCANNED, ROWS_MATCHED, hourly by table×query_hash×warehouse; not in catalog) or GET_QUERY_OPERATOR_STATS (on demand, 14 days) | **No** | ING-001, CON-005 | R2 |
| Q05 | GET_QUERY_OPERATOR_STATS join operator output rows vs. input rows (on demand only, 14 days, OPERATE/MONITOR on warehouse) | **No batch source** | WRK-005 | R2 (evidence enrichment, not recurring) |
| Q06 | QH **COMPILATION_TIME** (optional), EXECUTION_TIME | Partial | ING-001 | R2 |
| Q07 | AU.METERING_DAILY_HISTORY CREDITS_USED_CLOUD_SERVICES, CREDITS_ADJUSTMENT_CLOUD_SERVICES (req.); contributors QH CREDITS_USED_CLOUD_SERVICES (optional) | Yes (signal) | ING-001 (contributors only) | **R1** (contributors R2) |
| Q08 | QH EXECUTION_STATUS (req.), ERROR_CODE (optional), QUERY_RETRY_TIME/QUERY_RETRY_CAUSE (optional; these are Snowflake-internal retries, not user retries); logical execution IDs (WRK-002/004) | Partial | ING-001, WRK | R2 |
| ST01/ST02 | AU.ACCESS_HISTORY (QUERY_START_TIME, BASE_OBJECTS_ACCESSED, DIRECT_OBJECTS_ACCESSED, OBJECTS_MODIFIED) or AU.AGGREGATE_ACCESS_HISTORY; + TSM | Ext | ING-001, CON-005 | R2 (G-INS-04) |
| ST03 | AU.TABLE_STORAGE_METRICS ID, TABLE_CATALOG/SCHEMA/NAME, ACTIVE_BYTES, TIME_TRAVEL_BYTES, FAILSAFE_BYTES, RETAINED_FOR_CLONE_BYTES, CLONE_GROUP_ID, TABLE_DROPPED (req.); estimate needs AU.TABLES RETENTION_TIME (not in catalog) | Yes (detection) / No (estimate) | ING-001 (AU.TABLES, R2) | **R1** (no numeric estimate) |
| ST04 | TSM as ST03; transient eligibility needs AU.TABLES IS_TRANSIENT (not in catalog) | Yes / No | ING-001 (R2) | **R1** (no numeric estimate) |
| ST05 | TSM daily snapshots (≥ 8 after enrollment) or AU.DATABASE_STORAGE_USAGE_HISTORY | Yes / Ext | — | R2 |
| PL01/PL02 | Exact dbt invocations (WRK-002) / AU.TASK_HISTORY (Ext); change signal QH ROWS_INSERTED, ROWS_UPDATED, ROWS_DELETED (optional) | **No** | ING-001, WRK | R2 |
| PL03 | Same as PL01 | No | ING-001, WRK | R2 |
| PL04 | QH EXECUTION_STATUS + QAH credits + WRK logical execution graph | Partial | WRK | R2 |
| PL05 | Verified writer lineage: ACCESS_HISTORY OBJECTS_MODIFIED (Ext) | No | ING-001 | R2 |
| PI01 | AU.COPY_HISTORY per-file FILE_SIZE (not in catalog); PIPE_USAGE_HISTORY is hourly and cannot give a median | **No** | ING-001 | R2, non-monetary (G-INS-03) |
| PI02 | PIPE_USAGE_HISTORY FILES_INSERTED/hour (req.); median bytes needs COPY_HISTORY | Partial | ING-001 | R2, non-monetary |
| PI03 | PIPE_USAGE_HISTORY BYTES_INSERTED, FILES_INSERTED (req.) | Yes | — | R2, non-monetary |
| PI04 | PIPE_USAGE_HISTORY CREDITS_USED / BYTES_INSERTED (req.) | Yes | — | R2 (degenerate under per-GB pricing) |
| AI01 | CORTEX_AISQL_USAGE_HISTORY (Ext; FIN-018) | Ext | FIN-018 | R2 (R1 only if D-20 says Cortex) |
| AI02 | + approved quality-equivalence evaluation (**no source**; customer upload) | **No** | New customer-input contract | R2, capability-gated |
| AI03 | Cortex token + request counts (grain TO VERIFY per view) | Ext | FIN-018 | R2 |
| AI04 | Cortex user identifier (TO VERIFY per view) + D-10 HMAC | Ext | FIN-018 | R2 |
| AI05 | CORTEX_AGENT_USAGE_HISTORY | Ext | FIN-018 | R2 |
| AI06 | CORTEX_SEARCH_SERVING_USAGE_HISTORY + METERING_HISTORY search service rows | Ext | FIN-018 | R2 |
| AI07 | Business-transaction denominator (**no source**; customer dataset) | **No** | New customer-input contract | R2, capability-gated |
| SP01 | CPU utilization: **no ACCOUNT_USAGE source** (G-INS-06) | **No** | — | Not planned until telemetry capability |
| SP02 | SNOWPARK_CONTAINER_SERVICES_HISTORY CREDITS_USED per pool-hour (Ext, fields verified in catalog) + active-workload telemetry (none) | Partial | FIN-019 | R2 (billed-while-no-service variant only) |
| SP03 | Node-count history: **none** (SHOW COMPUTE POOLS is current state only) | **No** | — | Not planned until telemetry capability |
| SP04 | FIN-019 app attribution + customer workload unit | Partial | FIN-019 | R2 |

Totals (41 IDs): R1 = 9 IDs forming 8 detectors (WH01 with WH04 folded in as a tier, WH02, Q01, Q02, Q03, Q07, ST03, ST04). R2 = 28. Capability-gated = 4 (AI02, AI07, SP01, SP03).

### G-INS-01 · Detector inputs are missing from the required projections
Severity: BLOCKER · Type: GAP
Evidence: `source-catalog.md` QUERY_HISTORY row: "Add hash versions and performance fields only through verified optional projection". That row's required list has no BYTES_SPILLED_*, PARTITIONS_*, COMPILATION_TIME, QUEUED_OVERLOAD_TIME, ROWS_INSERTED/UPDATED/DELETED, CLUSTER_NUMBER, WAREHOUSE_TYPE, QUERY_PARAMETERIZED_HASH_VERSION or CREDITS_USED_CLOUD_SERVICES. `intelligence.md`: "Each detector declares the verified source projection that supplies its inputs during activation". No INS task depends on an ING/CON task that adds these columns.
Why it matters: Q03, Q04, Q06, WH02 (multi-cluster), WH06 and PL01–PL03 cannot be computed. Q01/Q02 families silently break when Snowflake bumps the parameterized-hash algorithm, because the hash version is not stored, so a false "new family"/"disappeared family" appears. Adding columns after a 365-day backfill means re-extracting history. QUERY_HISTORY is the highest-volume source, and a later projection change triggers ING-009 schema-drift handling across every tenant.
Resolution: Before ING-001 freezes the QUERY_HISTORY contract, add these to its REQUIRED projection: QUERY_PARAMETERIZED_HASH_VERSION, QUERY_HASH_VERSION, BYTES_SPILLED_TO_LOCAL_STORAGE, BYTES_SPILLED_TO_REMOTE_STORAGE, PARTITIONS_SCANNED, PARTITIONS_TOTAL, COMPILATION_TIME, QUEUED_OVERLOAD_TIME, QUEUED_PROVISIONING_TIME, CLUSTER_NUMBER, WAREHOUSE_TYPE, CREDITS_USED_CLOUD_SERVICES, ROWS_INSERTED, ROWS_UPDATED, ROWS_DELETED, ERROR_CODE. That is 16 numeric/short columns. Row count and extraction predicates do not change, so the added cost is only width, roughly +25–35 % Parquet bytes (measure in ING-004). Put AU.TABLE_QUERY_PRUNING_HISTORY, AU.WAREHOUSE_EVENTS_HISTORY, AU.WAREHOUSE_LOAD_HISTORY, AU.TABLES (RETENTION_TIME, IS_TRANSIENT) and AU.COPY_HISTORY on the ING R2 adapter list. Detector manifests (INS-001-S02) must fail validation when a required column is not in the active projection.
Affects: INS-001, INS-002, INS-003, INS-004; ING-001, ING-009, CON-005.

### G-INS-02 · No source exists for current warehouse configuration
Severity: BLOCKER (for WH02, the highest-value R1 detector) · Type: GAP / VENDOR-FACT
Evidence: `intelligence.md` WH02: "known auto-suspend setting above300s or disabled … absent settings suppress the setting recommendation"; WH05: "Configured max clusters>1". `grep -rn 'SHOW WAREHOUSES\|AUTO_SUSPEND' docs` finds no source contract. No ACCOUNT_USAGE view exposes AUTO_SUSPEND or MIN/MAX_CLUSTER_COUNT (WebSearch 2026-09-27 found only SHOW/DESCRIBE WAREHOUSES; TO VERIFY LIVE). `SHOW WAREHOUSES` only returns warehouses on which the role holds a privilege. Whether account-level MONITOR USAGE widens that to all warehouses is contradicted between search snippets: TO VERIFY LIVE. MANAGE WAREHOUSES also grants MODIFY/OPERATE, which breaks least privilege (search snippet of docs.snowflake.com/en/user-guide/security-access-control-privileges, 2026-09-27).
Why it matters: Without configuration, WH02 is always suppressed. Nothing can detect "Implemented" from a configuration change, so INS-007 is left with human attestation only. Adaptive-vs-classic and Gen1/Gen2 rate selection have no authoritative input.
Resolution: New task **INS-102**, an hourly `SHOW WAREHOUSES` snapshot run inside the D-07 account cycle. SHOW is a cloud-services metadata command and does not resume a warehouse (TO VERIFY LIVE). The snapshot is projected via RESULT_SCAN to name, type, size, min/max_cluster_count, scaling_policy, auto_suspend, auto_resume, resource_monitor and any generation/resource-constraint column (the new SHOW WAREHOUSES columns in BCR 2025_03/2025_07/2026_01 are TO VERIFY LIVE). It is loaded as a complete-snapshot source and turned into SCD2 `dim_warehouse_config`. Grant model: prefer account-level MONITOR USAGE if the live probe proves full visibility. Otherwise CON-003 grants MONITOR on each warehouse and CON-005 reports drift: a warehouse that appears in WAREHOUSE_METERING_HISTORY but not in the snapshot is "config unknown". If SHOW output has no warehouse ID, map name→WAREHOUSE_ID with the as-of join on WMH (WAREHOUSE_ID, WAREHOUSE_NAME) and flag renames.
Affects: INS-002, INS-006, INS-007, new INS-102; CON-003, CON-005, ING-001.

### G-INS-03 · Snowpipe per-GB pricing removes the monetary basis of PI01–PI04
Severity: HIGH · Type: VENDOR-FACT
Evidence: `intelligence.md` PI02: "impact uses billed model, not outdated per-file pricing assumption"; PI01 "Tiny files … <16MiB". VERIFIED (docs.snowflake.com/en/release-notes/2025/other/2025-12-08-snowpipe-simplified-pricing, search snippet 2026-09-27): "As of December 8, 2025, all Snowflake customers are charged a consistent 0.0037 credits per GB across all Snowpipe services, including file ingestion and streaming", and the per-1,000-files overhead is removed.
Why it matters: Under per-GB billing, 100 × 1 MiB files cost the same as 1 × 100 MiB file. PI01–PI03 would rank "savings" that do not exist. PI04's cost per byte is constant at 0.0037 credits/GB, so it can only fire on pricing-architecture changes or pre-2025-12-08 history, which is a guaranteed false positive around the transition date.
Resolution: Re-scope PI01–PI03 as non-monetary ingestion-hygiene observations (latency, file-count pressure) with `impact_kind=NONE`, no potential savings, and exclusion from ranking and the Home "Potential savings" total. Redefine PI04 as "Snowpipe spend per GB deviates from the billed per-GB rate". This is a reconciliation check, not a savings detector, and belongs with FIN-011. It fires when the effective per-GB cost differs by more than 5 % from the rate sheet after 2025-12-08. All four move to R2 (INS-104). Record the fact in RESEARCH_REGISTER as a new row.
Affects: INS-004, new INS-104; FIN-011.

### G-INS-04 · "No observed reads" is unprovable for shared tables; ACCESS_HISTORY volume is unplanned
Severity: HIGH · Type: VENDOR-FACT / GAP
Evidence: `intelligence.md` ST01: "Complete declared access evidence for30 days, no observed reads". The catalog lists ACCESS_HISTORY only as an extension candidate. VERIFIED (search snippet, docs.snowflake.com/en/user-guide/data-share-consumers, 2026-09-27): "the queries on the data share executed in the consumer account are logged and only visible to the consumer account, not the provider account." AU.AGGREGATE_ACCESS_HISTORY exists: "aggregated over time for repeated queries in one-minute intervals", 365 days, latency up to 3 h (search snippet, docs.snowflake.com/en/sql-reference/account-usage/aggregate_access_history, 2026-09-27).
Why it matters: A provider table read only by share consumers, a replicated secondary, or an Iceberg table read by an external engine appears as "no observed reads". Recommending a drop review of such a table is a high-severity false positive. Raw ACCESS_HISTORY has one row per query with nested JSON, so extracting it wholesale roughly doubles QUERY_HISTORY egress and customer warehouse cost (D-08).
Resolution: R2 (INS-104). Source-side aggregation contract: the extractor runs `LATERAL FLATTEN(BASE_OBJECTS_ACCESSED)` per UTC day and emits (account, object_id, object_domain, usage_date, read_query_count, distinct_user_hmac_count, last_read_at). Writes come from OBJECTS_MODIFIED. The source is AGGREGATE_ACCESS_HISTORY where the probe proves equivalence. This requires an ING amendment allowing "source-side aggregate" source kinds, which challenges PRD §19 "No FinOps calculations happen here" only in the sense that aggregation is not a FinOps calculation. ST01/ST02 are suppressed with SHARED_OR_EXTERNAL_READERS_POSSIBLE for any object in an outbound share (SHOW SHARES / SHARES view, TO VERIFY), a replication group, or an external/Iceberg table. Wording: "no reads observed in accounts connected to Bridge since <date>".
Affects: INS-004, new INS-104; ING-001, CON-003 (Enterprise edition + GOVERNANCE_VIEWER-type database role, TO VERIFY).

### G-INS-05 · Q04/Q05 depend on operator statistics that cannot be batch-extracted
Severity: HIGH · Type: GAP
Evidence: `intelligence.md` Q04: "missing operator counts suppresses"; Q05: "Verified join output/max(left input,right input)>10". `workloads.md`: GET_QUERY_OPERATOR_STATS "is on-demand, permission- and retention-gated … past14 days". WRK-005 owns it on demand.
Why it matters: A recurring detector that needs a per-query table function call against the customer account (one call per candidate query, warehouse cost, MONITOR grant per warehouse) is a hidden customer-side cost and a D-08 violation. It is also impossible beyond 14 days.
Resolution: Q04 in R2 uses AU.TABLE_QUERY_PRUNING_HISTORY. That view is hourly by table × query_hash × warehouse with PARTITIONS_SCANNED/PRUNED and ROWS_SCANNED/MATCHED (search snippet, docs.snowflake.com/en/sql-reference/account-usage/table_query_pruning_history, 2026-09-27; edition requirement TO VERIFY LIVE). Predicate: scan fraction = scanned/(scanned+pruned) > 0.80 and selectivity = rows_matched/rows_scanned < 0.10 in ≥ 3 hourly rows. Q05 becomes an evidence enrichment shown on the query deep dive when a user opens it (WRK-005), not a recurring detector.
Affects: INS-003, new INS-103; WRK-005, ING-001.

### G-INS-06 · SPCS utilization and scaling telemetry does not exist in Account Usage
Severity: HIGH · Type: VENDOR-FACT
Evidence: `intelligence.md` SP01 "Authorized measured CPU utilization<20%", SP03 "Observed pool capacity/active-node measure". VERIFIED (search snippet, docs.snowflake.com/en/developer-guide/snowpark-container-services/monitoring-services, 2026-09-27): compute pool metrics require "a service that uses Prometheus-compatible API to poll the metrics that the compute pool publishes", and service metrics are written to an event table only when "in the service specification, you define which metrics you want Snowflake to record".
Why it matters: Bridge is read-only (no deployed customer services), so SP01/SP03 can never be satisfied. Implementing them wastes effort, and heuristics would invent utilization from credits, which the contract forbids.
Resolution: Keep manifests for SP01/SP03 with `capability=SPCS_PLATFORM_METRICS_EVENT_TABLE` permanently SUPPRESSED(MISSING_CAPABILITY) until an ADR defines reading a customer event table (grant on the table, sanitized metric names). SP02 in R2 is redefined as "pool billed (SNOWPARK_CONTAINER_SERVICES_HISTORY CREDITS_USED > 0) for ≥ 60 min on 3 days while AU.SERVICES shows no service/job in RUNNING state on that pool" (AU.SERVICES status history availability TO VERIFY).
Affects: INS-005.

### G-INS-07 · WH04 duplicates WH01; WH05 flags free headroom
Severity: MEDIUM · Type: CONTRADICTION / OVER-ENGINEERING
Evidence: `intelligence.md` WH01 "idle/metered cost >25% for14 complete days"; WH04 "Classic idle ratio>50% with at least14 complete days". Every WH04 hit is therefore a WH01 hit on the same signal and window. WH05 "Configured max clusters>1 with measured peak active clusters below configured maximum".
Why it matters: WH04 doubles every severe idle insight, and the two join the same opportunity group anyway. Unused maximum clusters cost nothing, because clusters that never start are not billed. WH05 would therefore present a zero-cost observation as an optimization, a credibility defect in front of a platform team.
Resolution: Fold WH04 into WH01 as `severity_tier=HIGH` when the idle share is > 0.50. The WH04 ID is kept as a filter alias. This challenges the intelligence.md registry row. Redefine WH05 (R2) as "min_cluster_count > 1 with ≥ 1 cluster idle > 50 % of active cluster-hours" (billed standing capacity) or "scaling_policy=STANDARD with median cluster lifetime < 5 min" (ECONOMY review). Keep max_cluster_count only as a governance/blast-radius observation with `impact_kind=NONE`.
Affects: INS-002, new INS-106.

### G-INS-08 · The "shared monetary impact floor" is referenced but never defined
Severity: HIGH · Type: GAP
Evidence: `intelligence.md`: "All recurring detectors require … the shared monetary impact floor from the [governance contract]". `governance.md` defines only the anomaly rule "absolute impact≥max(10% of abs(median), one currency minor unit)" and "at most10 candidates per tenant". grep for "impact floor" finds no definition.
Why it matters: Each detector author would pick a floor, or none. With no floor, a 1.93 USD/month auto-suspend saving becomes an insight. That floods the inbox and destroys trust in the first-customer workshop (ONB-005).
Resolution: Config parameter `insights.impact_floor_30d` holds one Decimal per currency, default 25.00 in the tenant billing currency. It is applied to the detector's 30-day run-rate impact (`window_amount × 30 / window_days`), compared with a strict `>`, overridable per tenant and versioned via CTL-005. Detectors with `impact_kind=NONE` (Q02, Q03, PI*) are exempt but are ranked below monetary insights. Contract fixtures run with the floor at 0.00 in test config. The production default is proven by the WH02 fixture in INS-002-S08.
Affects: INS-001, all detector tasks.

### G-INS-09 · Insight and action lifecycles are conflated; the UI states contradict the contract
Severity: HIGH · Type: CONTRADICTION / AMBIGUITY
Evidence: `intelligence.md`: "Required lifecycle: Detected → Reviewed → Assigned → Planned → Implemented → Verifying → Validated, with Dismissed, Accepted Risk and Not Applicable". `pages/actions.md`: "Lifecycle: Proposed → accepted → in progress → implemented → verifying → verified / rejected". INS-006 has its own "Action … status". PRD §107 puts `status` on the action.
Why it matters: One insight can spawn several actions, for example auto-suspend and a schedule change. A single state field on the insight cannot carry two actions' Implemented dates or baselines. Three state vocabularies guarantee API/UI mismatch.
Resolution: Two state machines (INS-006-S01).
**Insight** (PostgreSQL `insight_workflow`, one per fingerprint): DETECTED, REVIEWED, ASSIGNED, DISMISSED, ACCEPTED_RISK, NOT_APPLICABLE, NO_LONGER_OBSERVED, RESOLVED.
**Action**: PLANNED, IMPLEMENTED, VERIFYING, VALIDATED, CANCELLED, REVERTED. VALIDATED carries `outcome ∈ {SAVING, INCREASE, INCONCLUSIVE}`.
The canonical 7-step display status is derived: an insight with an open action shows the most advanced action state. UI label mapping: Proposed=DETECTED, accepted=REVIEWED, in progress=PLANNED, verified=VALIDATED(outcome=SAVING), rejected=DISMISSED. This challenges `pages/actions.md`.
Affects: INS-006, INS-101.

### G-INS-10 · Fingerprint, observation identity, versioning and dismissal expiry are undefined
Severity: HIGH · Type: GAP
Evidence: `intelligence.md`: "Stable detection fingerprint prevents repeat insights on replay; a new observation appends history"; "carrying reason/actor/expiry where relevant"; "Threshold tuning creates a new detector version". INS-001 data model: "Insight fingerprint, observation ID, rule/input versions".
Why it matters: If the window or publication is in the fingerprint, the insight is duplicated daily. If the version is in it, every threshold tweak resurrects dismissed insights. If the resource name is in it, a warehouse rename creates a new insight. Without expiry, "dismissed" is permanent even if waste grows tenfold.
Resolution:
- `fingerprint = sha256("ins-fp-v1|" + tenant_id + "|" + detector_id + "|" + detector_major + "|" + account_uuid + "|" + resource_type + "|" + native_resource_id + "|" + variant)`. native_resource_id is WAREHOUSE_ID, TSM ID, (QUERY_PARAMETERIZED_HASH, hash_version), or the account for Q07. It never includes names, windows, publications, numbers or minor versions.
- `observation_id = UUIDv5(NS_INS, fingerprint + "|" + window_end_date + "|" + detector_version + "|" + sha256(sorted input_publication_ids))`.
- A minor version keeps the fingerprint and carries dismissals over. A major version creates a new fingerprint, and old insights auto-close as RESOLVED(reason=SUPERSEDED_BY_VERSION).
- Dismissal expiry: default 90 days, maximum 365. ACCEPTED_RISK requires an expiry ≤ 180 days and the FinOps Admin role. NOT_APPLICABLE has no expiry but is bound to the major version.
- A materiality re-open happens when the 30-day impact is ≥ 2 × the value at dismissal.
- NO_LONGER_OBSERVED follows 3 consecutive complete NOT_QUALIFIED evaluations. INSUFFICIENT_DATA does not count toward this. Re-qualification opens episode n+1 on the same fingerprint.
Affects: INS-001, INS-006.

### G-INS-11 · Potential-savings formulas, horizon and de-duplication are undefined
Severity: HIGH · Type: GAP
Evidence: `intelligence.md`: "Potential savings are null unless a documented counterfactual/rate/population supports a numerical estimate. Combine overlapping WH idle/suspend/consolidation candidates in one opportunity group". PRD §112 Home shows "Potential savings $31K" with no horizon. The contract gives no grouping algorithm.
Why it matters: Without a horizon, a 14-day window amount is compared with a monthly budget. Without an algorithm, "mutually exclusive opportunity sets" is implemented as ad-hoc SQL per page, so the Home and Insights totals disagree.
Resolution: Every potential is expressed as a **30-day run-rate** in native currency with `impact_kind ∈ {ESTIMATE, CEILING, EXPOSURE, OBSERVED_EXCESS, NONE}`. Formulas for the R1 detectors are in INS-002/003/004. De-duplication uses a **cost-pool tree** per (tenant, account, currency): WAREHOUSE_TOTAL(w) ⊃ {WAREHOUSE_IDLE(w), WAREHOUSE_ACTIVE(w) ⊃ QUERY_FAMILY(f,w)}; STORAGE_TABLE(t) ⊃ {TT(t), FS(t)}.
- `value(node) = min(pool_cost(node), max(max_member_potential(node), Σ value(children)))`.
- The portfolio total is Σ over roots per currency. It never crosses currencies, and null potentials count as "n without estimate", never 0.
- Fixtures: WH01 cap 60 with WH02 45 → 45. WH02 45 + Q01 30 on disjoint pools → 75. An R2 WH03 of 100 on WAREHOUSE_TOTAL → max(100, 75) = 100. EUR and USD are never summed.
Affects: INS-001, INS-101, UX-003 (Home).

### G-INS-12 · Savings verification lacks normalizers, windows, confidence method and an implementation-date source
Severity: HIGH · Type: GAP
Evidence: `intelligence.md`: "Freeze baseline version, intervention date, population, volume normalizer, rate basis, exclusion policy, horizon and overlap group"; "Expected cost = baseline cost per normalized unit × observed post-change units". None of the values is specified. `governance.md`: "No claimed confidence percentage without calibration evidence".
Recomputed fixture: baseline 200 USD / 100 executions = 2.00 USD/execution. Post period: 120 executions, observed 180. Counterfactual = 2 × 120 = 240, realized = 240 − 180 = **60**, versus the unadjusted 200 − 180 = 20. Adverse case: 240 − 260 = **−20** (not clamped). Coverage 20 of 25 post days = 80 % → VERIFYING, excluded from the verified total. Two overlapping actions → one joint group of 60, never 120. The estimate of 80 stays in the potential ledger. All confirmed.
Why it matters: The executions normalizer is wrong for idle/auto-suspend actions, because idle cost does not scale with query count. Leaving it open lets each engineer choose, so realized numbers are not comparable. A post-window chosen after seeing results is p-hacking.
Resolution: The measurement contract in INS-007-S01 fixes:
- **Normalizers**:
  - Query-family actions use EXECUTIONS.
  - Warehouse actions (auto-suspend, idle, resize, schedule) use MIX_ADJUSTED_EXECUTIONS = C_base × Σ_f n_post(f)·a_base(f) / Σ_f n_base(f)·a_base(f), where a_base is the baseline attributed credits per execution. New families use their post value. With a single family this reduces to 200 × 120/100 = 240.
  - Storage retention uses ACTIVE_GIB_DAYS.
  - Ingestion uses GIB_INGESTED.
  - Pipeline schedule uses CALENDAR_DAYS plus rows-changed as a covariate.
  - SPCS uses HOURS.
  - Cortex uses REQUESTS.
- **Windows**: baseline = 28 complete days ending the day before the intervention (minimum 14, labelled). The stabilization gap is 1 day for warehouse settings, 8 days for time-travel retention changes (TT→fail-safe transition, TO VERIFY LIVE) and 0 days for query rewrites. The post window has the same length as the baseline, in whole weeks.
- **Rate basis**: measure in native credits and price both sides with the frozen baseline effective rate (rate-neutral). Show the at-actual-rate figure separately with a RATE_CHANGE confounder.
- **Coverage**: 100 % of days FINAL per D-13. Otherwise VERIFYING; after 30 days past the post-window end, INCONCLUSIVE_COVERAGE.
- **Confidence**: moving-block bootstrap of the baseline daily unit cost (block 7 days, B = 2000, seed = first 8 bytes of sha256(measurement_id)), 5th–95th percentile, classes VERIFIED_SAVING / VERIFIED_INCREASE / INCONCLUSIVE, labelled UNCALIBRATED.
- **Implemented date**: HUMAN_ATTESTED or CONFIG_DETECTED (INS-102 SCD2 bracket). A discrepancy > 24 h needs confirmation, and the ambiguous bracket is excluded from both windows.
Affects: INS-006, INS-007.

### G-INS-13 · Baseline-freeze timing contradicts between PRD and task
Severity: MEDIUM · Type: CONTRADICTION
Evidence: PRD §108 flow: "action implemented ↓ baseline model frozen". INS-006: "Freeze measurement population and baseline before intervention". Failure list: "Action performed before baseline".
Why it matters: Customers often make a change and then tell the tool. A strict before-rule rejects legitimate actions, while an unconstrained after-rule allows cherry-picked baseline windows.
Resolution: A freeze is allowed at any time before the measurement job starts, if `baseline_window_end ≤ implemented_at` (or before the detected bracket start) and inputs are pinned to publications as of the freeze. A freeze after IMPLEMENTED must use the default window of 28 days immediately before implemented_at. Custom windows are allowed only while PLANNED (pre-registration). This resolves both texts.
Affects: INS-006.

### G-INS-14 · D-11 hot tier vs. measurement and WH02 horizons
Severity: MEDIUM · Type: RISK
Evidence: D-11: "query-level detail hot for 90 days; query-family × day aggregates … 400 days". The INS-007 failure list includes "post-period restatement" and the UI has "request remeasurement".
Why it matters: A 28 + 1 + 28-day study re-measured after a restatement at day 95 would need query-level rows that are already purged.
Resolution: All measurement and Q01/Q02/Q03 features read the family × day aggregate (extend the D-11 aggregate with attributed credits, spill counts/bytes and a dominant identity tuple). Query-level data is used only for WH02 busy-interval simulation (≤ 90 days, which is enough for 14-day windows) and for evidence samples.
Affects: INS-003, INS-007; DBT (D-11 aggregate owner).

### G-INS-15 · Query-family identity and counting hazards
Severity: MEDIUM · Type: RISK / VENDOR-FACT
Evidence: The catalog QAH row says "very short queries can be absent". The INS-003 oracle: "missing change-volume evidence suppresses". AU.AGGREGATE_QUERY_HISTORY exists (search result, docs.snowflake.com/en/sql-reference/account-usage/aggregate_query_history, 2026-09-27). Whether repeated short hybrid-table queries are omitted from QUERY_HISTORY is TO VERIFY LIVE.
Why it matters: Unit cost computed over attributed executions only is biased upward when short executions lack QAH rows. Frequency may be undercounted for Unistore workloads. Bridge's own extraction queries (D-08 QUERY_TAG `bridge_finops:*`) would show up as customer query families.
Resolution: Q01 requires attribution coverage (executions with a QAH row / executions) ≥ 0.90 in both cohorts, otherwise SUPPRESSED(ATTRIBUTION_COVERAGE). Q02 is suppressed for accounts where the probe finds AGGREGATE_QUERY_HISTORY rows (label). Families whose QUERY_TAG starts with `bridge_finops:` are excluded from Q01/Q02/Q03, and the Bridge warehouse is labelled "Bridge overhead" in WH01.
Affects: INS-003.

### G-INS-16 · Q07 must use billed cloud services, not gross
Severity: MEDIUM · Type: GAP
Evidence: `intelligence.md` Q07: "Service-level signed cloud usage exceeds robust monitor policy". The catalog METERING_DAILY_HISTORY row: "Signed adjustment is retained"; METERING_HISTORY: "Gross usage excludes later cloud-services adjustment".
Why it matters: Gross cloud services under the daily adjustment has zero billed cost. An anomaly on gross fires with no financial impact.
Resolution: Signal: `billed_cs_d = Σ_service (CREDITS_USED_CLOUD_SERVICES + CREDITS_ADJUSTMENT_CLOUD_SERVICES)` per account per UTC day (adjustment ≤ 0), passed to the GOV-005 anomaly function unchanged. Gross is shown as evidence only. Fixtures are in INS-003-S07.
Affects: INS-003.

### G-INS-17 · Over-serialized dependencies
Severity: HIGH · Type: RISK
Evidence: task-index: INS-006 deps `['INS-002','INS-003','INS-004','INS-005','CTL-004']`; INS-001 deps include `WRK-005`; INS-003 deps `WRK-002, WRK-004`; INS-004 deps `FIN-011, FIN-012`; INS-002 deps `UX-005`.
Why it matters: The workflow and savings engine are detector-agnostic but wait for the Cortex/SPCS detectors (INS-005), which wait for FIN-018/019 and UX-007. Q01 needs FIN-003, not dbt invocation graphs. Most of M8 is serial for no data reason.
Resolution: INS-001: −WRK-005 (moves to INS-103), +CTL-004, +CTL-005. INS-002: −UX-005 (drilldown link only), +FIN-003, +INS-102. INS-003: −WRK-002, −WRK-004 (to INS-103), +FIN-003, +ING-001 (projection). INS-004: −FIN-011, −FIN-012 (to INS-104). INS-006: −INS-003, −INS-004, −INS-005, +INS-101 (keep INS-002 for the E2E fixture). INS-007: +INS-102 (soft; config-detected implementation). INS-005 becomes R2 and leaves the R1 path.
Affects: all INS tasks.

### G-INS-18 · No task owns the insight read API, inbox or deep dive
Severity: MEDIUM · Type: GAP
Evidence: INS-002..005 all list `apps/web/insights` as output. INS-001: "accepted results feed semantic APIs". No `GET /v1/insights` is specified anywhere (grep). PRD §105 requires nine deep-dive sections.
Why it matters: Four teams would build four inboxes. Empty-state "evaluated scope and why no candidate qualifies" needs a detector-evaluation summary API that nobody owns.
Resolution: New task **INS-101** (R1): read API, deep-dive payload, evaluation summary, portfolio totals for Home, and the UI.
Affects: INS-002..005, UX-003.

### G-INS-19 · The retrospective false-positive review has no owner or metric
Severity: MEDIUM · Type: GAP
Evidence: `intelligence.md`: "must pass the same negative fixtures and retrospective false-positive review".
Resolution: New task **INS-105** (R1): a per-detector-version precision register fed by DISMISSED(reason=FALSE_POSITIVE). The release gate is a retrospective review of every candidate on at least one real account (Bridge's own Snowflake account or a design partner, owner question Q7) with documented verdicts. The enablement rule is precision ≥ 0.8 on ≥ 10 reviewed candidates, or explicit owner acceptance.
Affects: INS-002..004.

### G-INS-20 · Eligibility timing for first value
Severity: MEDIUM · Type: RISK
Evidence: The catalog TSM row: "No historical event-time predicate exists … Daily snapshot from enrollment". ST03/ST04 require 14 days. ONB-005: "review a supported actionable insight or documented no-candidate result".
Why it matters: On workshop day, storage detectors cannot run, and without an explicit state that reads as "no findings".
Resolution: The detector evaluation summary carries `eligible_on` (enrollment date + 14 snapshots). WH01/WH02/Q01/Q02/Q03/Q07 are backfill-eligible on day 1 (WMH/QH/QAH/METERING_DAILY have 365 days of history). The first-value workshop is scheduled ≥ 15 days after enrollment, or it states that storage detectors are pending.
Affects: INS-004, INS-101; ONB-005.

### G-INS-21 · Route naming mismatch
Severity: LOW · Type: CONTRADICTION
Evidence: INS-002 UX "Entry point | /optimize/insights" vs `pages/insights.md` "Route: `/insights`"; the same applies to actions and savings.
Resolution: Use `/insights`, `/insights/:id`, `/actions`, `/actions/:id`, `/savings`, `/savings/:measurementId` (UI spec wins; the navigation group is "Optimize").
Affects: INS-101, INS-006, INS-007.

## 3. Contract-first artifacts to author before coding

| Artifact | Exact content required | Produced by |
|---|---|---|
| Source projection change request | The 16 QUERY_HISTORY columns of G-INS-01; R2 adapters (TABLE_QUERY_PRUNING_HISTORY, WAREHOUSE_EVENTS_HISTORY, WAREHOUSE_LOAD_HISTORY, AU.TABLES, COPY_HISTORY, ACCESS_HISTORY aggregate); per-detector capability keys | INS-001-S02 → ING-001, CON-005 |
| `data/contracts/detector_manifest.schema.json` + `services/intelligence/detectors.v1.yaml` | Per detector: id, semver, family, release (R1/R2/GATED), required_inputs[{dataset, column, capability_key}], min_history_days, windows, cost_pool_kind, impact_kind, potential_method, default thresholds, tenant-overridable params | INS-001-S01/S02 |
| `data/contracts/insight_observation.schema.json` | tenant_id, observation_id, fingerprint, detector_id, detector_version, window_start/end, baseline/current windows, input_publication_ids (map), feature_snapshot_hash, eligibility_status {QUALIFIED, NOT_QUALIFIED, SUPPRESSED, INSUFFICIENT_DATA}, reason_code, metrics[{name, value(decimal string), unit}], impact_amount_30d, currency, impact_kind, potential_30d (nullable), potential_method, cost_pool_key, opportunity_group_key, sample_count, confidence_method, severity, severity_tier, evidence_ids[], resource {account_uuid, type, native_id, name_at_observation}, revision_id, as_of | INS-001-S01 |
| Reason-code enum | INSUFFICIENT_HISTORY, INCOMPLETE_COVERAGE, MISSING_CAPABILITY:<key>, ADAPTIVE_UNSUPPORTED, CURRENCY_INCOMPATIBLE, BELOW_IMPACT_FLOOR, ATTRIBUTION_COVERAGE, WORKLOAD_IDENTITY_CHANGED, CALIBRATION_FAILED, NOT_ACTIONABLE_DROPPED, SHARED_OR_EXTERNAL_READERS_POSSIBLE, EQUAL_AT_THRESHOLD | INS-001-S01 |
| Snowflake DDL (insert-only, D-05) | `insight_observation`, `insight_evidence` (≤ 200 rows/observation), `insight_detector_evaluation` (tenant, detector, version, window, evaluated, qualified, suppressed_by_reason, eligible_on), `insight_opportunity_group`, `action_baseline`, `savings_measurement`, `savings_measurement_day` | INS-001-S08, INS-006-S06, INS-007-S03 |
| PostgreSQL DDL | `insight_workflow` (tenant_id, insight_id, fingerprint UNIQUE(tenant_id, fingerprint), status, revision, owner_user_id, episode_no, reopen_count, dismissal_reason, dismissal_expires_at, impact_at_dismissal, last_observation_id), `insight_transition`, `action` (…, action_type, status, outcome, revision, implemented_at, implemented_at_source, baseline_id, baseline_hash), `action_transition`, `action_comment`; FORCE RLS; composite tenant FKs | INS-006-S02 |
| Lifecycle specs | `data/contracts/insight-lifecycle.json`, `action-lifecycle.json`: every transition with actor (user role / system), guard, required fields, error code; UI label mapping (G-INS-09) | INS-006-S01 |
| Measurement contract | `data/contracts/savings-measurement.json`: normalizer catalog per action_type, windows, stabilization, coverage, confidence method, confounder codes, overlap rule, horizon rule | INS-007-S01 |
| Config catalog | `insights.impact_floor_30d` = 25.00/currency; `wh02.target_auto_suspend_s` = 60; `q01.min_executions` = 10; `q01.min_attribution_coverage` = 0.90; `q02.identity_dominance` = 0.80; `dismiss.default_days` = 90, max 365; `accepted_risk.max_days` = 180; `no_longer_observed_after` = 3; `savings.baseline_days` = 28 (min 14); `savings.max_wait_days` = 30; `bootstrap.B` = 2000, block 7; `confounder.volume_shift` = 0.50; `confounder.mix_shift` = 0.20 | INS-001-S04, INS-007-S01 |
| `config/warehouse_credit_rates.v1.json` | credits/hour by (size, warehouse_type, generation); XS = 1 … 6XL = 512 for standard Gen1; other types TO VERIFY LIVE; unknown → suppress numeric estimate | INS-002-S06 |
| OpenAPI | `GET /v1/insights`, `GET /v1/insights/{id}`, `GET /v1/insights/{id}/evidence`, `GET /v1/insights/summary`, `GET /v1/detectors/evaluations`, `POST /v1/insights/{id}/transitions`, `POST /v1/actions`, `POST /v1/actions/{id}/transitions`, `POST /v1/actions/{id}/baseline:freeze`, `POST /v1/actions/{id}/measurements`, `GET /v1/savings`, `GET /v1/savings/{measurementId}` | INS-101, INS-006, INS-007 |
| Error codes | INS_STALE_REVISION 409, INS_DUPLICATE_OPEN_ACTION 409, INS_BASELINE_OVERLAPS_INTERVENTION 409, INS_VALIDATION_REQUIRES_MEASUREMENT 403, INS_OWNER_OUT_OF_SCOPE 403, INS_REASON_REQUIRED 422, INS_EXPIRY_OUT_OF_RANGE 422, INS_BASELINE_NOT_FROZEN 409 | INS-006-S03 |
| Events | `insights.published{tenant_id, publication_id, detector_family}`, `insight.transitioned`, `action.transitioned`, `savings.measured{measurement_id, revision, outcome}` (CTL-004 outbox) | INS-001-S11, INS-006, INS-007 |

## 4. Revised production backlog

### INS-001 — Build insight registry and evidence publication
Release: R1 · Estimate: 40–60 h · Risk: M · Decisions: D-05, D-06, D-10, D-12, D-13 · Closes: G-INS-01 (manifest gate), G-INS-08, G-INS-10, G-INS-11
Dependency changes: `−WRK-005` (only needed by R2 query/pipeline detectors → INS-103); `+CTL-004` (outbox link); `+CTL-005` (tenant-overridable detector parameters published as config versions).
| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| INS-001-S01 | Author the observation, evidence, detector-evaluation JSON Schemas and the reason-code enum (§3); money as decimal strings, units mandatory | `data/contracts/insight_observation.schema.json`, `insight_evidence.schema.json`, `detector_evaluation.schema.json` | Schema tests reject: a missing unit, a float money value, an unknown reason code, a potential without potential_method | 3 |
| INS-001-S02 | Implement the detector manifest loader; cross-check every `required_inputs` column against the ING-001 source-registry projection JSON | `services/intelligence/registry.py`, `detectors.v1.yaml` (41 rows, release flags) | A manifest requiring `QUERY_HISTORY.BYTES_SPILLED_TO_REMOTE_STORAGE` fails CI while the column is absent from the projection; all 41 IDs are present with the release flag of §2 | 3 |
| INS-001-S03 | Capability resolver per (tenant, account): combine CON-005 probe status + source activation; emit a SUPPRESSED(MISSING_CAPABILITY:<key>) evaluation row instead of silence | `services/intelligence/capabilities.py` | An account with QAH DENIED yields a Q01 evaluation row `suppressed_by_reason={"MISSING_CAPABILITY:QAH":n}`; no Q01 observations | 3 |
| INS-001-S04 | Money utilities: 30-day run-rate `amount×30/window_days` (Decimal, context precision 38), `impact_floor(currency, tenant)` from config, strict `>` comparison, presentation rounding HALF_EVEN only at the API edge | `services/intelligence/money.py` | 60 over 14 d → 128.5714…; floor 25.00 with run-rate exactly 25.00 → BELOW_IMPACT_FLOOR; EUR floor is used for EUR, never converted | 2 |
| INS-001-S05 | Fingerprint + observation_id per G-INS-10 | `services/intelligence/identity.py` | Tests: warehouse rename keeps fp; drop/recreate (new WAREHOUSE_ID) → new fp; minor bump keeps fp, major changes it; tenants A/B with identical native IDs → different fp; same inputs → same observation_id | 3 |
| INS-001-S06 | Pure engine runner `run(context, feature_snapshot)`: logical `as_of` from context, no wall clock or unseeded randomness (lint rule bans `datetime.now`, `random`, `uuid4` in `detectors/`), canonical sorted-key JSON output | `services/intelligence/engine.py`, lint config | 10 identical runs → byte-identical output and one logical observation per fingerprint (oracle) | 3 |
| INS-001-S07 | Feature snapshot loader: read accepted feature marts pinned to the publication set via the central WIF identity, Arrow batches per tenant; 15-min family timeout → FAILED with the last accepted publication untouched | `services/intelligence/features.py` | Timeout test leaves the prior `insight_observation` pointer unchanged; the loader refuses an unaccepted publication ID | 3 |
| INS-001-S08 | Publish observation/evidence/evaluation batches via the ING-005 batch-commit contract into insert-only revisioned tables (D-05); per-tenant pointer advance (D-06); reject on schema-hash drift | dbt models `data/dbt/models/marts/insights/*`, Snowflake DDL | Failing tenant B partition does not block tenant A pointer; a batch with an extra column is rejected with SCHEMA_DRIFT | 4 |
| INS-001-S09 | Evidence bounding + privacy: ≤ 200 rows/observation ordered by cost desc then stable key; query evidence = sanitized query IDs/param hash only (ADR-009); user identifiers as D-10 HMAC | `services/intelligence/evidence.py` | 10,000-candidate evidence fixture is truncated to 200 with `truncated_count=9800`; no plaintext USER_NAME in any evidence row (grep test) | 2 |
| INS-001-S10 | Cost-pool tree + opportunity grouping DP per (tenant, account, currency) per G-INS-11 | `services/intelligence/opportunity.py`, `insight_opportunity_group` | Fixtures 60/45→45; 45+30→75; WH03 100 vs 75→100; USD+EUR members → two groups; null potentials counted, not summed | 4 |
| INS-001-S11 | Outbox link: `insights.published` after acceptance; the PG consumer upserts `insight_workflow` by (tenant, fingerprint); a retracted publication (ADR-011) reverts `last_observation_id` or sets STALE_EVIDENCE | `apps/api/insights/consumer.py` | Replaying the same event 3× → one row, same revision; a retraction test restores the prior observation reference | 3 |
| INS-001-S12 | Isolation tests: engine for tenant A with B rows in the feature mart; consumer event naming a publication of tenant B | `tests/spec/INS-001/isolation_test.py` | Zero B rows in A outputs; foreign-publication event rejected and audited (SEC-008 event `INS_FOREIGN_PUBLICATION`) | 2 |
| INS-001-S13 | Observability: `ins_detector_eval_total{detector,outcome}`, `ins_engine_duration_seconds{family}`, `ins_publication_lag_seconds`; alarm: same family FAILED on 2 consecutive daily runs | OTel instrumentation, alarm definition | Synthetic failure fires the alarm in staging; metric labels contain no tenant IDs | 2 |
| INS-001-S14 | Runbook: rerun same publication (idempotent), disable a detector for one tenant, retract a bad publication; evidence bundle | `docs/runbooks/insights-engine.md`, `docs/evidence/INS-001/<commit>/` | The runbook drill is executed once in staging with recorded outputs | 3 |
Task acceptance:
- [ ] 10 identical evaluations → 1 insight, 1 observation (byte-identical outputs).
- [ ] Unavailable baseline or capability → SUPPRESSED with reason; numeric potential null.
- [ ] Portfolio grouping never exceeds the pool cap; no cross-currency totals.
- [ ] A manifest referencing an unprojected column fails CI.
- [ ] Tenant B data never appears in tenant A observations or workflow rows.

### INS-002 — Implement warehouse optimization detectors (R1: WH01 incl. WH04 tier, WH02)
Release: R1 · Estimate: 38–56 h · Risk: M · Decisions: D-08, D-11, D-13 · Closes: G-INS-02 (consumer side), G-INS-07
Dependency changes: `+FIN-003` (classic idle/attribution ledgers are the actual input), `+INS-102` (warehouse config), `−UX-005` (only a drilldown link; not blocking). Keep `FIN-004` (Adaptive flag). WH03/WH05–WH08 move to INS-106.
| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| INS-002-S01 | Build fixtures: classic 14 d (metered 200, attributed 140, idle 60 USD @ 2 USD/credit), equality (idle exactly 25 %), Adaptive (attributed null), 335/336 hours, attributed>used hours, gap sets (below), config absent, multi-cluster without CLUSTER_NUMBER | `tests/spec/INS-002/fixtures/*.parquet` + expected JSON | Fixture checksums recorded; expected outputs reviewed | 3 |
| INS-002-S02 | dbt `fct_ins_wh_hourly`: idle_credits = max(0, CREDITS_USED_COMPUTE − CREDITS_ATTRIBUTED_COMPUTE_QUERIES); residual_flag when attributed > used; is_adaptive; rate/currency from FIN-002; hour completeness | `data/dbt/models/marts/insights/features/fct_ins_wh_hourly.sql` | Σ idle equals `ledger_warehouse_idle` for the fixture (60 USD); negative idle never emitted | 3 |
| INS-002-S03 | WH01: share = Σidle/Σused over 336 complete hours; QUALIFIED iff share > 0.25; tier HIGH iff > 0.50 (WH04 alias); impact_kind CEILING = idle cost; suppress Adaptive (ADAPTIVE_UNSUPPORTED) and incomplete; label BRIDGE_FINOPS_WH as "Bridge overhead" (D-08) | `services/intelligence/detectors/wh01_idle.py` | 60/200 → QUALIFIED MEDIUM, cap 60, run-rate 128.57; 50/200 → NOT_QUALIFIED (EQUAL_AT_THRESHOLD); 120/200 → HIGH; Adaptive → SUPPRESSED | 3 |
| INS-002-S04 | WH01 false-positive guard: when config AUTO_SUSPEND ≤ 60 s, set severity LOW and use recommendation template "idle dominated by resume minimum/short bursts; review consolidation" | same module + template | Fixture of 5-s jobs every 10 min with AS = 60 → QUALIFIED LOW with that template; potential 0 via WH02 | 2 |
| INS-002-S05 | dbt `fct_ins_wh_busy_intervals`: union of [START_TIME, END_TIME] per (warehouse_id, cluster_number) for queries with EXECUTION_TIME > 0 and non-null WAREHOUSE_SIZE; emit gaps with next busy-period length; hot tier ≤ 90 d (D-11) | `fct_ins_wh_busy_intervals.sql` | Overlapping queries merged; a query spanning 00:00 UTC is one interval; result-cache hits (EXECUTION_TIME = 0) excluded | 4 |
| INS-002-S06 | WH02 simulation: per gap g, t_cur = min(g, AS_cur) (AS disabled → g), t_tgt = min(g, AS_tgt), penalty = [AS_tgt < g ≤ AS_cur] × max(0, 60 − b_next) s; saving_s = t_cur − t_tgt − penalty; credits = saving_s × k(size, type)/3600; AS_cur via as-of join to `dim_warehouse_config`; potential_30d = min(WH01 cap, Σ) × rate × 30/14 | `detectors/wh02_autosuspend.py`, `config/warehouse_credit_rates.v1.json` | Fixture: MEDIUM (4 cr/h), AS 600 → 60, 3 gaps/day × 14 d of 600 s, b_next ≥ 60 s: 42 × 540 s × 4/3600 = 25.20 cr → 50.40 USD/14 d → 108.00/30 d; with b_next = 20 s: 42 × 500 s × 4/3600 = 23.333… cr → 46.67 USD | 4 |
| INS-002-S07 | Calibration guard: modeled (busy + tail) credits vs WMH CREDITS_USED_COMPUTE per warehouse-day; relative error > 10 % → numeric potential null, reason CALIBRATION_FAILED; unknown size/type/generation → null | `detectors/wh02_calibration.py` | Fixture with hidden second cluster (no CLUSTER_NUMBER) fails calibration → WH01 ceiling only | 3 |
| INS-002-S08 | WH02 predicate + tests: QUALIFIED iff AS_cur > 300 or disabled, ≥ 3 gaps ≥ AS_tgt with the warehouse running, and run-rate > floor | tests | AS = 300 → NOT_QUALIFIED; AS disabled → QUALIFIED with t_cur = g; config absent → SUPPRESSED(MISSING_CAPABILITY:WAREHOUSE_CONFIG); contract fixture "three 600 s gaps" (XS: 3 × 540 s × 1/3600 = 0.45 cr = 0.90 USD/14 d = 1.93 USD/30 d) passes with test floor 0.00 and is BELOW_IMPACT_FLOOR at production floor 25.00 | 3 |
| INS-002-S09 | Grouping: WH01 and WH02 → pool WAREHOUSE_IDLE(w); group value = min(cap, WH02) | opportunity registration | Oracle "metered 200/query 140/idle 60 allows at most 60" holds for any WH02 value (property test with random gaps) | 2 |
| INS-002-S10 | Deterministic recommendation text templates (display only, e.g. "ALTER WAREHOUSE <quoted name> SET AUTO_SUSPEND = 60" as copyable text with a rollback line); architecture test proves `services/intelligence` imports no Snowflake write path | `detectors/templates/wh.v1.json`, import-lint rule | Lint fails if any detector module imports the connector cursor; texts are escaped (warehouse name `"x; DROP"` rendered quoted) | 2 |
| INS-002-S11 | Evidence payload: top 20 idle hours, ≤ 50 gap samples, config snapshot ID + valid_from; deep-dive contract fields | `detectors/wh_evidence.py` | Payload validates against the evidence schema; every sample's timestamps are UTC ISO-8601 | 2 |
| INS-002-S12 | Isolation: A-reader limited to account A1 sees no WH insights for A2 (through INS-101 serving path); foreign warehouse UUID in `/v1/insights?resource=` → empty/404 | `tests/spec/INS-002/authz_test.py` | Scoped 404 without counts; audit event recorded | 2 |
| INS-002-S13 | Observability + runbook: `ins_wh02_calibration_failed_total`, `ins_wh02_config_unknown_total`; runbook "new warehouse generation/type → update credit table → detector minor version" | runbook section | Staging run shows metrics; runbook reviewed | 2 |
| INS-002-S14 | Staging evidence on published synthetic Snowflake fixtures; replay determinism; no customer mutation (query log shows only SELECT/SHOW) | `docs/evidence/INS-002/<commit>/` | Evidence manifest complete | 3 |
Task acceptance:
- [ ] Idle potential never exceeds WMH idle cost for the same window and warehouse.
- [ ] No idle estimate for Adaptive warehouses.
- [ ] WH02 numeric estimate only when config is known and calibration is within 10 %.
- [ ] The 42-gap MEDIUM fixture yields exactly 50.40 USD (window) and 108.00 USD (30 d).
- [ ] WH04 never appears as a separate insight from WH01 for the same warehouse.

### INS-003 — Implement query optimization detectors (R1: Q01, Q02, Q03, Q07)
Release: R1 · Estimate: 34–50 h · Risk: M · Decisions: D-10, D-11, D-08 · Closes: G-INS-01 (Q columns), G-INS-14, G-INS-15, G-INS-16
Dependency changes: `−WRK-002`, `−WRK-004` (only PL detectors need them → INS-103); `+FIN-003`; `+ING-001` (projection must include hash version + spill columns before activation). Q04–Q06, Q08, PL01–PL05 → INS-103.
| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| INS-003-S01 | Fixtures: family 10 runs@2 → 20@3; 20 % equality; attribution coverage 0.85; hash-version change; frequency 10→20/day and 10→15/day; identity shift; 3 × 1 GiB remote spill vs local-only; cloud services MAD=0 (5.0→6.5) and gross-absorbed case; Bridge-tagged family | `tests/spec/INS-003/fixtures/` | Expected JSON reviewed | 3 |
| INS-003-S02 | dbt `fct_ins_query_family_day` (extends the D-11 aggregate): (tenant, account, param_hash, hash_version, usage_date, warehouse_id) → executions_total, executions_success, executions_attributed, attributed_credits (+QAS), cost, spill_remote_exec_count, spill_remote_bytes, identity tuple counts (user_hmac, role, warehouse); Adaptive credits from QMH summed across hours | `fct_ins_query_family_day.sql` | Row count = distinct family-days; cost reconciles to `ledger_query_compute` for the fixture | 4 |
| INS-003-S03 | Q01: cohorts B = [D−27, D−14], C = [D−13, D]; u = cost/attributed executions; QUALIFIED iff n_B, n_C ≥ 10, coverage ≥ 0.90 in both, u_C/u_B − 1 > 0.20; unit_effect = (u_C − u_B)·n_C; volume_effect = (n_C − n_B)·u_B; assert cost_C − cost_B = unit + volume; potential_30d = unit_effect × 30/14 (ESTIMATE "if unit cost returns to baseline") | `detectors/q01_cost_regression.py` | Fixture: unit 20, volume 20, total Δ 40 = 60 − 20; +20 % exactly → NOT_QUALIFIED; coverage 0.85 → SUPPRESSED(ATTRIBUTION_COVERAGE) | 3 |
| INS-003-S04 | Q01 confounder evidence: warehouse-size mix per cohort, warehouse move, hash-version change (families with different versions are never compared) | same module | Hash-version fixture yields no Q01 observation and no "new family" insight; size-mix change shown as evidence | 2 |
| INS-003-S05 | Q02: executions/day C vs B; QUALIFIED iff ratio > 1.5, n_B ≥ 10, dominant identity tuple ≥ 0.80 of executions in both cohorts; impact OBSERVED_EXCESS = volume_effect; potential null | `detectors/q02_frequency.py` | 10→20/day QUALIFIED (+100 %); 10→15 NOT (equality); identity shift → SUPPRESSED(WORKLOAD_IDENTITY_CHANGED) | 3 |
| INS-003-S06 | Q03: ≥ 3 executions in C with BYTES_SPILLED_TO_REMOTE_STORAGE > 0 and family attributed cost run-rate > floor; impact EXPOSURE = attributed cost of spilling executions; potential null; recommendation template (size test or rewrite, no credit conversion) | `detectors/q03_spill.py` | 3 × 1 GiB remote → QUALIFIED; local-only → NOT; 2 executions → NOT; below floor → BELOW_IMPACT_FLOOR | 3 |
| INS-003-S07 | Q07: dbt `fct_ins_cloud_services_daily` (gross, adjustment, billed per account-day) + GOV-005 anomaly call (28-d baseline, z ≥ 3.5 & impact ≥ max(10 % median, minor unit); MAD=0 → ABSOLUTE_DEVIATION ≥ max(20 % median, minor unit)) on billed | `fct_ins_cloud_services_daily.sql`, `detectors/q07_cloud_services.py` | 5.0→6.5 billed flags (1.5 ≥ 1.0); gross 5→8 with billed flat → no flag; missing day → INSUFFICIENT_DATA | 3 |
| INS-003-S08 | Q07 contributors (only when QH CREDITS_USED_CLOUD_SERVICES is projected): top 10 families by gross CS as explanatory evidence; never allocate adjustment per query | same module | Without the column, the deep dive shows "contributors unavailable" (not zero) | 2 |
| INS-003-S09 | Exclusions + grouping: exclude `bridge_finops:` tagged families; Q01 pool QUERY_FAMILY(f, w); Q02/Q03 on the same family join its group with null potential | opportunity registration | Bridge-tagged fixture produces no insight; Q01+Q02 same family → one group | 2 |
| INS-003-S10 | Privacy of evidence: show sanitized text only if SANITIZED text exists and the viewer holds query-text permission (security.md); otherwise param hash + sample query IDs | `detectors/q_evidence.py` + serving check | Viewer without SQL permission gets no text field (API contract test) | 2 |
| INS-003-S11 | Aggregated-query hazard: CON-005 probe flag for AGGREGATE_QUERY_HISTORY presence → Q02 SUPPRESSED(MISSING_CAPABILITY:COMPLETE_QUERY_COUNTS) on those accounts (TO VERIFY LIVE semantics) | capability key | Flagged account yields suppression rows, not observations | 2 |
| INS-003-S12 | Isolation, observability (`ins_q01_suppressed_total{reason}`), runbook, staging evidence | tests, runbook, `docs/evidence/INS-003/` | Foreign tenant family hash in a request → 404; evidence complete | 5 |
Task acceptance:
- [ ] Q01 decomposition identity holds on every qualifying family.
- [ ] No Q01/Q02 comparison across hash versions.
- [ ] Q07 never flags when billed cloud services are flat.
- [ ] Spill is never converted to credits.
- [ ] Bridge's own queries are never presented as customer optimization targets.

### INS-004 — Implement storage optimization detectors (R1: ST03, ST04)
Release: R1 · Estimate: 20–30 h · Risk: L · Decisions: D-13 · Closes: G-INS-20
Dependency changes: `−FIN-011`, `−FIN-012` (Snowpipe detectors are R2 and non-monetary → INS-104). Keep `FIN-006`. ST01/ST02/ST05/PI* → INS-104.
| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| INS-004-S01 | Fixtures: 14 daily TSM snapshots with TT 4 TiB of 10 TiB (40 %); exactly 30 %; 13 snapshots; dropped table; clone with RETAINED_FOR_CLONE_BYTES; zero denominator | `tests/spec/INS-004/fixtures/` | Reviewed expected JSON | 2 |
| INS-004-S02 | dbt `fct_ins_table_storage_daily` from daily TSM snapshots (captured_at UTC date): bytes per class, table_dropped, clone_group_id, storage rate per TiB-month from FIN-006 | `fct_ins_table_storage_daily.sql` | Snapshot gaps are explicit rows with `complete=false` | 3 |
| INS-004-S03 | ST03: tt_frac_s = TT/(ACTIVE+TT+FS+RFC) on each of 14 consecutive complete snapshots; QUALIFIED iff every value > 0.30 and exposure run-rate > floor; impact EXPOSURE = mean TT TiB × rate; potential null (R1) | `detectors/st03_time_travel.py` | 40 % → QUALIFIED, exposure 4 × 23.00 = 92.00 USD/30 d (fixture rate); 30 % → NOT; 13 snapshots → INSUFFICIENT_HISTORY with `eligible_on` | 3 |
| INS-004-S04 | ST04: same with FAILSAFE_BYTES; recommendation template "review whether data can be transient (recreate required, no fail-safe recovery)"; no "disable fail-safe" wording; potential null | `detectors/st04_failsafe.py` | Template lint forbids the phrases "disable fail-safe" and "immediate"; fixture 40/100 → QUALIFIED | 2 |
| INS-004-S05 | Clone/dropped handling: RFC bytes counted once at the owner; dropped tables → evaluation reason NOT_ACTIONABLE_DROPPED (bytes shown in the storage view, not as an insight) | same modules | Clone fixture total bytes = owner physical bytes; dropped table produces no insight | 2 |
| INS-004-S06 | Enrollment clock: `insight_detector_evaluation.eligible_on = first_snapshot_date + 13 d` when snapshots < 14 | evaluation summary | API shows "Storage detectors eligible on 2026-10-12" for a 2026-09-29 enrollment | 2 |
| INS-004-S07 | Opportunity pools STORAGE_TABLE(t) ⊃ {TT(t), FS(t)}; R2 hook: manifest param for AU.TABLES RETENTION_TIME estimate `TT×(1 − R_tgt/R_cur)` disabled | pool registration | ST03 + ST04 on one table → one group, potential null, exposure shown separately | 1 |
| INS-004-S08 | Isolation (table IDs of tenant B), observability, runbook, staging evidence | tests, `docs/evidence/INS-004/` | Evidence complete | 5 |
Task acceptance:
- [ ] Missing snapshots never produce certainty; the eligible date is shown.
- [ ] Clone-retained bytes are counted once.
- [ ] No immediate-reclamation promise in any text.
- [ ] Exposure uses the FIN-006 storage rate in native currency.

### INS-005 — Implement Cortex and container optimization detectors
Release: R2 (AI01/AI04 → R1 only if D-20 reports Cortex spend at the first customer) · Estimate: 36–54 h · Risk: H · Decisions: D-10, D-20 · Closes: G-INS-06
Dependency changes: none added; SP01/SP03 capability-gated; AI02/AI07 need the new customer-input contracts in S02.
| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| INS-005-S01 | Finalize input grain per Cortex view (request, token, model, user fields) from the FIN-018 activation evidence; update manifests | manifest rows AI01–AI07 | Every AI manifest column exists in the FIN-018 verified projection | 3 |
| INS-005-S02 | Customer-input contracts: `business_transaction_daily` (AI07/SP04 denominator) and `model_quality_evaluation` (AI02), uploaded via API with provenance/approval; absent → SUPPRESSED | `data/contracts/customer_denominator.schema.json` | Upload validated; no upload → null impact (oracle) | 4 |
| INS-005-S03 | AI01: GOV-005 anomaly on daily spend per (service, model) from the effective-dated authority layer (no old/new UNION) | `detectors/ai01.py` | A retired source produces no false drop (fixture) | 3 |
| INS-005-S04 | AI03: tokens/request, rise > 25 %, null/zero requests → suppress | `detectors/ai03.py` | 1000/10 = 100; 100→150 QUALIFIED; null count → SUPPRESSED | 3 |
| INS-005-S05 | AI04: top user HMAC share > 50 % over 7 complete days + floor; wording "concentration", resolved name only for authorized viewers (D-10) | `detectors/ai04.py` | 60/100 QUALIFIED; text contains no "abuse" | 3 |
| INS-005-S06 | AI05/AI06: parent-inclusive agent spend anomaly; search serving vs refresh components separated | `detectors/ai05_06.py` | Parent 10/child 4 stays 10 in both cohorts | 4 |
| INS-005-S07 | AI02/AI07 gated detectors using S02 inputs | `detectors/ai02_07.py` | 200/100 → 300/100 = +50 % with an explicit denominator; request count never substituted | 3 |
| INS-005-S08 | SP02 redefined (billed ≥ 60 min on 3 days with no RUNNING service/job per AU.SERVICES; TO VERIFY status history) | `detectors/sp02.py` | Pool charge 8 across two apps stays 8; unknown service state → SUPPRESSED | 4 |
| INS-005-S09 | SP04 app cost per approved unit (S02) with pool/app dedup | `detectors/sp04.py` | No denominator → spend-change evidence only | 3 |
| INS-005-S10 | SP01/SP03 manifests with capability `SPCS_PLATFORM_METRICS_EVENT_TABLE` permanently gated; UI capability explanation | manifests + copy | Evaluation summary shows "requires customer telemetry" | 1 |
| INS-005-S11 | Isolation, observability, runbook, evidence | tests, docs | Evidence complete | 5 |
Task acceptance:
- [ ] No utilization percentage is inferred from credits.
- [ ] No model-substitution recommendation without a quality evaluation.
- [ ] Parent/child and pool/app totals never double-count.

### INS-006 — Implement action workflow and immutable baseline capture
Release: R1 · Estimate: 44–64 h · Risk: H · Decisions: D-10, D-13, D-25 · Closes: G-INS-09, G-INS-10 (expiry), G-INS-13, G-INS-21
Dependency changes: `−INS-003`, `−INS-004`, `−INS-005` (workflow is detector-agnostic); keep `INS-002` (E2E fixture) and `CTL-004`; `+INS-101` (read API/UI shell); `+INS-102` soft (config-detected implementation suggestion).
| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| INS-006-S01 | Author both state machines (G-INS-09) with transition table: from, to, actor (role or SYSTEM), guard, required fields, error code; UI label mapping | `data/contracts/insight-lifecycle.json`, `action-lifecycle.json` | Generated diagram reviewed; every UI label in `pages/actions.md` maps to exactly one state | 3 |
| INS-006-S02 | PostgreSQL migrations per §3 with `tenant_id` composite keys, FORCE RLS, `revision` integer | `apps/api/migrations/*_insight_workflow.sql` | RLS test: runtime role without `app.tenant_id` reads 0 rows | 3 |
| INS-006-S03 | Command API with `expected_revision` and `Idempotency-Key`: `POST /v1/insights/{id}/transitions`, `POST /v1/actions`, `POST /v1/actions/{id}/transitions`, `PATCH /v1/actions/{id}` (owner, due date) | `apps/api/actions/routes.py` | Stale revision → 409 INS_STALE_REVISION with no row change (oracle) | 4 |
| INS-006-S04 | Insight guards: DISMISSED requires reason ∈ {FALSE_POSITIVE, BY_DESIGN, DUPLICATE, OTHER} + note + expiry ≤ 365 d (default 90); ACCEPTED_RISK requires FinOps Admin + expiry ≤ 180 d; NOT_APPLICABLE binds detector major | guard module + tests | Missing reason → 422 INS_REASON_REQUIRED; expiry 400 d → 422 INS_EXPIRY_OUT_OF_RANGE | 3 |
| INS-006-S05 | Daily lifecycle job: expired dismissals still QUALIFIED → DETECTED (reopen_count+1); materiality reopen when impact_30d ≥ 2 × impact_at_dismissal; 3 complete NOT_QUALIFIED → NO_LONGER_OBSERVED; requalification → episode+1 | `apps/api/insights/lifecycle_job.py` | Fixtures for each branch; INSUFFICIENT_DATA never advances counters | 3 |
| INS-006-S06 | Baseline freeze command → scoped analytical job: computes baseline on pinned publications using the INS-007 contract defaults per action_type; writes immutable `action_baseline` (Snowflake, insert-only) with sha256 over canonical JSON; PG stores baseline_id + hash | `services/intelligence/baseline.py`, `POST /v1/actions/{id}/baseline:freeze` (202) | Two freezes of identical inputs → same hash; job is scoped to the actor's permission profile | 4 |
| INS-006-S07 | Immutability: re-freeze only while PLANNED (new baseline revision, old retained); after IMPLEMENTED, frozen; data refresh/restatement never mutates the baseline, only emits `baseline_restatement_notice` | tests | Republish newer data revision → stored hash unchanged (oracle); edit attempt after IMPLEMENTED → 409 | 3 |
| INS-006-S08 | Record implementation: PLANNED→IMPLEMENTED requires frozen baseline, implemented_at (UTC, ≤ now, ≥ baseline_window_end), source HUMAN_ATTESTED/CONFIG_DETECTED; show INS-102 detected bracket as suggestion; > 24 h discrepancy requires confirmation flag | transition handler | implemented_at < baseline_window_end → 409 INS_BASELINE_OVERLAPS_INTERVENTION with a "refreeze default window" suggestion; future timestamp → 422 | 3 |
| INS-006-S09 | System transitions: IMPLEMENTED→VERIFYING at post-window start; VERIFYING→VALIDATED only by the measurement job (INS-007); CANCELLED (from PLANNED/IMPLEMENTED), REVERTED (with reverted_at; post window truncated) | system actor | Manual VALIDATED → 403 INS_VALIDATION_REQUIRES_MEASUREMENT | 2 |
| INS-006-S10 | Owner scope: assignment requires the owner's scope ⊇ resource; daily recheck → OWNER_OUT_OF_SCOPE flag + FinOps Admin notification; that owner's transitions → 403; revoked user cannot read evidence (SEC-006 epoch) | scope checker | Revoked-mid-session fixture: next call 403, evidence 404 | 3 |
| INS-006-S11 | Concurrency and duplicates: parallel transitions with the same revision → one 200, one 409; same Idempotency-Key → same action; second open action of the same action_type on the same insight → 409 INS_DUPLICATE_OPEN_ACTION | tests | 50-iteration race test green | 2 |
| INS-006-S12 | Audit: every transition/freeze → SEC-008 event (actor, from, to, reason, revision, baseline hash) | audit emitter | Audit rows match transitions 1:1 in the E2E test | 2 |
| INS-006-S13 | UI `/actions` list and `/actions/:id`: timeline, owner, due date, baseline card (window, normalizer, hash), implementation evidence, all UX states, keyboard path | `apps/web/actions/*` | Playwright: stale-edit banner on 409; denied state shows no amounts | 4 |
| INS-006-S14 | Isolation: foreign action UUID → 404; A-reader limited to A1 cannot list actions on A2 resources; cross-tenant owner assignment rejected | tests | Non-enumerating responses verified | 2 |
| INS-006-S15 | Observability (`ins_action_transitions_total{to}`, `ins_baseline_freeze_seconds`), runbook, staging evidence | docs | Evidence complete | 3 |
Task acceptance:
- [ ] Implemented never implies Validated; only a measurement run validates.
- [ ] Baseline hash unchanged after data refresh and restatement.
- [ ] Stale transition → 409 without mutation.
- [ ] Every dismissal and accepted risk carries reason, actor and expiry; expiry reopens if still qualifying.
- [ ] Owner losing scope cannot act and is surfaced to admins.

### INS-007 — Measure normalized savings and finish optimization acceptance
Release: R1 · Estimate: 45–66 h · Risk: H · Decisions: D-11, D-12, D-13 · Closes: G-INS-12, G-INS-14
Dependency changes: `+INS-102` soft (rollback detection and config-detected dates). Keep `INS-006`, `FIN-009`.
| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| INS-007-S01 | Author the measurement contract: normalizer per action_type (G-INS-12 list), windows (28/min 14), stabilization (1 d warehouse, 8 d retention, 0 d rewrite), coverage (100 % FINAL), max wait 30 d, confidence method, confounder codes, overlap rule, realized horizon (post window only; run-rate labelled ESTIMATE) | `data/contracts/savings-measurement.json` | Contract review sign-off; referenced by the INS-006 baseline job | 3 |
| INS-007-S02 | Golden fixtures: 200/100 → 120 units @ 180 → 60; 260 → −20; 20/25 post days complete → VERIFYING, excluded; two overlapping actions → group 60; estimate 80 separate; rate 2.00→2.20; volume ×1.6; 25 % new-family mix; post-period restatement | `tests/spec/INS-007/fixtures/` | Expected outputs computed by hand in the fixture README | 3 |
| INS-007-S03 | dbt measurement marts on D-11 aggregates (not raw queries): daily cost (credits + currency) and normalizer per scope (warehouse, family, table, pipe) | `data/dbt/models/marts/savings/*` | Mart reproducible 400 d back; no dependency on query-level tables (dbt graph test) | 4 |
| INS-007-S04 | Counterfactual engine: expected = unit_base × units_post (MIX_ADJUSTED variant for warehouse actions), realized = expected − observed, signed; rate-neutral with the frozen baseline rate; secondary at-actual-rate figure; native credits and currency; no currency mixing | `services/intelligence/savings.py` | 240 − 180 = 60; 240 − 260 = −20 (never clamped); single-family mix-adjusted = 240 | 4 |
| INS-007-S05 | Coverage & maturity gate: day-level completeness × D-13 FINAL for every required source; <100 % → stays VERIFYING, excluded from totals; 30 d past post end → INCONCLUSIVE_COVERAGE | gate module | 20/25 fixture → VERIFYING, verified total excludes it (oracle) | 3 |
| INS-007-S06 | Confidence: moving-block bootstrap on baseline daily unit costs (block 7, B = 2000, seed from sha256(measurement_id)), 5–95 % interval, classes VERIFIED_SAVING / VERIFIED_INCREASE / INCONCLUSIVE, label UNCALIBRATED | `savings_confidence.py` | Same measurement twice → identical interval; flat baseline + saving 60 → VERIFIED_SAVING; noisy baseline (CV 40 %) + saving 5 → INCONCLUSIVE | 4 |
| INS-007-S07 | Confounders: RATE_CHANGE, SIZE_CHANGE (not part of the action, from INS-102/QH size), OVERLAPPING_ACTION, VOLUME_SHIFT (\|n_post/n_base − 1\| > 0.5 → INCONCLUSIVE unless approved covariate), MIX_SHIFT (> 20 % post cost from families without baseline), ROLLBACK (config reverted → truncate post window; < 14 d → INCONCLUSIVE) | `savings_confounders.py` | Each fixture sets exactly its code; rate fixture reports rate-neutral 60 and at-actual-rate separately | 4 |
| INS-007-S08 | Overlap groups: actions with intersecting scopes (pool tree) and intersecting [baseline_start, post_end] → joint measurement at union scope (baseline before earliest implemented_at, post after latest + stabilization); no per-action apportionment in R1 | `savings_overlap.py` | Auto-suspend + rewrite on the same warehouse → one group, verified total 60, never 120 (oracle) | 3 |
| INS-007-S09 | Restatement: a newer publication for a measured window → new measurement revision superseding the old; totals use the latest; audit diff | revision logic | Restated fixture changes 60 → 58 with a linked supersession | 2 |
| INS-007-S10 | Horizon/YTD: realized = Σ daily realized over post-window days; YTD sums post-window days in the calendar year (UTC); annualized run-rate as separate ESTIMATE | aggregation | Home "Realized YTD" equals Σ of group-level daily realized in the year | 2 |
| INS-007-S11 | API: `GET /v1/savings` (per-currency summary + list), `GET /v1/savings/{id}`, `POST /v1/actions/{id}/measurements` (202, scoped job), remeasure; authorization same as costs | `apps/api/savings/*` | Foreign measurement ID → 404; job runs under the requester's profile | 3 |
| INS-007-S12 | UI `/savings` and `/savings/:id`: potential vs verified never summed; adverse outcome negative; method, windows, coverage, confounders, bootstrap interval with UNCALIBRATED label | `apps/web/savings/*` | Playwright: −20 fixture renders "−20.00", not "0"; VERIFYING rows excluded from the total with an explanation | 4 |
| INS-007-S13 | Measurement completion → INS-006 system transition VALIDATED with outcome ∈ {SAVING, INCREASE, INCONCLUSIVE} | integration | E2E: freeze → implement → post window → VALIDATED(SAVING, 60) | 2 |
| INS-007-S14 | Isolation, observability (`ins_measurement_total{outcome}`, `ins_measurement_coverage_wait_days`), runbook, staging evidence incl. optimization E2E acceptance | docs, evidence | Evidence complete | 4 |
Task acceptance:
- [ ] Verified 60; adverse −20; incomplete excluded; estimate 80 separate; overlap never 120.
- [ ] Measurement reproducible from D-11 aggregates after query-level purge.
- [ ] Rate changes cannot manufacture savings (rate-neutral primary figure).
- [ ] Bootstrap intervals are deterministic and labelled UNCALIBRATED.
- [ ] Each confounder code is present when its fixture condition holds.

## 5. New tasks required

### INS-101 — Insight read API, inbox, deep dive and portfolio totals
Release: R1 · Estimate: 35–52 h · Risk: M · Decisions: D-02, D-22, D-18 · Closes: G-INS-11 (serving), G-INS-18, G-INS-20, G-INS-21
Why/where: No task owns the read path. Plugs in after INS-001; INS-002/003/004 register detector-specific evidence renderers; INS-006 builds on it. Deps: INS-001, API-003, UX-002, SEC-006.
| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| INS-101-S01 | OpenAPI for list/detail/evidence/summary/evaluations with filters (detector, family, status, severity, account, warehouse, min impact), signed cursor | `apps/api/openapi/insights.yaml` | Contract tests generated; cursor replay with a modified scope rejected | 3 |
| INS-101-S02 | Serving views over `insight_observation` joined to the permission model through the query broker (D-22) and row policies (D-02) | Snowflake secure views + broker registration | A-reader limited to A1 gets zero A2 rows under a filter-free query | 4 |
| INS-101-S03 | `GET /v1/insights` joining PG workflow status with the Snowflake latest observation; stable sort (impact desc, fingerprint) | route | Pagination stable across a concurrent new publication (publication pinned in cursor) | 3 |
| INS-101-S04 | Deep-dive payload with PRD §105 sections: what (predicate + values), why (thresholds), when (windows, first/last seen), impact (kind, 30 d, currency), evidence, history (observations), contributors, affected resources, recommended action (template) | `GET /v1/insights/{id}` | Every section present or explicitly "unavailable" with reason | 4 |
| INS-101-S05 | `GET /v1/detectors/evaluations`: evaluated resources, qualified, suppressed_by_reason, eligible_on per detector for the scope | route | Empty state renders "evaluated 12 warehouses; 0 qualified; 3 suppressed: config unknown" | 2 |
| INS-101-S06 | `GET /v1/insights/summary`: per-currency portfolio potential (INS-001 DP), counts by status, "n without estimate"; used by Home (PRD §112) | route | USD and EUR returned separately; null potentials not summed | 2 |
| INS-101-S07 | UI `/insights` list: columns Opportunity, Estimated (30 d), Confidence, Status; impact kind badges (ESTIMATE/CEILING/EXPOSURE); filters; CSV export via the RPT CSV writer rules | `apps/web/insights/list.tsx` | Playwright: mixed currencies never summed; CEILING labelled "up to" | 4 |
| INS-101-S08 | UI `/insights/:id` deep dive with evidence tables and history chart; drill to warehouse/query views (UX-005 links when available) | `apps/web/insights/detail.tsx` | Keyboard path + 200 % zoom check; missing capability shown as "—" with reason | 4 |
| INS-101-S09 | Review/assign/dismiss/accept-risk dialogs calling INS-006 commands (feature-flagged until INS-006) | dialogs | 409 shows a reload prompt preserving input | 3 |
| INS-101-S10 | Isolation/BOLA suite: guessed insight/observation/evidence IDs, stale epoch, cursor from another tenant | `tests/spec/INS-101/security_test.py` | All non-enumerating 404/403; no counts leak in the summary | 3 |
| INS-101-S11 | Observability (p95 of list/detail, broker time) + staging evidence | docs | p95 ≤ 2 s warm on the 10k-insight fixture (operations.md target) | 3 |
Task acceptance:
- [ ] Home, Insights list and summary API report the same per-currency potential.
- [ ] Every suppressed detector is inspectable with reason and eligible date.
- [ ] No foreign or out-of-scope insight is discoverable via ID, cursor or aggregate.

### INS-102 — Warehouse configuration snapshot source (cross-domain; execute with ING/CON owners)
Release: R1 · Estimate: 23–34 h · Risk: M · Decisions: D-07, D-08, D-21 · Closes: G-INS-02
Why/where: WH02 and config-detected implementation need current configuration, which no source provides. Deps: CON-003 (grant), CON-005 (probe), ING-005/006 (batch path). Feeds INS-002, INS-006, INS-007, INS-106.
| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| INS-102-S01 | Live probe (TO VERIFY LIVE): does account-level MONITOR USAGE make `SHOW WAREHOUSES` list all warehouses? Compare with per-warehouse MONITOR; record the column list incl. new BCR columns and whether a warehouse ID column exists | `docs/evidence/INS-102/probe.md` | Evidence from one Standard and one Enterprise trial account | 3 |
| INS-102-S02 | Grant model in the install script: the chosen privilege; if per-warehouse, enumerate warehouses and emit `GRANT MONITOR ON WAREHOUSE <q> TO ROLE BRIDGE_FINOPS_READER`; revoke script counterpart | CON-003 script template section | Script diff reviewed; no MODIFY/OPERATE/MANAGE WAREHOUSES granted | 3 |
| INS-102-S03 | Extractor step in the account cycle (D-07): `SHOW WAREHOUSES` then `SELECT <explicit cols> FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))`; no warehouse resume; QUERY_TAG `bridge_finops:config` | `services/extractor/sources/warehouse_config.py` | Staging query log shows no WAREHOUSE_METERING delta caused by the step (TO VERIFY LIVE) | 3 |
| INS-102-S04 | Source contract as a complete-snapshot source (catalog rule); types (auto_suspend INTEGER nullable, 0/NULL = never), parse sizes/types to enums | ING registry entry | Unknown size string → quarantine + capability SCHEMA_MISMATCH | 3 |
| INS-102-S05 | name→WAREHOUSE_ID mapping via as-of join on WMH/QH (WAREHOUSE_ID, WAREHOUSE_NAME); rename detection (same ID, new name) | dbt `map_warehouse_name_id.sql` | Rename fixture keeps one ID with two names; ambiguous mapping flagged | 3 |
| INS-102-S06 | SCD2 `dim_warehouse_config` (valid_from = first snapshot showing the value, valid_from_lower_bound = previous snapshot time) + change events | dbt model | AS 600→60 between 10:00 and 11:00 snapshots → change bracket [10:00, 11:00) | 3 |
| INS-102-S07 | Drift/coverage: warehouse present in WMH but absent from snapshot → CONFIG_UNKNOWN capability per warehouse (CON-005 surface) | capability rows | Fixture with an ungranted warehouse shows it in Data Health | 2 |
| INS-102-S08 | Isolation/privacy (warehouse names are tenant data), observability (`ing_warehouse_config_snapshot_age_seconds`), runbook, evidence | docs | Evidence complete | 3 |
Task acceptance:
- [ ] The snapshot never requires or resumes a customer warehouse (verified live).
- [ ] No privilege beyond MONITOR/MONITOR USAGE is granted.
- [ ] Config changes are bracketed in time and consumable by INS-006/007.

### INS-103 — Query and pipeline detectors, R2 set (Q04, Q05 evidence, Q06, Q08, PL01–PL05)
Release: R2 · Estimate: 48–72 h · Risk: H · Decisions: D-11, D-16 · Closes: G-INS-05
Why/where: Split from INS-003 to take WRK dependencies off the R1 path. Deps: INS-003, WRK-002, WRK-004, WRK-005, ING adapter for TABLE_QUERY_PRUNING_HISTORY and QH ROWS_*/COMPILATION_TIME/ERROR_CODE.
| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| INS-103-S01 | TABLE_QUERY_PRUNING_HISTORY activation evidence (edition, grain, retention) + feature mart | `fct_ins_table_pruning_hourly.sql` | Probe evidence recorded | 4 |
| INS-103-S02 | Q04 per G-INS-05 (scan > 0.80, selectivity < 0.10, ≥ 3 rows) | `detectors/q04.py` | 90/100 scanned + 1 % matched QUALIFIED; zero ROWS_SCANNED → SUPPRESSED | 4 |
| INS-103-S03 | Q05 as on-demand evidence in the WRK-005 deep dive (join explosion ratio), no recurring insight | WRK-005 extension | 2000/max(100) = 20 shown; unknown denominator → hidden | 4 |
| INS-103-S04 | Q06 compilation share > 0.5 over ≥ 100 executions/14 d (elapsed-time evidence only) | `detectors/q06.py` | 600/(600+400) = 60 % QUALIFIED; 99 executions → NOT | 3 |
| INS-103-S05 | Q08 retry waste on WRK logical executions (failed charged attempts before success); otherwise "suspected repeated execution" | `detectors/q08.py` | Failed 3 + success 5 → retry expense 3 once | 5 |
| INS-103-S06 | PL01/PL02 overscheduling with exact invocations/task runs + rows-changed signal | `detectors/pl01_02.py` | 10→20 runs with unchanged 100 rows QUALIFIED; missing change signal → SUPPRESSED | 6 |
| INS-103-S07 | PL03 low-change frequent execution | `detectors/pl03.py` | 23/24 zero-change runs QUALIFIED; SELECT row counts never used as change | 4 |
| INS-103-S08 | PL04 failure/retry waste with distinct charge links | `detectors/pl04.py` | 10/50 = 20 % QUALIFIED | 4 |
| INS-103-S09 | PL05 duplicate pipeline via verified writer lineage (needs ACCESS_HISTORY aggregate from INS-104) | `detectors/pl05.py` | Two verified writers of one output → review candidate; hash similarity alone → nothing | 5 |
| INS-103-S10 | Pool registration (RETRY(logical), PIPELINE(p)) and dedup with Q01 | opportunity config | Q08 + PL04 on the same attempt count once | 3 |
| INS-103-S11 | Isolation, observability, runbook, evidence | docs | Evidence complete | 6 |
Task acceptance:
- [ ] No recurring detector calls GET_QUERY_OPERATOR_STATS.
- [ ] Inferred groups never substitute for exact runs.
- [ ] Retry cost is counted once across Q08/PL04.

### INS-104 — Storage access and ingestion hygiene detectors, R2 (ST01, ST02, ST05, PI01–PI04 re-scoped)
Release: R2 · Estimate: 40–60 h · Risk: H · Decisions: D-08, D-10 · Closes: G-INS-03, G-INS-04
Why/where: Split from INS-004. Deps: INS-004, FIN-011, FIN-012, ING adapter with the source-side access aggregation (ING amendment), AU.COPY_HISTORY adapter.
| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| INS-104-S01 | ING amendment proposal "source-side aggregate" kind + access aggregation SQL (FLATTEN BASE_OBJECTS_ACCESSED/OBJECTS_MODIFIED per UTC day) or AGGREGATE_ACCESS_HISTORY equivalence proof | ADR draft + extractor SQL | Customer credit cost measured on a 1 M-query/day fixture account | 6 |
| INS-104-S02 | Shared/external reader detection (outbound shares, replication groups, external/Iceberg tables) → suppression set | `fct_ins_object_external_readers.sql` | Shared table fixture → SUPPRESSED(SHARED_OR_EXTERNAL_READERS_POSSIBLE) | 5 |
| INS-104-S03 | ST01 (30 d) / ST02 (all observed history) with "observed since <date> in connected accounts" wording | `detectors/st01_02.py` | Denied access evidence → SUPPRESSED; pre-enrollment table shows limited history | 6 |
| INS-104-S04 | ST05 growth > 25 % over 7 d + tenant byte floor | `detectors/st05.py` | 100→150 GiB QUALIFIED above floor; clone counted once | 4 |
| INS-104-S05 | PI01–PI03 non-monetary hygiene (impact_kind NONE, excluded from potential totals); PI01 from COPY_HISTORY FILE_SIZE median | `detectors/pi01_03.py` | 100 × 1 MiB → observation with no monetary impact; Streaming ineligible | 5 |
| INS-104-S06 | PI04 redefined as a per-GB rate conformance check (± 5 % of 0.0037 credits/GB after 2025-12-08) → routed to FIN-011 reconciliation | check + FIN hand-off | Pre-2025-12-08 windows excluded; conformance fixture passes | 4 |
| INS-104-S07 | AU.TABLES adapter for RETENTION_TIME/IS_TRANSIENT → ST03 numeric estimate `TT×(1−R_tgt/R_cur)` (label uniform-churn assumption) | detector minor version | Estimate appears only when retention is known | 5 |
| INS-104-S08 | Isolation, observability, runbook, evidence | docs | Evidence complete | 5 |
Task acceptance:
- [ ] No "never used" wording; "no observed reads in connected accounts since X".
- [ ] Snowpipe hygiene never contributes to potential savings.

### INS-105 — Detector qualification: backtest and false-positive review
Release: R1 · Estimate: 25–38 h · Risk: M · Decisions: D-20 · Closes: G-INS-19
Why/where: The contract mandates a retrospective FP review; no owner exists. Runs in parallel with INS-002..004; gates enabling each R1 detector for customers.
| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| INS-105-S01 | Precision register table per detector version fed by DISMISSED(FALSE_POSITIVE) and reviewer verdicts | `insight_detector_quality` (PG) | Metric computed per version | 3 |
| INS-105-S02 | Backtest runner: replay detectors over historical publications of a real account (Bridge's own or a design partner, Q7) | `services/intelligence/backtest.py` | Produces candidate list with evidence for review | 4 |
| INS-105-S03 | Review protocol and form (TRUE/FALSE/UNSURE + reason) for FinOps reviewer | `docs/runbooks/detector-review.md` | Review of all R1 candidates on ≥ 1 account completed | 4 |
| INS-105-S04 | Release gate: enable per detector version iff precision ≥ 0.8 on ≥ 10 reviewed candidates or signed owner acceptance; flag stored in manifest | CI/config gate | A detector without a gate record cannot be enabled for customer tenants | 3 |
| INS-105-S05 | Threshold-change procedure: new version must pass all negative fixtures + rerun backtest diff | procedure + CI job | Diff report attached to the version PR | 3 |
| INS-105-S06 | Ongoing monitoring: weekly precision alarm < 0.6 over trailing 30 reviewed | alarm | Synthetic dismissals trigger alarm | 3 |
| INS-105-S07 | Internal reviewer console (operator plane, not customer UI): candidates with evidence, verdict form, reviewer identity; access time-bound and audited per security.md support-access rules | `apps/ops/detector-review/*` | Reviewer without an approved grant → 403; every verdict audited | 3 |
| INS-105-S08 | Evidence bundle: verdict set and precision per R1 detector version with the backtest publication IDs | `docs/evidence/INS-105/<commit>/` | One bundle per enabled detector version | 2 |
Task acceptance:
- [ ] Every enabled R1 detector version has a recorded review verdict set.
- [ ] Threshold edits always produce a new version with backtest evidence.

### INS-106 — Warehouse detectors, R2 set (WH03, WH05 redefined, WH06, WH07, WH08)
Release: R2 · Estimate: 34–51 h · Risk: M · Decisions: D-08 · Closes: G-INS-07 (WH05)
Why/where: Split from INS-002. Deps: INS-002, INS-102, ING adapters for WAREHOUSE_EVENTS_HISTORY/WAREHOUSE_LOAD_HISTORY, QH QUEUED_OVERLOAD_TIME.
| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| INS-106-S01 | Feature marts from WAREHOUSE_EVENTS_HISTORY (resume/suspend/spin-up events per cluster) and WAREHOUSE_LOAD_HISTORY | `fct_ins_wh_events.sql`, `fct_ins_wh_load.sql` | Activation evidence recorded | 5 |
| INS-106-S02 | WH06 queue share > 20 % in ≥ 3 daily cohorts ≥ 100 queries (guardrail + observation) | `detectors/wh06.py` | 30/100 s QUALIFIED; 99 queries → NOT | 3 |
| INS-106-S03 | WH03 rightsizing candidate (experiment only; potential null) gated on WH06 = not qualified and no remote spill | `detectors/wh03.py` | Queue fixture blocks downsizing recommendation | 4 |
| INS-106-S04 | WH05 redefined (standing min clusters; STANDARD vs ECONOMY review); max-cluster headroom as NONE observation | `detectors/wh05.py` | Max 4/peak 1 → governance note, zero potential | 4 |
| INS-106-S05 | WH07 thrashing: ≥ 6 resume events/h in 3 distinct hours, median active interval < 5 min | `detectors/wh07.py` | Six cycles QUALIFIED; missing events → SUPPRESSED | 4 |
| INS-106-S06 | WH08 consolidation with tenant isolation/SLA policy input (CTL config) | `detectors/wh08.py` | Incompatible isolation requirement suppresses | 5 |
| INS-106-S07 | Pool tree update (WAREHOUSE_TOTAL for WH03/WH08) and DP regression tests | opportunity config | 100 vs 75 fixture holds | 3 |
| INS-106-S08 | Isolation, observability, runbook, evidence | docs | Evidence complete | 6 |
Task acceptance:
- [ ] No downsizing proposal while queueing or remote spill is present.
- [ ] Headroom with zero cost never ranks as savings.

## 6. Estimate summary

| Task | Release | Low h | High h |
|---|---|---:|---:|
| INS-001 | R1 | 40 | 60 |
| INS-002 | R1 | 38 | 56 |
| INS-003 | R1 | 34 | 50 |
| INS-004 | R1 | 20 | 30 |
| INS-006 | R1 | 44 | 64 |
| INS-007 | R1 | 45 | 66 |
| INS-101 | R1 | 35 | 52 |
| INS-102 | R1 | 23 | 34 |
| INS-105 | R1 | 25 | 38 |
| INS-005 | R2 | 36 | 54 |
| INS-103 | R2 | 48 | 72 |
| INS-104 | R2 | 40 | 60 |
| INS-106 | R2 | 34 | 51 |
| **Total R1** | | **304** | **450** |
| **Total R2** | | **158** | **237** |

## 7. Owner questions

1. Default auto-suspend target for WH02 potential (proposed 60 s), and may recommendations show copyable `ALTER WAREHOUSE` text (display only)?
2. Insight impact floor default 25.00 per currency per 30 days: acceptable, and should it vary by plan?
3. Dismissal defaults: 90 days (max 365), accepted risk ≤ 180 days with FinOps Admin approval?
4. In an overlap group, may realized savings ever be apportioned to individual actions or owners (for team scorecards), or is group-level only acceptable (R1 proposal: group-level only)?
5. May the install script grant MONITOR on every warehouse (or MONITOR USAGE on the account) to read configuration? This will appear in the customer's security review.
6. Should detectors run on Bridge's own extraction warehouse at all, or only label it "Bridge overhead"?
7. Which real Snowflake account (Bridge's own or a design partner, with written consent) is used for the INS-105 false-positive review before any detector is enabled for the first customer?
8. For AI02/AI07/SP04, is a customer-uploaded denominator or quality evaluation in product scope, or are these detectors dropped?
