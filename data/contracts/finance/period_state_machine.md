---
contract: finance-period-state-machine
version: 1
status: DRAFT
owner_task: FIN-010
contributing_tasks: [FIN-010-S01, FIN-010-S03, FIN-010-S04, FIN-010-S06, FIN-107-S01, FIN-107-S03, FIN-107-S04]
decisions: [D-05, D-11, D-13, D-25, D-35]
adrs: [ADR-003 (amendment 2026-09-28), ADR-009 (amendment item 5), ADR-014 §9, ADR-015 §8]
last_changed: 2026-09-28
machine_files:
  - contracts/state-machines/period.yaml
  - contracts/state-machines/period_close_request.yaml
  - contracts/state-machines/restatement.yaml
ddl: contracts/postgres/finance.sql
schemas:
  - data/contracts/finance/close_manifest.schema.json
  - data/contracts/finance/statement.schema.json
fixtures: [data/fixtures/finance/f_rest_01/, data/fixtures/finance/fin_gold_01/]
---

# Financial period close, statements and corrections

This contract makes FIN backlog §3.5 executable. A **financial period** is one UTC calendar month for one
(tenant, organization, currency): `finance.financial_period`, unique `(tenant_id, organization_id, period, currency)`,
half-open `[period_start, period_end)`. Periods are UTC everywhere (G-FIN-26); local-time views are labelled
"not comparable to billing" and never feed a period.

Three status axes stay separate (ADR-003, CONVENTIONS §6): row maturity (`data_status` PROVISIONAL / FINAL /
RECONCILED), reconciliation result (`PENDING / MATCHED / WARNING / FAILED` per control) and period state. This file owns
the third.

## 1. States and the public projection

`financial_period.status` holds the workflow state of machine `period`. The API also returns `period_state`, the
canonical enum of `contracts/common/maturity.schema.json#/$defs/period_state`, derived as follows:

| Workflow `status` | Meaning | `period_state` (API) |
|---|---|---|
| `OPEN` | Month running or `now < period_end + N days` | `OPEN` |
| `MONTH_STABLE` | `period_stability = STABLE` (month end + N days, N = 5 default, D-13) | `MONTH_STABLE` |
| `CLOSE_PREVIEWED` | Close request exists (preview computing or awaiting the checker, 24 h TTL) | `MONTH_STABLE` |
| `CLOSING_ARTIFACTS` | Close/restatement approved; publication, Object Lock upload and pin being confirmed | `MONTH_STABLE` if `close_version = 1`, else previous (`CLOSED` or `RESTATED`) |
| `CLOSED` | Close version 1 completed | `CLOSED` |
| `RESTATEMENT_PROPOSED` | A correction proposal awaits approval | `CLOSED` if `current_close_version = 1`, else `RESTATED` |
| `RESTATED` | Close version ≥ 2 completed | `RESTATED` |

The API adds `workflow_status` (the machine state), `close_version`, `stable_at` and `pending_action`
(`CLOSE_APPROVAL`, `RESTATEMENT_APPROVAL`, `ARTIFACTS`, or null) so the UI never infers workflow from the projection.

## 2. Transitions (summary of `contracts/state-machines/period.yaml`)

| From | To | Event | Actor (capability) | Guards (all must hold) |
|---|---|---|---|---|
| OPEN | MONTH_STABLE | `stability_reached` | `system:finance-maturity-evaluator` | `now ≥ period_end + month_stability_days` of the charge-authority source (UICD; MDH for tenants without organization billing) |
| MONTH_STABLE | OPEN | `stability_revoked` | system | A new maturity policy version raised N and `now < period_end + N` |
| MONTH_STABLE | CLOSE_PREVIEWED | `close_requested` | `finance.period.close.request` | STABLE; no active close request; scope not trial-only (D-35); requester scope covers the organization |
| CLOSE_PREVIEWED | CLOSING_ARTIFACTS | `close_approved` | `finance.period.close.approve` | Preview PREVIEWED and not expired; preconditions still hold; pins unchanged (else `FIN_STALE_PREVIEW`); approver ≠ requester (else `FIN_MAKER_CHECKER_VIOLATION`) unless the owner-acknowledged waiver; fresh durable authorization check; step-up ≤ 10 min |
| CLOSE_PREVIEWED | MONTH_STABLE | `close_rejected`, `close_preview_expired`, `close_preview_invalidated` | request or approve capability; system | — |
| CLOSING_ARTIFACTS | CLOSED | `close_artifacts_confirmed` | `system:finance-worker` | `close_version = 1`; CONFIG publication verified; JSON/CSV/PDF stored with Object Lock; publication pin created |
| CLOSING_ARTIFACTS | RESTATED | `close_artifacts_confirmed` | system | `close_version ≥ 2`; same three confirmations |
| CLOSED or RESTATED | RESTATEMENT_PROPOSED | `restatement_proposed` | `finance.period.restate.request` | A live correction case (OPEN) exists; the proposal names RESTATE or CARRY_FORWARD |
| RESTATEMENT_PROPOSED | CLOSING_ARTIFACTS | `restatement_approved` | `finance.period.restate.approve` | decision RESTATE; approver ≠ proposer (no waiver); proposal pins unchanged |
| RESTATEMENT_PROPOSED | CLOSED / RESTATED | `carry_forward_approved` | `finance.period.restate.approve` | decision CARRY_FORWARD; approver ≠ proposer; target accounting period OPEN or MONTH_STABLE; target by current close version |
| RESTATEMENT_PROPOSED | CLOSED / RESTATED | `proposal_withdrawn` | request/approve capability or system (pins changed) | by current close version |

