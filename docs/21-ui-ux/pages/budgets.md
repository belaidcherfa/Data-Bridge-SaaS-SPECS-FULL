# Budgets — detailed screen design

Design unit: `budgets`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../12-budgets-monitoring/governance.md).

This file covers 4 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## budgets — Budgets

Route: `/budgets` (prototype `#/budgets`). Persona: **FinOps lead / finance controller**.

Goal: Set a boundary. See risk before the month ends.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  GOVERN  /  Budgets                                                                |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Set a boundary. See risk before the month ends.                                                          |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| BUDGET: $28,000.00 [i]  ||  ACTUAL TO DATE: $15,000.00 [i]                                               |
| Approved September limit  ||  15 complete days × 1,000                                                   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| BUDGET REMAINING: $13,000.00 [i]  ||  MONTH-END FORECAST: $30,000.00 [i]                                 |
| 28,000 minus 15,000  ||  15,000 actual + 15,000 estimate                                                 |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: September organization plan [>] | Create a budget [>] | Forecast methodology [>]               |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| BURN AND FORECAST                                                                                        |
|      Actual ========15,000.........30,000 forecast | budget 28,000                                       |
| Budget 28,000; actual through 15 complete days 15,000; burn 1,000/day; forecast 30,000.                  |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| PORTFOLIO DISCIPLINE                                                                                     |
|      Actual ========15,000.........30,000 forecast | budget 28,000                                       |
| Overlapping budgets are separate controls; never sum overlapping actuals as spend.                       |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Budget                    | Period                    | Actual USD                | Forecast USD              |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Organization plan         | Sep 01–30                 | 15,000.00                 | 30,000.00                 |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| September planning fixture is separate from August closed ledger. Forecast remains an estimate.          |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `budget` | Budget: **$28,000.00** | Approved September limit | Sep 01–30 / synthetic; PLAN |
| `budgetactual` | Actual to date: **$15,000.00** | 15 complete days × 1,000 | Sep 01–15 / synthetic; PROVISIONAL |
| `remaining` | Budget remaining: **$13,000.00** | 28,000 minus 15,000 | September planning fixture; Derived |
| `forecast` | Month-end forecast: **$30,000.00** | 15,000 actual + 15,000 estimate | September planning fixture; ESTIMATE |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Burn and forecast**: Budget 28,000; actual through 15 complete days 15,000; burn 1,000/day; forecast 30,000.
- **Portfolio discipline**: Overlapping budgets are separate controls; never sum overlapping actuals as spend.
- **DataTable** columns, in order: Budget, Period, Actual USD, Forecast USD. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Drilldowns**: `/budget-detail`, `/budget-new`, `/forecast`. Use named links; never assume every row represents the same execution.

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
| Goal | Set a boundary. See risk before the month ends. |
| Entry point | Govern navigation; deep link supported. |
| Happy path | Read context → inspect Burn and forecast → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No budgets for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: budget-detail, budget-new, forecast. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; September planning fixture is separate from August closed ledger. Forecast remains an estimate. |

### Domain subtleties

September planning fixture is separate from August closed ledger. Forecast remains an estimate.

Overlapping budgets are separate controls; never sum overlapping actuals as spend.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Budgets                                  |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Burn and forecast                        |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/budgets` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `budget` explanation and status.
- [ ] Inspect exact columns: Budget, Period, Actual USD, Forecast USD. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## budget-detail — September organization plan

Route: `/budget-detail` (prototype `#/budget-detail`). Persona: **FinOps lead / finance controller**.

