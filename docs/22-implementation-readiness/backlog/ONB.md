# ONB — Implementation-readiness review and production backlog

Canonical contract: [onboarding.md](../../18-customer-onboarding/onboarding.md), [FIRST_VALUE.md](../../18-customer-onboarding/FIRST_VALUE.md), PRD §119–§121, §158. Tasks reviewed: ONB-001, ONB-002, ONB-003, ONB-004, ONB-005. Reviewer: domain audit agent, 2026-09-27. Status of all tasks: NOT_STARTED.

## 1. Verdict

Implementable after three design decisions are written down. The onboarding contract is honest about partial history, snapshot-only metadata and reconciliation status, but (1) it does not say whether onboarding state is a second workflow engine or a projection of connection/sync/finance facts — the former will diverge; (2) it has no timeline, although customer-side lead time (procurement, change approval, network allowlisting, six admin script runs) dominates and the backfill costs the customer credits that must be disclosed before consent (D-08); (3) "first value" mixes things available in week 1 (historical cost, provisional reconciliation, retroactive allocation) with things that only exist after the first full post-enrollment month is closed (tag-faithful chargeback, Bridge-closed period, verified savings). Offboarding export/reconnection has no owner, and PRD §158's "without Bridge Data manually intervening" conflicts with the white-glove ONB-003..005 unless interventions are logged as defects.

## 2. Findings

### G-ONB-01 · Onboarding state would duplicate domain state
Severity: HIGH · Type: AMBIGUITY
Evidence: `onboarding.md` — "Each step stores configuration version, actor, prerequisite evidence, started/completed times and blocked reason. No analytical totals are duplicated into PostgreSQL"; `ONB-001` — "Persist resumable step state".
Why it matters: if steps are stored as mutable status rows, a revoked account, a re-planned backfill or a new reconciliation run leaves the onboarding checklist saying COMPLETED while Data Health says FAILING — exactly the "misleading completion" ONB-001 must prevent.
Resolution: step status is a pure projection of domain facts (connection/capability, backfill plan and coverage, reconciliation run, ruleset/simulation, budget/monitor/report, insight disposition) plus an append-only acknowledgement ledger for human decisions (gap acceptance, consent, limitation acceptance, optional skip), each bound to the exact domain revision it acknowledges. A cached projection row stores the source versions it was computed from and is recomputed on domain outbox events and by a 10-minute sweep. State machine in §3.
Affects: ONB-001.

### G-ONB-02 · No realistic onboarding timeline; customer cost of backfill undisclosed
Severity: HIGH · Type: GAP
Evidence: `onboarding.md` — "Estimate completion only when throughput evidence exists"; `FIRST_VALUE.md` step 2 — "install per-account WIF using reviewed scripts"; D-08 — "wizard shows estimated monthly credits before consent"; `orchestration.md` — "backfill 2 total/1 per tenant".
Why it matters: M11/M12 planning and the first customer's expectations assume onboarding is a step, not weeks. For a 5-account customer the critical path is customer-side; and with one backfill slot per tenant, five accounts backfill sequentially. Customer credits: steady state at hourly cadence bills ≈ 90–120 s per resume (60 s minimum + work + 60 s AUTO_SUSPEND) → 24 × 90–120 s ≈ 0.6–0.8 XSMALL-hours/day ≈ 18–24 credits/month per account → **≈ 90–120 credits/month for 5 accounts** (ASSUMPTION until OPS-105 calibrates; XSMALL = 1 credit/hour). Backfill: 5 accounts × 365 daily chunks × 2 query-grain sources × ≈ 40 s/chunk ≈ 146,000 s ≈ 41 credits one-off (assumed 40 s/chunk, TO VERIFY by OPS-105).
Resolution: plan with the timeline below; new ONB-101 computes and displays credit and duration ranges from OPS-105 coefficients before consent; the consent acknowledgement binds to the estimate version.

| Phase | Elapsed | Critical path |
|---|---|---|
| P0 order form, DPA, security questionnaire | 5–20 business days | customer procurement/security (LCH-102 pack) |
| P1 scope record, tenant, invitations | 1 day | Bridge CS (ONB-003) |
| P2 customer change approval + network policy allowlist of NAT IPs (D-09) | 2–10 business days | customer IT |
| P3 1 organization-level + 5 account scripts (≈ 20–40 min each) | 0.5–2 days | customer ORGADMIN/ACCOUNTADMIN |
| P4 capability probes, gap acceptance, consent with credit estimate | 0.5 day | customer admin + finance |
| P5 finance-first backfill (daily billing sources, 365 d) | hours | Bridge |
| P6 query-grain backfill (5 accounts sequential) | 1–4 days (OPS-105 measured) | Bridge; customer credits |
| P7 catch-up to steady state | < 1 day | Bridge |
| P8 reconciliation vs Snowflake currency data for M−1 or M−2 | day after P5 | Bridge + customer finance |
| P9 invoice reconciliation | when customer supplies invoice | customer finance |
| P10 workshop: ownership, allocation simulation, budget, monitor, report, insight | weeks 2–3 | customer FinOps |
| P11 FV-1 acceptance | ≈ 3–4 weeks after P3 | – |
| P12 FV-2: first Bridge close of a full post-enrollment month | first full month end + 5 days (≈ 5–9 weeks after P3) | – |

