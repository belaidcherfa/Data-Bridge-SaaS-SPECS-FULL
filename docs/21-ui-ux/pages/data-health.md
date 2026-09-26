# Data Health — detailed screen design

Design unit: `data-health`. Owner: UX / Frontend / QA. [Design index](../SCREEN_INDEX.md) · [Shared foundations](../FOUNDATIONS.md) · [Canonical domain](../../05-ingestion/ingestion.md).

This file covers 3 distinct routes. ASCII is a structural design specification; the React prototype supplies the actual light/amber visual treatment. Production scope and authorization come from the canonical contracts.

## data-health — Data Health

Route: `/data-health` (prototype `#/data-health`). Persona: **Tenant admin / data platform owner**.

Goal: Know what is complete, delayed or needs attention.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  PLATFORM  /  Data Health                                                          |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Know what is complete, delayed or needs attention.                                                       |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| OBSERVED COVERAGE: 100% [i]  ||  SOURCE CONTRACTS: 6 [i]                                                 |
| Complete selected synthetic intervals  ||  Representative coverage subset                                |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| BLOCKED SOURCE INTERVALS: 0 [i]  ||  LAST ACCEPTED SNAPSHOT: Sep 01 [i]                                  |
| Selected accepted fixture  ||  00:00 UTC; synthetic fixed as-of                                          |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| SUBPAGES: Query history coverage [>] | Synchronization history [>]                                       |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| COVERAGE TIMELINE                                                                                        |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Per source/account show contiguous complete interval and expected availability; source latency differs.  |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| CUSTOMER LANGUAGE                                                                                        |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Explain what data is missing and affected metrics before support-only implementation evidence.           |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Stage                     | State                     | Coverage                  | Next action               |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Source extraction         | Healthy                   | Complete                  | Inspect                   |
| Durable delivery          | Healthy                   | Complete                  | Inspect                   |
| Transformations           | Healthy                   | Complete                  | Inspect                   |
| Reconciliation            | Needs review              | Mismatch scenario         | Investigate               |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Availability and financial maturity are different axes.                                                  |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `coverage` | Observed coverage: **100%** | Complete selected synthetic intervals | August 2026 / synthetic; Observed |
| `sources` | Source contracts: **6** | Representative coverage subset | August 2026 / synthetic; Observed |
| `sourcefailed` | Blocked source intervals: **0** | Selected accepted fixture | August 2026 / synthetic; Observed |
| `lastsync` | Last accepted snapshot: **Sep 01** | 00:00 UTC; synthetic fixed as-of | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Coverage timeline**: Per source/account show contiguous complete interval and expected availability; source latency differs.
- **Customer language**: Explain what data is missing and affected metrics before support-only implementation evidence.
- **DataTable** columns, in order: Stage, State, Coverage, Next action. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Drilldowns**: `/source-detail`, `/sync-history`. Use named links; never assume every row represents the same execution.

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
| Persona | Tenant admin / data platform owner |
| Goal | Know what is complete, delayed or needs attention. |
| Entry point | Platform navigation; deep link supported. |
| Happy path | Read context → inspect Coverage timeline → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No data health for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Related routes: source-detail, sync-history. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Availability and financial maturity are different axes. |

### Domain subtleties

Availability and financial maturity are different axes.

Explain what data is missing and affected metrics before support-only implementation evidence.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Data Health                              |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Coverage timeline                        |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/data-health` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `coverage` explanation and status.
- [ ] Inspect exact columns: Stage, State, Coverage, Next action. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## source-detail — Query history coverage

Route: `/source-detail` (prototype `#/source-detail`). Persona: **Tenant admin / data platform owner**.

