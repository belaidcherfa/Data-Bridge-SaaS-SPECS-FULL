# ALC — Implementation-readiness review and production backlog

Canonical contract: [allocation.md](../../11-allocation/allocation.md). Tasks reviewed: ALC-001, ALC-002, ALC-003, ALC-004, ALC-005, ALC-006, ALC-007, ALC-008 (plus PRD §79–§88, ADR-002/003/005/007, [ledger.md](../../08-finops-ledger/ledger.md), [semantic-api.md](../../09-api/semantic-api.md), [security.md](../../02-security/security.md), [validation-strategy.md](../../15-testing/validation-strategy.md), UI pages tags/allocation/usage-groups/showback/chargeback). Reviewer: domain audit agent, 2026-09-27. Status of all tasks: NOT_STARTED.

## 1. Verdict

Not implementable as specified. The contract names the right concepts (books, methods, conservation, lifecycle, largest remainder) but leaves the parts that decide money and access undefined. Four blockers: (1) under D-12 a warehouse-compute charge is an account×day billing bucket, so the golden "warehouse200 → query140 + idle60" fixture has no input grain to run on (G-ALC-01); (2) there is no predicate data model, subject-level precedence, null semantics or runtime conflict rule (G-ALC-02); (3) the allocation output and the UI both let a team-restricted reader work out sibling spend: the showback team page prints "Allocated idle 3,600 = 60% of 6,000" (G-ALC-03); (4) no task turns usage-group hierarchies into Snowflake entitlements, so team-scoped reading is unbuildable (G-ALC-04). Recomputed fixtures: 84/56 → 120/80 PASS; 84/56/60 PASS; each book = 200, never 400, PASS. 1.00 → 0.34/0.33/0.33 and −1.00 → −0.34/−0.33/−0.33 PASS only once the internal 12-dp residual uses the same tie-break. The specified "absolute-value largest remainder" FAILS for mixed-sign lines (G-ALC-05). Author first: allocation unit and line DDL, predicate tables, the rounding specification, the disclosure policy, the ruleset and statement state machines, and the D-15 seed. ALC-005 and ALC-008 carry most of the risk. Realistic effort is about 414–590 h across 12 tasks (8 existing + 4 new), not 8 × 2–6 h.

## 2. Findings

### G-ALC-01 · Allocation input grain does not exist under D-12 billing-bucket charges
Severity: BLOCKER · Type: GAP
Evidence: `allocation.md` — "Output grain = charge_id × allocation_book/group_set × target × rule_version" and "Parent warehouse200 consists of query140 and idle60"; D-12 — `fct_charge` grain = "(tenant, organization, scope_kind, account, usage_date UTC, service_type, rating_type, billing_type, currency, is_adjustment)"; `ledger.md` — `bridge_charge_attribution` "Charge→resource/workload/query/group decomposition… sums back to parent per attribution set".
Why it matters: one account-day `WAREHOUSE_METERING` charge covers every warehouse. Query-cost, idle-by-owner and per-warehouse proportional-idle policies cannot run on `charge_id` alone. Without a defined unit, implementers will either allocate the whole bucket (idle policy becomes meaningless) or read `fct_query_compute` as if it were money (the double counting ADR-002 forbids).
Resolution: introduce `int_alloc_unit`, the only input to allocation. Columns: `(tenant_id, charge_id, charge_revision, usage_date, currency, charge_family, component_kind ∈ {QUERY, IDLE, HOUR_RESIDUAL, RESOURCE, WHOLE}, component_ref, warehouse_id NULL, subject_kind, subject_key, amount NUMBER(38,12))`. Build it from `fct_charge` plus `bridge_charge_attribution`:
- Warehouse compute: QUERY units aggregated per `(charge_id, warehouse_id, classification_key)` (see G-ALC-16); one IDLE unit per `(charge_id, warehouse_id)`; one HOUR_RESIDUAL unit per `(charge_id, warehouse_id)` (the D-14 residual).
- Storage and serverless: RESOURCE units from their bridges.
- Anything without a bridge: one WHOLE unit.
- Mandatory dbt test: Σ units = charge amount exactly (12 dp) per charge.
The output grain becomes `charge_id × book_id × policy_version × component_kind × target_group_id × method`. `component_kind` is kept so statements can show "Warehouse compute / Idle" as PRD §86 requires.
Affects: ALC-005, ALC-103, ALC-006, ALC-008.

### G-ALC-02 · Rule engine (D-16) lacks predicate model, subject levels, null semantics and runtime-conflict rule
Severity: BLOCKER · Type: GAP
Evidence: `allocation.md` — "typed bounded expression AST… Explicit priority wins; overlapping equal-priority assignments of different values are conflicts that block publication"; ALC-002 — "Pure evaluate_rules(context,ruleset)… SQL-friendly predicates compiled in dbt"; D-16 names operators only. Nothing says whether a query-level rule on `query_tag` beats a warehouse-level classification. It also does not say what happens when data arriving after publication matches two equal-priority rules, which publication-time blocking cannot prevent.
Why it matters: order-dependent or implementation-dependent assignments move money between teams. The "block publication" rule alone cannot handle conflicts that first appear in tomorrow's queries. The result would be either nondeterministic picks or failed runs.
Resolution:
- **AST**: disjunctive normal form only. `match.any_of[≤8] → all_of[≤8] → predicate{attribute, op, value|values[≤1,000], ci}`. R1 operators (D-16): `eq, in, prefix, suffix, contains, is_null` plus negations `not_eq, not_in, not_prefix, not_suffix, not_contains, is_not_null`. `regex` is R2. `additionalProperties:false`. Limits: rule ≤ 32 KB, ruleset ≤ 2,000 rules.
- **Null semantics**: a NULL attribute makes every operator false except `is_null`. Negated operators are also false on NULL. Empty strings normalize to NULL for identifier attributes. `in []` is rejected.
- **Subject levels**, resolved in this order: `OVERRIDE > ACTIVITY rule (query/task-run/cortex call) > OBJECT rule (table/pipe/task/compute pool) > CONTAINER rule (schema→database→account) > inherited carrier (a query inherits its warehouse's RESOURCE assignment) > UNCLASSIFIED`. Priority is compared only within a level.
- **Resolution**: `RANK() OVER (PARTITION BY subject_key, dimension ORDER BY level_rank, priority DESC)`. If there is exactly one distinct assignment at rank 1, it is the winner. Identical duplicate assignments are not a conflict. Two or more distinct assignments give status `CONFLICT`.
- **Runtime conflicts** found after publication never pick a winner: the subject goes to the `UNASSIGNED` leaf with status CONFLICT, raises the quality counter and ALC_RUNTIME_CONFLICT_NEW. Publication-time blocking still applies to conflicts visible in the simulation window.
- **Static check at save**: exact intersection for eq/in; prefix-vs-prefix overlap. Other combinations get a `POTENTIAL_OVERLAP` warning.
- **UI default**: assign unique priorities as an ordered list. Equal priority becomes an explicit choice.
Affects: ALC-001, ALC-002, ALC-003.

### G-ALC-03 · Team-restricted readers can work out hidden sibling spend (schema and UI)
Severity: BLOCKER · Type: RISK (security) / CONTRADICTION
Evidence:
- `allocation.md` — output "Fields include signed source/allocated amount… weight" and "neither hidden groups nor hidden grand totals leak through percentages".
- `21-ui-ux/pages/showback.md` (team page KPI) — "`financeidle` Allocated idle: $3,600.00 — 60% of 6,000"; the same page says "Do not show hidden tenant-wide denominators to team viewers".
- `usage-groups.md` — "Finance weight 60% — 8,400 / 14,000".
Computation: 6,000 − 3,600 = 2,400, which is exactly Marketing's idle. 14,000 − 8,400 = 5,600, which is Marketing's query cost. With two consumers, every weight/denominator pair reveals the sibling's exact amount.
Why it matters: this is a cross-team disclosure inside the tenant and violates security.md: "a team-restricted identity must never query an account-only total that includes hidden teams".
Resolution:
- Split storage in two. `fct_allocation_line` is internal and carries source amount, weight, numerator and denominator; only book-wide profiles and service roles can read it. `srv_allocation_restricted` holds `(tenant, book, target_group_id, usage_date, service_category, component_kind, method, allocated_amount, data_status, explain_ref)` only, with no source amount, weight, driver or pool total.
- Add a per-pool/idle disclosure policy: `CONCEALED` by default, or `DISCLOSED`, which requires an explicit Organization Admin acknowledgement. When a pool has ≤ 2 consumers, the UI warns that "others" identifies one group.
- The API planner rejects share-of-total, coverage and `spend` (unallocated `fct_charge`) for group-restricted profiles.
- Explain for a restricted reader stops at "allocated by method M under policy vN" and shows only the reader's own operands.
- Correct the three UI fixtures: team pages show "$3,600 idle (proportional to your query cost)", with no percentage or denominator.
Affects: ALC-005, ALC-006, ALC-007, ALC-101, ALC-102, API-005.

### G-ALC-04 · No task produces group-scope authorization; "versions are part of scope" is unworkable as written
Severity: BLOCKER · Type: GAP
Evidence:
- `security.md` — "Group set IDs and versions are part of scope to prevent reclassification broadening access"; "Shared and unallocated costs require explicit scope grants".
- SEC-005 — `SECURITY.principal_entitlement(principal,tenant,profile,account,group_set,group,epoch,active)`.
- No ALC or SEC micro-task expands a grant on a parent group to its effective-dated descendants, and none maintains that expansion when a hierarchy is published.
- PRD §115 — serving tables carry `usage_group_id`.
Why it matters: a restricted team reader either sees nothing, which breaks showback and team budgets, or someone hand-writes WHERE filters, which ADR-005 rejects. Pinning a hierarchy version in each grant means every monthly reorganisation silently freezes access at the old tree.
Resolution:
- A grant clause references `(group_set_id, group_id, include_descendants=true)`. It follows the published hierarchy.
- Broadening is controlled at publication: an access-impact review plus a `permission_epoch` bump (G-ALC-08). Grants do not pin versions.
- A security-owned job materializes `SECURITY.group_entitlement_expanded(profile_role, tenant, book_id, group_id, valid_from, valid_to)` from grants × effective-dated closure. The job runs on grant change or hierarchy publication.
- The row access policy on `srv_allocation_restricted` checks the D-02 tenant user and `EXISTS(entitlement for CURRENT_ROLE(), row.book_id, row.target_group_id, row.usage_date within validity)`.
- New task ALC-101.
Affects: ALC-004, ALC-007, SEC-005, SEC-006, GOV-001.