Affects: ONB-003, ONB-004, ONB-005, new ONB-101; LCH-002/LCH-004 timing.

### G-ONB-03 · "Complete period", first chargeback and savings cannot all be in first value
Severity: HIGH · Type: AMBIGUITY
Evidence: `FIRST_VALUE.md` step 5 — "Reconcile a complete period"; step 3 — "Label snapshot histories as beginning at enrollment"; `transformation.md` — "For snapshot-only metadata, capture SCD2 from first observation and record uncertainty before enrollment"; `intelligence.md` — "at least 14 complete comparable daily observations"; D-13 — "month considered billing-stable after month_end+N days (N configurable, default 5)"; `source-catalog.md` USAGE_IN_CURRENCY_DAILY — "up to 72h latency".
Why it matters: a complete month does exist on day 1 because billing sources retain history — but only if onboarding happens after month_end + 5 days (+ 72 h latency) of the previous month; otherwise it is M−2. Tag/ownership state before enrollment is unknown, so any chargeback for a pre-enrollment month uses current tags retroactively. Verified savings need ≥ 14 complete days after an action. Treating all as "first value" either delays acceptance by 2 months or overstates evidence.
Resolution: split first value. **FV-1 (week 1–4)**: cost by account/service/day over retained history (credits; currency when ORGANIZATION_USAGE is available); warehouse query-attributed vs idle; top query families/roles; storage trend; Data Health with gaps; reconciliation of the latest billing-stable month vs Snowflake currency data (+ invoice when supplied); Bridge overhead (D-08); retroactive allocation simulation labelled "current tag state applied to past periods"; budget with forecast, monitor dry-run, one report; insight review and optional action with frozen baseline. **FV-2 (first full calendar month after enrollment, closed at month_end + 5 days)**: Bridge-closed period (FIN-010), tag-faithful showback/chargeback statement, budget vs actual for a full month, live monitor incidents, first verified saving only if the action is ≥ 14 complete days old. Period-selection rule: reconcile the latest month M with `month_end(M) + 5 d + 72 h ≤ now`. ONB-005 accepts FV-1; LCH-004 reviews FV-2.
Affects: ONB-004, ONB-005, LCH-004; PRD §119 step 14 wording.

### G-ONB-04 · PRD progress example contradicts the "no invented percentages" rule
Severity: MEDIUM · Type: CONTRADICTION
Evidence: PRD §120 — "Estimated coverage 96%", "Snowpipe loaded 2.4B rows / dbt transformed 2.3B rows"; `onboarding.md` — "use counts/dates, not invented percentages".
Why it matters: a blended percentage across sources hides a 241/365-day query gap behind a large metering denominator; loaded vs transformed row counts differ by deduplication, so 2.3 < 2.4 reads as unfinished work.
Resolution: per-source coverage ratio = covered_days / available_days (a measured ratio, allowed) plus requested vs available days; no cross-source blended percentage; stage counts shown per stage with a note that deduplication reduces rows; ETA shown only as a p50–p90 range after ≥ 3 completed chunks (ONB-101). Challenges PRD §120 example; resolution keeps its information.
Affects: ONB-001, ONB-101.

### G-ONB-05 · "Without Bridge Data manually intervening" vs white-glove onboarding
Severity: MEDIUM · Type: CONTRADICTION
Evidence: PRD §158 — "without Bridge Data manually intervening"; `ONB-003` — "Have customer execute reviewed scripts"; `ONB-005` — "first-value workshop".
Why it matters: an assisted first customer can hide product gaps (a CS engineer silently fixes grants, re-runs a backfill), so the self-serve claim is never tested.
Resolution: assistance is allowed; every operator action on a tenant during onboarding is recorded as `onboarding.manual_interventions` (reason code, step, ops API call id) and becomes a product backlog item; ONB-002 clean-room rehearsal proves the unassisted path on synthetic accounts; the acceptance record lists interventions.
Affects: ONB-001, ONB-002, ONB-005.

### G-ONB-06 · Offboarding export and reconnection have no owning task
Severity: MEDIUM · Type: GAP
Evidence: `onboarding.md` — "Offboarding pauses schedules, disables identities, exports approved records … Reconnection uses the same tenant/account identity mapping … do not create duplicate historical charges"; `RUNBOOKS.md` RB-14.
Why it matters: DPA terms require return or deletion of data at the end of service (GDPR Art. 28(3)(g)); a reconnect that creates a new account UUID duplicates history.
Resolution: new ONB-102 (export bundle, pause/disconnect/offboard semantics, reconnection re-binding by organization + account locator with coverage-aware backfill).
Affects: new ONB-102, OPS-005.