Illegal transitions (for example `OPEN → CLOSED`, `MONTH_STABLE → CLOSED`, anything out of `CLOSING_ARTIFACTS` other than
the confirmation) return `409 FIN_PERIOD_STATE_CONFLICT`; the DB check `financial_period_close_ck` also rejects a closed
status without a close record. The state-machine linter generates a rejection test for every undeclared pair.

Capabilities are proposed to K2 (SEC-004/SEC-005) in `contracts/_handoffs/K5.md`; SEC Appendix C currently names them
`period.close.request / restatement.request / period.close.approve / restatement.approve`. Four-eyes defaults follow SEC
Appendix C.4: close and restatement REQUIRED, no self-approval, step-up for both actors, approval binds
`(period_id, revision, sha256(close manifest))`.

## 3. Close preconditions (FIN-010-S03)

`GET /v1/periods/{period_id}/preconditions` and the preview evaluate the ordered list below; the first failing item is
the returned problem code, and the full list is returned as `remedies[]` (code, message key, target link):

| # | Check | Pass rule | Failure → problem / remedy |
|---|---|---|---|
| P1 | Stability | `status ∈ {MONTH_STABLE, CLOSE_PREVIEWED}` | `FIN_PERIOD_NOT_STABLE` (e.g. August 2026 before 2026-09-06T00:00:00.000Z) — "wait until `stable_at`" |
| P2 | Trial scope (D-35) | at least one eligible account without `TRIAL_ACCOUNT` flag (TRUE or UNKNOWN counts as trial) | `FIN_TRIAL_ACCOUNT_DEMO_ONLY` |
| P3 | Latest control run | a SUCCEEDED run pinned to the current `pub_seq` for the period and currency | remedy `RUN_RECONCILIATION` (the preview enqueues one with trigger `CLOSE_PREVIEW`) |
| P4 | Required controls | every control with `required_for_close` (controls.yaml; C5 per `close_policy.c5_required_for_close`) is `MATCHED`, or `WARNING` whose excess buckets all carry APPROVED explanations, or `PENDING` covered by an APPROVED `CONTROL` exception; controls with status NULL + `NOT_APPLICABLE` are skipped | `FIN_CONTROL_BLOCKING` with `errors[].field = control_id` |
| P5 | Coverage | share of eligible (account, day) pairs with contiguous charge-authority coverage ≥ `close_policy.min_account_day_coverage` | `FIN_COVERAGE_BELOW_POLICY` |
| P6 | Open corrections | no correction case of a **previous** closed period of the same organization and currency is PROPOSED/APPROVED with CARRY_FORWARD targeting this period and not yet published | `FIN_OPEN_CORRECTION_CASE` |
| P7 | Pending references | no billing reference for the period is SUBMITTED or APPROVED-not-ACTIVE (otherwise C5 would change right after close) | `FIN_REFERENCE_PENDING_APPROVAL` |

## 4. Freeze set (close manifest)

The preview computes the canonical manifest (`data/contracts/finance/close_manifest.schema.json`, JSON canonicalized per
RFC 8785 before hashing); `manifest_sha256` is what the checker approves and what `STALE_PREVIEW` compares. Members:

1. `publication`: tenant `pub_seq` and per-dataset `dataset_version` for `fct_charge`, `bridge_charge_attribution`,
   allocation facts (when ALC enabled), `fct_billing_reference`, `fct_reconciliation`.
