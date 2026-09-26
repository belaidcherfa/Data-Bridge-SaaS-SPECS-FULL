# Cost Explorer — detailed screen design

Design unit: `explorer`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../08-finops-ledger/ledger.md).

This file covers 3 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## explorer — Cost Explorer

Route: `/explorer` (prototype `#/explorer`). Persona: **FinOps analyst / data engineer**.

Goal: Understand what changed, then follow the cost to its source.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  Cost Explorer                                                         |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Understand what changed, then follow the cost to its source.                                             |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| NET SNOWFLAKE SPEND: $27,000.00 [i]  ||  WAREHOUSE COMPUTE: $20,000.00 [i]                               |
| Signed charges · USD  ||  Billed compute · excludes cloud services                                       |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| BILLED STORAGE: $1,200.00 [i]  ||  ORGANIZATION NET: $200.00 [i]                                         |
| Priced billing basis  ||  Support 500 less rebate 300                                                    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: Billing ledger [>] | Service breakdown [>]                                                     |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| DAILY SPEND                                                                                              |
|      __/\___/      \____/  \__    [service] [account]                                                    |
| Stack by approved service dimensions; signed rebates remain visible in the table.                        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CONTRIBUTION TO CHANGE                                                                                   |
|      __/\___/      \____/  \__    [service] [account]                                                    |
| Compare complete, equally covered periods only. July is unavailable in this fixture; no invented delta.  |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ANALYSIS BUILDER                                                                                         |
|      __/\___/      \____/  \__    [service] [account]                                                    |
| Select service or account grouping; retain filters in URL; export visible authorized rows.               |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Service                   | Net cost USD              | Basis                     | Maturity                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Warehouse                 | 20,000.00                 | Charge                    | RECONCILED                |
| Cloud services            | 1,000.00                  | Net adjustment            | RECONCILED                |
| Storage                   | 1,200.00                  | Billed                    | RECONCILED                |
| Serverless                | 1,800.00                  | Charge                    | RECONCILED                |
| AI / Cortex               | 600.00                    | Charge                    | RECONCILED                |
| SPCS                      | 800.00                    | Pool charge               | RECONCILED                |
| Data transfer             | 400.00                    | Charge                    | RECONCILED                |
| Application fees          | 1,000.00                  | Charge                    | RECONCILED                |
| Organization support      | 500.00                    | Org only                  | RECONCILED                |
| Organization rebate       | -300.00                   | Org only                  | RECONCILED                |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Only CHARGE facts contribute to spend. Query/idle attribution does not add to warehouse cost.            |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `spend` | Net Snowflake spend: **$27,000.00** | Signed charges · USD | August 2026 / synthetic; RECONCILED |
| `warehouse` | Warehouse compute: **$20,000.00** | Billed compute · excludes cloud services | August 2026 / synthetic; RECONCILED |
| `storage` | Billed storage: **$1,200.00** | Priced billing basis | August 2026 / synthetic; RECONCILED |
| `orgnet` | Organization net: **$200.00** | Support 500 less rebate 300 | August 2026 / synthetic; RECONCILED |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Daily spend**: Stack by approved service dimensions; signed rebates remain visible in the table.
- **Contribution to change**: Compare complete, equally covered periods only. July is unavailable in this fixture; no invented delta.
- **Analysis builder**: Select service or account grouping; retain filters in URL; export visible authorized rows.
- **DataTable** columns, in order: Service, Net cost USD, Basis, Maturity. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Drilldowns**: `/ledger`, `/services`. Use named links; never assume every row represents the same execution.

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
| Persona | FinOps analyst / data engineer |
| Goal | Understand what changed, then follow the cost to its source. |
| Entry point | Explore navigation; deep link supported. |
| Happy path | Read context → inspect Daily spend → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No cost explorer for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: ledger, services. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Only CHARGE facts contribute to spend. Query/idle attribution does not add to warehouse cost. |

### Domain subtleties

Only CHARGE facts contribute to spend. Query/idle attribution does not add to warehouse cost.

Select service or account grouping; retain filters in URL; export visible authorized rows.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Cost Explorer                            |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Daily spend                              |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/explorer` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `spend` explanation and status.
- [ ] Inspect exact columns: Service, Net cost USD, Basis, Maturity. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## ledger — Billing ledger

Route: `/ledger` (prototype `#/ledger`). Persona: **FinOps analyst / data engineer**.