### G-ONB-07 · Onboarding blockers are not catalogued
Severity: MEDIUM · Type: GAP
Evidence: D-09 — "PrivateLink-only customer accounts = R2 (explicit onboarding blocker message in R1)"; `ONB-001` failure list — "no organization permission; unsupported history"; `source-catalog.md` — "Reseller access may be unavailable".
Why it matters: without stable codes and messages, the checklist shows generic errors and CS cannot plan (reseller customers have no currency data; standalone accounts have no organization view; network policies block the service user).
Resolution: blocker catalogue in §3 with code, detection, customer message and product consequence; each blocker maps to a step status BLOCKED with that code.
Affects: ONB-001, ONB-002.

### G-ONB-08 · Entitlement limits are needed at M5 but defined at M10
Severity: MEDIUM · Type: GAP (dependency)
Evidence: `LCH-001` — "show limits before costly backfill admission" (M10); `ONB-001` (M5) selects accounts and starts backfills.
Why it matters: the onboarding flow either ignores plan limits or is rebuilt at M10.
Resolution: `+LCH-101` (plan-agnostic entitlements at M2) on ONB-001 and ONB-101.
Affects: ONB-001, ONB-101.

### G-ONB-09 · First value is gated on verified-savings measurement (INS-007)
Severity: MEDIUM · Type: RISK (dependency)
Evidence: `ONB-005` deps include `INS-007` ("Measure normalized savings"); `FIRST_VALUE.md` step 8 — "do not claim savings before post-change verification".
Why it matters: INS-007 requires post-change observation windows; FV-1 only needs insight review and action/baseline capture.
Resolution: replace `ONB-005 −INS-007` with `+INS-006` (action workflow and baseline); INS-007 moves to LCH-004/FV-2. Challenges the current ONB-005 dependency list.
Affects: ONB-005.

## 3. Contract-first artifacts to author before coding

| Artifact | Exact content required | Produced by |
|---|---|---|
| `docs/onboarding/state-machine.md` | Steps (key, prerequisites, completion predicate over domain facts, acknowledgement type): S01 ORG_CREATED; S02 SNOWFLAKE_ORG_CONNECTED (optional → SKIPPED_OPTIONAL with ack "standalone coverage limited"); S03 ACCOUNTS_DISCOVERED; S04 ACCOUNTS_SELECTED (≤ entitlement); S05 ACCOUNT_WIF_INSTALLED (per account); S06 CAPABILITIES_VERIFIED (per account, required/optional); S07 HISTORY_PLAN_ACCEPTED (ack bound to plan revision + estimate version); S08 HISTORY_SYNCED (contiguous coverage of accepted available ranges); S09 RECONCILED (run status RECONCILED, or WARNING/FAILED/UNAVAILABLE + limitation ack → COMPLETED_WITH_LIMITATIONS, status text preserved); S10 OWNERSHIP_CLASSIFIED; S11 ALLOCATION_SIMULATED (conservation PASS); S12 BUDGET_CREATED; S13 MONITORS_CREATED (dry run done); S14 INSIGHT_REVIEWED (disposition or no-candidate ack); S15 FIRST_VALUE_PACK (restricted member invited, report delivered). Statuses: BLOCKED_BY_PREREQ, READY, IN_PROGRESS, WAITING_ON_CUSTOMER, WAITING_ON_SYSTEM, COMPLETED, COMPLETED_WITH_LIMITATIONS, FAILED, BLOCKED(code), SKIPPED_OPTIONAL. Run: ACTIVE, PAUSED, FV1_ACCEPTED, ABANDONED | ONB-001-S01 |
| DDL `onboarding.*` (PG) | `runs(tenant_id, run_id, status, revision, created_by, created_at)`; `step_acknowledgements(tenant_id, run_id, step_key, account_id NULL, ack_type, bound_ref, bound_revision, payload_hash, actor, created_at)` append-only; `step_projection(tenant_id, run_id, step_key, account_id NULL, status, blocked_code NULL, source_versions JSONB, computed_at)`; `manual_interventions(tenant_id, run_id, step_key, operator, reason_code, ops_call_id, created_at)` | ONB-001-S02 |
| OpenAPI onboarding paths | `GET /v1/onboarding`; `POST /v1/onboarding/runs` (idempotent, one ACTIVE per tenant); `POST /v1/onboarding/steps/{step_key}/acknowledgements` (If-Match revision, Idempotency-Key; body `{ack_type, bound_ref, bound_revision}`); `POST /v1/onboarding/pause`, `/resume` (delegate to sync) | ONB-001-S06 |
| `docs/onboarding/blockers.yaml` | Code → detection → customer message → consequence: PRIVATELINK_ONLY (R2 message), RESELLER_NO_ORG_USAGE (credits only, invoice via reseller), STANDALONE_ACCOUNT (no organization coverage), ORG_ACCESS_UNAVAILABLE (organization view privilege/organization account missing — TO VERIFY LIVE), NETWORK_POLICY_BLOCKED (show NAT IPs), MISSING_GRANT_<source>, ACCOUNT_ALREADY_BOUND, ENTITLEMENT_ACCOUNT_LIMIT, ENTITLEMENT_HISTORY_LIMIT, WAREHOUSE_QUOTA_EXHAUSTED (customer resource monitor suspended), SOURCE_RETENTION_SHORTER, CROSS_CLOUD_ACCOUNT (non-AWS egress disclosure) | ONB-001-S07 |
| `data/estimates/onboarding-estimate.v1.json` | Inputs (accounts, sources, available ranges, 7-day query volume, coefficients version); outputs (backfill credits range, steady credits/month range, duration p50–p90, rows) | ONB-101-S01 |
| `docs/onboarding/first-value.md` | FV-1 and FV-2 content lists from G-ONB-03, period-selection rule, acceptance fields | ONB-005-S01 |
| Export bundle manifest `tenant-export.v1.json` | datasets, period, publication id, files with SHA-256, row counts, currency totals | ONB-102-S01 |