### G-ALC-05 · "Largest remainder on absolute amounts, then reapply sign" breaks signed totals for mixed-sign lines
Severity: HIGH · Type: CONTRADICTION
Evidence: `allocation.md` — "Statement rounding uses largest remainder on absolute amounts and a stable target ID tie-breaker, then reapplies sign." Computation (Decimal prototype):
- Lines c=+1.005, a=−0.335, b=−0.335. Exact sum is +0.335, so the rounded total is 0.34 (half-even).
- Absolute LR: abs total 1.675 rounds to 1.68; floors 1.00/0.33/0.33 leave 2 units; the tie-break by id gives a and b 0.34 each. Result: +1.00 −0.34 −0.34 = **0.32 ≠ 0.34**. **FAIL.**
- A second defect: the 12-dp internal allocation must also resolve its residual (1.00 × ⅓ cannot be exact). If that residual lands on the last id (0.333333333334), the statement's 0.34 goes to that target instead of the first id. The fixture's "stable tie-break" then silently depends on internal ordering.
Why it matters: statements do not sum to the statement total whenever credits and charges mix inside one target, which is routine with rebates. Separately rounded target totals and line totals can also disagree.
Resolution: sign-normalized signed largest remainder, applied hierarchically.
- For a vector x with required total T in minor units: s = −1 if T < 0 else +1; y_i = s·x_i; f_i = floor(y_i/u)·u; r = (s·T − Σf_i)/u, which lies in [0, n]. Give +u to the r entries with the largest (y_i − f_i), ties broken by `target_id` ascending (lowercase UUID, bytewise). Output s·f_i.
- The same function and the same tie-break are used at 1e-12 internally and at minor units on statements.
- Hierarchy: T_book = round_half_even(Σ exact); LR across targets; then LR across each target's lines with T = that target's rounded total.
- Restatement deltas: LR over exact deltas. This provably gives 0 to targets whose exact delta is 0, because an entry with zero fraction never receives a unit when r ≤ count(frac > 0).
- Fixtures (prototype outputs): 1.00 thirds → 0.34/0.33/0.33 (first id), PASS. −1.00 → −0.34/−0.33/−0.33, PASS. Mixed example → sum 0.34, PASS.
Affects: ALC-005, ALC-008.

### G-ALC-06 · Snowflake decimal scale rules silently cut below the 12-dp internal precision
Severity: HIGH · Type: VENDOR-FACT
Evidence: `allocation.md` — "Use exact decimals; allocate at internal precision". Snowflake docs, VERIFIED via search snippet of docs.snowflake.com/en/sql-reference/operators-arithmetic (2026-09-27): multiplication scale = min(S1+S2, max(S1,S2,12)); division "adding 6 digits to the scale of the numerator, up to a maximum threshold of 12 digits, unless the scale of the numerator is larger than 12".
Why it matters: dividing a NUMBER(38,2) billing amount by a driver gives scale 8, not 12. Computing a share (num/den) before multiplying loses further digits. Conservation then fails by up to n·10⁻⁸, or engineers add tolerances that hide real defects.
Resolution: one macro `alloc_mul_div(amount, num, den) = ROUND(CAST(amount AS NUMBER(38,18)) * num / NULLIF(den,0), 12)`. Always multiply before dividing. Every method ends with a 1e-12 largest-remainder step so Σ lines = unit amount exactly, and the dbt conservation test uses `= 0`, never a tolerance. Whether an implicit scale reduction rounds or truncates is TO VERIFY LIVE; the design does not depend on it.
Affects: ALC-005, ALC-103, ALC-008.

### G-ALC-07 · "Data revision invalidates approval" makes approval impossible under hourly publication
Severity: HIGH · Type: AMBIGUITY
Evidence: `allocation.md` — "Simulation screens show data and rule versions and require rerun when either changes before approval"; allocation-preview UI — "A data revision invalidates approval and requires a rerun"; ORC publishes per tenant as batches arrive (hourly default, D-08).
Why it matters: a maker-checker approval that takes hours is invalidated by every hourly publication, so nothing can ever be published. The opposite shortcut, ignoring data changes, would let a restatement inside the simulated window be approved unseen.
Resolution:
- The simulation pins `(input_publication_id, window [start,end), scope)` and stores `window_fingerprint = sha256(ordered (charge_id, charge_revision) for charges in window∩scope)` plus `config_dependency_versions` (dimension definitions, group set/hierarchy version, active policy version).
- Approval and publication both recompute these values. Staleness is triggered only by (a) a fingerprint change (a revision inside the window), (b) a dependency version change, (c) a ruleset content-hash change, or (d) approval age above 7 days.
- Data appended after the window never invalidates.
- After publication, a parity check compares the first live run over the same window and publication with the simulation's candidate at 12 dp. Any difference raises ALC_SIM_PARITY_MISMATCH.
Affects: ALC-003, ALC-006.

### G-ALC-08 · The security review for access-relevant rules is undefined (who approves, what is computed, when it is rechecked)
Severity: HIGH · Type: GAP
Evidence: `allocation.md` — "A rule that changes access-relevant group membership requires authorization review before publication"; tags UI — "Block if… access-relevant impact lacks security review". No approver role, impact definition or recheck point is given.
Why it matters: tag rules decide which charges fall into a group, and grants on that group decide who reads them. Publishing a rule is therefore an access grant. With no review, a FinOps Admin can widen a team's visibility; with no recheck, a grant added between review and publication escapes review.
Resolution:
- **Access impact** = for every `(group_set, group)` referenced by an active grant clause (including ancestors via closure), the set of subjects, charges and amount entering and leaving its effective membership under the candidate compared with the baseline, plus the count and list of users whose visible scope widens.
- The ruleset is access-relevant when any entering set is non-empty.
- Approval: an `ACCESS` approval by an Organization Admin or Owner is required, and the approver must differ from the author. It is separate from the `FINANCIAL` approval by a FinOps Admin. Four-eyes is on by default for FINANCIAL (tenant policy may relax it); ACCESS approval is always required.
- Access impact is recomputed at publish time, because grants may have changed. Any new impact produces 409 `ACCESS_REVIEW_STALE`.
- Publication bumps `permission_epoch` for affected profiles through the SEC-006 outbox. Audit records the impact digest.
Affects: ALC-003, ALC-004, ALC-101, SEC-006.

### G-ALC-09 · Effective dating and retroactivity across open and closed periods are undefined
Severity: HIGH · Type: GAP
Evidence: `allocation.md` — "Reclassification must not retroactively mutate closed statements"; "Manual overrides are scoped, effective-dated"; ADR-003 — "Later corrections create a restatement or next-period adjustment". No rule says what a new ruleset with `valid_from` in the past recomputes.
Why it matters: an unbounded backdated rule either rewrites closed months, which breaks close, or silently recomputes 400 days of allocation, which is a runaway credit cost.
Resolution:
- Rules, overrides, mappings and hierarchies are bitemporal: `valid_from/valid_to` (business time, UTC dates) plus `published_at` (config_version).
- A run for usage_date D uses, from the latest published config_version pinned by the run, the rows valid on D.
- Publication marks dirty partitions `[max(valid_from, first_open_period_start), today]` in the processing ledger (D-06).
- `valid_from < first_open_period_start` → 422 `CLOSED_PERIOD_RETROACTIVE`, unless the request sets `apply_from=FIRST_OPEN_PERIOD`, which clamps the date and shows a warning.
- Closed-period restatement is only possible through the FIN-010 reopen/restate flow, followed by ALC-008 restatement.
- Recompute budget: at most 2 open periods by default.
Affects: ALC-002, ALC-003, ALC-004, ALC-005.

### G-ALC-10 · Method algorithms, fallback chains, D-15 defaults and manual transfers are under-specified
Severity: HIGH · Type: GAP
Evidence: `allocation.md` lists nine methods and "Idle policy is explicit"; no formulas, driver windows or fallbacks are given. The conservation equation `direct + rule_allocated + shared + unallocated = source_charge` has no term for manual transfers, although "Manual internal transfers have equal/opposite entries". D-15 names the policies but not how they map to methods.
Why it matters: each open point changes numbers. Examples: idle per hour vs per day, whether unclassified consumers count in the idle denominator, negative drivers, whether a pool may use another pool's output, and whether transfers are per charge or per book.
Resolution (all versioned in `allocation_policy`):
- **direct**: unit → group by membership (split weights); UNASSIGNED membership → status UNALLOCATED.
- **query-cost**: Σ QUERY units per group; unclassified queries → UNALLOCATED.
- **idle**:
  - OWNER: warehouse resource group.
  - PROPORTIONAL_CONSUMERS: per (charge, warehouse, usage_date), idle × group query-cost / total query-cost. `include_unassigned_in_denominator=true` by default, so the unassigned share stays UNALLOCATED instead of inflating teams.
  - PLATFORM: a fixed group.
  - Adaptive warehouses produce no IDLE units (FIN-004).
- **fixed %**: weights with ≤ 6 dp summing to exactly 1.
- **proportional / measured usage / weighted**: driver b_g ≥ 0 taken from a registry metric (usage) or multiplied by group weights (weighted), over the same usage_date by default. A negative driver sends the unit to UNALLOCATED with reason `NEGATIVE_DRIVER`; Σb = 0 gives reason `ZERO_DENOMINATOR`.
- **Fallback chain**: an ordered list, part of the approved policy, e.g. `PROPORTIONAL_CONSUMERS → OWNER → UNALLOCATED`.
- **shared pool**: stage 2, driver = gross-positive stage-1 allocation per group. R1 is single level: a pool→pool reference gives 422 `POOL_REFERENCE_NOT_SUPPORTED`, which also makes cycles impossible. Multi-level pools as a DAG are R2.
- **residual**: at most one per book, runs last, and is shown separately in the quality view.
- **manual transfer**: book-level `(from, to, amount, period, currency)` producing ±x lines with `charge_id NULL`. Conservation becomes: per charge, Σ lines = charge; per book×period×currency, Σ transfer lines = 0.
- **D-15 seed** (ALC-103):
  - WAREHOUSE compute: QUERY_COST, idle PROPORTIONAL_CONSUMERS → OWNER → UNALLOCATED.
  - CLOUD_SERVICES: proportional to gross query cloud-services credits.
  - STORAGE: OWNER(database).
  - Serverless: OWNER(object).
  - TRANSFER, REPLICATION, org support fees and rebates: PLATFORM.
  - Everything else, including `UNMAPPED_BILLABLE_SERVICE`: UNALLOCATED.
Affects: ALC-005, ALC-103, ONB-004.