Goal: USD · Sep 01–30 · actuals through Sep 15

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  GOVERN  /  September organization plan                                            |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| USD · Sep 01–30 · actuals through Sep 15                                                                 |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ACTUAL TO DATE: $15,000.00 [i]  ||  BUDGET REMAINING: $13,000.00 [i]                                     |
| 15 complete days × 1,000  ||  28,000 minus 15,000                                                        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| MONTH-END FORECAST: $30,000.00 [i]  ||  FORECAST OVER BUDGET: $2,000.00 [i]                              |
| 15,000 actual + 15,000 estimate  ||  30,000 minus 28,000; +7.14%                                         |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| FORECAST BRIDGE                                                                                          |
|      Actual ========15,000.........30,000 forecast | budget 28,000                                       |
| Actual 15,000 + modeled remaining 15,000 = 30,000; forecast variance +2,000 USD / 7.142857%.             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| POLICY                                                                                                   |
|      Actual ========15,000.........30,000 forecast | budget 28,000                                       |
| Insufficient or partial observations suppress forecast rather than fabricating confidence intervals.     |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Threshold                 | Basis                     | Value                     | Status                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
| 80% spent                 | Actual / budget           | 53.57%                    | Not breached              |
| 100% forecast             | Forecast / budget         | 107.14%                   | At risk                   |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Budget actual uses signed net cost. Forecast interval unavailable: uncalibrated run-rate fallback.       |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `budgetactual` | Actual to date: **$15,000.00** | 15 complete days × 1,000 | Sep 01–15 / synthetic; PROVISIONAL |
| `remaining` | Budget remaining: **$13,000.00** | 28,000 minus 15,000 | September planning fixture; Derived |
| `forecast` | Month-end forecast: **$30,000.00** | 15,000 actual + 15,000 estimate | September planning fixture; ESTIMATE |
| `forecastvariance` | Forecast over budget: **$2,000.00** | 30,000 minus 28,000; +7.14% | September planning fixture; ESTIMATE |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Forecast bridge**: Actual 15,000 + modeled remaining 15,000 = 30,000; forecast variance +2,000 USD / 7.142857%.
- **Policy**: Insufficient or partial observations suppress forecast rather than fabricating confidence intervals.
- **DataTable** columns, in order: Threshold, Basis, Value, Status. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `budgets`; breadcrumb and browser Back preserve scope.

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
| Goal | USD · Sep 01–30 · actuals through Sep 15 |
| Entry point | Parent route /budgets; deep link supported. |
| Happy path | Read context → inspect Forecast bridge → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No september organization plan for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Budget actual uses signed net cost. Forecast interval unavailable: uncalibrated run-rate fallback. |

### Domain subtleties

Budget actual uses signed net cost. Forecast interval unavailable: uncalibrated run-rate fallback.

Insufficient or partial observations suppress forecast rather than fabricating confidence intervals.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| September organization plan              |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Forecast bridge                          |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/budget-detail` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `budgetactual` explanation and status.
- [ ] Inspect exact columns: Threshold, Basis, Value, Status. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## budget-new — Create a budget

Route: `/budget-new` (prototype `#/budget-new`). Persona: **FinOps lead / finance controller**.

Goal: Define scope, amount, owner and thresholds.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  GOVERN  /  Create a budget                                                        |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Define scope, amount, owner and thresholds.                                                              |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| BUDGET: $28,000.00 [i]  ||  ACTUAL TO DATE: $15,000.00 [i]                                               |
| Approved September limit  ||  15 complete days × 1,000                                                   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| BUDGET REMAINING: $13,000.00 [i]  ||  MONTH-END FORECAST: $30,000.00 [i]                                 |
| 28,000 minus 15,000  ||  15,000 actual + 15,000 estimate                                                 |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SCOPE BUILDER                                                                                            |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Organization, account, service or authorized group. Preview exactly what will be measured.               |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| NOTIFICATIONS                                                                                            |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Choose already-authorized destinations; no external message is sent by the mockup.                       |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Field                     | Selected value            | Validation                | Reason                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Currency                  | USD                       | Required                  | No implicit FX            |
| Amount                    | 28,000.00                 | Positive decimal          | Minor-unit precision      |
| Period                    | September 2026            | UTC boundaries            | Complete calendar         |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Zero budget is allowed by production contract with null percentage variance; editor must explain this    |
| edge case.                                                                                               |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `budget` | Budget: **$28,000.00** | Approved September limit | Sep 01–30 / synthetic; PLAN |
| `budgetactual` | Actual to date: **$15,000.00** | 15 complete days × 1,000 | Sep 01–15 / synthetic; PROVISIONAL |
| `remaining` | Budget remaining: **$13,000.00** | 28,000 minus 15,000 | September planning fixture; Derived |
| `forecast` | Month-end forecast: **$30,000.00** | 15,000 actual + 15,000 estimate | September planning fixture; ESTIMATE |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Scope builder**: Organization, account, service or authorized group. Preview exactly what will be measured.
- **Notifications**: Choose already-authorized destinations; no external message is sent by the mockup.
- **DataTable** columns, in order: Field, Selected value, Validation, Reason. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save budget draft. Opens labelled form fields; required values validate before local save. In production, server validates authorization, schema and stale version.
- **Parent**: `budgets`; breadcrumb and browser Back preserve scope.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Save budget draft                                           [X]            |
| Budget name: [____________________________]                                |
| Amount USD: [____________________________]                                 |
| Owner: [____________________________]                                      |
| Threshold percent: [____________________________]                          |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Save budget draft]                                              |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | FinOps lead / finance controller |
| Goal | Define scope, amount, owner and thresholds. |
| Entry point | Parent route /budgets; deep link supported. |
| Happy path | Read context → inspect Scope builder → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No create a budget for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save budget draft reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save budget draft; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Zero budget is allowed by production contract with null percentage variance; editor must explain this edge case. |