Goal: PRODUCTION · query evidence · source health

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  PLATFORM  /  Query history coverage                                               |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| PRODUCTION · query evidence · source health                                                              |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| OBSERVED COVERAGE: 100% [i]  ||  LOGICAL BATCHES: 3 [i]                                                  |
| Complete selected synthetic intervals  ||  Accepted contiguous intervals                                 |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| RETRIED BATCHES: 1 [i]  ||  COMPLETE THROUGH: Aug 31 [i]                                                 |
| Same logical batch identity  ||  Inclusive display; exclusive internal boundary Sep 01                   |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| COVERAGE DETAIL                                                                                          |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| 12,480 query rows across accepted contiguous intervals. Overlap/retries do not duplicate logical query   |
| IDs.                                                                                                     |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| RECOVERY                                                                                                 |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| A quarantined schema change explains blocked fields; replay does not falsely advance coverage before     |
| acceptance.                                                                                              |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Interval UTC              | State                     | Rows                      | Evidence                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
| Aug 01–10                 | Accepted                  | 4,000                     | Immutable manifest        |
| Aug 11–20                 | Accepted                  | 4,200                     | Immutable manifest        |
| Aug 21–31                 | Accepted                  | 4,280                     | Immutable manifest        |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Technical references expand only for authorized support users.                                           |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `coverage` | Observed coverage: **100%** | Complete selected synthetic intervals | August 2026 / synthetic; Observed |
| `batchcount` | Logical batches: **3** | Accepted contiguous intervals | August 2026 / synthetic; Observed |
| `retrycount` | Retried batches: **1** | Same logical batch identity | August 2026 / synthetic; Observed |
| `watermark` | Complete through: **Aug 31** | Inclusive display; exclusive internal boundary Sep 01 | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Coverage detail**: 12,480 query rows across accepted contiguous intervals. Overlap/retries do not duplicate logical query IDs.
- **Recovery**: A quarantined schema change explains blocked fields; replay does not falsely advance coverage before acceptance.
- **DataTable** columns, in order: Interval UTC, State, Rows, Evidence. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `data-health`; breadcrumb and browser Back preserve scope.

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
| Persona | Tenant admin / data platform owner |
| Goal | PRODUCTION · query evidence · source health |
| Entry point | Parent route /data-health; deep link supported. |
| Happy path | Read context → inspect Coverage detail → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No query history coverage for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Technical references expand only for authorized support users. |

### Domain subtleties

Technical references expand only for authorized support users.

A quarantined schema change explains blocked fields; replay does not falsely advance coverage before acceptance.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Query history coverage                   |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Coverage detail                          |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/source-detail` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `coverage` explanation and status.
- [ ] Inspect exact columns: Interval UTC, State, Rows, Evidence. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.

## sync-history — Synchronization history

Route: `/sync-history` (prototype `#/sync-history`). Persona: **Tenant admin / data platform owner**.

Goal: Backfill, catch-up and steady state in one timeline.

### Desktop composition

```text
+----------------------------------------------------------------------------------------------------------+
| BRIDGE DATA FINOPS  /  PLATFORM  /  Synchronization history                                              |
| Acme Group [v] | PRODUCTION / organization scope | Period explicitly named per panel | USD               |
| Backfill, catch-up and steady state in one timeline.                                                     |
| [Demo data]  [Maturity label]  As of fixed publication  |  [Explain] [Save view] [Export CSV]            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| LOGICAL BATCHES: 3 [i]  ||  RETRIED BATCHES: 1 [i]                                                       |
| Accepted contiguous intervals  ||  Same logical batch identity                                           |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| BLOCKED SOURCE INTERVALS: 0 [i]  ||  OBSERVED COVERAGE: 100% [i]                                         |
| Selected accepted fixture  ||  Complete selected synthetic intervals                                     |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| RETRY STORY                                                                                              |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Attempt 1 of batch_002 timed out after upload; retry reused logical batch identity and acceptance        |
| deduplicated.                                                                                            |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| REPLAY CONTROLS                                                                                          |
|      [Context / evidence panel]   [Inspect details >]                                                    |
| Bounded scope, impact preview, reason and permission gate. Scheduling replay is not immediate            |
| completion.                                                                                              |
+----------------------------------------------------------------------------------------------------------+
+----------------------------------------------------------------------------------------------------------+
| TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]                              |
+----------------------------------------------------------------------------------------------------------+
+---------------------------+---------------------------+---------------------------+---------------------------+
| Batch                     | Window                    | Attempt                   | Result                    |
+---------------------------+---------------------------+---------------------------+---------------------------+
| batch_001                 | Aug 01–10                 | 1                         | Accepted                  |
| batch_002                 | Aug 11–20                 | 2                         | Accepted                  |
| batch_003                 | Aug 21–31                 | 1                         | Accepted                  |
+---------------------------+---------------------------+---------------------------+---------------------------+
+----------------------------------------------------------------------------------------------------------+
| [Previous]   Rows are labelled sample or complete in context   [Next]                                    |
| Prototype recovery actions are simulations only.                                                         |
+----------------------------------------------------------------------------------------------------------+
```

### KPI contract

| Metric ID | Label / fixture value | Unit, formula or qualification | Scope / status |
|---|---|---|---|
| `batchcount` | Logical batches: **3** | Accepted contiguous intervals | August 2026 / synthetic; Observed |
| `retrycount` | Retried batches: **1** | Same logical batch identity | August 2026 / synthetic; Observed |
| `sourcefailed` | Blocked source intervals: **0** | Selected accepted fixture | August 2026 / synthetic; Observed |
| `coverage` | Observed coverage: **100%** | Complete selected synthetic intervals | August 2026 / synthetic; Observed |

