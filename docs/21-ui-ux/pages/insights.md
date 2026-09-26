# Insights — detailed screen design

Design unit: `insights`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../13-insights/intelligence.md).

This file covers 2 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## insights — Insights

Route: `/insights` (prototype `#/insights`). Persona: **Platform owner / FinOps analyst**.

Goal: Evidence first. Opportunity second.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  OPTIMIZE  /  Insights                                                             |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Evidence first. Opportunity second.                                                                      |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| POTENTIAL SAVINGS: $8,000.00 [i]  ||  OPPORTUNITY GROUP: 1 [i]                                           |
| Estimate · never add to realized  ||  Non-overlapping study                                              |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| HIGH-CONFIDENCE INSIGHTS: 0 [i]  ||  VERIFIED REALIZED: $6,000.00 [i]                                    |
| One medium-confidence estimate  ||  24,000 normalized minus 18,000 observed                              |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: Review warehouse scheduling [>]                                                                |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| OPPORTUNITY RANKING                                                                                      |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Estimated 8,000 belongs to a separate normalized-savings study period; do not claim more current idle    |
| saved than observed.                                                                                     |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| EVIDENCE QUALITY                                                                                         |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Baseline, observation window, constraints, expected impact range and overlap group are visible.          |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Opportunity               | Estimated USD             | Confidence                | Status                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Reduce warehouse idle     | 8,000.00                  | Medium                    | Review evidence           |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Potential is not realized and is not additive across overlapping recommendations.                        |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `potential` | Potential savings: **$8,000.00** | Estimate · never add to realized | Independent study / synthetic; ESTIMATE |
| `insightcount` | Opportunity group: **1** | Non-overlapping study | August 2026 / synthetic; Observed |
| `highconfidence` | High-confidence insights: **0** | One medium-confidence estimate | August 2026 / synthetic; Observed |
| `verifiedsavings` | Verified realized: **$6,000.00** | 24,000 normalized minus 18,000 observed | Independent study / synthetic; VERIFIED |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Opportunity ranking**: Estimated 8,000 belongs to a separate normalized-savings study period; do not claim more current idle saved than observed.
- **Evidence quality**: Baseline, observation window, constraints, expected impact range and overlap group are visible.
- **DataTable** columns, in order: Opportunity, Estimated USD, Confidence, Status. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Drilldowns**: `/insight-detail`. Use named links; never assume every row represents the same execution.

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
| Goal | Evidence first. Opportunity second. |
| Entry point | Optimize navigation; deep link supported. |
| Happy path | Read context → inspect Opportunity ranking → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No insights for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: insight-detail. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Potential is not realized and is not additive across overlapping recommendations. |

### Domain subtleties

Potential is not realized and is not additive across overlapping recommendations.

Baseline, observation window, constraints, expected impact range and overlap group are visible.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Insights                                 |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Opportunity ranking                      |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/insights` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `potential` explanation and status.
- [ ] Inspect exact columns: Opportunity, Estimated USD, Confidence, Status. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## insight-detail — Review warehouse scheduling

Route: `/insight-detail` (prototype `#/insight-detail`). Persona: **Platform owner / FinOps analyst**.

Goal: A measured opportunity with an explicit baseline

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  OPTIMIZE  /  Review warehouse scheduling                                          |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| A measured opportunity with an explicit baseline                                                         |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| POTENTIAL SAVINGS: $8,000.00 [i]  ||  VERIFIED REALIZED: $6,000.00 [i]                                   |
| Estimate · never add to realized  ||  24,000 normalized minus 18,000 observed                            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| BASELINE COST: $20,000.00 [i]  ||  OBSERVED POST COST: $18,000.00 [i]                                    |
| 100 observed baseline units  ||  120 observed post units                                                 |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| RECOMMENDATION                                                                                           |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Review schedule and idle evidence; owner must assess operational constraints before any Snowflake        |
| change.                                                                                                  |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SAVINGS EXPLANATION                                                                                      |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Normalized expected 24,000 minus actual 18,000 = verified 6,000; original estimate 8,000 remains         |
| separate.                                                                                                |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Evidence                  | Baseline                  | After                     | Interpretation            |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Comparable units          | 100                       | 120                       | Normalize volume          |
| Observed cost USD         | 20,000.00                 | 18,000.00                 | Different workload volume |
| Expected USD at old rate  | —                         | 24,000.00                 | 200 per unit              |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Before/after study is independent of the August ledger display period.                                   |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `potential` | Potential savings: **$8,000.00** | Estimate · never add to realized | Independent study / synthetic; ESTIMATE |
| `verifiedsavings` | Verified realized: **$6,000.00** | 24,000 normalized minus 18,000 observed | Independent study / synthetic; VERIFIED |
| `baseline` | Baseline cost: **$20,000.00** | 100 observed baseline units | Independent study / synthetic; FINAL |
| `postcost` | Observed post cost: **$18,000.00** | 120 observed post units | Independent study / synthetic; FINAL |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Recommendation**: Review schedule and idle evidence; owner must assess operational constraints before any Snowflake change.
- **Savings explanation**: Normalized expected 24,000 minus actual 18,000 = verified 6,000; original estimate 8,000 remains separate.
- **DataTable** columns, in order: Evidence, Baseline, After, Interpretation. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Create action draft. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `insights`; breadcrumb and browser Back preserve scope.

### Detail / dialog composition

```text
+----------------------------------------------------------------------------+
| Create action draft                                           [X]          |
| Selected metric / resource: [label and identifier]                         |
| Scope and period: [explicit, retained from entry]                          |
| Basis / input publication / coverage: [explain]                            |
| Evidence: [authorized source / parent component]                           |
| [Inline validation / stale-preview error, if any]                          |
| [Cancel]  [Create action draft]                                            |
| Prototype: local simulation only; no external write                        |
+----------------------------------------------------------------------------+
```

### UX state specification

| Requirement | Expected behavior |
|---|---|
| Persona | Platform owner / FinOps analyst |
| Goal | A measured opportunity with an explicit baseline |
| Entry point | Parent route /insights; deep link supported. |
| Happy path | Read context → inspect Recommendation → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No review warehouse scheduling for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Create action draft reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Create action draft; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Before/after study is independent of the August ledger display period. |

### Domain subtleties

Before/after study is independent of the August ledger display period.

Normalized expected 24,000 minus actual 18,000 = verified 6,000; original estimate 8,000 remains separate.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Review warehouse scheduling              |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Recommendation                           |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Create action draft]                    |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/insight-detail` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `potential` explanation and status.
- [ ] Inspect exact columns: Evidence, Baseline, After, Interpretation. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.
