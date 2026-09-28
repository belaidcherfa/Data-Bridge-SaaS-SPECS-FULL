# PRO — Product gaps vs recognized FinOps platforms (contracts, root cause, digests, coverage, experiments, exports, BI, action plane)

Source analysis: [SAAS_COMPLETENESS.md](../SAAS_COMPLETENESS.md) (feature matrix vs select.dev and peers, gaps G-PRO-xx, owner questions). Reviewer: SaaS completeness agent, 2026-09-28; integrated into the [revised graph](../revised-task-graph.json) the same day. Status of all tasks: NOT_STARTED. Lane H (product surfaces) with data work reviewed by the data/finops reviewers.

### PRO-001 — Snowflake capacity-contract burn-down, balance tracking and renewal forecast
Release: R1 · Estimate: 41–59 h · Risk: H · Decisions: D-12, D-13, D-20, D-26 · Closes: G-PRO-01
Why / where: capacity contracts are in R1 (D-20); select.dev [S4] and Snowflake's Organization Overview [N3] both show contract consumption and forecast; the plan extracts neither `REMAINING_BALANCE_DAILY` nor `CONTRACT_ITEMS`. Bridge can go further than peers by explaining drawdown per service through `funding_class`. S01 is authored in P2 and handed to ING-102; the rest follows FIN-002 and GOV-002.
Dependency changes: new; deps ING-001, ING-102, CON-005, FIN-002, FIN-104, FIN-105, GOV-002, GOV-003, API-001, UX-002; ING-102 activates the two contracts (step-level, no reverse edge).

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| PRO-001-S01 | Author source contracts `OU.REMAINING_BALANCE_DAILY` (DATE, ORGANIZATION_NAME, CONTRACT_NUMBER, CURRENCY, FREE_USAGE_BALANCE, CAPACITY_BALANCE, ON_DEMAND_CONSUMPTION_BALANCE, ROLLOVER_BALANCE — exact columns and types TO VERIFY LIVE) and `OU.CONTRACT_ITEMS` (full daily snapshot; columns TO VERIFY LIVE): ORG scope, ORGANIZATION_BILLING_VIEWER, latency ≤ 72 h, FINANCIAL retention class (D-26); hand off to ING-102. | `data/contracts/sources/ou_remaining_balance_daily.yaml`, `ou_contract_items.yaml` | Registry validation passes; ING-102 accepts the change request. | 3 |
| PRO-001-S02 | Add CON-005 capability outcomes: readable; empty because reseller contract; not readable because the organization is not the primary organization of a shared contract; standalone account → NOT_AVAILABLE with reason. | probe cases | Each outcome has a fixture and a customer-facing message. | 2 |
| PRO-001-S03 | Create the manual contract record for reseller, non-primary or no-access tenants: `finance.contracts` (contract_number, term start/end, committed amount, currency, rollover terms, on-demand rate reference to FIN-105), maker-checker (SEC-102), audited, provenance MANUAL vs SNOWFLAKE. | migration, `apps/api/contracts/` | A contract without a second approver stays DRAFT; provenance shown in UI. | 3 |
| PRO-001-S04 | Build `fct_contract_period` (contract × term, amendments as SCD2) and `fct_capacity_balance_daily` (per contract/day: capacity, rollover, free, on-demand balances; drawdown = −Δ(capacity + rollover + free); positive deltas labelled CONTRACT_EVENT — top-up or rollover injection — never negative consumption). | `data/dbt/models/ledger/contracts/*.sql` | Rollover-injection fixture yields a CONTRACT_EVENT row and no negative drawdown. | 4 |
| PRO-001-S05 | Add informational control C-CAP: daily drawdown vs Σ ledger charges with `funding_class` ∈ {CONTRACT, FREE, REBATE} per org/day/currency, tolerance one minor unit, classified delta shown on Reconciliation (FIN-009 surface, not a close gate). | `data/contracts/reconciliation/controls.yaml` entry, model | Fixture day with a 0.01 difference is MATCHED; 5.00 unexplained → WARNING (informational). | 3 |
| PRO-001-S06 | Register burn-down metrics in API-001: committed, consumed to date, remaining, % consumed vs % of term elapsed, average daily burn over 28 complete days, on-demand consumption to date; money strings with maturity labels (recent days PROVISIONAL under the 72 h latency). | registry YAML | Contract tests; metrics resolve through the planner. | 3 |
| PRO-001-S07 | Implement the forecast with GOV-002 methods on the daily drawdown (gross stream only): exhaustion date, projected consumption at term end, projected on-demand consumption repriced at the on-demand rate (RATE_SHEET or FIN-105), projected unused capacity at term end (forfeit risk under contract rollover terms), "renew early by" date; what-if growth % as an unsaved scenario; label UNCALIBRATED, no interval in R1. | `services/intelligence/contract_forecast.py` | Fixture: committed 900,000.00 over 365 days, 600,000.00 consumed by day 200 → 3,000.00/day → exhaustion at end of day 300, 65 days before term end, projected on-demand consumption 195,000.00 at contract-rate equivalent. | 4 |
| PRO-001-S08 | Implement `GET /v1/contracts` and `GET /v1/contracts/{id}/burn-down` (pinned publication; FinOps Admin and Finance roles; group-restricted users → 403 because contract amounts are organization-level). | `apps/api/contracts/` | Restricted viewer → 403; foreign contract id → 404. | 3 |
| PRO-001-S09 | Build screen 89 `/contract` (Govern): cumulative actual vs linear commitment vs forecast, KPI ribbon, amendment timeline, on-demand panel, drawdown by service family (from `funding_class`), data-status badges; screen contract added to the catalog. | `apps/web/src/pages/contract/` | Playwright asserts fixture values and badges; 390 px and keyboard checks pass. | 4 |
| PRO-001-S10 | Add monitor conditions `capacity_exhaustion_before(days_before_term_end)` and `on_demand_started` to the GOV-003 catalog; notifications through GOV-007. | condition catalog entries | Fixture forecast (65 days early) opens an incident with the configured 30-day threshold. | 3 |
| PRO-001-S11 | Handle several contracts per organization and several organizations drawing on one contract; never sum across currencies; attribute to the primary organization. | model rules + tests | Two-currency fixture shows two burn-downs and no cross-currency total. | 2 |
| PRO-001-S12 | Fixtures and tests: the S07 case, rollover injection, top-up mid-term, on-demand after exhaustion, manual reseller contract, restated balance day. | `tests/spec/PRO-001/` | All pass with hand-computed expectations in the fixture README. | 3 |
| PRO-001-S13 | Isolation and Explain: foreign tenant → 404; Explain root for "remaining" lists balance source, as-of and latency. | tests | Pass. | 2 |
| PRO-001-S14 | Docs page "Contract and capacity" (prerequisites, latency, reseller path) and evidence; live verification on tenant zero if Bridge's organization has a capacity contract, otherwise fixtures only (TO VERIFY LIVE). | SAS-002 page, `docs/evidence/PRO-001/<commit>/` | Evidence records which path was used. | 2 |