## 4. Revised production backlog

### 4.0 Dependency corrections

| Task | Milestone | Dependencies now → proposed |
|---|---|---|
| ONB-101 (new) | M5 | ING-010, CON-005, OPS-105, LCH-101 |
| ONB-001 | M5 | CON-006, ING-012, UX-002 → +LCH-101, +ONB-101 |
| ONB-102 (new) | M9 | OPS-005, API-004, ALC-008, CON-006 |
| ONB-002 | M9 (drafts from M5) | ONB-001, OPS-010 → +ONB-102 |
| ONB-003 | M11 | REL-004, ONB-002, LCH-001 → +LCH-003 (go-live precedes first customer, see LCH), +LCH-102 (DPA signed) |
| ONB-004 | M11 | ONB-003, ING-010, FIN-010 → +ONB-101 |
| ONB-005 | M11 | ONB-004, ALC-008, GOV-008, INS-007, RPT-005 → −INS-007, +INS-006 |

### ONB-001 — Build resumable onboarding checklist as a projection of domain state
Release: R1 · Estimate: 52–78 h · Risk: H · Decisions: D-08, D-09, D-13, D-17, D-18 · Closes: G-ONB-01, G-ONB-04, G-ONB-05, G-ONB-07, G-ONB-08
Dependency changes: `+LCH-101`, `+ONB-101`.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ONB-001-S01 | Write the state machine (§3) with every transition, guard and bound acknowledgement. | `docs/onboarding/state-machine.md` | Reviewed by CS, FinOps and backend; every step has a completion predicate referencing a domain API. | 4 |
| ONB-001-S02 | Create the `onboarding.*` tables with tenant RLS; acknowledgements INSERT-only. | Alembic migration `onboarding_0001` | Runtime UPDATE on acknowledgements denied; RLS foreign-tenant read returns 0 rows. | 3 |
| ONB-001-S03 | Implement the projection engine as a pure function (domain snapshots + acknowledgements → step statuses) with fixture snapshots. | `services/onboarding/projection.py` | 25 fixtures incl.: 8 accounts selected / 7 published → S08 IN_PROGRESS "7 of 8"; reconciliation FAILED + ack → COMPLETED_WITH_LIMITATIONS with text "FAILED (−1.00 USD)". | 6 |
| ONB-001-S04 | Recompute on domain outbox events (`connection.changed`, `capability.probed`, `backfill.plan.changed`, `coverage.advanced`, `reconciliation.completed`, `ruleset.published`, …) plus a 10-min sweep. | `services/onboarding/recompute.py` | Revoking a role updates S06 within 1 min of the capability event; sweep repairs a dropped event. | 3 |
| ONB-001-S05 | Implement acknowledgements bound to revisions: gap acceptance → backfill plan revision; consent → estimate version + entitlement snapshot; limitation → reconciliation run id; optional skip → reason. A new plan revision invalidates the old ack. | `services/onboarding/acks.py` | Re-planned backfill turns S07 back to WAITING_ON_CUSTOMER. | 4 |
| ONB-001-S06 | Implement the API paths (§3) with Idempotency-Key and If-Match. | `apps/api/onboarding/` | Duplicate POST → same response; stale If-Match → 412. | 4 |
| ONB-001-S07 | Implement the blocker catalogue and map probe/sync errors to codes and messages (EN strings externalized, D-18). | `docs/onboarding/blockers.yaml`, `services/onboarding/blockers.py` | Each code has a fixture producing BLOCKED(code) with message. | 3 |
| ONB-001-S08 | Enforce entitlements (LCH-101) at account selection and history plan; show limits before consent. | calls to `entitlements.check()` | Selecting 6 accounts on a 5-account plan → ENTITLEMENT_ACCOUNT_LIMIT, nothing created. | 2 |
| ONB-001-S09 | Build the checklist UI: step cards, per-account sub-steps, stage progress (extraction, journal, Snowpipe, transformation, financial validation) as counts/dates; per-source coverage `covered_days / available_days`; requested vs available; ETA range only from ONB-101. | `apps/web/onboarding/` | Playwright: no blended percentage rendered; 241/365 query days shown as partial. | 8 |
| ONB-001-S10 | Implement UI states (loading, empty, partial, error, denied, success) per step; non-admin personas see read-only or denied. | same | Viewer cannot acknowledge (button absent and API 403). | 3 |
| ONB-001-S11 | Resume tests: close browser mid-backfill; double-click start; restart workers. | `tests/spec/ONB-001/test_resume.py` | Same run id after reload; exactly one backfill plan; projection identical after restart. | 3 |
| ONB-001-S12 | Revocation mid-onboarding: revoke one account's role. | `tests/spec/ONB-001/test_revoke.py` | That account S06 FAILED(MISSING_GRANT_…); others continue; onboarding not complete. | 3 |
| ONB-001-S13 | Completion rule: FV-1 requires S01–S15 COMPLETED/COMPLETED_WITH_LIMITATIONS/SKIPPED_OPTIONAL plus FV acknowledgement; connection success alone never completes. | projection rule + test | Fixture with only S01–S06 complete → not complete. | 2 |
| ONB-001-S14 | Record manual interventions from ops API calls tagged with the onboarding run. | `services/onboarding/interventions.py` | Operator replay during onboarding appears in the intervention list. | 2 |
| ONB-001-S15 | Isolation tests: foreign run id, foreign step acknowledgement, Analyst acknowledging a financial limitation. | `tests/isolation/test_onboarding.py` | 404 for foreign ids; 403 for Analyst (FinOps Admin only). | 2 |
| ONB-001-S16 | Funnel metrics without tenant dimensions (steps reached, time in step, blocker code counts) and per-tenant ops facts. | metrics registry entries | Dashboard shows funnel from synthetic runs. | 2 |
| ONB-001-S17 | Docs and evidence. | `docs/evidence/ONB-001/<commit>/` | – | 2 |

