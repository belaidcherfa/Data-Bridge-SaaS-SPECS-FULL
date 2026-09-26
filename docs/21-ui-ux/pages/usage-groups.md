# Usage Groups — detailed screen design

Design unit: `usage-groups`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../11-allocation/allocation.md).

This file covers 2 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## usage-groups — Usage Groups

Route: `/usage-groups` (prototype `#/usage-groups`). Persona: **Finance controller / team owner**.

Goal: Independent books for teams, products and cost centers.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  ALLOCATE  /  Usage Groups                                                         |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Independent books for teams, products and cost centers.                                                  |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| INDEPENDENT BOOKS: 2 [i]  ||  BOOK LEAVES: 4 [i]                                                         |
| Teams and Products; not additive  ||  2 leaves per independent book                                      |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| UNALLOCATED: $0.00 [i]  ||  HIERARCHY CONFLICTS: 0 [i]                                                   |
| Warehouse Teams book only  ||  No cycles or invalid weights                                              |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: Finance group [>]                                                                              |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| HIERARCHY                                                                                                |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Each charge appears once per book; weighted assignments conserve source cost.                            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| MEMBERSHIP CHANGES                                                                                       |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Effective-dated moves retain historical hierarchy versions; cycles rejected before preview.              |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Book                      | Hierarchy                 | Source USD                | Status                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Teams                     | Finance / Marketing       | 20,000.00                 | Published                 |
| Products                  | Core / Growth             | 20,000.00                 | Published                 |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Two 20,000 books do not make 40,000 spend.                                                               |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `groupbooks` | Independent books: **2** | Teams and Products; not additive | August 2026 / synthetic; Observed |
| `groupleaves` | Book leaves: **4** | 2 leaves per independent book | August 2026 / synthetic; Observed |
| `unallocated` | Unallocated: **$0.00** | Warehouse Teams book only | August 2026 / synthetic; RECONCILED |
| `groupconflicts` | Hierarchy conflicts: **0** | No cycles or invalid weights | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Hierarchy**: Each charge appears once per book; weighted assignments conserve source cost.
- **Membership changes**: Effective-dated moves retain historical hierarchy versions; cycles rejected before preview.
- **DataTable** columns, in order: Book, Hierarchy, Source USD, Status. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Drilldowns**: `/usage-group-detail`. Use named links; never assume every row represents the same execution.

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
| Goal | Independent books for teams, products and cost centers. |
| Entry point | Allocate navigation; deep link supported. |
| Happy path | Read context → inspect Hierarchy → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No usage groups for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: usage-group-detail. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Two 20,000 books do not make 40,000 spend. |

### Domain subtleties

Two 20,000 books do not make 40,000 spend.

Effective-dated moves retain historical hierarchy versions; cycles rejected before preview.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Usage Groups                             |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Hierarchy                                |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/usage-groups` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `groupbooks` explanation and status.
- [ ] Inspect exact columns: Book, Hierarchy, Source USD, Status. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## usage-group-detail — Finance group

Route: `/usage-group-detail` (prototype `#/usage-group-detail`). Persona: **Finance controller / team owner**.

Goal: Teams book v1 · Finance ownership

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  ALLOCATE  /  Finance group                                                        |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Teams book v1 · Finance ownership                                                                        |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| FINANCE ALLOCATION: $12,000.00 [i]  ||  OWNED QUERY COMPUTE: $8,400.00 [i]                               |
| 8,400 query + 3,600 idle  ||  Direct workload ownership                                                  |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ALLOCATED IDLE: $3,600.00 [i]  ||  GROUP MEMBERS: 2 [i]                                                  |
| 60% of 6,000  ||  Synthetic identities                                                                   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| GROUP COMPOSITION                                                                                        |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Finance total 12,000 = query 8,400 + idle allocation 3,600.                                              |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| PERMISSION BOUNDARY                                                                                      |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| A Finance-only viewer cannot infer Marketing spend from percentages, totals or hidden member counts.     |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Member                    | Role                      | Scope                     | Status                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Alex Morgan               | Group viewer              | Finance only              | Active                    |
| Taylor Chen               | Group manager             | Finance only              | Active                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| This admin demo includes group context; production group-limited responses must be independently         |
| authorized.                                                                                              |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `financealloc` | Finance allocation: **$12,000.00** | 8,400 query + 3,600 idle | August 2026 / synthetic; RECONCILED |
| `financequery` | Owned query compute: **$8,400.00** | Direct workload ownership | August 2026 / synthetic; RECONCILED |
| `financeidle` | Allocated idle: **$3,600.00** | 60% of 6,000 | August 2026 / synthetic; RECONCILED |
| `groupmembers` | Group members: **2** | Synthetic identities | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Group composition**: Finance total 12,000 = query 8,400 + idle allocation 3,600.
- **Permission boundary**: A Finance-only viewer cannot infer Marketing spend from percentages, totals or hidden member counts.
- **DataTable** columns, in order: Member, Role, Scope, Status. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `usage-groups`; breadcrumb and browser Back preserve scope.

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
| Goal | Teams book v1 · Finance ownership |
| Entry point | Parent route /usage-groups; deep link supported. |
| Happy path | Read context → inspect Group composition → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No finance group for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; This admin demo includes group context; production group-limited responses must be independently authorized. |

### Domain subtleties

This admin demo includes group context; production group-limited responses must be independently authorized.

A Finance-only viewer cannot infer Marketing spend from percentages, totals or hidden member counts.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Finance group                            |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Group composition                        |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/usage-group-detail` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `financealloc` explanation and status.
- [ ] Inspect exact columns: Member, Role, Scope, Status. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.
