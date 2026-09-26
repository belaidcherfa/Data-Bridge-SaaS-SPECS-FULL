# Your spend, in focus — detailed screen design

Design unit: `home`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../10-frontend/product.md).

This file covers 1 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## home — Your spend, in focus

Route: `/home` (prototype `#/home`). Persona: **FinOps lead / executive**.

Goal: A clear view of cost, ownership and the next best action.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  OVERVIEW  /  Your spend, in focus                                                 |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| A clear view of cost, ownership and the next best action.                                                |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| NET SNOWFLAKE SPEND: $27,000.00 [i]  ||  WAREHOUSE COMPUTE: $20,000.00 [i]                               |
| Signed charges · USD  ||  Billed compute · excludes cloud services                                       |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| WAREHOUSE ALLOCATION: 100% [i]  ||  POTENTIAL SAVINGS: $8,000.00 [i]                                     |
| 20,000 allocated / 20,000 absolute source  ||  Estimate · never add to realized                          |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SPEND OVER TIME                                                                                          |
|      .       __/\__      __       [actual] [View data]                                                   |
| Daily signed net spend. Hover for exact USD; View data opens the same series.                            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| WHAT NEEDS ATTENTION                                                                                     |
|      .       __/\__      __       [actual] [View data]                                                   |
| One invoice mismatch, one allocation decision, one warehouse opportunity. Prioritize separately from     |
| monetary totals.                                                                                         |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| OWNERSHIP SNAPSHOT                                                                                       |
|      .       __/\__      __       [actual] [View data]                                                   |
| Warehouse book: Finance 12,000; Marketing 8,000. Applies to 20,000 compute, not all organizational       |
| spend.                                                                                                   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Driver                    | Cost USD                  | Change                    | Next step                 |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Warehouse compute         | 20,000.00                 | +6.4%                     | Explore                   |
| Serverless                | 1,800.00                  | +2.1%                     | Explore                   |
| Storage                   | 1,200.00                  | -3.2%                     | Explore                   |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| August 2026 synthetic closed-period charges total 27,000 USD. Potential savings and September forecast   |
| are separate estimate contexts.                                                                          |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `spend` | Net Snowflake spend: **$27,000.00** | Signed charges · USD | August 2026 / synthetic; RECONCILED |
| `warehouse` | Warehouse compute: **$20,000.00** | Billed compute · excludes cloud services | August 2026 / synthetic; RECONCILED |
| `allocation` | Warehouse allocation: **100%** | 20,000 allocated / 20,000 absolute source | August 2026 / synthetic; Observed |
| `potential` | Potential savings: **$8,000.00** | Estimate · never add to realized | Independent study / synthetic; ESTIMATE |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Spend over time**: Daily signed net spend. Hover for exact USD; View data opens the same series.
- **What needs attention**: One invoice mismatch, one allocation decision, one warehouse opportunity. Prioritize separately from monetary totals.
- **Ownership snapshot**: Warehouse book: Finance 12,000; Marketing 8,000. Applies to 20,000 compute, not all organizational spend.
- **DataTable** columns, in order: Driver, Cost USD, Change, Next step. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.

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
| Persona | FinOps lead / executive |
| Goal | A clear view of cost, ownership and the next best action. |
| Entry point | Overview navigation; deep link supported. |
| Happy path | Read context → inspect Spend over time → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No your spend, in focus for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; August 2026 synthetic closed-period charges total 27,000 USD. Potential savings and September forecast are separate estimate contexts. |

### Domain subtleties

August 2026 synthetic closed-period charges total 27,000 USD. Potential savings and September forecast are separate estimate contexts.

Warehouse book: Finance 12,000; Marketing 8,000. Applies to 20,000 compute, not all organizational spend.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Your spend, in focus                     |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Spend over time                          |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/home` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `spend` explanation and status.
- [ ] Inspect exact columns: Driver, Cost USD, Change, Next step. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.