Task acceptance:
- [ ] Reload, double submission and worker restart resume the same run without duplicate pipelines.
- [ ] Checklist status can never disagree with Data Health/reconciliation for the same publication.
- [ ] Acknowledgements are bound to the domain revision they accept and are invalidated by a new revision.
- [ ] No blended coverage percentage or unsupported ETA is displayed.
- [ ] Connection success alone never completes onboarding.

### ONB-002 — Prepare customer and support documentation with clean-room rehearsal
Release: R1 · Estimate: 36–54 h · Risk: M · Decisions: D-08, D-09, D-13, D-18 · Closes: G-ONB-05
Dependency changes: `+ONB-102`; drafting starts at M5 (after CON-003/CON-006), finalization at M9.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ONB-002-S01 | Define the doc set and version it against the release manifest: getting started, admin install (organization + account), network/IP allowlist (D-09), permissions reference (required vs optional per source), customer credit footprint (D-08) with formula, FinOps interpretation, history limitations, pause/revoke/reconnect, offboarding/deletion, support intake. | `docs/customer/index.md` | Each guide states the release version it matches. | 3 |
| ONB-002-S02 | Write the installation guide from CON-003 templates with placeholders only; include customer-side verification queries (`SHOW GRANTS TO ROLE …`, `DESCRIBE USER …`, `SHOW NETWORK POLICIES`). | `docs/customer/admin-guide.md` | Guide script text equals generated script for the same config revision (CI diff). | 5 |
| ONB-002-S03 | Write revoke/uninstall (drop service user, role, warehouse, resource monitor, network policy) and the expected Bridge-side result. | `docs/customer/revoke.md` | Following it on SYN_B makes the next cycle fail as `SOURCE_PERMISSION_DENIED`. | 3 |
| ONB-002-S04 | Write the FinOps interpretation guide: PROVISIONAL/FINAL (D-13), reconciliation statuses, 270 vs 271 example, currencies, adjustments, Bridge overhead workload. | `docs/customer/finops-guide.md` | FinOps reviewer sign-off. | 5 |
| ONB-002-S05 | Write limitations: per-source retention, snapshot-only metadata from enrollment, reseller/standalone, PrivateLink R2, retroactive tag state. | `docs/customer/limitations.md` | Every blocker code in `blockers.yaml` referenced. | 3 |
| ONB-002-S06 | Write offboarding: export (ONB-102), deletion stages, residual backups (≤ 35 d), report link revocation. | `docs/customer/offboarding.md` | Residual periods equal OPS-005 matrix. | 2 |
| ONB-002-S07 | Write the internal CS playbook: timeline P0–P12, checkpoints, blocker code → action, escalation. | `docs/support/onboarding-playbook.md` | Used in REL-003 tabletop 1. | 4 |
| ONB-002-S08 | Clean-room rehearsal: an engineer who did not write the guides installs on SYN_B from docs only and reaches first data; log every unclear step and fix. | `docs/evidence/ONB-002/<commit>/clean-room.md` | First data reached with 0 undocumented steps after fixes. | 6 |
| ONB-002-S09 | Revoke rehearsal via the guide. | same | No new extraction after revoke. | 2 |
| ONB-002-S10 | Generate screenshots with Playwright and pull UI strings from the externalized catalog to prevent stale docs. | `tools/docs/screenshots.spec.ts` | Screenshot job runs in CI per release. | 3 |
| ONB-002-S11 | Lint docs/scripts for secrets and real locators. | CI rule | Planted fake locator fails lint. | 1 |
| ONB-002-S12 | Evidence. | `docs/evidence/ONB-002/<commit>/` | – | 2 |