Display the exact price basis, currency, publication and as-of in Explain. Monetary fixture values are illustrative and independently scoped as labelled; they are not a new production metric registry. See the [semantic contract](../../09-api/semantic-api.md).

### Components and subpage behavior

- **Retry story**: Attempt 1 of batch_002 timed out after upload; retry reused logical batch identity and acceptance deduplicated.
- **Replay controls**: Bounded scope, impact preview, reason and permission gate. Scheduling replay is not immediate completion.
- **DataTable** columns, in order: Batch, Window, Attempt, Result. Stable sorting, row search, column visibility, density and bounded CSV export; no automatic sum of mixed units or sample rows.
- **Primary action**: Save view. Opens a review/evidence interaction or saves the current exploration state; it must not imply a production mutation in the prototype.
- **Parent**: `data-health`; breadcrumb and browser Back preserve scope.

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
| Persona | Tenant admin / data platform owner |
| Goal | Backfill, catch-up and steady state in one timeline. |
| Entry point | Parent route /data-health; deep link supported. |
| Happy path | Read context → inspect Retry story → search the table → open named evidence/drilldown → retain scope on Back. |
| Empty state | For fully covered scope with no records: “No synchronization history for this selection.” Offer period/filter reset. A search with no matches offers Clear search. |
| Loading state | Keep heading/scope; skeleton occupies KPI and panel footprint. No transient zero or old-scope values. |
| Partial-data state | Show missing-source reason and affected metrics. Unknown is —, not 0. Link Data Health; suppress unsupported inference. |
| Error state | “We could not load this view.” Preserve scope; Retry; safe support reference. Form errors stay beside fields. |
| Permission-denied state | Replace content with access message; no hidden names/counts/exports. Request approved access; server remains authority. |
| Success state | Save view reports a specific outcome. Prototype labels it local/demo; exports contain the visible scope only. |
| Drilldown behavior | Breadcrumb + URL context; selected entity and period stay explicit. Explain drawer gives metric evidence; avoid invented child entities. |
| Primary actions | Save view; Explain; search/sort/columns; CSV; Back where applicable. |
| Acceptance criteria | Fixture values equal the KPI contract; Prototype recovery actions are simulations only. |

### Domain subtleties

Prototype recovery actions are simulations only.

Bounded scope, impact preview, reason and permission gate. Scheduling replay is not immediate completion.

Production mutations require explicit authorization and idempotency, with stale-version rejection and recovery. A browser-only draft cannot establish production RBAC, reconciliation, notification delivery or customer onboarding.

### Mobile composition and keyboard path

```text
+------------------------------------------+
| [Menu] Bridge  [Search]                  |
| Synchronization history                  |
| [Scope / period] [Status]                |
| KPI 1      |      KPI 2                  |
| KPI 3      |      KPI 4                  |
| Retry story                              |
| [View data / expand evidence]            |
| Tabs / related routes scroll -->         |
| Table scrolls within panel -->           |
| [Save view]                              |
+------------------------------------------+
```

At 390px: sidebar becomes a focus-managed menu; cards use two columns, panels one; table horizontal scroll is local. Keyboard path: skip link → scope → page action → KPI Explain buttons → related routes → table search/headers/rows → pagination. Escape closes overlays and returns focus to trigger. At 200% zoom no action or error message is clipped.

### Validation and definition of done

- [ ] Open `#/sync-history` directly and through the named navigation; heading and browser history agree.
- [ ] Assert every KPI above against its fixture scope; verify `batchcount` explanation and status.
- [ ] Inspect exact columns: Batch, Window, Attempt, Result. Search an existing row and a nonexistent token; sorting and exported rows agree.
- [ ] Exercise loading, confirmed empty, partial, stale, error/retry and denied states independently. Denied views contain no financial values.
- [ ] Open overlay with keyboard, tab through controls, Escape, and verify focus returns. Validate required fields before save where applicable.
- [ ] Review 1440px and 390px screenshots and 200% zoom; inspect actual rendered labels, not just source.
- [ ] Production-only: verify another tenant/group cannot query the route, autocomplete, export or detail by guessed ID; client review mode is not that proof.

Done for design: route, ASCII, KPI, states, interactions and constraints reviewed. Done for prototype: route renders with synthetic data and declared interactive behavior verified. Done for production remains governed by the original task and live validation gates.