### G-ALC-11 · Rule sources and D-15 drivers need columns and views that are not extracted
Severity: HIGH · Type: GAP / VENDOR-FACT
Evidence:
- `source-catalog.md` QUERY_HISTORY projection: "QUERY_ID, START_TIME, END_TIME, WAREHOUSE_ID, WAREHOUSE_NAME, WAREHOUSE_SIZE, USER_NAME, ROLE_NAME, SESSION_ID, QUERY_TYPE, EXECUTION_STATUS, TOTAL_ELAPSED_TIME, EXECUTION_TIME, QUERY_HASH, QUERY_PARAMETERIZED_HASH; privacy-approved QUERY_TAG/QUERY_TEXT". There is no DATABASE/SCHEMA and no CREDITS_USED_CLOUD_SERVICES.
- PRD §80 lists "Snowflake tags, database, schema, client application, table access" as rule sources.
- grep finds no `TAG_REFERENCES` anywhere in docs.
- TAG_REFERENCES: latency up to 120 minutes, "only records the direct relationship between the object and the tag, and tag inheritance is not included", and object tagging requires Enterprise Edition or higher. VERIFIED via search snippets of docs.snowflake.com/en/sql-reference/account-usage/tag_references and user-guide/object-tagging (2026-09-27).
Why it matters: rules on database or schema for query subjects cannot match. The D-15 cloud-services driver has no per-query operand. Native-tag evidence has no source, and on Standard Edition there will never be one.
Resolution:
- ING projection additions (optional, verified): QUERY_HISTORY `DATABASE_ID, DATABASE_NAME, SCHEMA_ID, SCHEMA_NAME, CREDITS_USED_CLOUD_SERVICES`; SESSIONS `CLIENT_APPLICATION_ID`, capability-gated; TAG_REFERENCES as a daily snapshot with SCD2 from first observation, capability-gated to Enterprise+. Bridge computes container inheritance itself through levels (G-ALC-02).
- `table access` (ACCESS_HISTORY, Enterprise) and `Power BI` (WRK-003) are R1* or R2 attributes, marked unavailable in the attribute registry when the capability is missing.
- If CREDITS_USED_CLOUD_SERVICES is not approved, the D-15 cloud-services fallback is proportional to the group's warehouse query-cost for the same account-day, labelled as such.
- D-16 regex stays R2; remove "bounded regex evaluation" from ALC-002 R1 acceptance.
Affects: ALC-001, ALC-002, ALC-103, ING (projection task), CON (grants).

### G-ALC-12 · Chargeback statement model is missing (states, "issued", PDF, retention, restatement)
Severity: HIGH · Type: GAP
Evidence:
- ALC-008 — "Statement book/period/currency/version, lines, approvals, evidence and predecessor"; chargeback UI — "Prepared → reviewed → approved → issued"; "Issued statements: 2 — One per team".
- ADR-009 — "reports 30 days" (AUDIT X-31).
- RPT-003 depends on ALC-008 and owns the "Chargeback Statement" template, yet ALC-008 must issue statements. As written this is a cycle.
Why it matters: there is no definition of what makes a statement issued, whether issue waits for the PDF, what is immutable where, or what happens to already-issued targets when a closed charge changes. A retention of 30 days would delete financial evidence.
Resolution:
- **Header** in PG: `governance.chargeback_statements`, unique `(tenant, book, target_group, period, currency, version_no)`. States: `DRAFT → PREPARED → REVIEWED → APPROVED → ISSUED → SUPERSEDED`, plus `VOIDED_DRAFT`. PG trigger: after ISSUED only `state→SUPERSEDED` is allowed.
- **Lines** in Snowflake: `fct_chargeback_statement_line`, insert-only, with no UPDATE grant on the table. The header stores a digest `(line_count, total, sha256)`.
- **"Issued"** means the lines are frozen, the digest is recorded, statement data is visible to the target group's readers, and the idempotent key is consumed. Issue does **not** wait for the PDF.
- **PDF**: rendered asynchronously by the RPT-002 worker, stored in S3 with Object Lock (governance mode) under retention class `financial_statement` (default 7 years, configurable; X-31), with the checksum attached as `pdf_status=READY`. This breaks the RPT-003 cycle: RPT-003 styles the template; ALC-008 ships a minimal certified layout.
- **Preconditions**:
  - FIN-010 period CLOSED for the scope, or a recorded exception.
  - Required controls RECONCILED, or a recorded exception.
  - `price_basis = BILLED_SOURCE`, or a recorded exception.
  - One book and one currency.
  - Approver differs from the preparer (default).
- **Corrections**: `NEXT_PERIOD_ADJUSTMENT` by default (lines of kind PRIOR_PERIOD_ADJUSTMENT on the next open statement). `RESTATEMENT` (version n+1 with a predecessor) only after FIN-010 restate. Deltas are rounded per G-ALC-05.
Affects: ALC-008, RPT-002, RPT-003, FIN-010.

### G-ALC-13 · Book, group set, policy version and "teams" are conflated
Severity: MEDIUM · Type: AMBIGUITY
Evidence:
- `allocation.md` — "charge_id × allocation_book/group_set"; "alternative policies are separate versions, not additive results".
- `control-plane.md` — both `identity.teams/team_members` and `governance.usage_group_sets` exist.
- security.md role "Team Admin: Own team membership".
Why it matters: implementers cannot tell whether two idle policies are two books (each counted "once per book", so summable across books) or two versions. Nor can they tell whether a "team" grant means an identity team or a usage group.
Resolution:
- `book_id = group_set_id`. Exactly one ACTIVE `policy_version` per book per effective interval; alternative policies exist only as simulations or inactive versions.
- Each group set is bound 1:1 to a tag dimension; groups map dimension values in effective-dated mappings.
- Identity teams are user collections, used for recipients and Team Admin delegation. They are *linked* to a usage group by an explicit `team.usage_group_ref`, which is what grants reference. Grants never infer from team names.
Affects: ALC-004, ALC-005, ALC-101, CTL-003.

### G-ALC-14 · Coverage on the absolute basis depends on how adjustments are represented and can exceed 100%
Severity: MEDIUM · Type: AMBIGUITY
Evidence:
- `ledger.md` — "attribution coverage uses sum(abs(eligible charge amounts)) as denominator".
- D-12 includes `is_adjustment` in the charge grain.
- ALC-006 failure list — "Coverage ratio over100%; net-zero cancellation hides unassigned spend".
- Computation on F-270 with the D-15 seed and no team rules: PLATFORM gets transfer 4 + support 5 + rebate −3 = **6**; UNALLOCATED = 200+10+12+18+6+8+10 = **264**; total 270 PASS. Coverage = (4+5+3)/276 = **4.3478%** if cloud services is one net charge of 10. If the gross 30 and the adjustment −20 are separate D-12 rows, the result is 12/316 = **3.7975%**.
Why it matters: the same allocation yields different coverage depending on a ledger representation detail. If manual transfers or mixed-sign lines are counted per line, coverage can exceed 100%.
Resolution:
- The coverage basis is `coverage_bucket = (account|org, usage_date, service_type, currency)` net of adjustments: eligible_abs = Σ |net bucket amount|.
- For each bucket, covered_abs = |net bucket amount| × (net assigned / net bucket amount), clamped to [0, |net|]. A sign flip raises the quality flag COVERAGE_SIGN_MISMATCH.
- Transfers are excluded. Zero denominator → null.
- FIN states the bucket rule in its contract (cross-domain note).
Affects: ALC-006, ALC-102, FIN-001.

### G-ALC-15 · Simulation execution path, latency and cost are unspecified
Severity: MEDIUM · Type: GAP
Evidence: ALC-003 — "Run simulation over selected authorized scope… simulation timeout"; D-04 — "Draft simulations use a separate simulation_input schema". No runtime, target or budget is given.
Why it matters: simulation either reimplements the dbt logic in the API, which creates a second formula, or runs unbounded dbt builds on the shared dbt pool and starves steady state.
Resolution:
- The draft is compiled to rows in `SIMULATION_INPUT.cfg_*` keyed `(tenant_id, simulation_id)` by the config-publisher identity.
- An API-004 job launches a Dagster run: `dbt build --select tag:allocation_sim --vars {simulation_id, window, input_publication_id}` into `SIMULATION.*` tables keyed by simulation_id, with a TTL of 14 days.
- Baseline (currently published config) and candidate are computed on the **same pinned publication**.
- Separate pool: 1 per tenant, 2 global; 30 simulations per tenant per day. Window ≤ 92 days, default 31.
- Targets, TO VERIFY LIVE in ALC-104: p95 ≤ 5 min at reference scale (10 accounts × 1M queries/day × 31 days) on a MEDIUM simulation warehouse; hard timeout 20 min → `SIMULATION_FAILED(TIMEOUT)`, retryable. Estimated cost about 0.3 credits per simulation.
- A dbt graph test fails if any non-`allocation_sim` model references `SIMULATION_INPUT`.
Affects: ALC-003, ALC-104, ORC.

### G-ALC-16 · Volume at 1M queries/day/account needs classification-key deduplication and a bounded output grain
Severity: MEDIUM · Type: RISK
Evidence: 1M queries/day/account (review scope). `fct_query_compute` is query-grain. Contains/prefix predicates cannot use equi-joins. The output grain in G-ALC-01 is multiplied by books.
Why it matters: evaluating 500 rules against 1M rows per account-day, repeated for 3 books and on every simulation, is tens of billions of predicate evaluations per month and turns allocation into the largest central cost line (OPS-009).
Resolution:
- `int_query_classification_key` = sha2 over the fixed attribute tuple `(account_id, warehouse_id, role, user_pseudonym (D-10), query_tag, client_app, database_id, schema_id, dbt_project, dbt_model, query_parameterized_hash)`.
- Rules are evaluated on distinct keys per day (expected ≤ 5% of query rows; asserted on fixtures and measured live).
- QUERY units aggregate by `(charge, warehouse, key)` before the join.
- eq/in use equi-joins; prefix/suffix/contains use per-attribute joins over distinct values × predicates of that operator.
- Output ≈ charges × warehouses × components × groups: about 30k rows/day/tenant at 10 accounts × 100 warehouses × 3 books.
- Insert-only partitions `(tenant, book, usage_date)` per D-05, clustered by (tenant_id, usage_date).
Affects: ALC-001, ALC-002, ALC-005, ALC-104.