Task acceptance:
- [ ] A second engineer reaches synthetic first data from the guides alone.
- [ ] Scripts in docs equal generated scripts for the same configuration revision.
- [ ] Credit footprint, IP allowlist and deletion residuals are documented before consent.

### ONB-003 — Prepare authorized first-customer environment and identities
Release: R1 · Estimate: 18–30 h (+ customer elapsed time) · Risk: M · Decisions: D-08, D-09, D-17, D-20, D-23 · Closes: G-ONB-02, G-ONB-07
Dependency changes: `+LCH-003` (production go-live precedes the first real tenant), `+LCH-102` (signed DPA).

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ONB-003-S01 | Create the private customer record: authorization, order form and DPA references, region (EU, D-23), privacy mode, requested history, named organization owner, Snowflake admin, finance approver, support contacts. | private system record; public template `docs/customer-records/onboarding-template.md` | All fields filled; public repo contains template only (lint). | 2 |
| ONB-003-S02 | Run the pre-flight questionnaire: editions, account count, clouds/regions, reseller, PrivateLink-only, network policies, IdP/SSO, organization-view access. | questionnaire record | Every blocker code resolved or accepted before scheduling P3. | 2 |
| ONB-003-S03 | Provision the tenant with the approved entitlement revision (LCH-001) and invite the Owner through the invitation workflow (explicit acceptance; SSO binding if contracted). | tenant id in private record | Owner logs in with MFA; no other members. | 2 |
| ONB-003-S04 | Generate organization-level and per-account installation packages tied to the configuration revision; deliver through the authenticated portal, not e-mail attachments. | packages | Package hash recorded; download audited. | 2 |
| ONB-003-S05 | Support the customer's allowlisting and script execution; record timestamps per account. | private log | 5 accounts installed or blockers recorded. | 2 |
| ONB-003-S06 | Verify identity/account match: probed locator = selected account; account bound to another tenant is refused. | probe evidence | Mismatch fixture on canary fails; customer accounts match. | 2 |
| ONB-003-S07 | Record capability evidence per account; customer admin acknowledges required/optional differences. | S06/S07 acknowledgements | Acks bound to probe versions. | 2 |
| ONB-003-S08 | With customer consent, run a revoke/restore test on one account; otherwise record NOT_RUN with reason (canary covers the mechanism). | evidence | Result recorded. | 1 |
| ONB-003-S09 | Verify D-08 setup: BRIDGE_FINOPS_WH size/suspend, resource monitor quota, QUERY_TAG on Bridge queries. | probe output | All present. | 1 |
| ONB-003-S10 | Review manual interventions so far and file product items. | backlog items | Each intervention has an item. | 1 |
| ONB-003-S11 | Agree the backfill window with the customer (avoid their month close and peak hours). | calendar entry | Window recorded. | 1 |
| ONB-003-S12 | Redacted evidence. | `docs/evidence/ONB-003/<commit>/` | No real locators in public evidence. | 2 |

Task acceptance:
- [ ] Only approved accounts are selectable; wrong-account identity fails validation.
- [ ] Signed DPA and entitlement revision are referenced before any collection.
- [ ] Public repository contains templates only.

### ONB-004 — Complete historical synchronization and customer reconciliation (FV-1 financial evidence)
Release: R1 · Estimate: 26–42 h (+ 1–4 days elapsed backfill) · Risk: H · Decisions: D-08, D-11, D-12, D-13 · Closes: G-ONB-02, G-ONB-03
Dependency changes: `+ONB-101`.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ONB-004-S01 | Present the plan: requested vs available per source, gaps, estimate (ONB-101); obtain consent acknowledgement. | S07 acknowledgement | 365 requested / 90 available shows 90 available / 275 unavailable. | 2 |
| ONB-004-S02 | Run finance-first backfill; review per-source coverage twice daily; triage stall alarms. | coverage log | Billing sources contiguous for available ranges. | 4 |
| ONB-004-S03 | Run query-grain backfill under fair share; compare customer credit burn with the estimate; pause and re-plan if > 150 % of estimate. | burn log | Burn within estimate range or re-planned with customer ack. | 3 |
| ONB-004-S04 | Verify catch-up and steady state per source (HEALTHY per source, not account-wide). | Data Health snapshot | All required sources HEALTHY or explicitly degraded. | 2 |
| ONB-004-S05 | Select the reconciliation period with the rule `month_end(M) + 5 d + 72 h ≤ now`. | recorded rule output | Period recorded with reason. | 1 |
| ONB-004-S06 | Reconcile ledger vs Snowflake currency data by currency/service/account; record signed deltas and tolerance. | reconciliation run id | Deltas recorded; no balancing entry. | 3 |
| ONB-004-S07 | When customer finance supplies the invoice, register it as independent reference and compare; missing invoice → UNAVAILABLE, never RECONCILED. | reference entry | Status reflects evidence. | 3 |
| ONB-004-S08 | Investigate each delta (latency, adjustments, organization fees, reseller pricing, unmapped services via FIN-021). | investigation notes | Each delta has a cause or remains open with owner. | 4 |
| ONB-004-S09 | Record unavailable history, unpriced services and reseller limits in the acceptance record. | record | Complete. | 2 |
| ONB-004-S10 | Replay one account-day (ING-011) and confirm totals unchanged. | evidence | Totals identical. | 1 |
| ONB-004-S11 | Obtain customer finance sign-off on the truthful status (RECONCILED / WARNING / FAILED + reasons). | signed record | Signed. | 2 |
| ONB-004-S12 | Evidence (redacted). | `docs/evidence/ONB-004/<commit>/` | – | 2 |