Task acceptance:
- [ ] Capacity customers see committed, consumed, remaining, exhaustion date and forfeit/on-demand risk with data status, for Snowflake-sourced and manual contracts.
- [ ] Contract events never appear as negative consumption; currencies are never summed.
- [ ] Drawdown is reconciled against ledger charges by funding class, explaining which services consumed the commitment.

### PRO-002 — Cost-change root-cause engine (driver decomposition and co-occurring change events)
Release: R1 · Estimate: 38–55 h · Risk: H · Decisions: D-02, D-11, D-12, D-14, D-34 · Closes: G-PRO-02
Why / where: PRD §96 requires alerts naming the main contributor, primary model and change; GOV-007-S07 consumes "top ≤ 3 verified contributors" that no task computes; Home movers (UX-003-S04) and workload compare (WRK-005) are single-level. One deterministic, conserved engine serves incidents, alerts, Home and digests. Plugs in after API-002, WRK-005 and INS-102 (P5).
Dependency changes: new; deps API-001, API-002, API-004, API-104, WRK-005, WRK-104, INS-102, ALC-102.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| PRO-002-S01 | Author contract `root_cause.v1`: input (metric, scope, current and baseline complete windows, publication pin, max_depth ≤ 4, top_k ≤ 5), output tree nodes {dimension, value, baseline, current, delta, share_of_parent_delta, volume_effect, unit_cost_effect, residual, evidence_class}, invariant Σ children + Other + residual = parent delta exactly. | `data/contracts/root_cause.v1.json` | Schema suite passes; invariant stated with sign convention current − baseline. | 3 |
| PRO-002-S02 | Declare drill paths per metric family in the API-001 registry (compute: account → warehouse → workload kind → workload (dbt project/model, PBI activity, task graph) → query family → role/user pseudonym; serverless: service → object; storage: database → schema → table). | registry YAML | Registry validator rejects a path with a dimension not valid for the metric. | 3 |
| PRO-002-S03 | Build the planner: each level compiled as one semantic query through the broker (API-002) under the requester's profile and a single publication pin; restricted rows fold into RESTRICTED_REMAINDER without counts. | `services/analysis/root_cause/planner.py` | Restricted-viewer fixture shows RESTRICTED_REMAINDER and no hidden names or counts. | 4 |
| PRO-002-S04 | Implement explanatory selection: at each level expand the child with the largest absolute delta share; stop below 20 % share or at max depth; deterministic tie-break by stable id. | selector module | Two runs on the same publication return byte-identical trees. | 3 |
| PRO-002-S05 | Split volume and unit-cost effects at workload and query-family levels using WRK-005's fixed decomposition order with an explicit residual. | decomposition module | Effects + residual = node delta to the cent. | 3 |
| PRO-002-S06 | Attach co-occurring change events as evidence (never causality): warehouse size/auto-suspend/cluster changes (INS-102 snapshots), first-seen resources, dbt model first/last seen, rate changes (FIN-002), Bridge overhead changes, restatements. | `services/analysis/root_cause/events.py` | Resize fixture on the same warehouse-day is attached to that node only. | 4 |
| PRO-002-S07 | Carry maturity and coverage: nodes over PROVISIONAL data flagged; partial coverage → PARTIAL without extrapolation; unknown cost stays null. | node attributes | Null-cost day never yields a zero delta. | 2 |
| PRO-002-S08 | Execute synchronously for depth ≤ 2 (target p95 3 s) and as an API-004 job beyond; cache by (publication, scope hash, request hash). | API + job binding | Depth-4 request returns 202 with a job id; cached repeat is served without Snowflake queries. | 3 |
| PRO-002-S09 | Expose `POST /v1/analysis/root-cause` and a compact summary renderer (top path in ≤ 3 lines) for GOV-007-S07 payloads and PRO-003 digests. | `apps/api/analysis/root_cause.py` | Summary for the S11 fixture equals the expected three lines. | 3 |
| PRO-002-S10 | Build the "Why did this change?" drawer from incidents (GOV-008), Home drivers (UX-003) and Explorer deltas: tree with a waterfall per level, Explain links. | `apps/web/src/components/root-cause/` | Keyboard tree navigation works; waterfall bars sum to the node delta. | 4 |
| PRO-002-S11 | Fixture (PRD §96 shape): baseline 10,000.00/day → 14,100.00/day (+4,100.00, +41 %); dbt project FINANCE +3,800.00; model daily_transactions 5 → 21 executions (×4.2) at 225.00 each → +3,600.00, all volume effect; conservation at every level; restricted viewer variant. | `tests/spec/PRO-002/` | All expectations hand-computed and passing. | 3 |
| PRO-002-S12 | Benchmark on the OPS-008 C1 fixture: depth 4 as a job ≤ 15 s; serving credits per analysis recorded through QUERY_TAG (OPS-109). | benchmark report | Values recorded; budget alarm threshold proposed. | 2 |
| PRO-002-S13 | Evidence. | `docs/evidence/PRO-002/<commit>/` | – | 1 |

Task acceptance:
- [ ] Every explanation conserves the parent delta exactly and never reveals restricted rows.
- [ ] Alerts, incidents, Home and digests quote the same deterministic driver path for the same publication.
- [ ] Change events are labelled co-occurring, never causal.

