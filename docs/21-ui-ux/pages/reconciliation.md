# Reconciliation — detailed screen design

Design unit: `reconciliation`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../08-finops-ledger/ledger.md).

This file covers 2 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## reconciliation — Reconciliation

Route: `/reconciliation` (prototype `#/reconciliation`). Persona: **FinOps lead / finance controller**.

Goal: Know when reported cost agrees with billing.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  GOVERN  /  Reconciliation                                                         |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Know when reported cost agrees with billing.                                                             |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| LEDGER COMPARISON: $27,000.00 [i]  ||  BILLING REFERENCE: $27,100.00 [i]                                 |
| Selected mismatch scenario  ||  Selected mismatch scenario                                               |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| UNEXPLAINED DELTA: -$100.00 [i]  ||  MISMATCH CONTROL: FAILED [i]                                        |
| Ledger minus billing reference  ||  Selected alternative scenario                                        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: Investigate · August difference [>]                                                            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CONTROL RESULTS                                                                                          |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Scenarios are alternatives, not additive references. Primary mismatch scenario is explicitly labelled.   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| MATURITY POLICY                                                                                          |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Mismatch does not permit an unexplained plug. Reviewed reconciliation is distinct from closing the       |
| period.                                                                                                  |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Control                   | Ledger USD                | Reference USD             | Result                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Baseline fixture          | 27,000.00                 | 27,000.00                 | MATCHED                   |
| Mismatch scenario         | 27,000.00                 | 27,100.00                 | FAILED                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Comparison fixture has delta ledger minus reference = -100 USD; keep it visible until explained.         |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `ledgercompare` | Ledger comparison: **$27,000.00** | Selected mismatch scenario | August comparison fixture; FINAL |
| `invoicecompare` | Billing reference: **$27,100.00** | Selected mismatch scenario | August comparison fixture; FINAL |
| `recondelta` | Unexplained delta: **-$100.00** | Ledger minus billing reference | August comparison fixture; FAILED |
| `reconfailed` | Mismatch control: **FAILED** | Selected alternative scenario | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Control results**: Scenarios are alternatives, not additive references. Primary mismatch scenario is explicitly labelled.
- **Maturity policy**: Mismatch does not permit an unexplained plug. Reviewed reconciliation is distinct from closing the period.
- **DataTable** columns, in order: Control, Ledger USD, Reference USD, Result. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Drilldowns**: `/reconciliation-detail`. Use named links; never assume every row represents the same execution.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Save view                                           [X]                    |
| Selected metric / resource: [label and identifier]                         |
| Scope and period: [explicit, retained from entry]                          |
| Basis / input publication / coverage: [explain]                            |
| Evidence: [authorized source / parent component]                           |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Save view]                                                      |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | FinOps lead / finance controller |
| Goal | Know when reported cost agrees with billing. |
| Entry point | Govern navigation; deep link supported. |
| Happy path | Read context → inspect Control results → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No reconciliation for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: reconciliation-detail. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Comparison fixture has delta ledger minus reference = -100 USD; keep it visible until explained. |

### Domain subtleties

Comparison fixture has delta ledger minus reference = -100 USD; keep it visible until explained.

Mismatch does not permit an unexplained plug. Reviewed reconciliation is distinct from closing the period.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Reconciliation                           |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Control results                          |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/reconciliation` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `ledgercompare` explanation and status.
- [ ] Inspect exact columns: Control, Ledger USD, Reference USD, Result. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## reconciliation-detail — Investigate · August difference

Route: `/reconciliation-detail` (prototype `#/reconciliation-detail`). Persona: **FinOps lead / finance controller**.

Goal: Mismatch scenario · ledger vs billing reference

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  GOVERN  /  Investigate · August difference                                        |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Mismatch scenario · ledger vs billing reference                                                          |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| LEDGER COMPARISON: $27,000.00 [i]  ||  BILLING REFERENCE: $27,100.00 [i]                                 |
| Selected mismatch scenario  ||  Selected mismatch scenario                                               |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| UNEXPLAINED DELTA: -$100.00 [i]  ||  MISMATCH CONTROL: FAILED [i]                                        |
| Ledger minus billing reference  ||  Selected alternative scenario                                        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| EVIDENCE CHECKLIST                                                                                       |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Align currency, organization scope, usage period, price basis, source completeness and contractual       |
| adjustments.                                                                                             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| RESOLUTION CONTROLS                                                                                      |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Record evidence and resolution type; never allow a cosmetic balancing row.                               |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Candidate                 | Ledger USD                | Reference USD             | Difference USD            |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Net total                 | 27,000.00                 | 27,100.00                 | -100.00                   |
| Explanation               | —                         | —                         | Unresolved                |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Snapshot is a demo mismatch scenario independent of the matched baseline used by other pages.            |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `ledgercompare` | Ledger comparison: **$27,000.00** | Selected mismatch scenario | August comparison fixture; FINAL |
| `invoicecompare` | Billing reference: **$27,100.00** | Selected mismatch scenario | August comparison fixture; FINAL |
| `recondelta` | Unexplained delta: **-$100.00** | Ledger minus billing reference | August comparison fixture; FAILED |
| `reconfailed` | Mismatch control: **FAILED** | Selected alternative scenario | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Evidence checklist**: Align currency, organization scope, usage period, price basis, source completeness and contractual adjustments.
- **Resolution controls**: Record evidence and resolution type; never allow a cosmetic balancing row.
- **DataTable** columns, in order: Candidate, Ledger USD, Reference USD, Difference USD. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Record investigation. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `reconciliation`; breadcrumb and browser Back preserve scope.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Record investigation                                           [X]         |
| Selected metric / resource: [label and identifier]                         |
| Scope and period: [explicit, retained from entry]                          |
| Basis / input publication / coverage: [explain]                            |
| Evidence: [authorized source / parent component]                           |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Record investigation]                                           |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | FinOps lead / finance controller |
| Goal | Mismatch scenario · ledger vs billing reference |
| Entry point | Parent route /reconciliation; deep link supported. |
| Happy path | Read context → inspect Evidence checklist → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No investigate · august difference for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Record investigation reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Record investigation; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Snapshot is a demo mismatch scenario independent of the matched baseline used by other pages. |

### Domain subtleties

Snapshot is a demo mismatch scenario independent of the matched baseline used by other pages.

Record evidence and resolution type; never allow a cosmetic balancing row.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Investigate · August difference          |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Evidence checklist                       |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Record investigation]                   |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/reconciliation-detail` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `ledgercompare` explanation and status.
- [ ] Inspect exact columns: Candidate, Ledger USD, Reference USD, Difference USD. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.
