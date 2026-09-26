# Chargeback statements — detailed screen design

Design unit: `chargeback`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../11-allocation/allocation.md).

This file covers 2 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## chargeback — Chargeback statements

Route: `/chargeback` (prototype `#/chargeback`). Persona: **Finance controller / team owner**.

Goal: Controlled, versioned internal cost statements.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  ALLOCATE  /  Chargeback statements                                                |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Controlled, versioned internal cost statements.                                                          |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ISSUED STATEMENT TOTAL: $20,000.00 [i]  ||  ISSUED STATEMENTS: 2 [i]                                     |
| Two statements in one book  ||  One per team in Teams book                                               |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| DRAFT STATEMENTS: 0 [i]  ||  CLOSE STATUS: CLOSED [i]                                                    |
| Synthetic closed period  ||  Independent of maturity                                                     |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: ST-2026-08-FIN [>]                                                                             |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| STATEMENT LIFECYCLE                                                                                      |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Draft → review → approve → issue; final/reconciled policy enforced before issue.                         |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CORRECTION                                                                                               |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| A correction creates an adjustment/restatement linked to the original; issued lines remain immutable.    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Statement                 | Team                      | Amount USD                | Status                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
| ST-2026-08-FIN            | Finance                   | 12,000.00                 | Issued                    |
| ST-2026-08-MKT            | Marketing                 | 8,000.00                  | Issued                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| These are internal cost statements, not legal sales invoices or customer SaaS billing.                   |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `statementtotal` | Issued statement total: **$20,000.00** | Two statements in one book | August 2026 / synthetic; RECONCILED |
| `statementcount` | Issued statements: **2** | One per team in Teams book | August 2026 / synthetic; Observed |
| `statementdraft` | Draft statements: **0** | Synthetic closed period | August 2026 / synthetic; Observed |
| `close` | Close status: **CLOSED** | Independent of maturity | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Statement lifecycle**: Draft → review → approve → issue; final/reconciled policy enforced before issue.
- **Correction**: A correction creates an adjustment/restatement linked to the original; issued lines remain immutable.
- **DataTable** columns, in order: Statement, Team, Amount USD, Status. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Drilldowns**: `/statement`. Use named links; never assume every row represents the same execution.

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
| Goal | Controlled, versioned internal cost statements. |
| Entry point | Allocate navigation; deep link supported. |
| Happy path | Read context → inspect Statement lifecycle → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No chargeback statements for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: statement. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; These are internal cost statements, not legal sales invoices or customer SaaS billing. |

### Domain subtleties

These are internal cost statements, not legal sales invoices or customer SaaS billing.

A correction creates an adjustment/restatement linked to the original; issued lines remain immutable.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Chargeback statements                    |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Statement lifecycle                      |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/chargeback` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `statementtotal` explanation and status.
- [ ] Inspect exact columns: Statement, Team, Amount USD, Status. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## statement — ST-2026-08-FIN

Route: `/statement` (prototype `#/statement`). Persona: **Finance controller / team owner**.

Goal: Finance · issued Sep 02 · immutable statement v1

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  ALLOCATE  /  ST-2026-08-FIN                                                       |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Finance · issued Sep 02 · immutable statement v1                                                         |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| FINANCE ALLOCATION: $12,000.00 [i]  ||  OWNED QUERY COMPUTE: $8,400.00 [i]                               |
| 8,400 query + 3,600 idle  ||  Direct workload ownership                                                  |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| ALLOCATED IDLE: $3,600.00 [i]  ||  CLOSE STATUS: CLOSED [i]                                              |
| 60% of 6,000  ||  Independent of maturity                                                                |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| DOCUMENT HEADER                                                                                          |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Recipient Finance, USD, Aug 01–31 UTC, source pub v1, allocation v1, RECONCILED, CLOSED.                 |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| AUDIT TRAIL                                                                                              |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Prepared → reviewed → approved → issued with actor/time; export explains full monetary conservation.     |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Line                      | Basis                     | Amount USD                | Version                   |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Owned query compute       | Direct                    | 8,400.00                  | Teams v1                  |
| Allocated idle            | 60% of 6,000              | 3,600.00                  | Teams v1                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| A later 100 USD storage correction lies outside this warehouse-only statement.                           |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `financealloc` | Finance allocation: **$12,000.00** | 8,400 query + 3,600 idle | August 2026 / synthetic; RECONCILED |
| `financequery` | Owned query compute: **$8,400.00** | Direct workload ownership | August 2026 / synthetic; RECONCILED |
| `financeidle` | Allocated idle: **$3,600.00** | 60% of 6,000 | August 2026 / synthetic; RECONCILED |
| `close` | Close status: **CLOSED** | Independent of maturity | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Document header**: Recipient Finance, USD, Aug 01–31 UTC, source pub v1, allocation v1, RECONCILED, CLOSED.
- **Audit trail**: Prepared → reviewed → approved → issued with actor/time; export explains full monetary conservation.
- **DataTable** columns, in order: Line, Basis, Amount USD, Version. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Preview statement. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `chargeback`; breadcrumb and browser Back preserve scope.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Preview statement                                           [X]            |
| Selected metric / resource: [label and identifier]                         |
| Scope and period: [explicit, retained from entry]                          |
| Basis / input publication / coverage: [explain]                            |
| Evidence: [authorized source / parent component]                           |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Preview statement]                                              |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | Finance controller / team owner |
| Goal | Finance · issued Sep 02 · immutable statement v1 |
| Entry point | Parent route /chargeback; deep link supported. |
| Happy path | Read context → inspect Document header → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No st-2026-08-fin for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Preview statement reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Preview statement; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; A later 100 USD storage correction lies outside this warehouse-only statement. |

### Domain subtleties

A later 100 USD storage correction lies outside this warehouse-only statement.

Prepared → reviewed → approved → issued with actor/time; export explains full monetary conservation.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| ST-2026-08-FIN                           |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Document header                          |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Preview statement]                      |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/statement` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `financealloc` explanation and status.
- [ ] Inspect exact columns: Line, Basis, Amount USD, Version. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.