Goal: Every charge, adjustment and explanation in one place.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  Billing ledger                                                        |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Every charge, adjustment and explanation in one place.                                                   |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| NET SNOWFLAKE SPEND: $27,000.00 [i]  ||  ACCOUNT CHARGES: $26,800.00 [i]                                 |
| Signed charges · USD  ||  Organization adjustments excluded                                              |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ORGANIZATION NET: $200.00 [i]  ||  BASELINE RECONCILIATION: MATCHED [i]                                  |
| Support 500 less rebate 300  ||  Baseline reference equals 27,000                                        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CHARGE INSPECTOR                                                                                         |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Inspect charge ID, service, time grain, signed amount, price source and source lineage.                  |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| VERSION COMPARISON                                                                                       |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Published v1=27,000. A hypothetical storage correction v2=26,900 is never silently substituted into a    |
| closed statement.                                                                                        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Charge                    | Scope                     | Amount USD                | Evidence                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Warehouse compute         | PRODUCTION                | 20,000.00                 | Metered                   |
| Cloud services net        | PRODUCTION                | 1,000.00                  | Daily adjusted            |
| Storage                   | PRODUCTION                | 1,200.00                  | Invoice basis             |
| Serverless                | PRODUCTION                | 1,800.00                  | Service meter             |
| Cortex                    | PRODUCTION                | 600.00                    | Service meter             |
| SPCS                      | PRODUCTION                | 800.00                    | Pool meter                |
| Transfer                  | PRODUCTION                | 400.00                    | Metered                   |
| Application fees          | PRODUCTION                | 1,000.00                  | Contract                  |
| Support                   | Organization              | 500.00                    | Statement                 |
| Rebate                    | Organization              | -300.00                   | Credit note               |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Refunds are negative. Organization adjustments are not repeated under every account.                     |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `spend` | Net Snowflake spend: **$27,000.00** | Signed charges · USD | August 2026 / synthetic; RECONCILED |
| `accountcost` | Account charges: **$26,800.00** | Organization adjustments excluded | August 2026 / synthetic; RECONCILED |
| `orgnet` | Organization net: **$200.00** | Support 500 less rebate 300 | August 2026 / synthetic; RECONCILED |
| `recon` | Baseline reconciliation: **MATCHED** | Baseline reference equals 27,000 | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Charge inspector**: Inspect charge ID, service, time grain, signed amount, price source and source lineage.
- **Version comparison**: Published v1=27,000. A hypothetical storage correction v2=26,900 is never silently substituted into a closed statement.
- **DataTable** columns, in order: Charge, Scope, Amount USD, Evidence. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `explorer`; breadcrumb and browser Back preserve scope.

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
| Persona | FinOps analyst / data engineer |
| Goal | Every charge, adjustment and explanation in one place. |
| Entry point | Parent route /explorer; deep link supported. |
| Happy path | Read context → inspect Charge inspector → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No billing ledger for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Refunds are negative. Organization adjustments are not repeated under every account. |

### Domain subtleties

Refunds are negative. Organization adjustments are not repeated under every account.

Published v1=27,000. A hypothetical storage correction v2=26,900 is never silently substituted into a closed statement.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Billing ledger                           |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Charge inspector                         |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/ledger` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `spend` explanation and status.
- [ ] Inspect exact columns: Charge, Scope, Amount USD, Evidence. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## services — Service breakdown

Route: `/services` (prototype `#/services`). Persona: **FinOps analyst / data engineer**.

Goal: Compare native cost components without double counting.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  Service breakdown                                                     |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Compare native cost components without double counting.                                                  |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| WAREHOUSE COMPUTE: $20,000.00 [i]  ||  SERVERLESS COST: $1,800.00 [i]                                    |
| Billed compute · excludes cloud services  ||  700 + 500 + 200 + 200 + 200                                |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| AI / CORTEX COST: $600.00 [i]  ||  COMPUTE POOL COST: $800.00 [i]                                        |
| Additive family charges  ||  Billed once per pool                                                        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SERVICE MAP                                                                                              |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Service families retain native units. Do not add tokens, credits, bytes and runtime.                     |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| COVERAGE                                                                                                 |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| A missing family is unavailable, not zero. Costs only become comparable after currency/basis alignment.  |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Service                   | Amount USD                | Native unit               | Detail                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Warehouse                 | 20,000.00                 | Credits                   | Warehouses                |
| Serverless                | 1,800.00                  | Service credits           | Serverless                |
| Cortex                    | 600.00                    | Service dependent         | AI / Cortex               |
| SPCS                      | 800.00                    | Pool credits              | SPCS                      |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Storage and transfer appear in the full explorer. This panel shows four compute-related service          |
| families.                                                                                                |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `warehouse` | Warehouse compute: **$20,000.00** | Billed compute · excludes cloud services | August 2026 / synthetic; RECONCILED |
| `serverless` | Serverless cost: **$1,800.00** | 700 + 500 + 200 + 200 + 200 | August 2026 / synthetic; RECONCILED |
| `cortex` | AI / Cortex cost: **$600.00** | Additive family charges | August 2026 / synthetic; RECONCILED |
| `spcs` | Compute pool cost: **$800.00** | Billed once per pool | August 2026 / synthetic; RECONCILED |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Service map**: Service families retain native units. Do not add tokens, credits, bytes and runtime.
- **Coverage**: A missing family is unavailable, not zero. Costs only become comparable after currency/basis alignment.
- **DataTable** columns, in order: Service, Amount USD, Native unit, Detail. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `explorer`; breadcrumb and browser Back preserve scope.

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
| Persona | FinOps analyst / data engineer |
| Goal | Compare native cost components without double counting. |
| Entry point | Parent route /explorer; deep link supported. |
| Happy path | Read context → inspect Service map → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No service breakdown for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Storage and transfer appear in the full explorer. This panel shows four compute-related service families. |

### Domain subtleties

Storage and transfer appear in the full explorer. This panel shows four compute-related service families.

A missing family is unavailable, not zero. Costs only become comparable after currency/basis alignment.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Service breakdown                        |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Service map                              |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/services` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `warehouse` explanation and status.
- [ ] Inspect exact columns: Service, Amount USD, Native unit, Detail. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.