### G-ALC-17 · Over-serialized and missing dependency edges
Severity: MEDIUM · Type: RISK
Evidence (task-index.json): ALC-001←FIN-009 (full reconciliation), ALC-005←FIN-010 (close), ALC-008←ALC-007 (showback UI), ALC-006←UX-004 (Cost Explorer), GOV-001←ALC-007. Chain FIN-009→API-001→WRK-001→ALC-001…ALC-007→GOV-001 sits on the 73-task path.
Why it matters: allocation contracts and SQL cannot start until reconciliation UX is done. Chargeback waits on a showback UI it does not use. Team entitlements (ALC-101) have no edge at all.
Resolution: per-task "Dependency changes" in §4. Headline changes: ALC-001 −FIN-009 +FIN-001 +DBT-003; ALC-005 −FIN-010 +FIN-009 +ORC-005; ALC-006 −UX-004 +UX-002; ALC-008 −ALC-007 +ALC-006 +ALC-103 +RPT-002; ALC-007 +ALC-101 +ALC-102; GOV-001 −ALC-007 (+ALC-102 only for team budgets).
Affects: all ALC tasks, GOV-001.

## 3. Contract-first artifacts to author before coding

| Artifact | Exact content required | Produced by |
|---|---|---|
| `data/contracts/tags.json` | Dimension schema (key regex `^[a-z][a-z0-9_]{1,62}$`, reserved keys list incl. tenant_id/organization_id/account_id/book/group/currency/amount/publication_id), value_type STRING/ENUM (≤5,000 values), built-in 13 dimensions; tag assignment fact schema (source RULE/OVERRIDE/NATIVE_EVIDENCE/UNCLASSIFIED/CONFLICT, confidence enum) | ALC-001-S01 |
| `data/contracts/rule-attributes.json` | Subject kinds × attributes × normalization (UPPER identifiers, raw query_tag) × source relation × capability gate (Enterprise/ACCESS_HISTORY/TAG_REFERENCES) × level | ALC-001-S04 |
| `data/contracts/rule-ast.json` | DNF AST JSON Schema, operators R1, null truth table, limits, split assignment (weights ≤6 dp, Σ=1) | ALC-002-S01/S02 |
| Precedence spec `docs/…/alc-precedence.md` | Level order, per-level priority, conflict and runtime-conflict rules, inheritance chain query→warehouse, container chain table→schema→database→account | ALC-002-S04 |
| Snowflake CONFIG DDL | `cfg_rule, cfg_rule_predicate, cfg_rule_split, cfg_override, cfg_group_set, cfg_group, cfg_value_mapping, cfg_group_closure, cfg_allocation_policy, cfg_pool, cfg_transfer` keyed `(tenant_id, config_version, …)`, insert-only; mirrored in `SIMULATION_INPUT` keyed `(tenant_id, simulation_id, …)` | ALC-002-S07, ALC-004-S04, ALC-005-S02 |
| dbt model contracts | `int_alloc_subject_attrs, int_query_classification_key, int_tag_resolution, fct_tag_assignment, int_group_membership, dim_group_closure, int_alloc_unit, fct_allocation_line, srv_allocation_restricted, mart_allocation_quality, fct_chargeback_statement_line` with grain, unique key, tenant key, clustering, tests | ALC-001/002/004/005/006/008, ALC-101 |
| Rounding spec + fixtures | Signed LR algorithm (G-ALC-05), hierarchical order, 1e-12 and minor-unit use, ISO-4217 minor units, fixtures ALC-GOLD-R1…R5 | ALC-005-S04, ALC-008-S03 |
| State machines | Ruleset/hierarchy/policy: DRAFT→SIMULATING→REVIEWABLE→APPROVED→PUBLISHING→PUBLISHED→SUPERSEDED with STALE, SIMULATION_FAILED, PUBLISH_FAILED and guards; Statement: DRAFT→PREPARED→REVIEWED→APPROVED→ISSUED→SUPERSEDED | ALC-003-S01, ALC-008-S01 |
| Access-impact & disclosure spec | Impact computation, ACCESS approver role, recheck at publish, epoch bump; pool disclosure CONCEALED/DISCLOSED with k≤2 warning; restricted projection column list | ALC-003-S05, ALC-101-S01/S05 |
| OpenAPI | `/v1/tag-dimensions`, `/v1/rulesets{,/id/simulate,/approvals,/publish,/rollback}`, `/v1/simulations/{id}`, `/v1/usage-group-sets{…/groups,/hierarchy}`, `/v1/allocation/policies`, `/v1/allocation/quality`, `/v1/allocation/transfers`, `/v1/showback`, `/v1/chargeback/statements{…:prepare,:approve,:issue,:restate}` with Idempotency-Key/If-Match | ALC-001…008 |
| Error codes | `RESERVED_KEY, DIMENSION_IN_USE, RULE_SCHEMA_INVALID, WEIGHTS_NOT_ONE, HIERARCHY_CYCLE, CROSS_SET_PARENT, VALUE_MAPPED_TWICE, SIMULATION_STALE, ACCESS_REVIEW_STALE, SELF_APPROVAL_FORBIDDEN, CLOSED_PERIOD_RETROACTIVE, POOL_REFERENCE_NOT_SUPPORTED, NON_ADDITIVE_BOOKS, QUALITY_REQUIRES_BOOK_SCOPE, STATEMENT_PRECONDITION_FAILED, STATEMENT_IMMUTABLE` | each task |
| D-15 seed | `data/fixtures/allocation/default_book_v1.yaml` family→method→fallback table (G-ALC-10) | ALC-103-S06 |
| Golden fixtures | ALC-GOLD-01 (84/56→120/80), -02 (84/56/60), -03 (two books each 200; sum request 422), -04 (zero-usage pool → UNALLOCATED 200), -05 (1.00/−1.00 thirds; mixed-sign 0.34), -06 (F-270 default book: PLATFORM 6, UNALLOCATED 264, coverage 4.3478%), -07 (rebate −3 at 60/40 → −1.80/−1.20), -08 (restricted Finance response contains no Marketing ids/amounts) | ALC-005, ALC-103, ALC-101 |

## 4. Revised production backlog

### ALC-001 — Create dimension registry and external tag fact model
Release: R1 · Estimate: 36–52 h · Risk: M · Decisions: D-10, D-16 · Closes: G-ALC-11 (partial), G-ALC-16 (partial)
Dependency changes: `−FIN-009` (the registry needs the charge schema and resource identity, not reconciliation UX), `+FIN-001`, `+DBT-003` (SCD2 resource identity). WRK-001 is kept only for S07 (workload attributes).

| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| ALC-001-S01 | Author the dimension and tag-assignment JSON Schemas, including the reserved-key list and value types | `data/contracts/tags.json` | Positive/negative payload suite passes; `tenant_id` as a key is rejected by the schema | 2 |
| ALC-001-S02 | Create an Alembic migration for `governance.dimension_definitions` with `unique(tenant_id, lower(key))`, composite tenant FKs and FORCE RLS; seed the 13 built-ins idempotently on tenant creation | migration + seed function | Seeding twice leaves 13 rows; a query without tenant context returns 0 rows | 3 |
| ALC-001-S03 | Implement CRUD `/v1/tag-dimensions`: key immutable, label rename allowed, archive → 409 `DIMENSION_IN_USE` when referenced by an active rule or group set; archived dimensions stay resolvable for statements; Idempotency-Key and If-Match | `apps/api/tag_dimensions` | Contract tests: rename keeps id; stale If-Match → 409; archived dimension still resolves in explain | 4 |
| ALC-001-S04 | Author the attribute registry (subject kinds × attributes × normalization × source × capability gate × level); mark `database/schema/cloud_services_credits` as requiring the ING projection additions, `native_tag` as Enterprise-only, `table_access` as R2 | `data/contracts/rule-attributes.json`, `packages/rules/attributes.py` | Registry loads; an unavailable capability yields `ATTRIBUTE_UNAVAILABLE` at rule validation | 3 |
| ALC-001-S05 | Build dbt `int_alloc_subject_resource` (tenant, account, subject_kind, stable subject_id, attribute, value_norm, valid_from/to) from DBT-003 SCD2 resource history | `data/dbt/models/allocation/tags/int_alloc_subject_resource.sql` | A renamed warehouse keeps its subject_id with two name intervals; same name in A1/A2 gives distinct subject_ids | 4 |
| ALC-001-S06 | Build `int_alloc_native_tag_evidence` from a TAG_REFERENCES daily snapshot (SCD2 from first observation, direct tags only, capability-gated); emit an empty typed relation with a coverage row when the capability is absent | dbt model + capability flag | On Standard Edition the fixture yields 0 rows plus coverage `NATIVE_TAGS_UNAVAILABLE`; no Snowflake write to customer | 3 |
| ALC-001-S07 | Build `int_query_classification_key` (sha2 of the fixed tuple in G-ALC-16) and `int_classification_key_attrs` (distinct keys per day) | dbt models | On the fixture, the key table is ≤ 5% of query rows; the key is stable across reruns | 3 |
| ALC-001-S08 | Define `fct_tag_assignment` with explicit UNCLASSIFIED and CONFLICT rows; dbt test that every eligible subject × active dimension × day has exactly one row | dbt model + custom test | The test fails when an assignment is dropped; an unmatched resource appears as UNCLASSIFIED | 3 |
| ALC-001-S09 | Add edge fixtures: rename, invalid enum value, overlapping effective dates on a manual dimension value, same resource name across accounts, custom key `tenant_id` | `tests/spec/ALC-001/` | Expected: continuous history, 422 `VALUE_NOT_ALLOWED`, 422 `EFFECTIVE_OVERLAP`, no cross-account join, 422 `RESERVED_KEY` | 3 |
| ALC-001-S10 | Add authorization tests: foreign-tenant dimension id → non-enumerating 404; Viewer/Analyst/Team Admin mutation → 403; FinOps Admin allowed | API tests | All pass with the audit event recorded for denials | 2 |
| ALC-001-S11 | Implement `GET /v1/tag-dimensions/{key}/values` and a tag-coverage read through the semantic planner (no raw SQL), scoped by profile | API + registry entries | A restricted profile sees values only for authorized subjects | 3 |
| ALC-001-S12 | Add observability (log fields `tenant_ref, dimension_key, unclassified_subjects`; dbt test results attached to the run) and a runbook entry "native tags unavailable" | `docs/runbooks/allocation.md` §tags | Runbook reviewed; the log contains no raw user names (D-10) | 2 |
| ALC-001-S13 | Record evidence (local plus staging dbt run) | `docs/evidence/ALC-001/<commit>/` | Evidence record fields complete | 1 |

Task acceptance:
- [ ] A rename preserves tag history for the stable subject_id; the same resource name in two accounts never joins.
- [ ] Every eligible subject × active dimension has exactly one assignment row per day, including explicit UNCLASSIFIED.
- [ ] Reserved and invalid keys and values are rejected with typed errors; archived dimensions stay resolvable for issued statements.
- [ ] Native-tag evidence is capability-gated, and its absence is reported as coverage, not as "no tags".