### PRO-003 — Scheduled spend digests (inline Slack/Teams/e-mail) per owner and usage group
Release: R1 · Estimate: 27–39 h · Risk: M · Decisions: D-10, D-13, D-18, D-27 · Closes: G-PRO-03
Why / where: select [S3] and Vantage [V3] send recurring digests where owners work; the plan's Slack/Teams report delivery is link-only (G-RPT-08). Reuses RPT-004 scheduling and GOV-006/007 delivery. Plugs in after GOV-007, RPT-004 and PRO-002 (P5).
Dependency changes: new; deps GOV-006, GOV-007, RPT-004, ALC-102, ALC-007, GOV-001, INS-101, PRO-002, SEC-006.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| PRO-003-S01 | Author the digest schema: scope (tenant, usage group, budget, saved view), cadence (daily; weekly Monday; monthly on the 2nd; time zone), destinations, sections (spend vs previous complete period, top 5 movers with PRO-002 one-liners, budget status, open incidents, new insights potential labelled estimate, verified savings), disclosure level (SUMMARY/STANDARD, GOV-007-S09). | `data/contracts/digest.v1.json` | Positive and negative schema suites pass. | 2 |
| PRO-003-S02 | Implement CRUD with owner scope checks (scope ⊆ owner grants) and an LCH-101 quota (`digests`). | `apps/api/digests/` | Finance owner cannot create a Marketing digest; 11th digest on a 10-digest plan → 403 `ENTITLEMENT_LIMIT`. | 3 |
| PRO-003-S03 | Schedule through RPT-004's occurrence planner (DST fixtures) with a `digest` kind; one publication pin per occurrence; skip with a recorded reason when the publication is older than the freshness SLO. | planner binding | Weekly Monday 08:00 Europe/Paris fires once across the October DST change. | 3 |
| PRO-003-S04 | Compose via the broker JOB class under the owner's profile (as GOV-001-S05), PRO-002 summaries for movers, server-side money formatting per locale, maturity label per figure. | `services/notifications/digests/compose.py` | Digest totals equal Explorer for the pinned publication. | 4 |
| PRO-003-S05 | Render per channel: Slack Block Kit (≤ 50 blocks, section text ≤ 3,000 characters), Teams Adaptive Card, e-mail via SAS-006 templates; deep links with scope (GOV-007-S11). | renderers + snapshot tests | Snapshots stable; oversize content truncated with a "view more" link. | 4 |
| PRO-003-S06 | Reauthorize at send (GOV-007-S06); channel destinations default to SUMMARY (percentages and statuses, no amounts) unless a tenant admin allows STANDARD for that destination (audited). | policy check | SUMMARY payload scan finds no currency amounts. | 2 |
| PRO-003-S07 | Quiet rule: nothing above the GOV-101 impact floor → one-line "no material change" or skip, per digest setting. | rule | Flat fixture week produces the one-liner. | 1 |
| PRO-003-S08 | UI: create/edit digests from usage group, budget and saved-view pages and `/settings/digests`, with a live preview. | `apps/web/src/pages/settings/digests/` | Preview equals the next delivery's content for the same publication. | 3 |
| PRO-003-S09 | Tests: DST, totals parity, revoked recipient skipped, idempotent redelivery under the same logical id. | `tests/spec/PRO-003/` | All pass. | 3 |
| PRO-003-S10 | Register digest deliveries in OPS-110 delivery SLIs. | SLI config | Digest kind visible on the delivery dashboard. | 1 |
| PRO-003-S11 | Evidence (sandbox Slack, Teams and e-mail receipts). | `docs/evidence/PRO-003/<commit>/` | – | 1 |

Task acceptance:
- [ ] Owners receive scheduled, scope-correct digests in Slack, Teams or e-mail whose numbers equal Explorer for the pinned publication.
- [ ] Channel digests disclose no amounts unless an admin explicitly allowed it for that channel.

### PRO-004 — Attribution coverage and query-tagging guidance
Release: R1 · Estimate: 26–38 h · Risk: M · Decisions: D-15, D-16, D-34 · Closes: G-PRO-04
Why / where: chargeback accuracy is capped by attribution coverage; ALC-006 remediates unowned resources and WRK-002-S10 gives a dbt snippet, but there is no coverage KPI by mechanism, no snippet generator for other tools and no regression alert. Plugs in after ALC-006 and WRK-001 (P4).
Dependency changes: new; deps ALC-006, ALC-102, WRK-001, WRK-101, API-104, GOV-003. Step-level: S09 publishes on SAS-002.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| PRO-004-S01 | Register coverage metrics: share of compute spend on the ALC absolute-exposure basis attributed by mechanism {object tag, query-tag key, dbt metadata, BI tag, rule on user/role/warehouse, unallocated} per account, warehouse and workload. | registry YAML | Metric ids resolve; unit = ratio string. | 3 |
| PRO-004-S02 | Build `mart_attribution_coverage_daily` from existing ALC quality facts (no new allocation formula). | dbt model | Shares sum to 100 % of absolute exposure per day (test). | 3 |
| PRO-004-S03 | List top unattributed spend: query families and users/roles/warehouses with the largest unattributed amounts and the detected client application (WRK-001). | records dataset (API-104) | Fixture top item matches hand-computed ranking. | 2 |
| PRO-004-S04 | Build the snippet generator parameterized by the tenant's key convention: dbt `query-comment` with `append: true` and a `query_tag` macro; Python connector/Airflow `session_parameters={"QUERY_TAG": …}`; `ALTER USER … SET QUERY_TAG`; notes for Tableau (tags on by default) and Power BI (no configuration). | `packages/tagging_guide/` | Generated dbt snippet parses in a sample project in CI; Python snippet runs against a mock connector. | 3 |
| PRO-004-S05 | Register customer key conventions (e.g., `team`, `cost_center`, `app`) and check them against the WRK-101 allowlist; non-allowlisted keys are surfaced as "allowlist request required", never silently dropped from the guidance. | tenant config + check | Declaring an unknown key shows the request state. | 2 |
| PRO-004-S06 | Validate adoption: last-7-day parse status per declared key (valid JSON, key present, value in declared set) from WRK-101 `wlmeta_parse` metrics per tenant. | validator | Malformed-tag fixture shows the parse-error share. | 2 |
| PRO-004-S07 | Build screen 90 `/allocation/coverage`: KPI by mechanism, trend, top unattributed, snippet tabs, docs links. | `apps/web/src/pages/allocation/coverage/` | Playwright asserts fixture shares and snippet copy. | 4 |
| PRO-004-S08 | Add a monitor preset: coverage drop > 10 points week over week (GOV-003 relative threshold on the coverage metric). | preset | Fixture drop opens an incident. | 1 |
| PRO-004-S09 | Write the docs page "Tagging your Snowflake workloads" (SAS-002). | `docs/customer/tagging.md` | FinOps reviewer sign-off. | 2 |
| PRO-004-S10 | Tests: coverage conservation, snippet compilation, restricted viewer sees coverage only within scope. | `tests/spec/PRO-004/` | All pass. | 3 |
| PRO-004-S11 | Evidence. | `docs/evidence/PRO-004/<commit>/` | – | 1 |

