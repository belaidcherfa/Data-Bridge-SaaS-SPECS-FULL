# Shared components and interaction contracts

[Foundations](FOUNDATIONS.md) · [Screen catalog](SCREEN_INDEX.md) · [Product contract](../10-frontend/product.md).

## Component inventory

| Component | Contract | Prototype behavior | Production integration |
|---|---|---|---|
| AppShell / navigation | Grouped PRD hierarchy, active ancestor, breadcrumb, responsive menu | All catalog routes reachable; mobile Radix dialog | Authorized navigation tree only |
| Scope bar | Organization/account, period, currency, publication | One synthetic organization; all vs PRODUCTION on overview/explorer/ledger/services; other scopes explicitly pinned | Server-authorized org/account discovery; exact UTC ranges, comparison, currency availability |
| Page search | Find authorized pages/entities without disclosure | Searches the complete synthetic route catalog | Tenant-scoped search; no hidden entity enumeration |
| MetricStrip | Label, value, unit/basis, maturity, hint, Explain | Exact fixture values; partial/maturity review modes | Semantic API decimal strings and null reasons |
| Explain dialog | Formula, scope, publication, coverage and evidence | Focus-managed dialog and ledger navigation | Authorized evidence IDs, source versions, rounding, price basis |
| Badge | Maturity, quality, workflow are independent | Text labels, success/warning icons | No merging of reconciliation and financial-close state |
| Panel | Stable heading, action, content and footnote | Shared white surface; no jumping hover | Per-panel refresh/error metadata |
| DataTable | Search, stable sorting, columns, density, paging, export | TanStack Table v8; eight rows/page; visible-column CSV over filtered/sorted rows | Bounded server pagination/exports; selection and bulk authorization |
| SpendChart | Same accepted snapshot as KPIs; tabular alternative | Deterministic 31-day series whose cents sum to selected ledger | Source-backed daily aggregation and aligned comparison |
| ServiceBreakdown | Additive charges only, signed values | Ten service/adjustment rows; rebate magnitude bar with negative value | Dynamic registry dimensions and conserved Top N + Other |
| BudgetChart | Actual/estimate boundary and explicit budget | 15 actual days; dashed run-rate remainder; no invented interval | Versioned calibrated models and completeness policy |
| Allocation bridge | Source conserved within one book/policy | Toggle proportional vs Platform idle; published table stays clearly v1 | Simulation jobs, version conflict, approve/publish workflow |
| Execution evidence | Parent/child component scope, safe SQL | Representative query/AI/PBI evidence | Permission-filtered drilldowns and live profile eligibility |
| Pipeline graph | Verified topology, duration semantics | Parallel dbt inputs; sequential native task graph; selectable nodes | Verified native IDs and bounded graph pagination |
| Statement preview | Fixed period/book/version, immutable lines | Printable Finance statement; browser Save PDF | Isolated deterministic PDF renderer and secure artifact delivery |
| LocalForm | Required labels, validation, specific save outcome | Required fields; browser-only draft persistence and storage failure recovery | Typed schemas, server rules, authorization, idempotency, optimistic version checks |
| Review confirmation | Reason, reviewer and explicit outcome | Local review record; never issues a statement or publishes facts | Reauthorize approval, compare input/rule hash, separate duties where required |
| Wizard | Explicit progress and evidence per stage | Five conceptual stages; no secret collection | Map 14 PRD onboarding steps to these five stage groups; durable resume |
| Incident timeline | One episode, observations and acknowledgements | Four observations and local acknowledgement | Outbox, recovery confirmation, silence expiry and dispatch authorization |
| StateBlock | Loading/empty/error/denied are distinct | Review toolbar on every route; partial/stale notices | Real request lifecycle; no prior-tenant placeholder cache |

## Generic table anatomy

```text
+-------------------------------------------------------------------------------------+
| Execution explorer                                          [Saved view v] [CSV]     |
| Exact scope • period • source publication • sample/full-result qualification         |
| [Search query/hash...]  [Filter +]  [Group v]  [Columns v]  [Compact]                   |
+----------------+--------------+--------------+---------------+-----------------------+
| Query ID ^     | Compute USD  | Duration s   | Warehouse     | Evidence              |
+----------------+--------------+--------------+---------------+-----------------------+
| q_demo_042 [>] | 2.80         | 12.4         | ANALYTICS...  | Verified / sanitized  |
+----------------+--------------+--------------+---------------+-----------------------+
| 1 representative row; monthly aggregate is a different query       [<] 1 / 1 [>]     |
+-------------------------------------------------------------------------------------+
```

Prototype controls implemented are listed above. Advanced arbitrary pivots, multi-filter expressions, saved-view reopening and server export jobs are production contracts rather than implied working features. The prototype's Cost Explorer supports two actual grouping modes: service and account. Displayed “Explore” evidence labels are text unless an explicit named drilldown link is shown.

## Reusable interaction details

- Forms retain input after validation failures. Required-only prototype validation does not replace financial decimal, email, URL, SSO metadata, AST or role-scope validation in production.
- Dialogs trap focus, close on Escape and restore focus to the trigger. Review content must remain available before confirming. No irreversible production action exists in this prototype.
- Local draft keys use the `bridge-design:` namespace. Reset by deleting only that prefix; never clear unrelated browser storage. Never enter secrets or real personal data.
- Maturity review modes alter applicable reconciled financial labels to PROVISIONAL or FINAL; they do not certify a ledger. Empty/denied mode replaces the view before data panels mount.
- Charts retain their named period. Scope selection changes the net organization/account totals only on routes that expose that choice. Pinned study/planning/entity pages say so; they do not pretend to apply an unsupported global filter.
- Query execution text is sanitized in the fixture. Production sanitizes before persistence, not only during React rendering.

## Responsive and accessible acceptance

1. Every actionable control has an accessible name and visible focus.
2. A keyboard user can open/close a dialog, search a table, sort, change columns, switch related views and activate navigation without hover.
3. At 390px, page width remains within the viewport; wide query tables scroll inside their panel. At 200% zoom, no required control is clipped.
4. Data legends use labels and values, not color alone. Chart View data provides exact figures.
5. Loading never presents zero spend. Missing attribution and unavailable utilization display an em dash with a reason.
6. Automated accessibility checks support design review; manual assistive-technology qualification remains a production gate.