Task acceptance:
- [ ] All required available ranges are contiguous; gaps are explicit and accepted.
- [ ] Duplicate replay leaves totals unchanged.
- [ ] Reconciliation status is exactly what evidence supports (270 vs 271 stays FAILED −1; no invoice → no invoice-RECONCILED).
- [ ] Customer credit burn is within the disclosed estimate or re-consented.

### ONB-005 — Complete FV-1 workshop and customer acceptance
Release: R1 · Estimate: 20–32 h · Risk: M · Decisions: D-11, D-15, D-16 · Closes: G-ONB-03, G-ONB-05, G-ONB-09
Dependency changes: `−INS-007`, `+INS-006`.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ONB-005-S01 | Prepare the workshop pack from the FV-1 list using the customer's own publication (normal APIs only). | `docs/onboarding/first-value.md` (template) + private pack | No customer-specific pipeline or data copy. | 3 |
| ONB-005-S02 | Invite a restricted member and verify denial of an unassigned account/team live with the customer. | access review record | Restricted user sees only assigned scope. | 2 |
| ONB-005-S03 | Review the D-15 default allocation book, adjust ownership dimensions, simulate; show allocated + unallocated = eligible. | simulation id | Conservation PASS per currency. | 3 |
| ONB-005-S04 | Create budget and monitor (dry run on history, then live); deliver one authorized notification to a customer destination. | ids + delivery receipt | Receipt recorded. | 3 |
| ONB-005-S05 | Generate a report and check parity with Explorer at the same publication. | report id | Numbers identical. | 2 |
| ONB-005-S06 | Review a supported insight with evidence or record no-candidate; if acting, freeze baseline and assign owner; claim no savings. | insight disposition | Baseline id recorded if action. | 2 |
| ONB-005-S07 | Record FV-1 acceptance: decision ACCEPTED / ACCEPTED_WITH_DISCLOSED_LIMITS / NOT_ACCEPTED, limitations (incl. retroactive tag state), FV-2 date. | private acceptance record | Signed by customer admin and finance approver. | 2 |
| ONB-005-S08 | Support escalation test: customer opens a test ticket. | ticket | Response within LCH-104 policy. | 1 |
| ONB-005-S09 | Schedule first-week and FV-2 reviews (LCH-004). | calendar | Dates recorded. | 1 |
| ONB-005-S10 | Convert manual interventions into backlog items. | items | All converted. | 1 |
| ONB-005-S11 | Evidence (private) and redacted template update. | `docs/evidence/ONB-005/<commit>/` | – | 2 |

Task acceptance:
- [ ] Restricted user sees only assigned scope; allocation conserves; report equals Explorer.
- [ ] Acceptance distinguishes FV-1 evidence from FV-2 commitments with dates.
- [ ] No savings claimed without post-change verification.

## 5. New tasks required

### ONB-101 — Pre-consent history, credit and duration estimates
Release: R1 · Estimate: 26–40 h · Risk: M · Decisions: D-08, D-11, D-17 · Closes: G-ONB-02, G-ONB-04
Why / where: D-08 requires credits shown before consent; onboarding.md requires evidence-based ETAs. Plugs in at M5 after ING-010, CON-005, OPS-105, LCH-101; ONB-001 and ONB-004 depend on it.
Dependency changes: new; deps ING-010, CON-005, OPS-105, LCH-101.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ONB-101-S01 | Specify the estimate model (inputs/outputs in §3) and coefficient versioning. | `data/estimates/onboarding-estimate.v1.json` | Reviewed with OPS-105 owner. | 3 |
| ONB-101-S02 | Implement a bounded, tagged volume probe per account (7-day query count and approximate row width). | `services/onboarding/volume_probe.py` | Probe query tagged `bridge_finops:probe`; runtime ≤ 60 s on XSMALL for 3 M/day fixture. | 3 |
| ONB-101-S03 | Implement credit formulas: steady = accounts × cycles/day × billed_seconds_per_cycle/3600 × 30 (XSMALL = 1 credit/h); backfill = Σ chunks × seconds_per_chunk/3600; ranges from coefficient p50/p90. | `services/onboarding/estimate.py` | 5 accounts hourly at 90–120 s → 90–120 credits/month. | 3 |
| ONB-101-S04 | Implement duration estimate considering backfill slots per tenant and lane fairness; ETA only after ≥ 3 completed chunks during execution. | same | Before evidence the API returns `eta: null, reason: INSUFFICIENT_THROUGHPUT_EVIDENCE`. | 4 |
| ONB-101-S05 | Show entitlement preview (accounts, history days) vs selection. | API field | Over-limit selection flagged. | 2 |
| ONB-101-S06 | Build the consent panel: requested vs available per source, gaps, credits range with note "priced at your Snowflake contract rate", duration range; consent binds to estimate version. | `apps/web/onboarding/consent` | Changing selection invalidates prior consent. | 5 |
| ONB-101-S07 | Refine live during backfill from actual throughput. | projection field | ETA narrows as chunks complete. | 2 |
| ONB-101-S08 | Track estimate vs actual per onboarding for recalibration. | ops facts | Error distribution visible. | 2 |
| ONB-101-S09 | Tests: 365 requested / 90 available; zero-volume account; 3 M/day account. | `tests/spec/ONB-101/` | Outputs match expected ranges. | 2 |
| ONB-101-S10 | Docs and evidence. | `docs/evidence/ONB-101/<commit>/` | – | 2 |

