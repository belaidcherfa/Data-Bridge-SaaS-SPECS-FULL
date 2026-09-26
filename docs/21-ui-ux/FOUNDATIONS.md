# Identity, application shell and interaction foundations

Owner: UX / Frontend. Design phase: 2026-09-26. Canonical product semantics: [product](../10-frontend/product.md), [metrics](../09-api/semantic-api.md). This document specifies presentation, not alternative financial formulas.

## Visual provenance and decisions

Reference repository: [snowbridge-finops-mvp](https://github.com/belaidcherfa/snowbridge-finops-mvp). Inspected `src/index.css` at blob `641a90a58f99416e9b377e2dd95396fdd5f3da01`, `snowcost/layout/Sidebar.jsx` at `a49f41cbef3ea7a97de48e7cc7dbedc08c8171d1`, `ScopeBar.jsx` at `32e6f36435d4f885335d514c31ac4404a24f9e06`, `ui/AnalyticalCard.jsx` and `ui/MetricStrip.jsx`. Reuse visual ideas: light canvas, white analytical surfaces, amber selection, compact navigation, tabular figures, understated chart grids. Rebuild the shell and components independently. Preserve Bridge Data FinOps navigation and semantic contracts; do not import reference business logic, data, Base44 clients or authentication.

| Token | Value / use |
|---|---|
| Canvas / surface | #FCFCFC / #FFFFFF; secondary surface #F7F7F7 |
| Text / secondary / muted | #171717 / #4D4D4D / #616161 |
| Amber / amber ink / selection | #F59E0B / #92400E / #FFFBEB |
| Borders | rgba(0,0,0,.08), strong .12; no heavy box outlines in the rendered product |
| Success / warning / error ink | #065F46 / #92400E / #991B1B on pale tints; always text/icon |
| Service palette | compute amber; serverless violet; ingestion cyan; AI pink; platform emerald; storage slate; cloud blue |
| Typography | system sans locally, Inter-compatible metrics; mono for query IDs; tabular numbers |
| Size scale | page title 32–40; section 18–22; body 14; table 13; meta >=12px |
| Geometry | sidebar 224px; page max 1680; gutters 24–32; gap 20–24; card radius 14–18 |
| Density | rows 44px default / 36px dense; controls >=36px; mobile touch targets >=44px |

Amber background uses dark text to keep contrast. Static cards do not jump on hover. Motion is optional, <=160ms, disabled with reduced-motion preference. No remote font or tracking request is needed for the prototype.

## Desktop shell

```text
+----------------------+--------------------------------------------------------------------------+
| [B] Bridge Data      | Acme Group v | All accounts v | Sep 01–30 UTC v | USD v | Search pages   |
|     FinOps           +--------------------------------------------------------------------------+
| OVERVIEW             | Explore / Warehouses / ANALYTICS_PROD                 [Save] [Export]     |
|  Home                | ANALYTICS_PROD                                      [Explain this page]  |
|  Dashboards          | Classic warehouse • Finance • Acme Production                           |
| EXPLORE              | [PROVISIONAL] As of Sep 16 00:00 UTC • pub-demo-01 • partial month          |
|  Cost Explorer       +------------------+------------------+------------------+-----------------+
|  Warehouses          | Spend            | Query compute    | Idle compute     | Query count     |
|  Queries             | $20,000.00 [i]   | $14,000.00 [i]   | $6,000.00 [i]    | 12,480          |
|  Workloads           | credit rate      | attribution      | classic only     | complete data   |
|  Storage             +------------------+------------------+------------------+-----------------+
|  Serverless          | Overview | Queries | Workloads | Performance | Evidence                 |
|  AI / Cortex         +-----------------------------------------------+--------------------------+
|  SPCS                | Cost over time                                 | Query / idle composition |
| ALLOCATE             | [chart] actual solid / comparison dashed       | [bars with values]       |
| GOVERN               | [View data] keyboard accessible                | [Open query costs >]     |
| OPTIMIZE             +-----------------------------------------------+--------------------------+
| PLATFORM             | [Search] [Filters (2)] [Columns] [Density] [CSV]                          |
|                      | Workload            Cost USD    Share    Evidence          Detail         |
|  Data coverage 98%   | finance_daily       8,400.00     60%      Verified          [Open >]       |
|  Settings            | marketing_refresh   5,600.00     40%      Verified          [Open >]       |
+----------------------+--------------------------------------------------------------------------+
```

Shell navigation remains visually stable. Selected page is amber tinted with `aria-current`. Child routes use breadcrumbs and local tabs; do not put every execution ID in the sidebar. Scope belongs to the URL and survives drilldown/Back. Reset removes filters but never broadens authorization. Production account options are server authorized. Prototype uses one synthetic organization, clearly identified as a demo.

## Global state and overlay composition

```text
+-----------------------------------------+-------------------------------------------+
| Main page remains in place              | Explain this number                  [X]  |
| Focus returns to invoking KPI on close  | Spend • $27,000.00 USD                     |
|                                         | Basis: signed net charges                  |
| Page behind overlay is inert            | Publication: demo-2026-09-v1                |
| Escape closes unless critical write     | Period: Sep 01–30 UTC                       |
|                                         | Warehouse      20,000 | Storage     1,200 |
|                                         | Other services  5,600 | Org net       200 |
|                                         | [Open ledger] [Open reconciliation]       |
+-----------------------------------------+-------------------------------------------+
```

Explain shows metric ID/version, exact unit, sign, formula reference, scope, basis, publication, source as-of, coverage, rounding and authorized evidence. Drawers default 480px desktop/full width mobile. Radix dialog manages focus, Escape and background inertness in the prototype. Production asynchronous dialogs preserve a draft on recoverable failure, prevent repeated submits with idempotency keys, and identify stale-preview conflicts before approval.

## Financial status vocabulary

| Axis | Labels | Rule |
|---|---|---|
| Financial maturity | PROVISIONAL / FINAL / RECONCILED | Label each financial panel; mixed aggregates expose composition, never silently upgrade |
| Reconciliation | PENDING / MATCHED / WARNING / FAILED | Separate reconciliation outcome from maturity |
| Period close | OPEN / CLOSED / RESTATED | A matching open period is not a closed statement |
| Data quality | complete / partial / stale / unavailable | Coverage never substitutes for financial finality |
| Optimization | estimated potential / verified realized | Never sum both or silently treat estimates as savings |

Negative rebates reduce net spend; chart scales must accommodate negatives. Percent coverage uses absolute charge amounts. Never sum currencies or independent allocation books. Query-attributed compute is a component of warehouse charge. AI child attribution and SPCS service allocation do not add another parent charge. Exact numeric examples come from the ledger fixture.

## Required page states

| State | Visible behavior | Recovery |
|---|---|---|
| Loading | skeleton preserves geometry; no transient 0 | cancel old scope request; announce loading once |
| Empty confirmed | no observed activity for fully covered scope | change period or return to overview |
| Filtered empty | no matches; active filters visible | Clear filters |
| Partial | visible coverage message, missing sources, qualified values | Open Data Health |
| Stale | retain last accepted snapshot and timestamp | Retry; never mix new/old related cards |
| Error | plain-language explanation + support reference | Retry preserves filters |
| Permission denied | no forbidden values, names, counts or exports | request access through approved flow |
| Success | specific saved/simulated/downloaded outcome | inspect result; undo only reversible changes |

## Mobile and accessibility

```text
+-------------------------------------+
| [Menu] Bridge       [Search] [Avatar]|
| Acme / PROD v   Sep 01–30 UTC v      |
| Warehouses > ANALYTICS_PROD          |
| [PROVISIONAL] as of Sep 16           |
| Spend 20,000      Query 14,000       |
| Idle   6,000      Queries 12,480     |
| Overview | Queries | Workloads  --> |
| Cost chart                          |
| [View data]                         |
| Table scrolls inside this panel --> |
| [Primary action full width]         |
+-------------------------------------+
```

390px: collapse sidebar into modal navigation; scope wraps; two KPI columns; charts stack; data tables scroll inside a labelled region; page body must not overflow horizontally. No required hover-only interactions. Visible focus; skip link; one h1; heading hierarchy; control labels; sortable columns expose sort direction. Charts have a table equivalent. 200% zoom, reduced motion, keyboard and screen-reader checks are separate from visual approval.

## Sources checked for the prototype

Official [React createRoot](https://react.dev/reference/react-dom/client/createRoot), [Vite guide](https://vite.dev/guide/), [TanStack Table v8](https://tanstack.com/table/v8/docs/framework/react/react-table). Pin the actual tested versions in package/lock files; retain v8 table API intentionally rather than silently adopting a new major. Existing AWS/Snowflake research remains in the [research register](../00-project/RESEARCH_REGISTER.md).
