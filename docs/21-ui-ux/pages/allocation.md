# Allocation Studio — detailed screen design

Design unit: `allocation`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../11-allocation/allocation.md).

This file covers 3 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## allocation — Allocation Studio

Route: `/allocation` (prototype `#/allocation`). Persona: **Finance controller / team owner**.

Goal: A conserved, explainable path from cost to ownership.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  ALLOCATE  /  Allocation Studio                                                    |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| A conserved, explainable path from cost to ownership.                                                    |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| WAREHOUSE COMPUTE: $20,000.00 [i]  ||  FINANCE ALLOCATION: $12,000.00 [i]                                |
| Billed compute · excludes cloud services  ||  8,400 query + 3,600 idle                                   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| MARKETING ALLOCATION: $8,000.00 [i]  ||  UNALLOCATED: $0.00 [i]                                          |
| 5,600 query + 2,400 idle  ||  Warehouse Teams book only                                                  |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: Rule · Shared idle [>] | Allocation simulation [>]                                             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ALLOCATION BRIDGE                                                                                        |
|      Source 20,000 --> Finance 12,000 + Marketing 8,000                                                  |
| Source warehouse 20,000 → query 14,000 + idle 6,000 → Finance 12,000 / Marketing 8,000.                  |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| QUALITY                                                                                                  |
|      Source 20,000 --> Finance 12,000 + Marketing 8,000                                                  |
| Book Teams v1 only. Other service costs are outside this book fixture, not silently allocated.           |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Target                    | Query USD                 | Idle USD                  | Total USD                 |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Finance                   | 8,400.00                  | 3,600.00                  | 12,000.00                 |
| Marketing                 | 5,600.00                  | 2,400.00                  | 8,000.00                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Alternative Products and Teams books are not additive.                                                   |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `warehouse` | Warehouse compute: **$20,000.00** | Billed compute · excludes cloud services | August 2026 / synthetic; RECONCILED |
| `financealloc` | Finance allocation: **$12,000.00** | 8,400 query + 3,600 idle | August 2026 / synthetic; RECONCILED |
| `marketingalloc` | Marketing allocation: **$8,000.00** | 5,600 query + 2,400 idle | August 2026 / synthetic; RECONCILED |
| `unallocated` | Unallocated: **$0.00** | Warehouse Teams book only | August 2026 / synthetic; RECONCILED |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Allocation bridge**: Source warehouse 20,000 → query 14,000 + idle 6,000 → Finance 12,000 / Marketing 8,000.
- **Quality**: Book Teams v1 only. Other service costs are outside this book fixture, not silently allocated.
- **DataTable** columns, in order: Target, Query USD, Idle USD, Total USD. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Drilldowns**: `/allocation-rule`, `/allocation-preview`. Use named links; never assume every row represents the same execution.

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
| Persona | Finance controller / team owner |
| Goal | A conserved, explainable path from cost to ownership. |
| Entry point | Allocate navigation; deep link supported. |
| Happy path | Read context → inspect Allocation bridge → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No allocation studio for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: allocation-rule, allocation-preview. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Alternative Products and Teams books are not additive. |

### Domain subtleties

Alternative Products and Teams books are not additive.

Book Teams v1 only. Other service costs are outside this book fixture, not silently allocated.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Allocation Studio                        |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Allocation bridge                        |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/allocation` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `warehouse` explanation and status.
- [ ] Inspect exact columns: Target, Query USD, Idle USD, Total USD. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## allocation-rule — Rule · Shared idle

Route: `/allocation-rule` (prototype `#/allocation-rule`). Persona: **Finance controller / team owner**.

Goal: Versioned idle policy · warehouse compute only

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  ALLOCATE  /  Rule · Shared idle                                                   |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Versioned idle policy · warehouse compute only                                                           |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CLASSIC IDLE: $6,000.00 [i]  ||  ELIGIBLE QUERY COST: $14,000.00 [i]                                     |
| 20,000 minus 14,000  ||  Proportional denominator                                                        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| FINANCE WEIGHT: 60% [i]  ||  MARKETING WEIGHT: 40% [i]                                                   |
| 8,400 / 14,000  ||  5,600 / 14,000                                                                       |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| METHOD SELECTION                                                                                         |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Proportional to eligible query compute, or route idle to Platform. Zero denominator leaves UNALLOCATED   |
| unless approved fallback.                                                                                |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SCOPE AND ROUNDING                                                                                       |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Each charge once per book. Stable largest-remainder rounding preserves signed totals.                    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Consumer                  | Eligible query USD        | Weight                    | Idle USD                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Finance                   | 8,400.00                  | 60%                       | 3,600.00                  |
| Marketing                 | 5,600.00                  | 40%                       | 2,400.00                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Changing policy never mutates previously issued statements.                                              |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `idle` | Classic idle: **$6,000.00** | 20,000 minus 14,000 | August 2026 / synthetic; RECONCILED |
| `eligible` | Eligible query cost: **$14,000.00** | Proportional denominator | August 2026 / synthetic; RECONCILED |
| `financeweight` | Finance weight: **60%** | 8,400 / 14,000 | August 2026 / synthetic; Observed |
| `marketingweight` | Marketing weight: **40%** | 5,600 / 14,000 | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Method selection**: Proportional to eligible query compute, or route idle to Platform. Zero denominator leaves UNALLOCATED unless approved fallback.
- **Scope and rounding**: Each charge once per book. Stable largest-remainder rounding preserves signed totals.
- **DataTable** columns, in order: Consumer, Eligible query USD, Weight, Idle USD. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save allocation draft. Opens labelled form fields; required values validate before local save. In production, server validates authorization, schema and stale version.
- **Parent**: `allocation`; breadcrumb and browser Back preserve scope.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Save allocation draft                                           [X]        |
| Rule name: [____________________________]                                  |
| Idle policy: [____________________________]                                |
| Effective from: [____________________________]                             |
| Review reason: [____________________________]                              |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Save allocation draft]                                          |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | Finance controller / team owner |
| Goal | Versioned idle policy · warehouse compute only |
| Entry point | Parent route /allocation; deep link supported. |
| Happy path | Read context → inspect Method selection → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No rule · shared idle for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save allocation draft reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save allocation draft; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Changing policy never mutates previously issued statements. |