### ALC-002 — Implement bounded rule evaluation and deterministic conflicts
Release: R1 (regex R2) · Estimate: 44–62 h · Risk: H · Decisions: D-16, D-10 · Closes: G-ALC-02, G-ALC-16 (partial), G-ALC-11 (regex)
Dependency changes: none (`+CTL-005` moves to ALC-003).

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| ALC-002-S01 | Author the DNF rule AST JSON Schema (operators, limits, split assignment, `additionalProperties:false`) | `data/contracts/rule-ast.json` | `{"op":"sql"}`, unknown keys, 9 clauses, `in []` and a 33 KB rule are all rejected | 3 |
| ALC-002-S02 | Write the null-semantics truth table and implement the normalization (identifiers UPPER, empty→NULL) | spec + `packages/rules/normalize.py` | Independently written table tests (12 ops × {value, NULL, empty}) pass | 2 |
| ALC-002-S03 | Implement the pure Python reference `evaluate_rules(subject_attrs, ruleset) → candidates` | `packages/rules/evaluate.py` | Unit fixtures pass; no eval/exec; mypy strict | 4 |
| ALC-002-S04 | Implement resolution: level order, per-level priority, identical duplicates not a conflict, CONFLICT otherwise; inheritance query→warehouse and table→schema→database→account | `packages/rules/resolve.py` + precedence spec | Priority 100 beats 50; equal priority with different values → CONFLICT; equal with same value → assigned | 3 |
| ALC-002-S05 | Implement static validation at save: duplicates, same-priority overlap (eq/in intersection, prefix-prefix), weights Σ = 1 exactly, valid_to > valid_from | `packages/rules/validate.py` | `prefix 'FIN'` vs `prefix 'FINANCE'` at the same priority → `OVERLAP` error; 0.333333 ×3 → `WEIGHTS_NOT_ONE` | 3 |
| ALC-002-S06 | Create PG `governance.tag_rules, ruleset_versions, rule_overrides`; content hash = sha256 of canonical JSON; immutable once state ≥ SIMULATING | migrations | Updating a SIMULATING version → DB trigger error; the hash is stable across key order | 3 |
| ALC-002-S07 | Build the compiler: ruleset → `cfg_rule`, `cfg_rule_predicate`, `cfg_rule_split` rows with deterministic ordering; round-trip decompile | `packages/rules/compile.py` | compile→decompile equals the canonical AST for 1,000 generated rulesets | 3 |
| ALC-002-S08 | Write dbt macro `alloc_match_predicates`: equi-join for eq/in; per-attribute join over distinct values for prefix/suffix/contains; anti-join for negations; is_null via missing attribute | `data/dbt/macros/allocation/alloc_match_predicates.sql` | The query profile shows no cartesian join for eq/in on the fixture | 4 |
| ALC-002-S09 | Build `int_rule_clause_match` (all_of count = clause size), `int_rule_match` (any_of) and `int_tag_resolution` (RANK by level, priority) | dbt models | Fixture assignments equal the hand-computed table | 4 |
| ALC-002-S10 | Write a differential test: 5,000 Hypothesis-generated (attrs, ruleset) cases evaluated by the Python reference and by dbt in the CI Snowflake schema | `tests/spec/ALC-002/test_differential.py` | 0 mismatches; seed recorded | 4 |
| ALC-002-S11 | Implement overrides on stable subjects only (resource id, parameterized hash or workload_id — never a single query_id), with reason ≥ 10 chars and a validity interval; expiry falls back at the UTC day boundary | resolve + tests | An expired override on D+1 yields the rule result; a query_id override → 422 | 3 |
| ALC-002-S12 | Add fixtures for a malicious payload, an injection-looking value matched literally, rule-order permutation invariance (100 shuffles) and runtime conflict → UNASSIGNED/CONFLICT | `tests/spec/ALC-002/` | Identical output across permutations; `'); drop` is matched as a literal string only | 3 |
| ALC-002-S13 | Add a performance guard: evaluate on distinct keys only; assert key/query ratio and predicate-join row counts in run metadata | dbt run artifacts | Ratio ≤ 5% on the fixture; metadata published | 2 |
| ALC-002-S14 | Add observability (conflicts per run, new runtime conflicts alarm `ALC_RUNTIME_CONFLICT_NEW`) and a runbook "conflict spike" | alarm + runbook | The alarm fires in a staging injection | 2 |
| ALC-002-S15 | Record evidence | `docs/evidence/ALC-002/` | Complete | 1 |

Task acceptance:
- [ ] Python reference and dbt SQL agree on 5,000 generated cases.
- [ ] Output is invariant to rule order; equal-priority different values → CONFLICT, never an arbitrary winner.
- [ ] NULL semantics follow the truth table for all 12 operators.
- [ ] No executable expression path exists (the schema rejects it; values are always bound literals).
- [ ] Evaluation runs on distinct classification keys, never per query row.

### ALC-003 — Build simulation, review and ruleset publication
Release: R1 · Estimate: 54–77 h · Risk: H · Decisions: D-04, D-06, D-05 · Closes: G-ALC-07, G-ALC-08, G-ALC-09, G-ALC-15
Dependency changes: `+CTL-005` (config-publisher, D-04); `+FIN-010` contract only (the period-state read interface for the retroactivity guard; no live evidence needed); `+SEC-006` (epoch bump on access-relevant publish).

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| ALC-003-S01 | Specify the ruleset state machine with all transitions and guards (incl. STALE, SIMULATION_FAILED, PUBLISH_FAILED) and implement it as a PG-checked transition function | `apps/api/rulesets/state.py` + spec | An illegal transition → 409 `INVALID_TRANSITION`; table-driven test covers every edge | 3 |
| ALC-003-S02 | `POST /v1/rulesets/{id}/simulate`: validate, create an API-004 job and outbox event; the config-publisher inserts compiled draft rows into `SIMULATION_INPUT.cfg_*` keyed (tenant, simulation_id) | API + publisher handler | Published `CONFIG.cfg_*` rows untouched (checksum before/after); a dbt graph test forbids non-sim models from reading SIMULATION_INPUT | 3 |
| ALC-003-S03 | Add the dbt `allocation_sim` selector with vars (simulation_id, window ≤ 92 d, input_publication_id) writing baseline and candidate into `SIMULATION.*` on the same pinned publication | dbt selectors + Dagster job | Baseline equals the live published allocation when the publication is unchanged (12-dp equality) | 4 |
| ALC-003-S04 | Build `sim_preview_summary`: coverage before/after (abs basis), movement matrix, top 50 changed subjects, conflicts with ≤ 20 samples each, untested scope (days/accounts with incomplete coverage) | dbt model + API projection | Fixture: Finance subset coverage 0% → 100%, 1 matched workload, 0 conflicts (UI fixture) | 4 |
| ALC-003-S05 | Compute access impact per granted (group_set, group) incl. ancestors: entering/leaving subjects and amount, affected profiles and users | dbt model + API | Moving a subject into granted group G flags access_relevant with 1 affected profile | 3 |
| ALC-003-S06 | Store the window fingerprint and dependency versions on the simulation; approvals reference simulation_id + fingerprint + content hash | PG columns + fingerprint SQL | The fingerprint changes when a charge revision in the window changes and not when data is appended after the window | 2 |
| ALC-003-S07 | `POST /v1/rulesets/{id}/approvals {kind: FINANCIAL|ACCESS}`: FINANCIAL = FinOps Admin ≠ author (four-eyes default); ACCESS = Org Admin/Owner ≠ author; TTL 7 days; If-Match; audit | API | Self-approval → 403 `SELF_APPROVAL_FORBIDDEN`; FinOps Admin giving ACCESS → 403 | 3 |
| ALC-003-S08 | Evaluate staleness at approve and at publish (fingerprint, dependencies, hash, TTL, recomputed access impact) | API service | Revised in-window charge → 409 `SIMULATION_STALE`; a new grant since review → 409 `ACCESS_REVIEW_STALE` | 3 |
| ALC-003-S09 | Publish: Idempotency-Key → outbox → config-publisher `INSERT … WHERE NOT EXISTS (config_version)` → mark dirty partitions in the processing ledger → PUBLISHING until the ORC publication with that config_version → PUBLISHED; epoch bump if access-relevant | API + publisher + ORC hook | Duplicate publish → one config_version; state reaches PUBLISHED only after the pointer advance | 4 |
| ALC-003-S10 | Add the closed-period guard and the `apply_from=FIRST_OPEN_PERIOD` clamp | API validation | valid_from in a CLOSED month → 422 `CLOSED_PERIOD_RETROACTIVE`; the clamp yields the first open date; closed partitions are not in the dirty set | 2 |
| ALC-003-S11 | Rollback: `POST /rollback {to_version}` creates version N+1 with the prior content; normal simulation and approvals apply | API | After rollback, open-period allocations equal the target version's; closed periods unchanged | 3 |
| ALC-003-S12 | Add the post-publication parity check (live run vs simulation over the same window and publication) | Dagster asset check | An injected divergence raises `ALC_SIM_PARITY_MISMATCH` | 2 |
| ALC-003-S13 | Add failure tests: lost ack after config insert (reconciler adopts), simulation timeout at 20 min, worker crash mid-simulation, unauthorized reviewer, dataset revised during review | `tests/spec/ALC-003/` | Each ends in the documented recoverable state; no partial config_version visible | 4 |
| ALC-003-S14 | Tag Studio rule editor `/allocate/tags/rules`: DNF builder, ordered priorities, validation messages, draft save | `apps/web/tag_studio/rules` | Playwright: create, validate, save; keyboard-only path works | 4 |
| ALC-003-S15 | Preview and approval UI: before/after coverage, movement matrix, conflicts, access-impact panel, stale banner, publication pending/accepted | `apps/web/tag_studio/preview` | Playwright UX state matrix (empty/loading/partial/error/denied/success) | 4 |
| ALC-003-S16 | Add security tests: foreign simulation_id → 404; Team Admin rule targeting a group outside delegation → 403; simulation results only for book-wide profiles | API tests | All pass; denials audited | 3 |
| ALC-003-S17 | Add observability: simulation duration, credits via QUERY_TAG `bridge_finops:alc_sim`, queue wait, stale rate; runbook "simulation timeout / stale loops" | metrics + runbook | Dashboard panel shows the staging simulation | 2 |
| ALC-003-S18 | Record evidence | `docs/evidence/ALC-003/` | Complete | 1 |

Task acceptance:
- [ ] A draft never affects live tags or allocations (checksums of CONFIG and serving unchanged).
- [ ] A revision inside the window, a dependency change or a TTL breach blocks approval or publication; appended data does not.
- [ ] Access-relevant rulesets cannot publish without an ACCESS approval by an Org Admin/Owner different from the author, rechecked at publish.
- [ ] Duplicate publish yields one config_version; PUBLISHED only after the ORC pointer advance.
- [ ] Closed periods are never recomputed by publication or rollback.