Task acceptance:
- [ ] Customers see what share of spend is attributable, by which mechanism, and get working tagging snippets for their tools.
- [ ] A coverage regression raises an incident; guidance never promises keys the extractor drops.

### PRO-005 — Right-sizing experiments with performance guardrails
Release: R1 · Estimate: 27–39 h · Risk: H · Decisions: D-11, D-13 · Closes: G-PRO-05
Why / where: INS-007 validates savings on cost only; a change that saves money while degrading latency, queueing or spill would be reported as a verified saving. Plugs in after INS-006/INS-007 and WRK-104 (P5).
Dependency changes: new; deps INS-006, INS-007, WRK-104, INS-102, GOV-101.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| PRO-005-S01 | Author the guardrail contract per action type (warehouse: p95/p99 elapsed from t-digest, queued-overload time share, local/remote spill bytes, timeout failures; query rewrite: family p95; schedule change: freshness lag) with default thresholds (p95 +25 %, queue share +10 points, any new remote spill) editable per action with approval. | `data/contracts/guardrails.v1.json` | Contract reviewed with INS and WRK owners. | 3 |
| PRO-005-S02 | Confirm the D-11 family aggregates carry the needed sketches and sums (elapsed t-digest, queued time, spill bytes); raise a WRK-104 change request for any missing field. | change request or confirmation | WRK-104 owner acknowledgement recorded. | 2 |
| PRO-005-S03 | Add the experiment plan to actions: hypothesis, change (e.g., LARGE → MEDIUM, AUTO_SUSPEND 600 → 60), window ≥ 14 complete days, guardrails, rollback instruction; frozen with the INS-006 baseline hash. | `apps/api/actions/experiments.py` | Editing a frozen plan after IMPLEMENTED → 409. | 3 |
| PRO-005-S04 | Evaluate guardrails from merged sketches (never averaged percentiles — G-API-04): PASS, BREACH or INCONCLUSIVE (fewer than 200 executions in either window). | `services/intelligence/guardrails.py` | Sketch-merged p95 is within the t-digest error bound of the exact p95 on the fixture. | 4 |
| PRO-005-S05 | Join with INS-007: VALIDATED gains `performance_outcome`; SAVING + BREACH is labelled "saving with regression" and excluded from verified totals unless the owner accepts the trade-off (reason, audited). | integration | Home "Realized YTD" excludes the BREACH fixture until acceptance. | 3 |
| PRO-005-S06 | Evaluate daily during the post window; on BREACH notify the action owner with the rollback instruction (no automatic change in R1). | scheduled evaluation + GOV-007 notification | BREACH fixture notifies once per episode. | 3 |
| PRO-005-S07 | Enrich WH01/WH02 insights with a proposed experiment plan (predicted cost range, required window, guardrails). | INS evidence renderer | Insight detail shows the proposed plan. | 2 |
| PRO-005-S08 | UI: experiment card on action detail (baseline vs post p95 chart, queue share, spill, status, accept-trade-off dialog). | `apps/web/src/pages/actions/experiment/` | Playwright asserts BREACH rendering and the audited acceptance. | 3 |
| PRO-005-S09 | Fixtures: saves 60.00/day with p95 1.0 s → 1.8 s (+80 %) → BREACH; saves 60.00/day with p95 +5 % → PASS; 150 executions → INCONCLUSIVE; new remote spill → BREACH. | `tests/spec/PRO-005/` | All pass. | 3 |
| PRO-005-S10 | Evidence. | `docs/evidence/PRO-005/<commit>/` | – | 1 |

Task acceptance:
- [ ] No saving that breaches a performance guardrail counts as verified without an audited owner decision.
- [ ] Guardrails are computed from mergeable sketches, never from averaged percentiles.