### Domain subtleties

Zero budget is allowed by production contract with null percentage variance; editor must explain this edge case.

Choose already-authorized destinations; no external message is sent by the mockup.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Create a budget                          |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Scope builder                            |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save budget draft]                      |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/budget-new` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `budget` explanation and status.
- [ ] Inspect exact columns: Field, Selected value, Validation, Reason. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## forecast — Forecast methodology

Route: `/forecast` (prototype `#/forecast`). Persona: **FinOps lead / finance controller**.

Goal: Understand the estimate before relying on it.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  GOVERN  /  Forecast methodology                                                   |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Understand the estimate before relying on it.                                                            |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| MONTH-END FORECAST: $30,000.00 [i]  ||  FORECAST OVER BUDGET: $2,000.00 [i]                              |
| 15,000 actual + 15,000 estimate  ||  30,000 minus 28,000; +7.14%                                         |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| DAILY BURN: $1,000.00 [i]  ||  COMPLETE HISTORY: 15 days [i]                                             |
| 15,000 / 15 complete days  ||  Insufficient for seasonal model                                           |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| OBSERVED / ESTIMATED BOUNDARY                                                                            |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Solid actual line ends Sep 15; dotted estimate begins Sep 16 and includes every remaining calendar day.  |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| MODEL GOVERNANCE                                                                                         |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Show training period, input publication, backtest eligibility and limitations. No invented 90%           |
| confidence band.                                                                                         |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Model                     | History                   | Calibration               | Selection                 |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Run-rate fallback         | 15 complete days          | No interval               | Eligible baseline         |
| Seasonal naive            | Requires 28+ days         | Not eligible              | Insufficient history      |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| The mockup illustrates the approved fallback, not a trained ML model.                                    |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `forecast` | Month-end forecast: **$30,000.00** | 15,000 actual + 15,000 estimate | September planning fixture; ESTIMATE |
| `forecastvariance` | Forecast over budget: **$2,000.00** | 30,000 minus 28,000; +7.14% | September planning fixture; ESTIMATE |
| `burnday` | Daily burn: **$1,000.00** | 15,000 / 15 complete days | September planning fixture; Derived |
| `history` | Complete history: **15 days** | Insufficient for seasonal model | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Observed / estimated boundary**: Solid actual line ends Sep 15; dotted estimate begins Sep 16 and includes every remaining calendar day.
- **Model governance**: Show training period, input publication, backtest eligibility and limitations. No invented 90% confidence band.
- **DataTable** columns, in order: Model, History, Calibration, Selection. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `budgets`; breadcrumb and browser Back preserve scope.

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
| Goal | Understand the estimate before relying on it. |
| Entry point | Parent route /budgets; deep link supported. |
| Happy path | Read context → inspect Observed / estimated boundary → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No forecast methodology for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; The mockup illustrates the approved fallback, not a trained ML model. |

### Domain subtleties

The mockup illustrates the approved fallback, not a trained ML model.

Show training period, input publication, backtest eligibility and limitations. No invented 90% confidence band.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Forecast methodology                     |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Observed / estimated boundary            |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/forecast` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `forecast` explanation and status.
- [ ] Inspect exact columns: Model, History, Calibration, Selection. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.