2. `revision_set_sha256`: sha256 over the sorted `(dataset_id, scope_id, partition_start, revision_id)` of every
   partition of the period read at that `pub_seq`.
3. `crosswalk_version`, `maturity_policy_version`, `rate_version_set_sha256` (sha256 of the sorted `rate_id@rate_version`
   used by any active row), `fx_version` (always null in R1, FIN-109 is R2).
4. Configuration versions: tag, rule, allocation book and group-set `config_version` per kind (CONFIG header).
5. Controls: `control_run_id`, per control and currency the status, and the ids of APPROVED explanations/exceptions.
6. Billing references: `(reference_id, version, content_sha256)` of every ACTIVE reference of the period.
7. Statement: `statement_json_sha256` of the preview document (artifact hashes are added to the close record once stored).
8. Actors and times: requester, preview time (UTC), close policy revision, excluded trial accounts.

Storage of the frozen set:
- PostgreSQL `finance.period_close` (authoritative control state; `manifest_json` + hashes; unique
  `(tenant_id, period_id, close_version)`).
- Snowflake insert-only mirror `CONFIG.PERIOD_CLOSE` (+ `CONFIG.STATEMENT_LINE`) through the D-04 config publisher
  (kind `PERIOD_CLOSE`, key `close_id`), exposed by dbt as `ledger.fct_period_close` / `ledger.fct_statement_line`.
- Artifacts `tenants/{tenant_id}/finance/closes/{close_id}/statement.{json,csv,pdf}`, S3 Object Lock **GOVERNANCE**
  (RECORD class, ADR-009 amendment item 5), `retain_until = issued_at + close_policy.record_retention_days`
  (default 400 d, up to 7 years; owner Q7), break-glass bypass only.
- Retention pins: a `PUBLICATION.PIN(holder_kind = PERIOD_CLOSE, holder_id = close_id, pub_seq)` (K4). D-05 GC never
  deletes pinned revisions; D-11 purge keeps query-family aggregates of pinned periods and query-level drilldown older
  than `hot_days` answers "detail expired by retention policy" (FIN-010-S07).

## 5. Approval execution and retry safety (FIN-010-S06, S08, S10)

1. One PostgreSQL transaction: re-check guards, insert `finance.period_close` (version 1, `CLOSING_ARTIFACTS`), insert
   `finance.statement` (`GENERATING`), set the request `APPROVED`, move the period to `CLOSING_ARTIFACTS`, write the
   outbox events. A concurrent second approval violates `period_close_version_uq` and returns the existing record (200).
2. The close worker (idempotent, keyed by `close_id`): D-04 publication of `PERIOD_CLOSE` and `STATEMENT_LINE`
   (identical content is a no-op) → S3 `PutObject` with `If-None-Match: *` (equal checksum = success) → `PUBLICATION.PIN`.
   Each step sets its sub-status to `DONE`. A crash after the PG commit resumes from the sub-statuses; no duplicate.
3. When the three sub-statuses are `DONE`: record `COMPLETED`, statement `ISSUED`, period `CLOSED` (or `RESTATED`),
   events `bridge.finance.period.closed|restated` and `bridge.finance.statement.issued`.
4. A late billing revision between preview and approval changes the recomputed manifest → `409 FIN_STALE_PREVIEW`, the
   request becomes `STALE` and the period returns to `MONTH_STABLE`; a new preview works (FIN-010-S08).

## 6. Statements (FIN-010-S05)

- Lines by section: `ACCOUNT` (one block per account: lines per `service_family`), `ORGANIZATION` (organization-scope
  families: fees, credits, unmapped organization rows), `PRIOR_PERIOD_ADJUSTMENTS` (carry-forward lines whose
  `accounting_period` is this period), and for restatements `DIFFERENCES` (new − closed per family and account).
  Trial accounts are listed only as an exclusion note ("excluded — demonstration account", D-35).
- Amounts: exact NUMBER(38,12) per line from the pinned publication; rounded with `round_statement_lines`
  (`packages/bridge_money/API.md` §6) per currency; the rounded lines always add to the rounded total.
- Consumption lines select `entry_kind <> PRIOR_PERIOD_ADJUSTMENT` rows with `usage_date` in the month; the PPA section
  selects `entry_kind = PRIOR_PERIOD_ADJUSTMENT` rows with `accounting_period` = the month.
- JSON (canonical, schema `statement.schema.json`), CSV (API-102 writer, formula-neutralized) and PDF (RPT renderer);
  each artifact's sha256 is stored; re-download is byte-identical.