### ALC-004 — Implement usage group sets and effective hierarchies
Release: R1 · Estimate: 37–53 h · Risk: M · Decisions: D-04, D-05 · Closes: G-ALC-13, G-ALC-04 (part)
Dependency changes: none. PG CRUD (S01–S03) may start in parallel with ALC-003; publication (S06) needs ALC-003.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| ALC-004-S01 | Author the contract: group_set bound 1:1 to a dimension; groups with parent, system_kind UNASSIGNED/PLATFORM; value→group mappings with validity; hierarchy_version | `data/contracts/usage-groups.json` | Schema suite passes | 2 |
| ALC-004-S02 | Create PG migrations `usage_group_sets, usage_groups, group_value_mappings, hierarchy_versions` with composite tenant FKs; auto-create a non-deletable UNASSIGNED leaf | migrations | Deleting UNASSIGNED → DB error; RLS enforced | 3 |
| ALC-004-S03 | Add hierarchy validation: acyclic (DFS), depth ≤ 8, ≤ 5,000 groups/set, no cross-set parent, no orphan, one group per dimension value per interval | `apps/api/usage_groups/validate.py` | 422 `HIERARCHY_CYCLE`, `CROSS_SET_PARENT`, `VALUE_MAPPED_TWICE` on fixtures | 3 |
| ALC-004-S04 | Implement effective-dated moves as a new hierarchy version; compute closure rows (ancestor, descendant, depth, valid_from, valid_to); publish via the config-publisher | `cfg_group_closure` export | A move on Sep 15 gives two closure intervals; the prior version is retained | 4 |
| ALC-004-S05 | Build dbt `dim_group_closure` and `int_group_membership` (subject → group per day; UNCLASSIFIED/CONFLICT → UNASSIGNED); test split weights Σ = 1 per (subject, set, day) | dbt models + tests | The conservation test passes; the CONFLICT subject lands in UNASSIGNED | 3 |
| ALC-004-S06 | Add CRUD `/v1/usage-group-sets`, `/groups`, `/hierarchy:preview`, `/hierarchy:publish` reusing the ALC-003 simulation, approval and publication machinery | API | Hierarchy publication creates a config_version and goes through the same guards | 4 |
| ALC-004-S07 | Delete/rename semantics: a group referenced by a published allocation or statement is archive-only; rename keeps id | API + tests | Delete used group → 409 `GROUP_IN_USE`; rename reflected in statements by id | 2 |
| ALC-004-S08 | Access relevance of moves and mappings (reusing ALC-003-S05): moving C under granted parent B flags impact | tests | "Permission broadened by move" requires an ACCESS approval | 3 |
| ALC-004-S09 | Add book-additivity tests: the same 200 in Teams and Products books each totals 200; a request summing two books → 422 `NON_ADDITIVE_BOOKS` (registry rule from ALC-102) | `tests/spec/ALC-004/` | Each book 200; combined 400 is never returned | 2 |
| ALC-004-S10 | Build the tree editor `/allocate/usage-groups`: create/move with an effective-date picker, unassigned always visible | `apps/web/usage_groups` | Playwright: create set, move group, preview, publish | 4 |
| ALC-004-S11 | Build the group detail page with members/resources, charges and rules drilldown (admin scope only) | `apps/web/usage_groups/detail` | UX state matrix passes | 3 |
| ALC-004-S12 | Add authorization tests: Team Admin edits only descendants of the delegated group; foreign set id → 404 | API tests | All pass | 2 |
| ALC-004-S13 | Record observability and evidence | runbook + evidence | Complete | 2 |

Task acceptance:
- [ ] Each book conserves the same charge independently; the API refuses cross-book sums.
- [ ] Cycles, cross-set parents and duplicate mappings cannot be published.
- [ ] Moves are effective-dated; prior hierarchy versions remain resolvable for old allocations and statements.
- [ ] Access-broadening moves require an ACCESS approval.

### ALC-005 — Implement allocation methods and conservation
Release: R1 · Estimate: 49–70 h · Risk: H · Decisions: D-05, D-06, D-12, D-14, D-15 · Closes: G-ALC-01, G-ALC-06, G-ALC-10 (core methods), G-ALC-16
Dependency changes: `−FIN-010` (runs do not need close; statements do); `+FIN-009` (all charge families and bridges incl. FIN-021 buckets); `+ORC-005` (publication manifest). Pools, residual, transfers and the D-15 seed move to ALC-103.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| ALC-005-S01 | Write DDL contracts for `int_alloc_unit` and `fct_allocation_line` (unique key, NUMBER(38,12), status ALLOCATED/UNALLOCATED/CONFLICT, reason codes) | `data/contracts/allocation-line.json` + dbt contracts | dbt contract enforcement passes | 3 |
| ALC-005-S02 | Author the `allocation_policy` config: family selector → component → method → params → fallback chain; one ACTIVE version per book per interval; every family covered or explicitly UNALLOCATED | `data/contracts/allocation-policy.json` + validator | A missing family → 422 `POLICY_INCOMPLETE`; a cyclic fallback → 422 | 3 |
| ALC-005-S03 | Build `int_alloc_unit` from `fct_charge` + bridges (QUERY units by (charge, warehouse, key); IDLE; HOUR_RESIDUAL; RESOURCE; WHOLE) | dbt model | Test: Σ units = charge amount exactly, for 100% of charges | 4 |
| ALC-005-S04 | Implement precision macros `alloc_mul_div` (cast to (38,18), multiply first, ROUND 12) and `alloc_lr_1e12` (signed LR, tie-break target_id asc) | `data/dbt/macros/allocation/precision.sql` + `packages/allocation_helpers/rounding.py` | NUMBER(38,2) amount / driver keeps 12 dp; Python and SQL outputs identical on 1,000 vectors | 3 |
| ALC-005-S05 | Implement the direct method via `int_group_membership`, with split weights and LR | dbt model | Unit classified 50/50 split of 1.00 → 0.500000000000 each | 2 |
| ALC-005-S06 | Implement query-cost: Σ QUERY units per group; unclassified → UNALLOCATED | dbt model | Fixture query140 → Finance 84, Marketing 56 | 2 |
| ALC-005-S07 | Implement the idle policies OWNER, PROPORTIONAL_CONSUMERS (per charge×warehouse×day, `include_unassigned_in_denominator`) and PLATFORM; no IDLE units on Adaptive warehouses; fallback chain | dbt model | ALC-GOLD-01: 120/80; ALC-GOLD-02: 84/56/60; zero consumers → OWNER → UNALLOCATED | 4 |
| ALC-005-S08 | Implement fixed percentage (weights ≤ 6 dp, Σ = 1) | dbt model | 1.00 × (0.333333, 0.333333, 0.333334) conserves at 12 dp | 2 |
| ALC-005-S09 | Implement proportional, measured-usage and weighted drivers from registry metrics; negative driver → UNALLOCATED(`NEGATIVE_DRIVER`); Σb = 0 → UNALLOCATED(`ZERO_DENOMINATOR`) unless fallback | dbt macro | Fixtures for each reason; the fallback applies only when part of the approved policy | 4 |
| ALC-005-S10 | Implement the cloud-services driver: gross query cloud credits per group for the account-day; fallback query-cost share when the column is unavailable (labelled) | dbt model | FIN-GOLD cloud 10 split by gross-credit shares; label present in the fallback case | 2 |
| ALC-005-S11 | Implement storage by database owner and serverless by object owner from the FIN-006/FIN-011…017 bridges; missing bridge → WHOLE UNALLOCATED | dbt models | Storage 12 → database groups; a missing bridge gives UNALLOCATED 12, not dropped | 3 |
| ALC-005-S12 | Write dbt conservation tests: per (tenant, book, run, charge, currency) Σ lines − charge = 0; each charge once per ACTIVE book per run; line currency = charge currency | `data/dbt/tests/allocation/` | Injected 1e-12 drift fails the test; publication is blocked | 2 |
| ALC-005-S13 | Add signed fixtures: rebate −3 at 60/40 → −1.80/−1.20; refund with zero driver → UNALLOCATED −3; 1.00 and −1.00 thirds at 12 dp | `tests/spec/ALC-005/` | Exact expected values match (independently computed) | 3 |
| ALC-005-S14 | Handle late charge correction: a new charge revision in an open period recomputes the partition as a new revision (D-05) with the old one retained; closed periods are not recomputed (the delta goes to ALC-008) | dbt + ORC hook | Revision 2 replaces revision 1 in the open month only | 3 |
| ALC-005-S15 | Implement insert-only publication: partitions (tenant, book, usage_date) with revision ids, runs pinning charge publication + config versions, clustering (tenant_id, usage_date) | dbt config + manifest entries | Rerun with identical inputs → identical line hashes; no MERGE on allocation facts | 4 |
| ALC-005-S16 | Add an explain_ref on each line resolving to unit → policy/rule → driver operands (book-wide readers only) | API-005 node types | Explain for a restricted reader omits driver/denominator (ALC-101) | 2 |
| ALC-005-S17 | Add observability: rows in/out, unallocated_abs per book (protected log), conservation failure alarm that blocks publication; runbook | alarm + runbook | Alarm fires in a staging injection | 2 |
| ALC-005-S18 | Record evidence (live dbt with F-270 and ALC-GOLD-01/02/07) | `docs/evidence/ALC-005/` | Complete | 1 |

Task acceptance:
- [ ] ALC-GOLD-01 (120/80) and ALC-GOLD-02 (84/56/60) both conserve 200; alternatives are versions, never summed.
- [ ] Conservation per charge×book×currency is exact (= 0 at 12 dp) for every run; failure blocks publication.
- [ ] Zero/negative denominators leave UNALLOCATED with a reason unless an approved fallback exists.
- [ ] Signed charges allocate with preserved sign; late open-period corrections create a new revision, closed periods are untouched.