Task acceptance:
- [ ] Customer sees credits and duration ranges before consent; consent binds to the estimate version.
- [ ] No ETA without throughput evidence.

### ONB-102 — Offboarding export, disconnect/pause semantics and reconnection
Release: R1 · Estimate: 26–40 h · Risk: M · Decisions: D-10, D-11 · Closes: G-ONB-06
Why / where: DPA return-or-delete obligation and duplicate-free reconnection; plugs in at M9 after OPS-005, API-004, ALC-008, CON-006; ONB-002 depends on it.
Dependency changes: new; deps OPS-005, API-004, ALC-008, CON-006.

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ONB-102-S01 | Define the export bundle: charges by D-12 bucket, allocation results, closed statements (PDF + CSV), budget/monitor configuration, tenant audit — Parquet + CSV with manifest and checksums. | `data/contracts/tenant-export.v1.json` | Schema reviewed. | 3 |
| ONB-102-S02 | Implement the export as an analysis job (API-004) pinned to one publication; artifacts in the reports bucket with 7-day expiry; brokered download. | `services/export/tenant_export.py` | Bundle totals equal Explorer totals for the publication. | 5 |
| ONB-102-S03 | Implement the offboarding workflow API/UI: request → confirm → pause → export (optional) → OPS-005 deletion request with residual dates. | `apps/api/offboarding/`, settings page | Only Organization Owner can start. | 4 |
| ONB-102-S04 | Define and implement pause (retain data, no extraction), disconnect account (revoke, keep history, account DISCONNECTED), offboard tenant (delete). | state docs + code | Each state has distinct UI and admission behaviour. | 3 |
| ONB-102-S05 | Implement reconnection: same organization + account locator re-binds to the same account UUID within retention; re-probe; backfill only uncovered windows. | `services/connections/reconnect.py` | No new account UUID; covered days untouched. | 5 |
| ONB-102-S06 | Guard: locator bound to another tenant is refused unless that tenant is deleted and tombstoned. | check | ACCOUNT_ALREADY_BOUND returned. | 2 |
| ONB-102-S07 | Test: disconnect, reconnect 10 days later. | `tests/spec/ONB-102/test_reconnect.py` | Gap backfilled; totals for previously covered days unchanged; no duplicate charges. | 3 |
| ONB-102-S08 | Authorization: Owner/Admin only; audited; foreign export id → 404. | tests | All pass. | 2 |
| ONB-102-S09 | Docs and evidence. | `docs/evidence/ONB-102/<commit>/` | – | 2 |

Task acceptance:
- [ ] Export bundle reproduces Explorer totals at the pinned publication.
- [ ] Reconnection never creates a new account identity or duplicate charges.

## 6. Estimate summary

| Task | Release | Low h | High h |
|---|---|---:|---:|
| ONB-001 | R1 | 52 | 78 |
| ONB-002 | R1 | 36 | 54 |
| ONB-003 | R1 | 18 | 30 |
| ONB-004 | R1 | 26 | 42 |
| ONB-005 | R1 | 20 | 32 |
| ONB-101 | R1 | 26 | 40 |
| ONB-102 | R1 | 26 | 40 |
| **Total R1** | | **204** | **316** |
| **Total R2** | | **0** | **0** |

Customer elapsed time (P0–P12) is not engineering effort and is excluded.

## 7. Owner questions (only those not already covered by D-01…D-25)

1. May the first customer start as a design partner on dark production (REL-104) before M10 under pilot terms, to surface onboarding defects earlier? (Changes ONB-003 dependency on REL-004.)
2. Acceptable customer-side steady-state footprint: hourly cadence ≈ 18–24 credits/month per account (ASSUMPTION) — keep hourly, or offer a 3-hourly "economy" cadence for non-query sources?
3. Is FV-1 (week 1–4) sufficient for the first-value acceptance and invoicing trigger, with FV-2 reviewed at day 30–60?