F-270 statement v1 (August 2026, USD, organization O1): account A1 section 200.00 + 10.00 + 12.00 + 5.00 + 7.00 +
2.00 + 2.00 + 2.00 + 6.00 + 8.00 + 4.00 + 10.00 = 268.00; organization section 5.00 − 3.00 = 2.00; total 270.00.
EUR 20.00 (account A2) is a separate EUR period and statement.

## 7. Corrections: restatement vs carry-forward (FIN-107, machine `restatement`)

- Detection: nightly control **C9 CLOSED_PERIOD_DRIFT** per (organization, period, currency, service_family):
  `delta = current_active_consumption(period) − (closed_amount(latest close version) + Σ carried-forward PPA amounts
  whose original period is this period)`. Signs are declared: `delta = new − closed` (G-FIN-10).
- A non-zero delta opens (or updates) the live case of that family; lines per (scope, account, usage_date) are stored
  in `finance.correction_case_line`.
- Materiality (tenant policy, owner Q4): `threshold = max(restate_abs_threshold, restate_rel_threshold × |closed period
  total|)`, defaults 100 currency units and 0.5 %. `|delta| ≥ threshold` → `proposed_default = RESTATE`, else
  `CARRY_FORWARD`. The maker may choose the other decision; both are maker-checker.
- RESTATE: new close version n+1 with new pins, statement v(n+1) linked to vn, difference lines; vn stays downloadable;
  every other live case of the period is MERGED; event `bridge.finance.period.restated` (ALC-008 re-issues linked
  chargeback adjustments).
- CARRY_FORWARD: one `finance.prior_period_adjustment` per case line (amount = line delta, `usage_date` unchanged,
  `accounting_period` = target OPEN period), published as CONFIG kind `CORRECTION_DECISION`; dbt emits `fct_charge` rows
  with `basis_class = PPA`, `entry_kind = PRIOR_PERIOD_ADJUSTMENT`. Consumption KPIs exclude them; statements include them;
  the original period keeps its issued version with the annotation "later correction carried to YYYY-MM (case id)".
- Guard against double effect (FIN-107-S05): Σ issued statements (closed versions + PPA sections) = Σ current truth once
  cases are RESOLVED. No period shows the double-counted value.

### Worked example F-REST-01 (data/fixtures/finance/f_rest_01/)

1. 2026-09-06T00:00:00.000Z: August 2026 (O1, USD) becomes MONTH_STABLE (month end 2026-09-01T00:00Z + 5 d).
2. 2026-09-07: U1 requests close; controls C1–C4, C6 MATCHED, C5 MATCHED against the usage statement 270.00, C7 NULL
   (NOT_APPLICABLE, allocation disabled), C8 NULL (NOT_APPLICABLE, no estimate superseded in the fixture), C9 NULL
   (NOT_APPLICABLE, period not closed). 2026-09-08: U2
   approves; close v1, statement v1 = 270.00 (A1 268.00; organization 5.00 − 3.00 = 2.00).
3. 2026-10-14: UICD revision for 2026-08-17 storage 12.00 → 11.00; the active August ledger is 269.00; statement v1
   still reads 270.00.
4. 2026-10-15 nightly C9: delta = 269.00 − (270.00 + 0.00) = −1.00 for STORAGE → case CC-1; threshold =
   max(100.00, 0.005 × 270.00 = 1.35) = 100.00; |−1.00| < 100.00 → `proposed_default = CARRY_FORWARD`.
5. Option A RESTATE (U1 proposes, U2 approves): close v2, statement v2 = 269.00 with difference line "Storage −1.00";
   August `period_state = RESTATED`.
6. Option B CARRY_FORWARD (U1 proposes target 2026-10, U2 approves): PPA −1.00 with usage_date 2026-08-17 and
   accounting_period 2026-10; October consumption (fixture 100.00) unchanged; October statement preview 100.00 − 1.00 =
   99.00; August stays CLOSED v1 = 270.00 with the annotation. Σ statements = 270.00 + 99.00 = 369.00 = current truth
   269.00 + 100.00.
7. Explorer "August" in both options shows current truth 269.00 with the banner "differs from closed statement v1 by
   −1.00" (delta = 269.00 − 270.00).

## 8. Audit, events, metrics

Every transition writes a SEC-008 audit event (request, approve, reject, pins, hashes) and an outbox event listed in
`contracts/events/catalog/finance.yaml`. Metric `fin_period_close_total{outcome}` (no tenant label). Alarm: a FAILED
control in a CLOSE_PREVIEWED or closed period pages on-call (RB-06, FIN-009-S17).