### PRO-006 — FOCUS 1.3-aligned allocated-cost export and scheduled bulk exports
Release: R1 · Estimate: 29–42 h · Risk: M · Decisions: D-12, D-13, D-15, D-23 · Closes: G-PRO-06
Why / where: enterprise FinOps teams consolidate spend in multi-cloud tools or their own warehouse; FOCUS 1.3 is the FinOps Foundation standard and Snowflake publishes unallocated FOCUS data [N5]. Bridge's allocated, reconciled ledger in FOCUS shape makes it the Snowflake source of truth for those tools. Export kinds belong to API-102 and downloads to SEC-006-S08 (RECONCILIATION U-10). Plugs in after API-102 and ALC-008 (P5).
Dependency changes: new; deps API-102, API-004, ALC-005, ALC-008, FIN-009, FIN-010, SEC-006, RPT-004, GOV-006.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| PRO-006-S01 | Write the Bridge → FOCUS 1.3 mapping: BilledCost, EffectiveCost, ListCost, ContractedCost from ledger price bases; BillingCurrency; ChargePeriodStart/End (UTC day); ChargeCategory from entry kind (Usage, Purchase, Tax, Credit, Adjustment); ServiceName/ServiceCategory from service family; ResourceId; SubAccountId (account); Tags (allocation book, usage-group path); `x_DataStatus`, `x_ReconciliationStatus`, `x_PublicationId`, `x_AllocationBook`, `x_Revision`; list non-conformant columns (TO VERIFY against the FOCUS 1.3 text). | `data/contracts/exports/focus_1_3_mapping.md` | Reviewed by FIN and ALC owners. | 4 |
| PRO-006-S02 | Build `srv_export_focus_daily`: allocated charges per book, exact decimals, one row per charge × allocation target, row policies applied. | `data/dbt/models/serving/exports/srv_export_focus_daily.sql` | Σ rows = ledger total per day and currency to the cent. | 4 |
| PRO-006-S03 | Add API-102 export kinds `FOCUS_1_3_ALLOCATED` and `LEDGER_NATIVE`: Parquet (zstd) and CSV, partitioned by month, manifest with row counts, per-currency sums, publication ids and sha256. | export kind registration | Manifest sums equal serving totals for the pinned publication. | 3 |
| PRO-006-S04 | Schedule exports (monthly after close or MONTH_STABLE, selectable; daily rolling labelled PROVISIONAL) through RPT-004; notify by signed `export.ready` webhook (GOV-006 Standard Webhooks) and e-mail; download via SEC-006-S08; 30-day artifact retention. | `apps/api/exports/schedules.py` | Scheduled fixture delivers once per period with a verifiable signature. | 3 |
| PRO-006-S05 | Restatements (FIN-107): a restated closed month produces a new export revision with `x_Revision` and a change manifest; prior files kept until expiry. | revision logic | Restated fixture yields revision 2 with the delta listed. | 2 |
| PRO-006-S06 | Unload server-side (COPY INTO a per-tenant stage prefix through the broker JOB class under the tenant profile), never streaming through the API process; size cap and LCH-101 quota. | job implementation | 10 M-row fixture exports without API memory growth; over-quota → 403. | 3 |
| PRO-006-S07 | Authorization: FinOps Admin and Finance roles; group-restricted users export only their scope; hidden groups never contribute totals. | tests | Restricted export sum equals the restricted Explorer total. | 2 |
| PRO-006-S08 | Fixtures: FOCUS total = ledger total per currency/day; allocation targets sum to the charge; tax and credit lines categorized; restated month. | `tests/spec/PRO-006/` | All pass. | 3 |
| PRO-006-S09 | Validate files with the FinOps Foundation validator if one exists for 1.3 (TO VERIFY) and a DuckDB load script as a consumer test. | `tools/exports/validate_focus.py` | Validator or consumer test passes on the fixture export. | 2 |
| PRO-006-S10 | Docs: schema reference and loading guides (Snowflake, BigQuery, Databricks) on SAS-002; `/settings/exports` UI for schedules. | docs pages, UI | Playwright creates a schedule; guide commands tested on DuckDB. | 2 |
| PRO-006-S11 | Evidence. | `docs/evidence/PRO-006/<commit>/` | – | 1 |

Task acceptance:
- [ ] Scheduled FOCUS-shaped and native exports reproduce ledger and allocation totals exactly, with data status and revision per row.
- [ ] Exports respect the requester's scope and are delivered only through the artifact broker.

### PRO-007 — Capture BI-tool attribution signals before the WRK-101 allowlist freeze
Release: R1 · Estimate: 4–6 h · Risk: H · Decisions: D-10, D-11, D-20, D-34 · Closes: G-PRO-07
Why / where: select attributes cost to Looker, Sigma and Tableau assets [S8]; the plan covers Power BI only (WRK-003). Extraction is irreversible (G-WRK-01): Tableau's default `QUERY_TAG` LUIDs and Sigma's comment keys must be allowlisted before the first backfill or 365 days of BI attribution are lost. D-01/D-20: promote the R2 part to R1 if the first customer's main BI tool is one of these.
Dependency changes: new; no dependency (specification task). WRK-101 +PRO-007 (allowlist v1 must include these keys before freeze; extraction is irreversible, G-WRK-01). The R2 remainder is PRO-014.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| PRO-007-S01 | Specify signals: Tableau query tagging (on by default for Snowflake; workbook/dashboard/worksheet LUIDs in `QUERY_TAG`), Sigma query comments (keys TO VERIFY LIVE), Looker context comment `-- Looker Query Context '{"user_id":…,"history_slug":…,"instance_slug":…}'` (prepended — Snowflake strips leading comments, so presence in `QUERY_TEXT` is TO VERIFY LIVE), Hex/Metabase (TO VERIFY). | `docs/05-ingestion/bi-signals.md` | Each signal marked VERIFIED, ABSENT or TO VERIFY with a source link. | 2 |
| PRO-007-S02 | Submit the allowlist change to WRK-101 before freeze: Tableau LUID keys, Sigma keys, Looker slugs where extractable; PII review (Looker `user_id` → HMAC per D-10); golden-corpus samples. | WRK-101 change request | Accepted into allowlist v1 before ING-010's first backfill. | 2 |

Task acceptance:
- [ ] BI metadata keys (Tableau LUIDs, Sigma keys, Looker slugs where extractable) are in WRK-101 allowlist v1 with PII review, so they are captured from the first backfill even before the BI pages ship.

### PRO-008 — Unit economics with customer business metrics
Release: R2 · Estimate: 28–41 h · Risk: M · Decisions: D-10, D-12, D-15 · Closes: G-PRO-08
Why / where: Vantage, CloudZero and Finout lead with unit costs [V1, Z1, F1]; INS AI07/SP04 need an approved business denominator that no source provides. Plugs in after ALC-005 and CTL-005.
Dependency changes: new; deps ALC-005, ALC-102, API-001, CTL-005, CON-003, SEC-006, GOV-003, INS-005.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| PRO-008-S01 | Define business metrics: name, unit, daily grain, optional dimensions (usage group, product), source (CSV upload or customer view), maker-checker approval, versioning. | `data/contracts/business_metric.v1.json` | Schema suites pass. | 3 |
| PRO-008-S02 | Implement CSV upload: schema validation, exact decimals, duplicates by (metric, date, dims) → revision; evidence stored with Object Lock; published through D-04 config publication. | `apps/api/business_metrics/upload.py` | Malformed row rejected with line number; re-upload creates a revision. | 4 |
| PRO-008-S03 | Add the customer-view source: contract for a customer-created `BUSINESS_METRICS_DAILY` view, install-script grant (CON-003 optional block), daily extraction of that view only. | source contract, script block | Probe reports the view readable; no other object is granted. | 4 |
| PRO-008-S04 | Register unit-cost metrics: allocated cost (book) ÷ business metric at matching grain; null with reason when the denominator is missing or zero, never 0. | registry YAML | Zero-denominator fixture returns null with `DENOMINATOR_ZERO`. | 3 |
| PRO-008-S05 | Build the unit economics page (trend, by group) and the metric management page. | `apps/web/src/pages/unit-economics/` | UX-008 state matrix passes. | 4 |
| PRO-008-S06 | Add a unit-cost regression monitor condition and feed AI07/SP04 inputs. | GOV-003 entry, INS input | Fixture rise > 25 % opens an incident. | 3 |
| PRO-008-S07 | Tests: mixed currency refused, restated metric revision propagates, restricted viewer scope. | `tests/spec/PRO-008/` | All pass. | 3 |
| PRO-008-S08 | Add capability `unit_economics.read` (business metrics may be commercially sensitive). | SEC-004 capability | Viewer without capability → 403. | 2 |
| PRO-008-S09 | Docs and evidence. | SAS-002 page, `docs/evidence/PRO-008/<commit>/` | – | 2 |