### ALC-006 — Build allocation studio and quality remediation
Release: R1 · Estimate: 37–53 h · Risk: M · Decisions: D-15 · Closes: G-ALC-14
Dependency changes: `−UX-004` (the Cost Explorer is not needed), `+UX-002` (scope state and semantic components), `+ALC-102`.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| ALC-006-S01 | Specify the quality metrics on coverage buckets (G-ALC-14): eligible_abs, direct/rule/shared/residual/unallocated abs, coverage, null on zero denominator | `docs/…/alc-quality.md` + registry entries | F-270 default-book fixture → coverage 4.3478% | 3 |
| ALC-006-S02 | Build `mart_allocation_quality`, conflicts and unowned resources (spend > 0 and UNASSIGNED) with remediation filter keys | dbt models | The fixture's counts equal the hand table | 3 |
| ALC-006-S03 | Implement `/v1/allocation/quality` (book-wide scope only → else 403 `QUALITY_REQUIRES_BOOK_SCOPE`) and `/v1/allocation/policies` CRUD + simulate/publish via the ALC-003 machinery | API | Contract tests; restricted profile → 403 | 4 |
| ALC-006-S04 | Build the method editor per charge family: fallback chain, idle policy, eligible components; 409 stale banner when a version changes while the form is open | `apps/web/allocation_studio/editor` | Playwright: concurrent edit → stale banner, input preserved | 4 |
| ALC-006-S05 | Build the before/after waterfall per target (published vs simulation), exact decimals, table alternative; never add before and after | `apps/web/allocation_studio/preview` | Totals equal the source; accessible table present | 4 |
| ALC-006-S06 | Build the quality dashboard tiles with clickable remediation (Tag Studio filtered by subjects; prefilled draft rule) | `apps/web/allocation_studio/quality` | Each tile opens the matching filter | 4 |
| ALC-006-S07 | Add edge fixtures: zero-total period (null coverage), rebate display, net-zero (+100/−100 unassigned → unallocated_abs 200), coverage property test ≤ 100% | tests | All expected values hold; 10k random cases ≤ 100% | 3 |
| ALC-006-S08 | Add hidden-group tests: restricted viewer → 403 on studio/quality; partially delegated admin sees only delegated groups; no denominators in payloads | API + Playwright | JSON scan finds no foreign group ids | 3 |
| ALC-006-S09 | Add the parity E2E: publish → first run → studio values equal the simulation | E2E | 12-dp equality | 2 |
| ALC-006-S10 | Run the UX state matrix at 390 px plus keyboard | Playwright | All states pass | 4 |
| ALC-006-S11 | Add the quality CSV export with formula-injection protection | API | `=cmd()` cell is prefixed/escaped | 2 |
| ALC-006-S12 | Record evidence | evidence | Complete | 1 |

Task acceptance:
- [ ] Coverage components reconcile to eligible absolute exposure on the coverage-bucket basis and never exceed 100%.
- [ ] Hidden groups never leak through denominators, lists or counts.
- [ ] Simulation values equal the published run for identical inputs.
- [ ] Every quality number opens its remediation filter.

### ALC-007 — Build scoped showback portal
Release: R1 · Estimate: 30–43 h · Risk: M · Decisions: D-02 · Closes: G-ALC-03 (UI), G-ALC-17 (part)
Dependency changes: `+ALC-101`, `+ALC-102`; keep UX-003.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| ALC-007-S01 | Author the `GET /v1/showback` contract (book, group, period, currency → allocated total, by category, 13-month trend, change, top workloads/resources, new spend, budget/forecast/anomaly/opportunity refs with an explicit `UNAVAILABLE` state, coverage/status) | OpenAPI | Schema tests pass | 3 |
| ALC-007-S02 | Build `srv_showback_group_period` from the restricted projection; parent rollup = Σ lines whose target ∈ effective-dated descendants(g) on usage_date | dbt model | Parent Business = 200 when Finance 120 + Marketing 80; no double count | 4 |
| ALC-007-S03 | Show the shared/unallocated policy text ("includes $3,600 idle allocated proportionally to your query cost, policy v3"); pool totals only if DISCLOSED | API + UI copy | The Finance response contains no 6,000 or 60% | 2 |
| ALC-007-S04 | Restrict the portfolio (multi-group) view to users with grants on every shown group or book-wide | API guard | A Finance-only user → 403 on portfolio | 2 |
| ALC-007-S05 | Top workloads/resources from QUERY units allocated to the group, joined to WRK workloads; shared resource names shown with the own amount only | dbt + API | WH_SHARED shows Finance 12,000 only | 3 |
| ALC-007-S06 | Build the showback landing and team page with provisional labels and the "no financial transfer" notice | `apps/web/showback` | Playwright UX matrix passes | 4 |
| ALC-007-S07 | Build the trend and drivers components and the drilldown group → service/workload → charge explanation | `apps/web/showback/team` | Drilldown keeps scope/filters | 3 |
| ALC-007-S08 | Add tests: Finance sees 120 (not 200), Marketing 80; a child moved mid-period splits the parent rollup by date; stale allocation labelled | `tests/spec/ALC-007/` | All expected values match | 4 |
| ALC-007-S09 | Add security tests: foreign group → 404; group in another book → 404; cursor replayed under another group → 403; sibling-leak JSON scan | API tests | No Marketing ids, names or amounts in Finance responses | 2 |
| ALC-007-S10 | Performance: p95 ≤ 2 s for the 13-month trend on the reference tenant (TO VERIFY LIVE) | perf report | Measured and recorded | 2 |
| ALC-007-S11 | Record evidence | evidence | Complete | 1 |

Task acceptance:
- [ ] Finance sees 120 under proportional policy, never 200; the parent equals the unique child allocations.
- [ ] No sibling identifiers, denominators or pool totals appear for restricted viewers unless the pool is DISCLOSED.
- [ ] Showback creates no financial transfer or statement.
- [ ] Unavailable modules (budget/forecast/insights) show explicit unavailable states.

### ALC-008 — Implement chargeback statements, rounding and adjustments
Release: R1 · Estimate: 43–61 h · Risk: H · Decisions: D-05, D-25 · Closes: G-ALC-05, G-ALC-12
Dependency changes: `−ALC-007` (not needed), `+ALC-006` (UI components), `+ALC-103` (transfers), `+RPT-002` (renderer; PDF async); keep FIN-010 and API-005. RPT-003 keeps its ALC-008 edge (template styling only).

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| ALC-008-S01 | Write the PG DDL for `chargeback_statements` and `statement_approvals` (states, digest, pdf fields, idempotency) and the Snowflake DDL for `fct_chargeback_statement_line` (insert-only, no UPDATE grant) | migrations + DDL | A post-ISSUED update trigger → error; the Snowflake role lacks UPDATE/DELETE | 3 |
| ALC-008-S02 | Build the statement run: pin the close record's allocation publication; compute exact per (target, category); hierarchical signed LR book → target → line; store per-line rounding deltas | dbt model + service | Σ statements = T_book; Σ lines = statement total, for all fixtures | 4 |
| ALC-008-S03 | Build the shared rounding library and SQL macro parity: 1.00 thirds → 0.34/0.33/0.33; −1.00 → −0.34/−0.33/−0.33; mixed +1.005/−0.335/−0.335 → Σ 0.34; property test over 10k mixed-sign vectors | `packages/allocation_helpers/rounding.py` | All pass; Python = SQL | 4 |
| ALC-008-S04 | Implement the issue preconditions (close/exception, RECONCILED/exception, BILLED_SOURCE/exception, single book and currency, four-eyes) | `apps/api/chargeback/guards.py` | Each missing precondition → 409 `STATEMENT_PRECONDITION_FAILED` with a code list | 3 |
| ALC-008-S05 | Issue: Idempotency-Key + If-Match → freeze digest → ISSUED → async PDF render (RPT-002) to S3 with Object Lock and retention class `financial_statement` (7 years default) → `pdf_status=READY` + sha256 | API + worker | A duplicate issue returns the same statement id; the PDF checksum matches the stored value | 4 |
| ALC-008-S06 | Corrections: NEXT_PERIOD_ADJUSTMENT (default) and RESTATEMENT after FIN-010 restate; exact-delta LR; unchanged targets get 0 | service + dbt | Storage 12→11 correction: only affected targets get −1.00 total delta; others 0.00 | 4 |
| ALC-008-S07 | Add TRANSFER lines (net zero across the book) | dbt | Transfer 50 Finance→Marketing: −50/+50; book total unchanged | 2 |
| ALC-008-S08 | Build the CSV export with a conservation block (book total = Σ statements; statement total = Σ lines) and explain links | API | CSV totals equal the frozen digest | 2 |
| ALC-008-S09 | Build the list/preview UI (period/book selection, preconditions checklist, approve/issue) | `apps/web/chargeback` | Playwright UX matrix passes | 4 |
| ALC-008-S10 | Build the detail/compare UI (version diff, restatement lineage, PDF download) | `apps/web/chargeback/statement` | Compare shows a predecessor with deltas | 3 |
| ALC-008-S11 | Add tests: duplicate issue, immutability, mixed currencies → separate statements, missing approval, stale ledger (close record ≠ current publication → re-prepare), the "internal cost statement, not a tax invoice" label | `tests/spec/ALC-008/` | All expected outcomes hold | 4 |
| ALC-008-S12 | Add security: team viewers read only their own group's ISSUED statements; drafts hidden; foreign id → 404; PDF streamed through the API after reauthorization (no raw S3 URL) | API tests | Revoked user mid-download → 403 | 3 |
| ALC-008-S13 | Add observability (issued/restated counts, rounding-delta invariant alarm |Σ deltas| ≤ n·0.5 unit) and a runbook for restatement and PDF render failure | alarm + runbook | Alarm tested | 2 |
| ALC-008-S14 | Record evidence | evidence | Complete | 1 |

Task acceptance:
- [ ] Rounded lines sum exactly to the statement total and statements sum to the book total, including mixed-sign lines.
- [ ] ISSUED statements are immutable in PG and Snowflake; a duplicate request returns the same statement.
- [ ] Corrections produce linked adjustments or restatements; unchanged targets receive zero deltas.
- [ ] The PDF is retained under the financial_statement class and verified by checksum; issue does not depend on the PDF.

## 5. New tasks required

