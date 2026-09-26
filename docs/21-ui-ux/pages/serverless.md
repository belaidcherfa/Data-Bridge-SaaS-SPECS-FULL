# Serverless services — detailed screen design

Design unit: `serverless`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../10-frontend/workloads.md).

This file covers 2 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## serverless — Serverless services

Route: `/serverless` (prototype `#/serverless`). Persona: **FinOps analyst / data engineer**.

Goal: The right unit and evidence for each managed service.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  Serverless services                                                   |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| The right unit and evidence for each managed service.                                                    |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SERVERLESS COST: $1,800.00 [i]  ||  SERVERLESS TASKS: $700.00 [i]                                        |
| 700 + 500 + 200 + 200 + 200  ||  Task service charge                                                     |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SNOWPIPE COST: $500.00 [i]  ||  OTHER SERVERLESS: $600.00 [i]                                            |
| Native billing basis  ||  Clustering + search + materialized views                                       |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: Snowpipe · ingest_events [>]                                                                   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SERVICE DISTRIBUTION                                                                                     |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| 700 + 500 + 200 + 200 + 200 = 1,800 USD.                                                                 |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| RESOURCE DRILLDOWN                                                                                       |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Keep service-specific usage quantities and source timing; no universal warehouse idle KPI.               |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Service                   | Billed USD                | Unit                      | Coverage                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Tasks                     | 700.00                    | Credits                   | Complete                  |
| Snowpipe                  | 500.00                    | Service units             | Complete                  |
| Clustering                | 200.00                    | Credits                   | Complete                  |
| Search optimization       | 200.00                    | Credits                   | Complete                  |
| Materialized views        | 200.00                    | Credits                   | Complete                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Service unit and price basis come from the canonical ledger/source catalog.                              |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `serverless` | Serverless cost: **$1,800.00** | 700 + 500 + 200 + 200 + 200 | August 2026 / synthetic; RECONCILED |
| `taskcost` | Serverless tasks: **$700.00** | Task service charge | August 2026 / synthetic; RECONCILED |
| `pipecost` | Snowpipe cost: **$500.00** | Native billing basis | August 2026 / synthetic; RECONCILED |
| `otherServerless` | Other serverless: **$600.00** | Clustering + search + materialized views | August 2026 / synthetic; RECONCILED |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Service distribution**: 700 + 500 + 200 + 200 + 200 = 1,800 USD.
- **Resource drilldown**: Keep service-specific usage quantities and source timing; no universal warehouse idle KPI.
- **DataTable** columns, in order: Service, Billed USD, Unit, Coverage. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Drilldowns**: `/serverless-detail`. Use named links; never assume every row represents the same execution.

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
| Goal | The right unit and evidence for each managed service. |
| Entry point | Explore navigation; deep link supported. |
| Happy path | Read context → inspect Service distribution → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No serverless services for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: serverless-detail. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Service unit and price basis come from the canonical ledger/source catalog. |

### Domain subtleties

Service unit and price basis come from the canonical ledger/source catalog.

Keep service-specific usage quantities and source timing; no universal warehouse idle KPI.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Serverless services                      |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Service distribution                     |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/serverless` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `serverless` explanation and status.
- [ ] Inspect exact columns: Service, Billed USD, Unit, Coverage. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## serverless-detail — Snowpipe · ingest_events

Route: `/serverless-detail` (prototype `#/serverless-detail`). Persona: **FinOps analyst / data engineer**.

Goal: Ingestion service · PRODUCTION · August 2026

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  EXPLORE  /  Snowpipe · ingest_events                                              |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Ingestion service · PRODUCTION · August 2026                                                             |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SNOWPIPE COST: $500.00 [i]  ||  LOADED FILES: 42,000 [i]                                                 |
| Native billing basis  ||  Deduplicated accepted fixture                                                  |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| LOADED VOLUME: 3 TB [i]  ||  UNRESOLVED LOAD FAILURES: 0 [i]                                             |
| Observed uncompressed bytes  ||  Accepted intervals only                                                 |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| USAGE AND COST                                                                                           |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Files and loaded bytes explain activity but do not establish an invented per-file Snowflake billing      |
| rate.                                                                                                    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| LOAD EVIDENCE                                                                                            |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Deduplicated ingestion observations, failed files and replay history are separate from billed totals.    |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Object                    | Billed USD                | Files                     | Status                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
| ingest_events             | 500.00                    | 42,000                    | Healthy                   |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Native fee basis must remain labelled when source or pricing revision changes.                           |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `pipecost` | Snowpipe cost: **$500.00** | Native billing basis | August 2026 / synthetic; RECONCILED |
| `files` | Loaded files: **42,000** | Deduplicated accepted fixture | August 2026 / synthetic; Observed |
| `ingested` | Loaded volume: **3 TB** | Observed uncompressed bytes | August 2026 / synthetic; Observed |
| `loadfail` | Unresolved load failures: **0** | Accepted intervals only | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Usage and cost**: Files and loaded bytes explain activity but do not establish an invented per-file Snowflake billing rate.
- **Load evidence**: Deduplicated ingestion observations, failed files and replay history are separate from billed totals.
- **DataTable** columns, in order: Object, Billed USD, Files, Status. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `serverless`; breadcrumb and browser Back preserve scope.

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
| Goal | Ingestion service · PRODUCTION · August 2026 |
| Entry point | Parent route /serverless; deep link supported. |
| Happy path | Read context → inspect Usage and cost → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No snowpipe · ingest_events for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Native fee basis must remain labelled when source or pricing revision changes. |

### Domain subtleties

Native fee basis must remain labelled when source or pricing revision changes.

Deduplicated ingestion observations, failed files and replay history are separate from billed totals.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Snowpipe · ingest_events                 |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Usage and cost                           |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/serverless-detail` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `pipecost` explanation and status.
- [ ] Inspect exact columns: Object, Billed USD, Files, Status. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.