Task acceptance:
- [ ] Unit costs use approved denominators only and are null, never zero, without one.

### PRO-009 — Opt-in automated warehouse optimization (action plane)
Release: R2 (owner go/no-go, §5 Q3) · Estimate: 51–74 h · Risk: H · Decisions: D-02, D-08, D-19, D-25 · Closes: G-PRO-09
Why / where: automation is the second competitive axis (select [S5], Keebo [K1], Espresso [E1], Slingshot [C1]); PRD §10/§147 reserve an action plane with a separate identity, opt-in, allowlist, bounds, approval, rollback, audit and verification. It changes Bridge's posture from read-only, so it is not R1. Plugs in after PRO-005.
Dependency changes: new; deps CON-003, INF-103, SEC-001, SEC-102, REL-102, INS-006, INS-007, PRO-005, OPS-004, LCH-101.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| PRO-009-S01 | Write the ADR and threat-model delta: per-account operator WIF identity `BRIDGE_FINOPS_OPERATOR` with its own IAM role, never inherited by the reader; consent text. | ADR, SEC-001 update | Security owner approval. | 4 |
| PRO-009-S02 | Extend the install/revoke scripts: operator role with `MODIFY` only on allowlisted warehouses (minimal privilege for size, auto-suspend and cluster settings TO VERIFY LIVE). | CON-003 template block | Operator cannot alter a non-allowlisted warehouse (live test on INF-101 estate). | 3 |
| PRO-009-S03 | Define the policy model per warehouse: size min/max, auto-suspend range, cluster range, schedules, change budget per day, mode (auto within bounds or maker-checker). | `data/contracts/automation_policy.v1.json` | Out-of-bounds policy rejected. | 3 |
| PRO-009-S04 | Build the executor: separate task role, the only holder of operator identities (launcher pattern as ING-106), idempotent change commands with captured before-state. | `services/automation_executor/` | Replayed command is a no-op. | 4 |
| PRO-009-S05 | Run the guardrail loop hourly on PROVISIONAL data (PRO-005 guardrails); on breach roll back to the before-state and notify. | guardrail job | Injected latency regression triggers rollback within one hour. | 4 |
| PRO-009-S06 | Build the schedule engine (tenant time zone, DST-safe) on the RPT-004 resolver. | scheduler | Weekday 08:00–18:00 Europe/Paris schedule correct across DST. | 3 |
| PRO-009-S07 | Detect manual drift (INS-102 snapshot differs from last applied state) → pause automation for that warehouse and notify. | drift detector | Manual resize fixture pauses automation. | 3 |
| PRO-009-S08 | Audit every change (policy version, approver, before/after, ALTER query id) in the customer-visible log; QUERY_TAG `bridge_finops:action`. | audit events | Each change has exactly one audit event. | 2 |
| PRO-009-S09 | Add kill switches (global, tenant, account, warehouse) on REL-102 with ≤ 60 s propagation. | flags | Measured propagation ≤ 60 s. | 2 |
| PRO-009-S10 | Feed automation changes to INS-007 as system actions with frozen baselines; report automated verified savings separately from manual. | integration | Savings page splits automated vs manual. | 3 |
| PRO-009-S11 | Build the automation settings UI per warehouse (bounds, schedule, mode) and activity log. | `apps/web/src/pages/automation/` | UX-008 state matrix passes. | 4 |
| PRO-009-S12 | Adversarial tests (OPS-004 extension): executor cannot touch other warehouses, exceed bounds or act across tenants. | `tests/security/automation/` | All denied. | 4 |
| PRO-009-S13 | Live proof on the INF-101 estate: 14-day schedule on a generator warehouse with measured savings and guardrail PASS. | evidence | Savings and guardrail results recorded within the D-32 credit budget. | 3 |
| PRO-009-S14 | Rollback drill and failure injection (Snowflake error mid-change, partial cluster change). | drill record | Before-state restored in every case. | 3 |
| PRO-009-S15 | Gate the feature by entitlement (LCH-101 feature flag `automation`). | plan feature | Tenant without the feature cannot enable a policy. | 1 |
| PRO-009-S16 | Maker-checker approval UX with step-up (SEC-102) for manual mode. | UI + API | Self-approval refused. | 3 |
| PRO-009-S17 | Update customer docs, security whitepaper and DPA description (write access), evidence. | docs, `docs/evidence/PRO-009/<commit>/` | Counsel notified of the processing change. | 2 |

Task acceptance:
- [ ] Automation acts only on allowlisted warehouses within bounds, through a separate identity, with audit, kill switches and automatic rollback on guardrail breach.
- [ ] Automated savings are verified by INS-007 and reported separately.