### ALC-101 — Group-scope authorization and restricted allocation serving
Release: R1 · Estimate: 31–44 h · Risk: H · Decisions: D-02 · Closes: G-ALC-03, G-ALC-04, G-ALC-08 (epoch)
Why: no task turns usage-group grants into Snowflake entitlements or builds a non-leaking projection. Plugs in after SEC-005, SEC-006 and ALC-004; required by ALC-007, ALC-102 and GOV-001 (team budgets).
Dependency changes: `+SEC-005, +SEC-006, +ALC-004, +ALC-005`.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| ALC-101-S01 | Specify the grant clause `(group_set_id, group_id, include_descendants)`, the profile normalization and the expanded entitlement DDL | spec + DDL `SECURITY.group_entitlement_expanded` | Reviewed with SEC | 2 |
| ALC-101-S02 | Build the security-owned expansion job triggered by grant change or hierarchy publication; epoch bump + outbox | job under the security identity | A grant on the parent expands to descendants with validity intervals | 4 |
| ALC-101-S03 | Build `srv_allocation_restricted` (restricted column list) with a RAP: D-02 tenant user + EXISTS entitlement(CURRENT_ROLE, book, group, date) | dbt + policy DDL | Direct SQL without filters returns own rows only | 4 |
| ALC-101-S04 | Restrict `fct_allocation_line` to book-wide profiles and service roles | RAP + grants | A restricted role reading it → 0 rows / denied | 2 |
| ALC-101-S05 | Implement pool disclosure CONCEALED/DISCLOSED with Org Admin acknowledgement and a k ≤ 2 warning; `srv_pool_disclosure` | API + dbt | A DISCLOSED pool shows its total to consumers; CONCEALED does not | 3 |
| ALC-101-S06 | Add planner rules: restricted profiles only get allocated_spend on granted books; share-of-total/coverage/spend → 403 | API-002 extension | Contract tests pass | 3 |
| ALC-101-S07 | Add SQL attack tests: no-filter select, SUM equals own total, read internal fact, weight column absent, pre-move rows invisible to the new parent grant, stale-epoch pool reuse | `tests/security/ALC-101/` | All denied or limited as expected | 4 |
| ALC-101-S08 | Build the JSON leakage scanner over showback/allocations/explain responses for the Finance-only profile against Marketing fixtures | test tool | 0 hits | 3 |
| ALC-101-S09 | Test revocation: grant removed → entitlements deleted, epoch bump, cached responses unreachable ≤ 30 s | test | Measured ≤ 30 s | 2 |
| ALC-101-S10 | Measure the RAP overhead on a 10M-row restricted view (TO VERIFY LIVE) | perf report | p95 overhead recorded | 3 |
| ALC-101-S11 | Record evidence | evidence | Complete | 1 |

Task acceptance:
- [ ] A restricted reader can reconstruct no sibling amount, even with two consumers.
- [ ] Moves are respected per usage_date; revocation takes effect within 30 s.
- [ ] Filter-free SQL under the restricted role returns only authorized rows.

### ALC-102 — Allocation metrics and group dimensions in the semantic registry
Release: R1 · Estimate: 13–18 h · Risk: L · Decisions: — · Closes: G-ALC-14 (registry), GOV G-GOV-04 prerequisite
Why: `semantic-api.md` has no allocated-spend metric, yet team budgets, showback and explorer-by-team need one (and "do not create a separate budget formula"). Plugs in after API-001 and ALC-005.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| ALC-102-S01 | Register `allocated_spend v1` (source srv_allocation_restricted/fct_allocation_line; book_id required; dimensions group, group_ancestor, service_category, component, method, usage_date; additive within one book only) | `packages/semantic_metrics/allocation.py` | Registry contract test passes; the metric is served for a Finance profile | 2 |
| ALC-102-S02 | Register `unallocated_spend v1` (UNASSIGNED leaf; requires an explicit unallocated grant or book-wide scope) | registry | A Finance-only profile → 403; book-wide → value | 1 |
| ALC-102-S03 | Register `allocation_coverage v1` on the coverage-bucket basis (G-ALC-14), book-wide scope only, null on zero denominator | registry | F-270 default fixture → 0.043478…; zero bucket → null | 2 |
| ALC-102-S04 | Add the allocation version policy: FLOATING_LATEST by default; `allocation_publication_id` pin for reports and statements; response meta names the allocation publication | registry + planner | Pinned request returns the pinned revision; meta present | 2 |
| ALC-102-S05 | Add negative contract tests: two books → 422 `NON_ADDITIVE_BOOKS`; group dimension on `spend` → 422 `DIMENSION_UNSUPPORTED`; restricted profile requesting coverage → 403 | tests | All pass | 2 |
| ALC-102-S06 | Offer the group dimension in the Explorer only with allocated_spend; book selector required | UX-004 hook | The selector hides group for spend; saved views store book_id | 2 |
| ALC-102-S07 | Add Explain nodes for allocated_spend (book-wide: operands; restricted: method + policy version only) | API-005 node types | Restricted explain omits denominators | 1 |
| ALC-102-S08 | Record evidence | evidence | Complete | 1 |

Task acceptance:
- [ ] Budgets, showback and the Explorer read one allocated_spend definition; cross-book sums are impossible.

### ALC-103 — Shared pools, residual, manual transfers and D-15 default book
Release: R1 · Estimate: 24–34 h · Risk: M · Decisions: D-15 · Closes: G-ALC-10 (pools/transfers/seed), G-ALC-14 (fixture)
Why: split out of ALC-005 (nine methods in one task are unreviewable) and needed by ONB-004 ("verify allocated plus unallocated equals eligible ledger total"). Plugs in after ALC-005; ONB-004 gains `+ALC-103`.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| ALC-103-S01 | Author the shared-pool contract (member selector, driver = gross-positive stage-1 allocation of targets), R1 single level | contract + validator | Pool→pool reference → 422 `POOL_REFERENCE_NOT_SUPPORTED`; self-reference → 422 | 2 |
| ALC-103-S02 | Implement pool allocation as dbt stage 2; Σ driver = 0 → UNALLOCATED | dbt model | ALC-GOLD-04: zero-usage pool → UNALLOCATED 200 | 3 |
| ALC-103-S03 | Implement the residual rule (≤ 1 per book, last; method RESIDUAL) | dbt model | Residual appears separately in quality | 2 |
| ALC-103-S04 | Implement manual transfers: PG table, approval ≠ requester, config export, dbt ±x lines with `charge_id NULL`; book-period test Σ transfers = 0 | migrations + dbt | Transfer lines net to 0; charge conservation unaffected | 4 |
| ALC-103-S05 | Add transfer guards: closed period → next open period; hidden groups not selectable; reversal = opposite transfer | API | Tests pass | 2 |
| ALC-103-S06 | Build the idempotent D-15 seed at onboarding: "Teams (default)" book bound to `team`, UNASSIGNED + PLATFORM groups, policy v1 per family | `data/fixtures/allocation/default_book_v1.yaml` + seeder | Running the seeder twice yields one book | 3 |
| ALC-103-S07 | Run the onboarding simulation fixture on F-270 with no team rules | test | PLATFORM 6; UNALLOCATED 264; total 270; coverage 4.3478% | 3 |
| ALC-103-S08 | Run the same fixture with Finance/Marketing query rules | test | Finance 120, Marketing 80, PLATFORM 6, UNALLOCATED 64; total 270 | 2 |
| ALC-103-S09 | Record observability and evidence | evidence | Complete | 3 |

Task acceptance:
- [ ] The default book exists for every new tenant and allocates F-270 exactly as the fixture states.
- [ ] Transfers net to zero per book×period×currency and never alter a charge.
- [ ] Pools cannot reference pools in R1.

### ALC-104 — Allocation scale and cost benchmark
Release: R1 · Estimate: 16–23 h · Risk: M · Decisions: D-05, D-06, D-08 · Closes: G-ALC-15, G-ALC-16 (live)
Why: 1M queries/day/account × rules × books is the dominant central-compute risk; targets must be measured before OPS-009 margins. Plugs in after ALC-005 and ALC-003; feeds OPS-009.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| ALC-104-S01 | Build the synthetic generator: 10 accounts × 1M queries/day × 31 days; 50k keys/day; 500 rules (40% eq/in, 30% prefix, 20% contains, 10% negated); 3 books × 200 groups | `tools/bench/alc_generator.py` | Deterministic seed; row counts verified | 3 |
| ALC-104-S02 | Load the generator output through the normal RAW→staging path (not direct inserts) so bridges and classification keys are production-shaped | staging dataset | dbt tests green on the bench tenant | 2 |
| ALC-104-S03 | Measure the daily incremental allocation (1 day × 3 books) and record credits (QUERY_TAG), elapsed time, bytes scanned and rows out | bench report §incremental | Target ≤ 10 min on MEDIUM (TO VERIFY LIVE) | 2 |
| ALC-104-S04 | Measure 31-day simulations (10 runs, p50/p95) | bench report §simulation | Target p95 ≤ 5 min (TO VERIFY LIVE) | 2 |
| ALC-104-S05 | Measure a retroactive republish of 2 open periods (dirty-partition recompute) | bench report §retro | Credits and elapsed recorded; within the admission budget | 2 |
| ALC-104-S06 | Tune clustering, join strategy and key-deduplication ratio from query profiles, then rerun S03–S05 | PR + report | Before/after recorded; any regression explained | 3 |
| ALC-104-S07 | Publish the cost-model entry (credits per 1M queries/day per book; per simulation) and propose per-plan simulation quotas | OPS-009 input | Reviewed by OPS | 1 |
| ALC-104-S08 | Record evidence | evidence | Complete | 1 |

Task acceptance:
- [ ] Measured credits and latency are published at reference scale; any target miss comes with a mitigation.

## 6. Estimate summary

| Task | Release | Low h | High h |
|---|---|---:|---:|
| ALC-001 | R1 | 36 | 52 |
| ALC-002 | R1 | 44 | 62 |
| ALC-003 | R1 | 54 | 77 |
| ALC-004 | R1 | 37 | 53 |
| ALC-005 | R1 | 49 | 70 |
| ALC-006 | R1 | 37 | 53 |
| ALC-007 | R1 | 30 | 43 |
| ALC-008 | R1 | 43 | 61 |
| ALC-101 | R1 | 31 | 44 |
| ALC-102 | R1 | 13 | 18 |
| ALC-103 | R1 | 24 | 34 |
| ALC-104 | R1 | 16 | 23 |
| D-16 regex operators (ALC-002 R2 follow-up: RE2-safe engine check, cost test) | R2 | 8 | 14 |
| **Total R1** | | **414** | **590** |
| **Total R2** | | **8** | **14** |

## 7. Owner questions (only those not already covered by D-01…D-25)

1. **Four-eyes default.** Should FINANCIAL approval of rulesets and policies and chargeback issue *require* a distinct approver? Recommended: yes by default, tenant-relaxable for FINANCIAL only. ACCESS approval by an Org Admin/Owner is always mandatory. Single-admin customers would then need a second admin.
2. **Chargeback correction default.** Should corrections of issued statements default to next-period adjustment (recommended) or to restatement of the closed statement?
3. **Statement retention.** How many years for `financial_statement` artifacts (recommended 7, configurable per tenant)? Are customer branding or disclaimers required on the statement PDF?
4. **Shared-cost transparency.** Should team viewers see pool totals by default (DISCLOSED) or only their share (CONCEALED, recommended)? Is showing shared resource names such as `WH_SHARED` to consuming teams acceptable?
5. **Cloud-services driver.** Will the customer approve extracting `QUERY_HISTORY.CREDITS_USED_CLOUD_SERVICES`, `DATABASE_*` and `SCHEMA_*` (needed for the D-15 cloud-services driver and database/schema rules)? If not, the labelled query-cost fallback is used.
