# Savings, verified — detailed screen design

Design unit: `savings`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../13-insights/intelligence.md).

This file covers 2 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## savings — Savings, verified

Route: `/savings` (prototype `#/savings`). Persona: **Platform owner / FinOps analyst**.

Goal: Separate opportunity from observed, normalized impact.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  OPTIMIZE  /  Savings, verified                                                    |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Separate opportunity from observed, normalized impact.                                                   |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| VERIFIED REALIZED: $6,000.00 [i]  ||  POTENTIAL SAVINGS: $8,000.00 [i]                                   |
| 24,000 normalized minus 18,000 observed  ||  Estimate · never add to realized                            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| BASELINE COST: $20,000.00 [i]  ||  OBSERVED POST COST: $18,000.00 [i]                                    |
| 100 observed baseline units  ||  120 observed post units                                                 |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: Warehouse efficiency verification [>]                                                          |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| FINANCIAL BRIDGE                                                                                         |
|      Baseline 20,000 --> Normalized 24,000 --> Actual 18,000                                             |
| Baseline 20,000 / 100 units = 200 per unit; 120 post units imply 24,000 expected; actual 18,000.         |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| OVERLAP AND UNCERTAINTY                                                                                  |
|      Baseline 20,000 --> Normalized 24,000 --> Actual 18,000                                             |
| A study participates once in a non-overlapping savings total. Negative impact remains negative.          |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Study                     | Expected USD              | Actual USD                | Realized USD              |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Warehouse efficiency      | 24,000.00                 | 18,000.00                 | 6,000.00                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Savings study period is pinned and independent of current explorer selection.                            |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `verifiedsavings` | Verified realized: **$6,000.00** | 24,000 normalized minus 18,000 observed | Independent study / synthetic; VERIFIED |
| `potential` | Potential savings: **$8,000.00** | Estimate · never add to realized | Independent study / synthetic; ESTIMATE |
| `baseline` | Baseline cost: **$20,000.00** | 100 observed baseline units | Independent study / synthetic; FINAL |
| `postcost` | Observed post cost: **$18,000.00** | 120 observed post units | Independent study / synthetic; FINAL |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Financial bridge**: Baseline 20,000 / 100 units = 200 per unit; 120 post units imply 24,000 expected; actual 18,000.
- **Overlap and uncertainty**: A study participates once in a non-overlapping savings total. Negative impact remains negative.
- **DataTable** columns, in order: Study, Expected USD, Actual USD, Realized USD. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Drilldowns**: `/savings-detail`. Use named links; never assume every row represents the same execution.

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
| Persona | Platform owner / FinOps analyst |
| Goal | Separate opportunity from observed, normalized impact. |
| Entry point | Optimize navigation; deep link supported. |
| Happy path | Read context → inspect Financial bridge → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No savings, verified for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: savings-detail. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Savings study period is pinned and independent of current explorer selection. |

### Domain subtleties

Savings study period is pinned and independent of current explorer selection.

A study participates once in a non-overlapping savings total. Negative impact remains negative.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Savings, verified                        |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Financial bridge                         |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/savings` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `verifiedsavings` explanation and status.
- [ ] Inspect exact columns: Study, Expected USD, Actual USD, Realized USD. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## savings-detail — Warehouse efficiency verification

Route: `/savings-detail` (prototype `#/savings-detail`). Persona: **Platform owner / FinOps analyst**.

Goal: Matched usage basis · complete study windows

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  OPTIMIZE  /  Warehouse efficiency verification                                    |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Matched usage basis · complete study windows                                                             |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| BASELINE COST: $20,000.00 [i]  ||  NORMALIZED EXPECTATION: $24,000.00 [i]                                |
| 100 observed baseline units  ||  20,000 / 100 × 120                                                      |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| OBSERVED POST COST: $18,000.00 [i]  ||  VERIFIED REALIZED: $6,000.00 [i]                                 |
| 120 observed post units  ||  24,000 normalized minus 18,000 observed                                     |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| METHOD                                                                                                   |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Expected = baseline unit cost × post volume. Realized = expected − observed. No fabricated causal        |
| certainty.                                                                                               |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ADVERSE OUTCOME                                                                                          |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Alternative fixture with 26,000 post cost yields -2,000 impact, never clamped to zero.                   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Input                     | Value                     | Unit                      | Evidence                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Baseline cost             | 20,000.00                 | USD                       | Complete period           |
| Baseline volume           | 100                       | Units                     | Observed                  |
| Post volume               | 120                       | Units                     | Observed                  |
| Post cost                 | 18,000.00                 | USD                       | Observed                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Alternative adverse fixture is for validation, not an additional study total.                            |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `baseline` | Baseline cost: **$20,000.00** | 100 observed baseline units | Independent study / synthetic; FINAL |
| `normalized` | Normalized expectation: **$24,000.00** | 20,000 / 100 × 120 | Independent study / synthetic; ESTIMATE |
| `postcost` | Observed post cost: **$18,000.00** | 120 observed post units | Independent study / synthetic; FINAL |
| `verifiedsavings` | Verified realized: **$6,000.00** | 24,000 normalized minus 18,000 observed | Independent study / synthetic; VERIFIED |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Method**: Expected = baseline unit cost × post volume. Realized = expected − observed. No fabricated causal certainty.
- **Adverse outcome**: Alternative fixture with 26,000 post cost yields -2,000 impact, never clamped to zero.
- **DataTable** columns, in order: Input, Value, Unit, Evidence. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `savings`; breadcrumb and browser Back preserve scope.

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
| Persona | Platform owner / FinOps analyst |
| Goal | Matched usage basis · complete study windows |
| Entry point | Parent route /savings; deep link supported. |
| Happy path | Read context → inspect Method → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No warehouse efficiency verification for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Alternative adverse fixture is for validation, not an additional study total. |

### Domain subtleties

Alternative adverse fixture is for validation, not an additional study total.

Alternative fixture with 26,000 post cost yields -2,000 impact, never clamped to zero.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Warehouse efficiency verification        |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Method                                   |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/savings-detail` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `baseline` explanation and status.
- [ ] Inspect exact columns: Input, Value, Unit, Evidence. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.