### PRO-010 — Allocated-cost delivery via Snowflake Secure Data Sharing
Release: R2 · Estimate: 26–38 h · Risk: H · Decisions: D-02, D-05, D-23 · Closes: G-PRO-10
Why / where: Snowflake customers want the allocated ledger inside their own account for joins and BI without ETL; select exports metadata to a GCS bucket rather than sharing [S15]. Cross-region delivery replicates data and must respect D-23. Plugs in after PRO-006.
Dependency changes: new; deps PRO-006, DBT-006, SEC-005, INF-008, REL-103, OPS-005.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| PRO-010-S01 | Design a per-tenant share (dedicated database of secure views over the PRO-006 export dataset, bound to one tenant — no multi-tenant `CURRENT_ACCOUNT()` policy) and consumer-account verification by challenge (customer runs a query returning their locator and a one-time token). | ADR | Security owner approval. | 4 |
| PRO-010-S02 | Same-region direct share; cross-region only via private listing with auto-fulfillment restricted to EU regions unless the customer signs a residency waiver (D-23); replication cost attributed to the tenant (OPS-009). | provisioning rules | Non-EU fulfillment without waiver is refused. | 4 |
| PRO-010-S03 | Build the provisioner: create database/share per tenant, grant secure views, add consumer; revoke as an OPS-005 deletion stage handler. | `services/share_provisioner/` | Offboarding removes the share; consumer query fails afterwards. | 4 |
| PRO-010-S04 | Pin shared views to the tenant's published revision (D-05) and expose `publication_id`; version via REL-103 namespaces. | view definitions | Shared totals equal Explorer for the same publication. | 3 |
| PRO-010-S05 | Security tests: consumer cannot see other tenants or view definitions; revocation is immediate; residency guard. | `tests/security/sharing/` | All pass on the INF-101 estate. | 4 |
| PRO-010-S06 | UI: Settings › Data delivery (request, verify account, status, revoke). | UI | Only Owner/FinOps Admin can request. | 3 |
| PRO-010-S07 | Docs: consumer setup, sample queries, compute-cost note. | SAS-002 page | Reviewed. | 2 |
| PRO-010-S08 | Evidence with a consumer account on the INF-101 estate. | `docs/evidence/PRO-010/<commit>/` | Totals match Explorer. | 2 |

Task acceptance:
- [ ] Each tenant's share exposes only its own published allocated data; residency is enforced by default.

### PRO-011 — Read-only MCP server over the semantic API
Release: R2 · Estimate: 23–33 h · Risk: M · Decisions: D-02, D-22 · Closes: G-PRO-11
Why / where: select exposes its Copilot over MCP [S11] and Vantage supports MCP [V1]; PRD §145–§146 target MCP and a Copilot that queries the semantic registry with citations. A thin, read-only MCP adapter over the public API gives governed AI access without an in-app LLM. Plugs in after API-006.
Dependency changes: new; deps API-006, API-001, API-005, API-104, PRO-002.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| PRO-011-S01 | Define tools: `list_metrics`, `query_metric` (registry-validated semantic request), `explain_number` (API-005), `root_cause` (PRO-002), `list_incidents`, `list_insights`, `get_budget_status`; read-only; no free SQL. | `apps/mcp/TOOLS.md` | Reviewed by API owner. | 3 |
| PRO-011-S02 | Implement the server with the MCP Python SDK (streamable HTTP transport) as a thin adapter calling the public API with the caller's token. | `apps/mcp/` | Reference MCP client lists and calls each tool on staging. | 4 |
| PRO-011-S03 | Authorization: user-delegated OAuth (authorization code + PKCE per the MCP authorization spec) mapped to Cognito, or API-006 machine clients; scopes = capabilities. | auth integration | Token without `analytics.read` cannot call `query_metric`. | 4 |
| PRO-011-S04 | Shape responses: every figure with unit, currency, maturity, publication id and deep link (citations); size limits with continuation. | response models | Snapshot tests pass. | 3 |
| PRO-011-S05 | Safety: per-client rate limits (API-006), customer-controlled names quoted as data (prompt-injection-safe rendering), audit per tool call. | middleware | Injection-shaped tag value is returned quoted; audit row per call. | 3 |
| PRO-011-S06 | Tests: scope parity with the UI for a restricted user; foreign tenant; revoked client. | `tests/spec/PRO-011/` | All pass. | 3 |
| PRO-011-S07 | Docs on the developer portal (SAS-015) and evidence. | docs, `docs/evidence/PRO-011/<commit>/` | – | 2 |
| PRO-011-S08 | Publish client configuration snippets for common MCP clients. | docs section | Snippets verified with one client. | 1 |

Task acceptance:
- [ ] AI clients read Bridge data only through registry-validated, scope-enforced, audited read-only tools with cited figures.

### PRO-012 — Ticketing and paging integrations for actions and incidents (Jira, ServiceNow, PagerDuty)
Release: R2 · Estimate: 23–33 h · Risk: M · Decisions: D-23 · Closes: G-PRO-12
Why / where: PRD §95 lists Jira and PagerDuty as later destinations (Opsgenie reaches end of support in 2027, OPS-102); enterprise FinOps routes recommendations into engineering backlogs. Plugs in after GOV-006 and INS-006.
Dependency changes: new; deps GOV-006, GOV-007, GOV-102, INS-006, GOV-008.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| PRO-012-S01 | Build the Jira Cloud OAuth 2.0 (3LO) app and per-tenant project/issue-type mapping. | `services/notifications/adapters/jira.py` | Test site install succeeds; tokens stored as secrets. | 4 |
| PRO-012-S02 | Create/update Jira issues from actions (INS-006) with a back-link; Jira status changes produce action status *suggestions* only (VALIDATED stays measurement-only). | integration | Same action → one issue; Jira "Done" never sets VALIDATED. | 4 |
| PRO-012-S03 | Build the ServiceNow adapter (table API, OAuth client credentials) for incidents and tasks from monitors. | adapter | Test instance receives one record per incident. | 4 |
| PRO-012-S04 | Build the PagerDuty Events API v2 adapter (trigger, acknowledge, resolve; `dedup_key` = incident id). | adapter | Recovery resolves the same PagerDuty incident. | 3 |
| PRO-012-S05 | Reuse the egress proxy and SSRF guard; secrets write-only; destination health in GOV-006-S13. | configuration | SSRF suite passes for new hosts. | 2 |
| PRO-012-S06 | Tests: idempotency, revoked OAuth → destination PAUSED, status-sync conflict handling. | `tests/spec/PRO-012/` | All pass. | 3 |
| PRO-012-S07 | Docs and evidence. | SAS-002 pages, `docs/evidence/PRO-012/<commit>/` | – | 2 |
| PRO-012-S08 | Document the generic-webhook path for Jira Data Center and other tools. | docs section | Reviewed. | 1 |

