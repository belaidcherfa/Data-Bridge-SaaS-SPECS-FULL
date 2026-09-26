# Showback — detailed screen design

Design unit: `showback`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../11-allocation/allocation.md).

This file covers 2 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## showback — Showback

Route: `/showback` (prototype `#/showback`). Persona: **Finance controller / team owner**.

Goal: Give every team a cost story they can act on.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  ALLOCATE  /  Showback                                                             |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Give every team a cost story they can act on.                                                            |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| WAREHOUSE COMPUTE: $20,000.00 [i]  ||  FINANCE ALLOCATION: $12,000.00 [i]                                |
| Billed compute · excludes cloud services  ||  8,400 query + 3,600 idle                                   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| MARKETING ALLOCATION: $8,000.00 [i]  ||  WAREHOUSE ALLOCATION: 100% [i]                                  |
| 5,600 query + 2,400 idle  ||  20,000 allocated / 20,000 absolute source                                  |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: Finance showback [>]                                                                           |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| BUSINESS VIEW                                                                                            |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| One selected book and period. Showback explains costs without transferring money.                        |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TEAM DRILLDOWN                                                                                           |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Authorized team portal includes its own trend, workload evidence and approved opportunities.             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Team                      | Allocated USD             | Share of book             | Owner                     |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Finance                   | 12,000.00                 | 60%                       | Alex Morgan               |
| Marketing                 | 8,000.00                  | 40%                       | Taylor Chen               |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| The portfolio view requires access to both teams; do not expose it to a restricted group viewer.         |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `warehouse` | Warehouse compute: **$20,000.00** | Billed compute · excludes cloud services | August 2026 / synthetic; RECONCILED |
| `financealloc` | Finance allocation: **$12,000.00** | 8,400 query + 3,600 idle | August 2026 / synthetic; RECONCILED |
| `marketingalloc` | Marketing allocation: **$8,000.00** | 5,600 query + 2,400 idle | August 2026 / synthetic; RECONCILED |
| `allocation` | Warehouse allocation: **100%** | 20,000 allocated / 20,000 absolute source | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Business view**: One selected book and period. Showback explains costs without transferring money.
- **Team drilldown**: Authorized team portal includes its own trend, workload evidence and approved opportunities.
- **DataTable** columns, in order: Team, Allocated USD, Share of book, Owner. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Drilldowns**: `/showback-team`. Use named links; never assume every row represents the same execution.

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
| Goal | Give every team a cost story they can act on. |
| Entry point | Allocate navigation; deep link supported. |
| Happy path | Read context → inspect Business view → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No showback for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: showback-team. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; The portfolio view requires access to both teams; do not expose it to a restricted group viewer. |

### Domain subtleties

The portfolio view requires access to both teams; do not expose it to a restricted group viewer.

Authorized team portal includes its own trend, workload evidence and approved opportunities.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Showback                                 |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Business view                            |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/showback` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `warehouse` explanation and status.
- [ ] Inspect exact columns: Team, Allocated USD, Share of book, Owner. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## showback-team — Finance showback

Route: `/showback-team` (prototype `#/showback-team`). Persona: **Finance controller / team owner**.

Goal: Your team · August 2026 · Teams book v1

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  ALLOCATE  /  Finance showback                                                     |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Your team · August 2026 · Teams book v1                                                                  |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| FINANCE ALLOCATION: $12,000.00 [i]  ||  OWNED QUERY COMPUTE: $8,400.00 [i]                               |
| 8,400 query + 3,600 idle  ||  Direct workload ownership                                                  |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ALLOCATED IDLE: $3,600.00 [i]  ||  TEAM OPPORTUNITY: $800.00 [i]                                         |
| 60% of 6,000  ||  Estimate only                                                                          |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| WHAT DROVE YOUR COST                                                                                     |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Explain only authorized workload and shared-cost components.                                             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| NEXT ACTION                                                                                              |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Review finance model schedule; potential opportunity 800 USD is an estimate, not realized savings.       |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Component                 | Allocated USD             | Method                    | Evidence                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Query compute             | 8,400.00                  | Direct ownership          | Verified workload         |
| Idle share                | 3,600.00                  | Proportional allocation   | Approved policy           |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Do not show hidden tenant-wide denominators to team viewers.                                             |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `financealloc` | Finance allocation: **$12,000.00** | 8,400 query + 3,600 idle | August 2026 / synthetic; RECONCILED |
| `financequery` | Owned query compute: **$8,400.00** | Direct workload ownership | August 2026 / synthetic; RECONCILED |
| `financeidle` | Allocated idle: **$3,600.00** | 60% of 6,000 | August 2026 / synthetic; RECONCILED |
| `teamopportunity` | Team opportunity: **$800.00** | Estimate only | Finance study / synthetic; ESTIMATE |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **What drove your cost**: Explain only authorized workload and shared-cost components.
- **Next action**: Review finance model schedule; potential opportunity 800 USD is an estimate, not realized savings.
- **DataTable** columns, in order: Component, Allocated USD, Method, Evidence. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `showback`; breadcrumb and browser Back preserve scope.

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
| Goal | Your team · August 2026 · Teams book v1 |
| Entry point | Parent route /showback; deep link supported. |
| Happy path | Read context → inspect What drove your cost → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No finance showback for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Do not show hidden tenant-wide denominators to team viewers. |

### Domain subtleties

Do not show hidden tenant-wide denominators to team viewers.

Review finance model schedule; potential opportunity 800 USD is an estimate, not realized savings.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Finance showback                         |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| What drove your cost                     |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/showback-team` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `financealloc` explanation and status.
- [ ] Inspect exact columns: Component, Allocated USD, Method, Evidence. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.