### Domain subtleties

Changing policy never mutates previously issued statements.

Each charge once per book. Stable largest-remainder rounding preserves signed totals.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Rule · Shared idle                       |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Method selection                         |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save allocation draft]                  |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/allocation-rule` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `idle` explanation and status.
- [ ] Inspect exact columns: Consumer, Eligible query USD, Weight, Idle USD. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## allocation-preview — Allocation simulation

Route: `/allocation-preview` (prototype `#/allocation-preview`). Persona: **Finance controller / team owner**.

Goal: Compare two policies before publishing

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  ALLOCATE  /  Allocation simulation                                                |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Compare two policies before publishing                                                                   |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| WAREHOUSE COMPUTE: $20,000.00 [i]  ||  FINANCE ALLOCATION: $12,000.00 [i]                                |
| Billed compute · excludes cloud services  ||  8,400 query + 3,600 idle                                   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| MARKETING ALLOCATION: $8,000.00 [i]  ||  CONSERVATION: PASS [i]                                          |
| 5,600 query + 2,400 idle  ||  Each policy version equals 20,000 USD                                      |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CONSERVATION GATE                                                                                        |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Both policy versions total 20,000 USD. Difference is redistribution, not new savings.                    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| VERSION GATE                                                                                             |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Publication and rule hash pinned. A data revision invalidates approval and requires a rerun.             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Target                    | Proportional USD          | Platform idle USD         | Movement USD              |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Finance                   | 12,000.00                 | 8,400.00                  | -3,600.00                 |
| Marketing                 | 8,000.00                  | 5,600.00                  | -2,400.00                 |
| Platform                  | 0.00                      | 6,000.00                  | +6,000.00                 |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Preview is a separate version; never sum before and after columns.                                       |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `warehouse` | Warehouse compute: **$20,000.00** | Billed compute · excludes cloud services | August 2026 / synthetic; RECONCILED |
| `financealloc` | Finance allocation: **$12,000.00** | 8,400 query + 3,600 idle | August 2026 / synthetic; RECONCILED |
| `marketingalloc` | Marketing allocation: **$8,000.00** | 5,600 query + 2,400 idle | August 2026 / synthetic; RECONCILED |
| `conservation` | Conservation: **PASS** | Each policy version equals 20,000 USD | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Conservation gate**: Both policy versions total 20,000 USD. Difference is redistribution, not new savings.
- **Version gate**: Publication and rule hash pinned. A data revision invalidates approval and requires a rerun.
- **DataTable** columns, in order: Target, Proportional USD, Platform idle USD, Movement USD. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Approve demo preview. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `allocation`; breadcrumb and browser Back preserve scope.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Approve demo preview                                           [X]         |
| Selected metric / resource: [label and identifier]                         |
| Scope and period: [explicit, retained from entry]                          |
| Basis / input publication / coverage: [explain]                            |
| Evidence: [authorized source / parent component]                           |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Approve demo preview]                                           |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | Finance controller / team owner |
| Goal | Compare two policies before publishing |
| Entry point | Parent route /allocation; deep link supported. |
| Happy path | Read context → inspect Conservation gate → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No allocation simulation for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Approve demo preview reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Approve demo preview; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Preview is a separate version; never sum before and after columns. |

### Domain subtleties

Preview is a separate version; never sum before and after columns.

Publication and rule hash pinned. A data revision invalidates approval and requires a rerun.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Allocation simulation                    |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Conservation gate                        |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Approve demo preview]                   |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/allocation-preview` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `warehouse` explanation and status.
- [ ] Inspect exact columns: Target, Proportional USD, Platform idle USD, Movement USD. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.