Task acceptance:
- [ ] Actions and incidents reach Jira, ServiceNow or PagerDuty once per logical event; external status never validates savings.

### PRO-013 — Snowflake Marketplace / Native App distribution decision spike
Release: R2 · Estimate: 21–30 h · Risk: M · Decisions: D-17, D-23, D-36 · Closes: G-PRO-13
Why / where: capacity customers want to pay from their Snowflake commitment; Marketplace Capacity Drawdown is GA only for US-based consumers buying from US-based providers and accepts data shares, Native Apps and Connected Apps [N6]; Sundeck and Revefi distribute through the Marketplace [D1, R1x]. The French entity (D-36) is ineligible today; a Native App would move computation into customer accounts. Decision needed before any build.
Dependency changes: new; no hard deps; inputs OPS-009, LCH-001, SEC-001.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| PRO-013-S01 | Collect current MCD eligibility (provider and consumer countries, product types, Connected App requirements) with the Snowflake partner team (TO VERIFY). | `docs/decisions/marketplace/eligibility.md` | Written confirmation attached. | 2 |
| PRO-013-S02 | Describe options: A — Connected App listing for the existing SaaS (billing through the Marketplace, product unchanged); B — Native App running extraction/transformation inside the customer account; C — no listing. | options memo | Reviewed by architecture owner. | 3 |
| PRO-013-S03 | Assess option B's architecture impact: components that move (extractor, transforms), what stays central (publication, UI, ledger close), isolation, upgrades, residency. | analysis | Conflicts with ADRs listed explicitly. | 4 |
| PRO-013-S04 | Assess commercial impact: Marketplace fees (TO VERIFY), invoicing entity (US entity?), D-17 band metering through Marketplace pricing plans. | analysis | Owner-readable cost table. | 3 |
| PRO-013-S05 | Assess security and DPA roles when code runs in the customer account. | analysis | Counsel questions listed. | 2 |
| PRO-013-S06 | Prototype a free private listing in a provider sandbox to measure effort. | prototype record | Listing visible to a test consumer. | 4 |
| PRO-013-S07 | Decision memo with recommendation; owner decision recorded as a new D-xx. | `docs/decisions/marketplace/decision.md` | Owner decision recorded. | 2 |
| PRO-013-S08 | Evidence. | `docs/evidence/PRO-013/<commit>/` | – | 1 |

Task acceptance:
- [ ] The owner decides on Marketplace distribution with verified eligibility, architecture and commercial facts.

### PRO-014 — BI-tool workload attribution: Tableau, Sigma, Looker (classifier, marts, metadata, pages)
Release: R2 · Estimate: 34–49 h · Risk: H · Decisions: D-10, D-11, D-20, D-34 · Closes: G-PRO-07
Why / where: select attributes cost to Looker, Sigma and Tableau assets [S8]; the plan covers Power BI only (WRK-003). Extraction is irreversible (G-WRK-01): Tableau's default `QUERY_TAG` LUIDs and Sigma's comment keys must be allowlisted before the first backfill or 365 days of BI attribution are lost. D-01/D-20: promote the R2 part to R1 if the first customer's main BI tool is one of these. D-01/D-20: promote to R1 if the first customer's main BI tool is one of these.
Dependency changes: new (R2 remainder of PRO-007); deps PRO-007, WRK-101, WRK-001, WRK-104, API-104, UX-002.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| PRO-014-S01 | Add classifier rules to WRK-001 (set-based dbt SQL) for BI_TABLEAU, BI_SIGMA, BI_LOOKER with evidence classes TAGGED, COMMENTED, SESSION_ONLY. | classifier rules + Python oracle cases | Oracle and SQL agree on the corpus. | 4 |
| PRO-014-S02 | Build `fct_bi_activity` per tool (Tableau workbook/view LUID per session window, Sigma workbook/element, Looker history slug): query count, cost = Σ distinct query costs, wall time. | `data/dbt/models/marts/bi/*` | Each query's cost counted once across tool, workbook and dashboard levels. | 4 |
| PRO-014-S03 | Design name enrichment per tenant: default ids only; optional CSV upload of LUID → name; optional read-only BI API credential (Tableau PAT, Looker API client) in Secrets Manager — a new third-party credential class for SEC review. | `docs/05-ingestion/bi-metadata.md` | SEC owner review recorded. | 4 |
| PRO-014-S04 | Build the metadata worker for Tableau REST (workbooks, views) and Looker API (dashboards, looks, explores; history-to-query mapping TO VERIFY LIVE) through the egress proxy, rate-limited, metadata only. | `services/bi_metadata/` | Fixture API responses populate names; no data rows fetched. | 4 |
| PRO-014-S05 | Register records datasets and dimensions (`bi_tool`, `bi_workbook`, `bi_dashboard`, `bi_explore`) in API-104. | registry YAML | API-104 serves activity lists with keyset paging. | 2 |
| PRO-014-S06 | Build `/explore/workloads/bi` list page (cost per dashboard/workbook, trend, filters by tool). | `apps/web/src/pages/workloads/bi/` | UX-008 state matrix passes. | 3 |
| PRO-014-S07 | Build per-tool detail pages (top queries, refresh cadence, users by pseudonym). | detail pages | Missing names render ids with an explanation, never invented names. | 3 |
| PRO-014-S08 | Produce "refreshing but not viewed" evidence for R2 pipeline detectors (data only). | model | Fixture unused workbook flagged in evidence table. | 2 |
| PRO-014-S09 | Tests: spoofed tags labelled DECLARED not VERIFIED (WRK spoofing rule), single counting, ids without names, cross-account activities kept separate. | `tests/spec/PRO-014/` | All pass. | 4 |
| PRO-014-S10 | Security review of stored BI credentials: least privilege, rotation, revocation on offboarding (OPS-005 stage handler), audit. | review record | Revocation removes the secret within one run. | 2 |
| PRO-014-S11 | Docs and evidence. | SAS-002 page, `docs/evidence/PRO-014/<commit>/` | – | 2 |

Task acceptance:
- [ ] Cost per dashboard/workbook is counted once, evidence-classed, and never shows fabricated names.
