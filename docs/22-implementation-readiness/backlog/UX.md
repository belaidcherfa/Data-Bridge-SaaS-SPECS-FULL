# UX — Implementation-readiness review and production backlog

Canonical contract: [product.md](../../10-frontend/product.md) (plus [docs/21-ui-ux](../../21-ui-ux/README.md) design workbench, [ADR-013](../../architecture/adr/ADR-013-ui-design-prototype.md) and [prototypes/finops-react](../../../prototypes/finops-react/README.md)). Tasks reviewed: UX-001, UX-002, UX-003, UX-004, UX-005, UX-006, UX-007, UX-008; consistency review of FOUNDATIONS.md, COMPONENTS.md, SCREEN_INDEX.md, FIXTURES_AND_SCOPE.md, VALIDATION.md, the 26 page documents and the prototype source. Reviewer: domain audit agent, 2026-09-27. Status of all tasks: NOT_STARTED.

Related reviews: [API.md](API.md) (registry, meta, tokens and the tenant selector the UI depends on), [WRK.md](WRK.md) (workload pages), [SEC.md](SEC.md) (G-SEC-04 role names, G-SEC-19 sign-in page), [FIN.md](FIN.md) (G-FIN-21 missing pricing/close/reference screens).

## 1. Verdict

The visual identity and information architecture are good enough to build on, and the prototype proves that the shell, tables, dialogs and state vocabulary render accessibly. Production is not implementable from these documents as written:
- The 87 page documents come from one template. All 87 have a CSV table toolbar, including `/sign-in` and `/mfa`, and all 87 use the same empty-state sentence "No <page title> for this selection". Per-screen data bindings therefore still have to be written.
- The screen metric keys do not match the registry (API G-API-03).
- **20 of the 87 screens have no owning task**, or an owner that cannot build them.
- Routes disagree between the tasks (`/explore/cost`), the catalog (`/explorer`) and the prototype (`#/warehouse-detail` with no entity ID).
- The prototype encodes financial formulas that production must not copy.
- Nothing specifies the multi-tab tenant race, the publication pinning across tiles, D-18 string externalization or bundle budgets.
Author these first: the canonical route map with tenant prefix and entity IDs (§3), the URL-state schema, the query-key factory, the screen-contract template, and the screen→task ownership table (§3.1). Then UX-001 can start on day 1 and UX-002 can build against the OpenAPI contract with MSW mocks, before the live API exists.

## 2. Findings

### G-UX-01 · 20 of 87 screens have no owning task or an owner that cannot build them
Severity: HIGH · Type: GAP
Evidence: the task entry points (grep `^| Entry point` over docs/tasks) compared with `SCREEN_INDEX.md`:
- `/dashboards` and `/dashboard-builder`. The only owner is CTL-007 (M1, "Add saved views, dashboards and commercial control records"), which persists definitions but has no semantic query layer (API-003 is M5).
- `/ledger`, `/services`: no task names them; UX-004 names only `/explore/cost`.
- `/workloads` overview, `/native-apps`, `/custom-apps`, `/ad-hoc`: WRK-004 claims the entry "/explore/workloads" for "tasks, procedures and other workload execution graphs".
- `/integrations`, `/connection-detail` (Integration Health): CON-004/CON-006 cover the org/account settings and the connection wizard only.
- `/settings`, `/settings-roles`, `/settings-audit`, `/settings-privacy`, `/support`: no task has these entry points. SEC-008 has an audit API but no UI; SEC-007 has a privacy mode but no UI.
- `/insights`, `/insight-detail`: INS-002…INS-005 all name "/optimize/insights" and none owns the shared list/detail UI.
- `/data-health`, `/source-detail`, `/sync-history`: ING-012 bundles them with the "bounded hot history" path, which D-24 defers to R2.
Why it matters: these screens will either be skipped or built ad hoc at integration time. Several are needed for a production R1:
- audit log and privacy settings (D-25 SOC 2-ready, D-10 erasure),
- Integration Health (grant gaps, egress IPs D-09, customer warehouse credits D-08),
- Data Health (R1 per RELEASE_PLAN).
Resolution: the ownership table in §3.1 plus these new tasks:
- UX-102 Settings & administration pages (R1)
- UX-103 Integration Health (R1)
- UX-104 Explain drawer, jobs and exports center (R1)
- UX-101 Dashboards (R2; in R1 the Dashboards navigation item lists saved views from UX-004)
- WRK-102 Workloads overview + ad hoc (R1), WRK-105 Native/custom apps (R2) — see WRK.md.
Recommendations to other owners: INS-001 owns the insights list/detail UI; ING-012 splits "Data Health UX" (R1) from "hot path" (R2).
Affects: CTL-007, WRK-004, CON-006, SEC-007, SEC-008, INS-001…005, ING-012, UX-101…104.

### G-UX-02 · Three incompatible route vocabularies; prototype routes carry no entity identity
Severity: HIGH · Type: CONTRADICTION
Evidence:
- Tasks use hierarchical paths: `UX-004 /explore/cost`, `ALC-001 /allocate/tags`, `GOV-001 /govern/budgets`, `ING-012 /platform/data-health`, `CTL-003 /settings/members`, `SEC-002 /login`.
- `SCREEN_INDEX.md` uses flat paths: `/explorer`, `/tags`, `/budgets`, `/data-health`, `/settings-people`, `/sign-in`.
- The prototype uses hash routes such as `#/warehouse-detail` and `#/query-detail` with no ID (`prototypes/finops-react/src/app/navigation.ts`: `id: path || "home"`).
- `product.md` requires "Use opaque IDs in routes".
Why it matters: deep links, saved views, report links, notification links (GOV-007) and the Back-button contract all depend on stable URLs. An entity page without an ID in the URL cannot be shared or restored, and three vocabularies will leak into emails and reports that cannot be changed later.
Resolution: a canonical production route map (§3): `/t/{tenantSlug}/{group}/{page}[/{opaqueId}][/{tab}]`, following PRD §143 groups and the task entry points. The catalog IDs remain **screen IDs**, not URLs; FIN's proposed `/settings-pricing`, `/reconciliation-close`, `/reconciliation-references` (G-FIN-21) become screen IDs too. Entities use internal UUIDs (warehouse, pool, dbt project, etc.), and queries use `/{accountId}/{queryId}`. Browser history routing replaces hash routing, which requires the CloudFront/ALB SPA fallback in INF-006.
Affects: UX-001, UX-002, all page tasks, GOV-007, RPT-005, INF-006.

### G-UX-03 · The page designs are template-generated; per-screen content is thinner than VALIDATION.md claims
Severity: HIGH · Type: GAP
Evidence: `VALIDATION.md` says "Each route has a dedicated ASCII composition, KPI contract, table schema, interaction/dialog, mobile composition, all 13 required UX fields". A grep over `docs/21-ui-ux/pages/*.md` shows:
- 87/87 pages contain `TABLE TOOLBAR: [Search rows...] [Sort column] [Columns v] [Density v] [CSV]`.
- 87/87 empty states read "No <title> for this selection", for example “No your spend, in focus for this selection.” (`home.md`), “No review warehouse schedule for this selection.”, “No ai execution · ai_042 for this selection.”
- `sign-in.md` shows the scope bar, "[Explain] [Save view] [Export CSV]" and primary actions "Continue demo sign-in; Explain; search/sort/columns; CSV" (also G-SEC-19).
- `home.md` draws "What needs attention" and "Ownership snapshot" with the same chart glyph as "Spend over time", even though they are lists.
- Every page has 2–4 KPIs and a table with ≤ 4 columns and 2–3 rows.
Why it matters: engineers will copy a generic page template to screens that need different interactions (sign-in, wizard, rule editor, statement, incident timeline), or re-derive the content, with drift between pages. The "13 UX requirements" are mostly boilerplate, like the task files (AUDIT X-01).
Resolution: treat `docs/21-ui-ux` as the visual/IA reference only. Every page-owning task starts with a step that writes a **screen contract** (template in §3). It contains:
- data bindings (registry metric@version, records dataset, entity endpoint),
- real columns with types and sort keys,
- the permission capability per action,
- specific empty/partial/denied copy keys,
- entity IDs in the route,
- an acceptance oracle with fixture numbers.
Auth screens (`/sign-in`, `/mfa`) use a separate unauthenticated layout with no scope bar, export or Explain.
Affects: all page tasks (UX-003…UX-008, UX-101…104, ALC-*, GOV-*, RPT-*, INS-*, WRK-*), SEC-002.

### G-UX-04 · Screen metric keys and labels do not match the registry; "P95 execution" contradicts `query_elapsed_p95`
Severity: HIGH · Type: CONTRADICTION
Evidence: the KPI tables use keys `warehouse`, `querycompute`, `allocation`, `p95`, `potential` (176 keys; mapping in API.md §3.3). `queries.md` `p95` reads "P95 execution: 18.6 s". The registry only has `query_elapsed_p95`, and elapsed includes compile and queue (0.4 + 0.2 s in the fixture query).
Why it matters: tiles will be bound to the wrong population, or a UI-specific formula will be added.
Resolution: tiles bind to registry IDs only, through generated types (`apps/web/src/generated/registry.ts`, API-001-S11). A label must name the registry metric's population ("P95 execution time" → `query_execution_p95`). The screen-contract step of each task maps design keys to registry IDs using API.md §3.3. A CI check fails if a component references a metric ID that is absent from the compiled registry.
Affects: UX-003…UX-007, API-001.

### G-UX-05 · Tenant switch, multi-tab and permission-epoch races are unspecified on the client
Severity: HIGH · Type: GAP
Evidence: UX-002 says "TanStack keys include tenant/profile/epoch/publication; no token in localStorage" and oracle "Switch A→B shows no A rows even briefly". `security.md` says "Invalidate principal pools and browser caches on tenant switch/logout". The client cannot know the permission epoch unless the server tells it, and all tabs share one BFF cookie.
Why it matters:
- A pending A response that resolves after the switch renders A numbers under B's labels.
- A tab left on tenant A sends requests after another tab switched the server-side "active tenant" (API G-API-13).
- `placeholderData`/`keepPreviousData` shows the old scope's numbers during a scope change, which violates "no old-scope values".
Resolution:
- (1) The tenant lives in the URL (`/t/{tenantSlug}`) and in the `X-Bridge-Tenant` header of every request (G-API-13). There is no server-side active tenant.
- (2) Bootstrap `GET /v1/me/context` returns profile_hash, membership_epoch, capabilities and the current publication.
- (3) Key factory: `['t', tenantId, 'p', profileHash, 'e', epoch, 'pub', publicationId, kind, requestHash]`.
- (4) The fetch wrapper rejects any response whose `meta.tenant_id` differs from the key's tenant, or whose `meta` epoch/profile is newer than the key's. The latter triggers a context refetch and `removeQueries(['t', tenantId])`.
- (5) Tenant switch = navigate to `/t/{new}/home` after `cancelQueries()` + `clear()`.
- (6) A `BroadcastChannel('bridge-session')` carries logout and epoch-bump events to the other tabs.
- (7) `placeholderData` is allowed only when the keys differ solely by `publicationId` (a refresh of the same scope), never across scope or filter changes.
Affects: UX-002, API-003, SEC-006.

### G-UX-06 · "Tiles share one publication" needs a page-level publication pin and an explicit refresh
Severity: HIGH · Type: GAP
Evidence: `product.md` says "Background refresh keeps prior accepted values with as-of label; a new dataset version replaces related tiles together". UX-002 MT3 says "Share one response/version across chart/table/KPIs and support dataset update notification without mixed versions".
Why it matters: tiles load independently. If publication N+1 lands between the first and the fifth tile request, "latest" resolves differently, and the page shows a mix of N and N+1 even though every tile is individually correct.
Resolution:
- The first semantic response on a page pins `publicationId` in the page context, and all later requests on that page send `publication: <id>`. Home uses `POST /v1/analytics/batch` (API-002-S11), so all tiles come from one resolution.
- A 60 s visibility-aware poll of `GET /v1/publications/current` shows the banner "Newer data available (as of …) — Refresh". Refresh re-pins and re-fetches every key atomically, and the old values stay visible until all new keys resolve.
- A render guard asserts that every tile's `meta.publication_id` equals the page pin, and a tile that fails the guard shows the stale state.
- Explicit historical pins (links from a closed statement or report) put `pub=<id>` in the URL. If the publication is retired, a 410 shows "This view referenced data version X, no longer retained — showing current".
Affects: UX-002, UX-003, API-003.

### G-UX-07 · The prototype encodes financial formulas and heuristics that production must not copy
Severity: HIGH · Type: RISK
Evidence (`prototypes/finops-react/src/data/financial.ts`, `catalog.ts`, `App.tsx`):
- `spend()` sums charges in the browser.
- `budget()` computes `forecast = actual + burn × (days − completeDays)` and `variance = forecast − limit`.
- `savings()` computes `realized = expected − post`.
- `allocation()` returns hard-coded splits.
- `dailySpend()` **fabricates** a 31-day series by allocating the monthly total over invented weights.
- `allocateCents()` does the largest remainder on floating-point weights (`Math.abs(sum − 1) > 1e-9`) with ties broken by array index.
- `metricFor('orgnet')` returns **0** cents for account scope (`scope === "all" ? 20000 : 0`), which renders "$0.00" where the correct state is "not applicable at account scope".
- The page status badge is derived from the page id (`p.id.startsWith("reconciliation") … ? "FINAL" : … "RECONCILED"`).
- `DataTable` sorts numbers by `Number(s.replaceAll(",", ""))` on display strings.
- Charts format axes with `"$" + Math.round(v)`, which ignores locale and currency.
Why it matters: each of these, copied into production, is a competing financial formula or a lie that `product.md` forbids ("React displays returned values", "Unknown cost uses an em dash plus reason, not 0"). The fabricated daily series is especially dangerous because it looks real.
Resolution: the prototype is a **reference for identity and interaction only** (reuse matrix in §3.2). Production enforces this mechanically:
- (a) Money values are a branded type `MoneyString` from the generated API types.
- (b) A custom ESLint rule `bridge/no-money-arithmetic` forbids `Number()`, `parseFloat`, unary `+` and arithmetic operators on `MoneyString`, and forbids importing `prototypes/**`.
- (c) Totals, Other, deltas and percentages come only from `meta.totals`, the `__OTHER__` row and the server's `delta`/`delta_pct`.
- (d) Status badges read `meta.data_status`, `reconciliation_status` and `close_status` per panel.
- (e) Sorting is server-side (keyset).
- (f) Not-applicable is a null with the reason `NOT_APPLICABLE_SCOPE`.
Largest-remainder rounding belongs to ALC-008/FIN-106 on exact decimals with stable target-ID tie-breaks.
Affects: UX-001, UX-002, UX-003, UX-004, ALC-008.

### G-UX-08 · D-18 string externalization and locale formatting are absent from the designs and the prototype
Severity: MEDIUM · Type: GAP
Evidence: DECISIONS D-18 ("all UI strings externalized, locale-aware number/date formatting from day 1"). A grep of `FOUNDATIONS.md` and `COMPONENTS.md` for i18n/locale/translation finds nothing. The prototype hard-codes English in `screens.json` (3,017 lines) and components, `new Intl.NumberFormat("en-US", …)` in `financial.ts`, and `"$" + v / 1000 + "k"` in `Charts.tsx`.
Why it matters: retrofitting 87 screens costs more than externalizing from the first component. Money formatted through JS `number` loses exactness above 2^53 minor units and rounds half-even differently from the server.
Resolution:
- Use FormatJS (`react-intl`, ICU MessageFormat) with catalogs under `apps/web/src/i18n/{locale}/*.json`, and the lint rule `formatjs/no-literal-string-in-jsx` in CI.
- A pseudo-locale `en-XA` (+35 % length, accented) is part of the visual tests.
- Formatting goes through `format/money.ts`, which passes the **decimal string** to `Intl.NumberFormat(locale, {style:'currency', currency, signDisplay:'negative'})`. ECMA-402 NumberFormat v3 formats string input exactly; confirm in the FND-002 browser matrix. `signDisplay:'negative'` avoids "-$0.00".
- Dates are always labelled UTC (G-FIN-26).
- Server-side strings (problem messages, notification templates) use message keys + params and are rendered client-side.
Affects: UX-001, UX-002, RPT-001, GOV-007.

### G-UX-09 · The design-system choice is unresolved between shadcn/ui (contract) and local CSS components (prototype)
Severity: MEDIUM · Type: AMBIGUITY
Evidence: `product.md` says "shadcn/ui primitives". ADR-013 says "local presentation components follow the intended shadcn-style … production shadcn adoption remains part of the original foundation task". The prototype uses `radix-ui` 1.6.7, `src/styles/app.css` (2,010 lines) and `tokens.css` (151 lines), with no Tailwind.
Why it matters: shadcn/ui is copy-in source on Radix + Tailwind. Porting 2,000 lines of bespoke CSS into it is a redesign, not a migration, and two styling systems in one codebase double the review surface.
Resolution: production adopts shadcn/ui (Radix primitives, Tailwind CSS v4, pinned in FND-002).
- Keep: `tokens.css` becomes Tailwind theme CSS variables, and the component *behaviors* documented in COMPONENTS.md.
- Discard: `app.css`, `ui.tsx`, the page layout logic.
- Pin one chart library (Recharts 3.x, as in the prototype, with `accessibilityLayer`) and one table library (TanStack Table v8, manual/server modes).
- Record this as an ADR-013 amendment in UX-001-S01.
Affects: UX-001, FND-002.

### G-UX-10 · Screens required by tasks and decisions are missing from the design catalog
Severity: MEDIUM · Type: GAP
Evidence: the task entry points `/settings/api-clients` (API-006), `/settings/pricing` (FIN-002), `/govern/reconciliation/period` (FIN-010) and `/reports/templates` (RPT-003) are not in `SCREEN_INDEX.md`. API-004 "Submit deep analysis → follow progress → open completed result" has no job screen. G-FIN-21 lists the missing pricing, close and reference-intake screens. The following are absent too:
- D-08 "wizard shows estimated monthly credits before consent" is not in `integrations.md` (grep "credit" finds nothing in the onboarding section).
- D-09 fixed egress IPs are absent (grep "egress|IP address": 0 hits).
- D-11 retention-tier states ("query-level detail retained 90 days") are absent from `queries.md`.
- There is no tenant chooser for multi-tenant users.
- The metric-substitution banner (API G-API-02) is absent.
Why it matters: these are R1 behaviors with no visual/IA contract, so engineers will improvise inconsistent patterns.
Resolution: the design additions in §3.3, authored as screen contracts by the owning tasks (UX-102/103/104, API-006-S09, FIN tasks per G-FIN-21, ONB/CON for D-08/D-09 content).
Affects: UX-102, UX-103, UX-104, API-006, FIN-002, FIN-010, CON-006, ONB-001.

### G-UX-11 · The storage fixture apportions billed storage by the latest active gauge; production must not copy this
Severity: MEDIUM · Type: RISK
Evidence: `storage.md`: "ANALYTICS | 840.00 | 7 TB" and "RAW | 360.00 | 3 TB" with "Latest active storage: 10 TB". 840/1,200 = 0.70 = 7/10, so the billed storage is apportioned by the **latest active** bytes. The same page lists ANALYTICS time travel 1.2 TB and fail-safe 0.4 TB, and "Retained bytes: 2 TB". 1.2 + 0.4 = 1.6 TB ≠ 2 TB, and the remaining 0.4 TB is unexplained.
Why it matters: billed storage accrues on daily average bytes over the month, including time-travel and fail-safe bytes (FIN-006; G-FIN-16 per-database historical source). Apportioning by an end-of-month active gauge misallocates:
- a database that was dropped mid-month,
- a database whose fail-safe dominates.
A UI that recomputes 840 from bytes would contradict the ledger.
Resolution: database billed storage comes only from FIN-006's attribution (`attributed_cost` by `database`, time-weighted daily bytes over all billable classes) and is displayed as returned. The byte chart uses `storage_bytes` (latest/twa) and is labelled as a different quantity. The fixture is corrected to state its basis (the 0.4 TB is either `retained_for_clone` or removed).
Affects: UX-006, FIN-006, FND-004 (fixtures).

### G-UX-12 · Accessibility evidence is narrower than claimed, and amber fails non-text contrast
Severity: MEDIUM · Type: RISK
Evidence:
- `VALIDATION.md`: "Axe on Home, Explorer, Budget editor, Allocation, Warehouse detail and Security settings" covers 6 of 87 routes. Mobile width was checked "on six representative compositions".
- `FOUNDATIONS.md` sets the amber token `#F59E0B`, "Service palette | compute amber …", and "Selected page is amber tinted".
- Computed: relative luminance of #F59E0B = 0.2126·0.913 + 0.7152·0.341 + 0.0722·0.003 ≈ 0.438, so contrast against white = 1.05/0.488 ≈ **2.15:1**. That is below the WCAG 1.4.11 3:1 minimum for graphical objects (chart bars, focus/selection indicators). `#FFFBEB` selection tint vs `#FCFCFC` canvas is ≈ 1.03:1.
Why it matters: amber compute bars and amber-only selection states are not perceivable by low-vision users, and passing axe on 6 pages does not prove the other 81.
Resolution:
- The token audit script (UX-001-S02) checks every foreground/background pair: text ≥ 4.5:1, non-text ≥ 3:1. Amber is allowed as fill only with a ≥ 3:1 outline (`#B45309`, ≈ 5:1 on white) or direct labels. The selected navigation item gets a non-color indicator (3 px `#92400E` left bar + `aria-current`).
- Axe runs on all routes in CI (UX-008).
- A manual screen-reader checklist (NVDA+Firefox, VoiceOver+Safari) covers 10 page families.
Affects: UX-001, UX-008.

### G-UX-13 · No performance budgets, error-boundary granularity or client telemetry
Severity: MEDIUM · Type: GAP
Evidence: none of `product.md`, UX-001…UX-008 or `FOUNDATIONS.md` defines a JS budget, LCP target or error-boundary rule. PRD §141 says "Target sub-second experience after cache". The prototype imports `screens.json` (3,017 lines) and `metrics.json` (1,463 lines) into the main bundle.
Why it matters: a dashboard SPA with Recharts, TanStack Table and 87 routes grows past 1 MB without budgets. A single render error blanks the whole page, and without client telemetry the 99th-percentile user experience is invisible.
Resolution:
- `size-limit` budgets in CI: initial route (shell + Home) ≤ 200 KB gzip JS, each lazy route ≤ 120 KB, the charts chunk loaded lazily.
- LCP p75 ≤ 2.5 s on cached Home (staging, throttled "Fast 4G").
- Error boundaries per route **and per panel**. A panel failure shows the panel error state with `request_id`, and siblings keep rendering.
- Client telemetry (web-vitals + error class + request_id; no values, no names) goes to an OPS endpoint.
Affects: UX-001, UX-002, UX-008, OPS-001.

### G-UX-14 · The UX dependency chain is over-serialized
Severity: MEDIUM · Type: GAP
Evidence: task-index.json: UX-004 ← UX-003 ← FIN-009; UX-005/UX-006/UX-007 ← UX-004; WRK-002/003/004 ← UX-005; UX-004 ← API-005; UX-002 ← API-003 (live).
Why it matters: Cost Explorer does not need Home. Warehouse, storage, AI and workload pages need the UX-002 data layer and their APIs, not the Explorer page. Explain is a drawer that can arrive later behind a feature flag. The chain adds five serial page tasks to the critical path.
Resolution:
- UX-003: −FIN-009 for build (MSW against the OpenAPI examples); FIN-009 and API-101 remain for the staging gate.
- UX-004: −UX-003, −API-005 (Explain via UX-104), +API-001.
- UX-005, UX-006, UX-007: −UX-004, +UX-002, +API-104.
- WRK-002/003/004: −UX-005, +UX-002, +API-104 (WRK.md).
- UX-002: builds on API-003-S01 (OpenAPI) and needs API-003 live only for its staging gate.
- UX-008: +UX-102, +UX-103, +UX-104.
Affects: UX-002…UX-008, WRK-002…WRK-004.

### G-UX-15 · Fixture and navigation inconsistencies in the design documents
Severity: LOW · Type: CONTRADICTION
Evidence:
- `FOUNDATIONS.md` desktop shell shows "[PROVISIONAL] As of Sep 16 00:00 UTC • pub-demo-01 • partial month" above the August closed-period values ($20,000 / $14,000 / $6,000) that `FIXTURES_AND_SCOPE.md` labels August/RECONCILED.
- Publication naming differs: `pub-demo-01` (shell), `demo-2026-09-v1` (Explain overlay), "demo publication v1" (prototype `App.tsx`).
- Navigation places Dashboards under OVERVIEW, while PRD §143 and `product.md` place Dashboards as a top-level item after Optimize.
- Workload fixtures: dbt `queries` 7,488 / 30 invocations = 249.6 queries per invocation and PBI 4,992 / 25 activities = 199.68, while the representative PBI activity has 32 queries and every activity costs exactly 224 (25 × 224 = 5,600). This is consistent only if the "representative" rows are declared non-uniform.
Why it matters: small, but these fixtures become Playwright oracles, and inconsistent ones produce either false failures or tests that assert contradictions.
Resolution:
- FND-004 fixtures carry one publication id and one as-of per period.
- The shell example uses September provisional numbers or the August RECONCILED label.
- The navigation follows PRD §143.
- The workload fixture adds a per-invocation/activity table whose sums equal 7,488 / 4,992 queries and 8,400 / 5,600 USD.
Affects: FND-004, UX-001, UX-008, WRK-002, WRK-003.

## 3. Contract-first artifacts to author before coding

| Artifact | Exact content required | Produced by (task/micro-task) |
|---|---|---|
| Canonical route map `apps/web/src/routes/route-map.ts` + doc | Production path per screen ID (§3.1): `/t/:tenantSlug/home`, `/t/:tenantSlug/explore/cost`, `…/explore/cost/ledger`, `…/explore/cost/services`, `…/explore/warehouses/:warehouseId[/performance]`, `…/explore/queries[/executions]`, `…/explore/queries/:accountId/:queryId`, `…/explore/workloads[/dbt/:projectId[/invocations/:invocationId\|/models/:modelId]]`, `…/explore/workloads/powerbi[/activities/:activityId]`, `…/explore/workloads/pipelines[/:graphId]`, `…/explore/storage[/:databaseId]`, `…/explore/serverless[/:serviceKey/:resourceId]`, `…/explore/ai[/:family[/:requestId]]`, `…/explore/spcs[/:poolId[/services/:serviceId]]`, `…/allocate/…`, `…/govern/…`, `…/optimize/…`, `…/dashboards[/:dashboardId[/edit]]`, `…/platform/data-health[/sources/:sourceId\|/sync-history]`, `…/platform/integrations[/:connectionId]`, `…/settings/{workspace,members,roles,organizations,security,audit,privacy,notifications,billing,api-clients,pricing}`, `…/support`, `…/jobs[/:jobId]`, `/sign-in`, `/mfa`, `/select-tenant` | UX-001-S10 |
| URL-state schema `apps/web/src/state/url-schema.ts` (zod) | `org`, `acct[]`, `from`/`to` (UTC dates, half-open `to`), `preset` (7\|30\|60\|90\|180\|365), `grain`, `cmp` (prev\|yoy\|custom + `cmpFrom`/`cmpTo`), `cur`, `mat` (all\|final\|reconciled), `dims[]` ≤ 4, `f` (base64url JSON filter AST ≤ 2 KB), `sort`, `topN`, `pub`, `view` (saved view id), `tab`. Parsing rules: unknown params dropped, invalid values reset to defaults with one notice, never widened beyond authorization | UX-002-S05 |
| Query-key factory spec | `['t',tenantId,'p',profileHash,'e',membershipEpoch,'pub',publicationId\|'latest',kind,requestHash]`; invalidation rules (epoch bump, tenant switch, publication refresh); placeholder rules | UX-002-S04 |
| Screen-contract template `docs/10-frontend/screen-contracts/_template.md` | Screen ID, route, persona, capabilities per action, data bindings (metric@version / records dataset / entity endpoint / control-plane endpoint), columns (id, type, sort key, i18n key), empty/filtered/partial/denied/stale copy keys, drilldowns (target route + carried params), exports, oracle with fixture values, a11y notes, mobile behavior | UX-001-S15 (template); each page task S01 |
| Money/number/date formatting spec `apps/web/src/format/README.md` | MoneyString branding, NullReason rendering ("—" + reason text + info tooltip), currency minor units from the server, compact axis notation, percentage (server ratio string → `style:'percent'`), durations, bytes (binary TB vs TiB decision: Snowflake bills TB = 2^40? → TO VERIFY LIVE with FIN-006; label exactly), UTC suffix | UX-001-S04 |
| i18n conventions | Key naming `domain.screen.element`, ICU plural/select usage, no concatenation, server message keys, pseudo-locale | UX-001-S03 |
| Component inventory (production) | Mapping of COMPONENTS.md contracts to shadcn/ui primitives and Bridge components (§3.2 reuse matrix) | UX-001-S01 |
| Budgets file `apps/web/.size-limit.json` + performance SLOs | Per G-UX-13 | UX-001-S12 |
| Accessibility test matrix | Routes × (axe, keyboard path, 200 % zoom, 390 px, SR checklist family) | UX-008-S01 |
| MSW handlers from OpenAPI examples | One handler per operation with state variants (ready, empty, partial, stale, denied, 422, 429, 503, slow 10 s) | UX-002-S01 |

### 3.1 Screen → owning task (87 screens)

| Screen IDs (SCREEN_INDEX) | Production route (under `/t/:tenant`) | Owner task | Release | Note |
|---|---|---|---|---|
| home | /home | UX-003 | R1 | |
| dashboards, dashboard-builder | /dashboards, /dashboards/:id/edit | **UX-101 (new)**; CTL-007 persists only | R2 | R1: nav item lists saved views (UX-004-S08) |
| explorer | /explore/cost | UX-004 | R1 | |
| ledger, services | /explore/cost/ledger, /explore/cost/services | UX-004 (added S10/S11) | R1 | previously unowned |
| warehouses, warehouse-detail, warehouse-performance | /explore/warehouses[/:id[/performance]] | UX-005 | R1 | |
| queries, query-executions, query-detail | /explore/queries[/executions], /explore/queries/:accountId/:queryId | UX-005 | R1 | needs API-104, WRK-104 |
| workloads, ad-hoc | /explore/workloads, /explore/workloads/ad-hoc | **WRK-102 (new)** | R1 | previously claimed by WRK-004 |
| dbt, dbt-project, dbt-invocation, dbt-model | /explore/workloads/dbt/… | WRK-002 | R1 | |
| power-bi, power-bi-activity | /explore/workloads/powerbi/… | WRK-003 | R1* | D-20 |
| pipelines, pipeline-detail, procedures, dynamic-tables | /explore/workloads/{pipelines,procedures,dynamic-tables}/… | WRK-004 | R1 | |
| native-apps, custom-apps | /explore/workloads/{native-apps,custom-apps} | **WRK-105 (new)** | R2 | |
| storage, storage-detail, serverless, serverless-detail | /explore/storage/…, /explore/serverless/… | UX-006 | R1 | |
| ai, ai-family, ai-execution, ai-search, ai-analyst | /explore/ai/… | UX-007 | R1* | D-20 |
| spcs, spcs-pool, spcs-service | /explore/spcs/… | UX-007 | R1* | D-20 |
| tags, tag-rule, tag-preview | /allocate/tags, /allocate/tags/rules/:id, /allocate/tags/preview/:simId | ALC-001, ALC-003 | R1 | |
| allocation, allocation-rule, allocation-preview | /allocate/allocation/… | ALC-006 | R1 | |
| usage-groups, usage-group-detail | /allocate/usage-groups/… | ALC-004 | R1 | |
| showback, showback-team | /allocate/showback/… | ALC-007 | R1 | |
| chargeback, statement | /allocate/chargeback/…, /statements/:id | ALC-008 | R1 | |
| reconciliation, reconciliation-detail | /govern/reconciliation[/:periodId] | FIN-009, FIN-010 | R1 | + close/reference screens (G-FIN-21) |
| budgets, budget-detail, budget-new | /govern/budgets/… | GOV-001 | R1 | |
| forecast | /govern/budgets/:id/forecast | GOV-002 | R1 | |
| monitors, incident / monitor-new | /govern/monitors/…, /govern/incidents/:id / /govern/monitors/new | GOV-008 / GOV-003 | R1 | |
| reports, report-history / report-builder / report-schedule | /govern/reports/… | RPT-005 / RPT-001 / RPT-004 | R1 | |
| insights, insight-detail | /optimize/insights[/:id] | **INS-001 (recommended owner)** | R1 | 4 detector tasks share the entry, and none owns the UI |
| actions, action-detail | /optimize/actions/… | INS-006 | R1 | |
| savings, savings-detail | /optimize/savings/… | INS-007 | R1 | |
| data-health, source-detail, sync-history | /platform/data-health/… | ING-012 **UX part (split)** | R1 | hot path R2 (D-24) |
| integrations, connection-detail | /platform/integrations[/:connectionId] | **UX-103 (new)** | R1 | CON-004/005/006 APIs |
| onboarding | /onboarding | ONB-001 (+CON-006 wizard) | R1 | |
| settings | /settings/workspace | **UX-102 (new)** | R1 | |
| settings-people | /settings/members | CTL-003 | R1 | |
| settings-roles | /settings/roles | **UX-102 (new)** | R1 | PRD role names (G-SEC-04) |
| settings-organizations | /settings/organizations | CON-004 | R1 | |
| settings-security | /settings/security | SEC-002 (MFA policy), SEC-003 (SSO) | R1 / R1* | |
| settings-audit | /settings/audit | **UX-102 (new)** on SEC-008 API | R1 | D-25 |
| settings-privacy | /settings/privacy | **UX-102 (new)** on SEC-007/OPS-005 APIs | R1 | D-10 |
| settings-notifications | /settings/notifications | GOV-006 | R1 | |
| settings-billing | /settings/billing | LCH-001 | R1 | |
| support | /support | **UX-102 (new)** | R1 | |
| sign-in, mfa | /sign-in, /mfa | SEC-002 | R1 | unauthenticated layout (G-UX-03) |

Screens required by tasks but absent from the catalog (design additions §3.3): `/settings/api-clients` (API-006-S09), `/settings/pricing` (FIN-002), reconciliation close and references (FIN-010/FIN-101), `/jobs` + job detail and exports list (UX-104), Explain drawer (UX-104; overlay, not a route), `/select-tenant`, `/govern/reports/templates` (RPT-003).

### 3.2 Prototype reuse matrix

| Prototype part | Verdict | Production use |
|---|---|---|
| `styles/tokens.css` | Reuse (port) | Tailwind v4 theme variables after the contrast audit (G-UX-12) |
| `styles/app.css` (2,010 lines) | Discard | Rebuilt on shadcn/ui + Tailwind utilities |
| `components/AppShell.tsx` | Reuse layout ideas only | Rebuilt with the authorized navigation manifest, tenant switcher, router |
| `components/ui.tsx` (Button, Badge, Overlay, Panel, StateBlock, LocalForm) | Reuse behavior specs, discard code | shadcn/ui primitives; StateBlock states kept; LocalForm replaced by typed forms (react-hook-form + zod from OpenAPI) |
| `components/MetricStrip.tsx` | Reuse composition | MetricTile bound to API meta/null reasons |
| `components/DataTable.tsx` (client-side paging/sorting) | Partially reuse | Column visibility/density UX kept; manual (server) pagination/sorting; export via API-102 |
| `components/Charts.tsx` | Reuse "View data" pattern | Series from API rows only; locale formatting; negative axis |
| `data/financial.ts`, `data/catalog.ts` | **Must not be copied** (G-UX-07) | Arithmetic moves to FIN/ALC/API; fixture numbers move to FND-004 golden fixtures |
| `catalog/screens.json`, `catalog/metrics.json` | Reuse as test/story fixtures only | Storybook stories and screen-contract checklists; not runtime |
| `app/navigation.ts` (hash routing) | Discard | TanStack Router with typed search params |
| `app/App.tsx` (one generic PageContent for all routes) | Discard | One module per screen contract |
| `tests/e2e/*.spec.ts` (Playwright + axe) | Reuse approach and harness | Extended to all routes, personas and live staging (UX-008) |
| `bridge-design:` localStorage drafts | Discard | Server drafts via CTL APIs; no business data in localStorage |

### 3.3 Design additions required (screen contracts to author)

| Addition | Minimum content | Owner |
|---|---|---|
| API clients | list, create (capabilities, profile, expiry), one-time secret reveal, rotate, revoke, last used, recent 429s | API-006-S09 |
| Pricing / rate sheets | effective-dated rates, source (billed vs contract vs customer-approved), ambiguity/missing states | FIN-002 (G-FIN-21) |
| Reconciliation close & references | close checklist with required controls, maker-checker, statement upload/manual entry | FIN-010, FIN-101 |
| Jobs & exports center | list of analysis jobs/exports with status, progress, cancel, open result, download, expiry | UX-104 |
| Explain drawer | lazy tree, remainder/restricted/unavailable nodes, copy reference, export evidence | UX-104 |
| Integration Health additions | D-08 customer warehouse credits (actual vs quota), D-09 egress IPs to allowlist, per-warehouse MONITOR grant gaps (WRK.md G-WRK-09), capability matrix per source | UX-103 |
| Retention-tier states | "Query-level detail is kept 90 days; showing daily family aggregates (≈ approximate percentiles)" | UX-005 |
| Metric substitution banner | "Grouped by warehouse: amounts are attributed components of billed spend; unattributed shown as its own row" | UX-004 |
| Tenant chooser | `/select-tenant` for multi-tenant users, no counts of foreign tenant data | UX-002 |
| Publication refresh banner | "Newer data available (as of …)" + Refresh | UX-002 |

## 4. Revised production backlog

### UX-001 — Design system, application shell and frontend platform
Release: R1 · Estimate: 42–58 h · Risk: M · Decisions: D-18, D-25 · Closes: G-UX-02 (route map), G-UX-03 (template), G-UX-07 (lint), G-UX-08, G-UX-09, G-UX-12, G-UX-13
Dependency changes: `+FND-002` (pin shadcn/ui, Tailwind v4, TanStack Router/Query/Table, Recharts, FormatJS, size-limit). Keep `FND-003`. Starts day 1 (lane D).

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| UX-001-S01 | Record the design-system decision (shadcn/ui + Tailwind v4 + Radix; Recharts 3; TanStack Table v8; TanStack Router; FormatJS) as an ADR-013 amendment and write the component inventory mapping COMPONENTS.md contracts → primitives | `docs/architecture/adr/ADR-013` amendment (via ADR process), `apps/web/src/design_system/INVENTORY.md` | Reviewed by UX + FE lead; versions pinned in FND-002 lockfile | 2 |
| UX-001-S02 | Port tokens to Tailwind theme variables; write a contrast audit script over all declared fg/bg pairs and chart palette entries (text ≥ 4.5:1, non-text ≥ 3:1); fix amber usages (outline `#B45309`, selected-nav bar `#92400E`) | `apps/web/src/design_system/tokens.css`, `tools/contrast-audit.ts` | Script passes in CI; #F59E0B as text/1px graphic on white is rejected (2.15:1) | 3 |
| UX-001-S03 | Set up i18n: FormatJS provider, `en` catalog, pseudo-locale `en-XA`, lint `formatjs/no-literal-string-in-jsx`, message extraction in CI | `apps/web/src/i18n/`, ESLint config | A literal JSX string fails CI; the `en-XA` build renders without clipping in stories | 4 |
| UX-001-S04 | Build the formatting library: MoneyString brand, `formatMoney(str, currency, locale)` using string input, `signDisplay:'negative'`, compact axis formatter, percent from ratio string, bytes, durations, UTC dates; NullValue component ("—" + reason label + tooltip) | `apps/web/src/format/*`, tests | `"-0.004"` USD → "$0.00" (not "-$0.00"); `"12345678901234567.89"` formats without precision loss; every NullReason has a message key | 3 |
| UX-001-S05 | Build primitives on shadcn/ui: Button, IconButton, Badge (4 vocabularies: maturity, reconciliation, close, quality — separate components so they cannot be merged), Panel, Tabs, Dialog, Drawer (480 px/full-width mobile), Tooltip (focusable trigger), Toast, Skeleton (geometry-preserving), StateBlock (loading, empty-confirmed, filtered-empty, partial, stale, error, denied, success) | `apps/web/src/design_system/components/*` | Stories for every state; the Badge prop type makes mixing vocabularies a type error | 5 |
| UX-001-S06 | Build MetricTile (label key, value or NullValue, unit/basis, maturity badge, as-of, Explain slot) with no arithmetic props | component + stories | Type test: passing a `number` as a money value fails compilation | 2 |
| UX-001-S07 | Build the DataTable wrapper (TanStack Table v8 manual pagination/sorting/filtering, column visibility, density, sticky first column, `aria-sort`, scroll region `role=region` + `aria-label` + `tabIndex=0`, load-more keyset control, totals row from props) | component + stories | Keyboard: tab into the region, arrow-scroll, sort with Enter; 390 px page body never overflows | 4 |
| UX-001-S08 | Build ChartContainer (Recharts with `accessibilityLayer`, mandatory View-data table from the same rows, negative-value axis, direct labels/patterns so color is never the only encoding, reduced motion) | component + stories | Axe clean; the View-data table equals chart points; a negative rebate renders below zero | 4 |
| UX-001-S09 | Build AppShell: authorized nav manifest (typed, filtered by capabilities), PRD §143 grouping (Dashboards top-level), breadcrumbs, skip link, single h1 slot, mobile modal nav, tenant switcher slot, page search slot; unauthenticated layout for `/sign-in`, `/mfa` (no scope bar/export/Explain) | `apps/web/src/layout/*` | Playwright: nav reflects the capability fixture; sign-in layout contains no scope bar or CSV control | 4 |
| UX-001-S10 | Implement the router skeleton from the route map with lazy route chunks, typed params (opaque UUIDs validated), 404 and retired-entity pages | `apps/web/src/routes/*` | Every screen ID in §3.1 resolves to a placeholder route; an invalid UUID param → 404 page without an API call | 3 |
| UX-001-S11 | Error boundaries: route-level and panel-level with request_id display and retry; client telemetry hook (web-vitals, error class, request_id; no values/names) | `apps/web/src/platform/errors.tsx`, `telemetry.ts` | A throwing panel story shows the panel error while siblings render; the telemetry payload scan finds no digits from money fixtures | 3 |
| UX-001-S12 | Bundle budgets with size-limit (initial ≤ 200 KB gz, route ≤ 120 KB gz, charts lazy) in CI | `.size-limit.json`, CI job | An oversized import fails CI | 2 |
| UX-001-S13 | Custom ESLint rules: `bridge/no-money-arithmetic`, `bridge/no-prototype-import`, `bridge/registry-metric-exists` (checks metric ids against the generated registry) | `tools/eslint-plugin-bridge/` | Rule tests: `Number(money)`, `a.value + b.value` on MoneyString and `import 'prototypes/…'` fail | 3 |
| UX-001-S14 | CSP-compatible build: no inline scripts; document the required CSP (`script-src 'self'`; style policy compatible with Radix/Recharts inline styles — decide nonce vs `'unsafe-inline'` for styles, recorded in SEC); SPA fallback requirement for INF-006 | `docs/10-frontend/csp.md` | App runs under the documented CSP in staging with zero CSP violations reported | 2 |
| UX-001-S15 | Author the screen-contract template and fill it for the shell screens | `docs/10-frontend/screen-contracts/_template.md` | Template reviewed by UX, FE, API owners | 1 |
| UX-001-S16 | Storybook test-runner with axe for all components × states × (1280, 390, 200 % zoom); visual baselines | CI job | Zero critical axe violations; baselines committed | 3 |

Task acceptance:
- [ ] Every core component works by keyboard, and the Dialog/Drawer trap focus and restore it to the trigger.
- [ ] No primary action is clipped at 390 px or 200 % zoom. Maturity, reconciliation and close badges are text, never color only.
- [ ] Literal UI strings, money arithmetic and prototype imports are all blocked by lint.
- [ ] The contrast audit passes for all tokens and chart colors. Bundle budgets are enforced.
- [ ] The sign-in/MFA layout exposes no scope, KPI or export control.

### UX-002 — Authenticated scope state, data layer and semantic query components
Release: R1 · Estimate: 44–60 h · Risk: H · Decisions: D-18 · Closes: G-UX-05, G-UX-06, G-UX-07 (data side), G-API-13 (client side)
Dependency changes: `API-003` → build against `API-003-S01` (OpenAPI) + MSW; live `API-003`/`API-101` for the staging gate only. `+SEC-002` (BFF session), `+API-001` (generated registry types), `+API-104` (scope-bar options). Keep `UX-001`, `SEC-006`.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| UX-002-S01 | Generate the typed client from OpenAPI (openapi-typescript + openapi-fetch) and MSW handlers with state variants from the OpenAPI examples; CI drift check | `apps/web/src/api/generated/*`, `apps/web/src/mocks/*` | Changing an OpenAPI schema without regenerating fails CI; MSW serves ready/empty/partial/stale/denied/422/429/503/slow variants | 3 |
| UX-002-S02 | Fetch wrapper: cookie credentials, CSRF header on mutations, `X-Bridge-Tenant`, AbortSignal, problem+json → typed errors with request_id, 401 → re-auth preserving URL, `meta.tenant_id` assertion (TenantMismatchError), If-None-Match with stored ETag | `apps/web/src/api/client.ts` | Unit tests: a mismatching `meta.tenant_id` never reaches the cache; 304 keeps the stored data | 3 |
| UX-002-S03 | Tenant context: `/t/:tenantSlug` resolution, `/select-tenant`, `GET /v1/me/context` bootstrap, tenant switch (cancelQueries → clear → navigate), BroadcastChannel `bridge-session` (logout, epoch bump) | `apps/web/src/state/tenant.tsx` | Two-tab Playwright test: logout in tab 2 clears tab 1 within 1 s; switching tenant in tab 2 does not change tab 1's tenant | 4 |
| UX-002-S04 | Query-key factory and invalidation (epoch bump → remove tenant keys + refetch context; publication refresh; tenant switch); placeholder rules (G-UX-05 point 7) | `apps/web/src/state/queryKeys.ts` | Unit tests of the key factory; a scope change never shows previous-scope values (DOM assertion) | 3 |
| UX-002-S05 | URL-state schema and parser (zod) with safe correction, history push/replace policy (filters push, typing debounced replace), scroll restoration on Back | `apps/web/src/state/url-schema.ts` | Restoring an invalid saved URL shows one "adjusted" notice and valid defaults; Back restores filters and scroll position | 4 |
| UX-002-S06 | Scope bar: organization/account pickers (API-104 dimension values, authorized only, no counts), UTC presets constrained by `history_days` entitlement and coverage, exact range picker (half-open), comparison selector with completeness hint, currency selector (currencies present; no FX), maturity filter | `apps/web/src/components/scope/*` | Restricted viewer sees only authorized accounts; a preset longer than history is disabled with a reason; reset never broadens authorization | 5 |
| UX-002-S07 | Semantic hooks: `useSemanticQuery`, `useSemanticBatch`, `useRecords`, `useEntity`; page-level publication pin context | `apps/web/src/components/analytics/hooks.ts` | All tiles on a page carry the pinned publication in their requests (network assertion) | 4 |
| UX-002-S08 | Publication change banner (visibility-aware 60 s poll of `/v1/publications/current`) and atomic refresh; render guard on `meta.publication_id` | component + hook | Injecting a new publication mid-page shows the banner; Refresh swaps all tiles together; a forced mixed response shows the stale state, never mixed numbers | 3 |
| UX-002-S09 | ResponseStateBoundary: maps pending/problem codes/meta to StateBlock (empty-confirmed vs filtered-empty vs unavailable via coverage; partial banner with missing sources + Data Health link; denied without names/counts) | component | Each MSW variant renders the right state; the denied state contains no numbers | 3 |
| UX-002-S10 | Totals/Other plumbing: tables and charts read `meta.totals`, the `__OTHER__` row and server deltas; currency-split rendering (one total per currency) | components | Chart total = table total incl. Other for the fixture (270 / 27,000); USD + EUR scope shows two totals, never a sum | 3 |
| UX-002-S11 | Async promotion: `QUERY_REQUIRES_ASYNC`/`QUERY_DEADLINE_EXCEEDED` → "Run as analysis" (creates a job via UX-104 flow with the same request) | component | The MSW 503 variant offers the job with the request preserved | 2 |
| UX-002-S12 | Race and revocation E2E (Playwright + MSW delays): A→B switch while A is pending 3 s (MutationObserver asserts no A value ever rendered); epoch bump mid-flight; revoked scope → denied state; stale cursor → restart notice | `tests/e2e/state/*.spec.ts` | All pass 20/20 runs (flake check) | 4 |
| UX-002-S13 | Saved-view integration primitives (serialize URL state + metric versions → CTL-007 request; open with migration banner if `needs_review`) | `apps/web/src/state/savedViews.ts` | Opening a view whose metric is deprecated shows the banner and the replacement | 2 |
| UX-002-S14 | Frontend data-layer contract doc (rules above) for all page tasks | `docs/10-frontend/data-layer.md` | Reviewed by API and page-task owners | 1 |

Task acceptance:
- [ ] A tenant switch, a logout in another tab and a mid-flight epoch bump never render the previous tenant's or scope's values.
- [ ] All tiles on a page show the same publication, and a new publication appears only after an explicit refresh.
- [ ] Invalid or unauthorized URL state is corrected safely without widening scope or revealing hidden entities.
- [ ] The UI performs no money arithmetic: totals, Other and deltas come from the server.

### UX-003 — Home and executive drivers
Release: R1 · Estimate: 24–34 h · Risk: M · Decisions: D-15, D-20 · Closes: G-UX-03 (Home contract), G-UX-06 (batch)
Dependency changes: `−FIN-009` for build (MSW), kept with `API-101` for the staging gate; `+API-001`; module tiles depend on capability flags, not on GOV/INS tasks being done.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| UX-003-S01 | Write the Home screen contract: tiles → `spend`, `forecast_total`, `budget_amount`, `potential_savings`, `realized_savings` (YTD), `allocation_coverage`; counts of budget risks/anomalies/insights from GOV/INS summary endpoints; one `analytics/batch` | `docs/10-frontend/screen-contracts/home.md` | Reviewed; every binding exists in the registry/OpenAPI | 2 |
| UX-003-S02 | KPI ribbon with capability states ("Budgets not set up" + CTA; module not enabled) — never 0 for absent modules | `apps/web/src/pages/home/Kpis.tsx` | No budget → "No budget" state, not $0 | 3 |
| UX-003-S03 | Spend-over-time chart (daily, signed) with View data | component | Series sum = spend tile (server totals) | 2 |
| UX-003-S04 | Drivers panel: server-computed movers between complete equivalent periods; new spend; PARTIAL_CURRENT label | component | Partial current month is labelled and never compared to a full month without the label | 3 |
| UX-003-S05 | Attention list: reconciliation failures, budget risks, open anomalies, unallocated spend — capped 5 each with "view all" | component | Each item links to its route with scope carried | 3 |
| UX-003-S06 | Ownership snapshot for the selected allocation book ("applies to X of Y") | component | Warehouse book fixture shows Finance 12,000 / Marketing 8,000 labelled "of 20,000 warehouse compute" | 2 |
| UX-003-S07 | Savings tiles: potential (estimate) and realized (verified) separate; never summed | component | DOM contains no sum of both | 1 |
| UX-003-S08 | New-tenant first-value state (links to ONB-001 steps) | component | Tenant without publication shows onboarding steps, not zeros | 2 |
| UX-003-S09 | Tests: fixture 270/27,000 equals ledger; absent forecast → "—" + INSUFFICIENT_HISTORY; restricted viewer (Finance+A1) sees authorized drivers only; all tiles share the publication | `tests/spec/UX-003/*` | All pass on MSW and on staging | 3 |
| UX-003-S10 | Mobile/a11y/screenshots (1280, 390, 200 %) | evidence | Axe clean; screenshots reviewed | 2 |

Task acceptance:
- [ ] The Home spend equals the ledger for the fixture, and all tiles carry one publication.
- [ ] An absent forecast or budget renders a state, never 0. Estimated savings never appear as realized.
- [ ] A restricted viewer sees only authorized drivers and attention items.

### UX-004 — Cost Explorer, billing ledger, services and saved analyses
Release: R1 · Estimate: 48–66 h · Risk: H · Decisions: D-12, D-18 · Closes: G-UX-01 (ledger/services), G-API-02 (UI side)
Dependency changes: `−UX-003` (independent page), `−API-005` (Explain via UX-104), `+API-001`, `+API-104`, `+API-102` (export). Keep `CTL-007`.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| UX-004-S01 | Write the screen contracts for explorer, ledger and services (bindings, columns, compatible dims from `GET /v1/metrics`) | `screen-contracts/explorer.md`, `ledger.md`, `services.md` | Reviewed with API owner | 3 |
| UX-004-S02 | Explorer state: metric picker (compatible only), group-by ≤ 4 from the compatibility matrix (incompatible options disabled with reason), filter builder (registry ops), grain, compare, top-N — URL-encoded | `apps/web/src/pages/explore/cost/state.ts` | Selecting query_compute_cost disables "database" with the reason text from the API | 4 |
| UX-004-S03 | KPI ribbon for the explorer scope | component | Values equal `meta.totals` | 2 |
| UX-004-S04 | Trend chart stacked by the first dimension with Other; negative adjustments below axis | component | Rebate −3 (−300 UI fixture) renders below zero | 3 |
| UX-004-S05 | Contribution waterfall from server deltas (+new, +disappeared, Other) | component | Sum of bars = server total delta | 3 |
| UX-004-S06 | Pivot table: server grouping, keyset load-more, column selection, totals row, metric-substitution banner and unattributed row styling | component | Spend by warehouse shows the banner and the unattributed row; total equals spend by service | 5 |
| UX-004-S07 | Currency separation and maturity filter display | component | Multi-currency fixture shows per-currency totals | 2 |
| UX-004-S08 | Saved analyses: save/load/rename/share (CTL-007), migration banner, sharing never grants data access (a shared view opened by a restricted user shows only their scope); Dashboards nav in R1 lists saved views | pages + hooks | A view shared by the owner and opened by Finance-only shows Finance rows only | 4 |
| UX-004-S09 | Drill navigation with breadcrumbs: organization→account→service→resource→workload→query; unsupported next level disabled with reason; filters carried | component | Back returns to the prior level with filters and scroll | 3 |
| UX-004-S10 | Billing ledger page on the `billing_ledger` records dataset (D-12 bucket grain): usage date, scope kind, account, service type, rating/billing type, currency, signed amount, price basis, maturity, reconciliation status; org rows only with the org grant | `pages/explore/cost/ledger` | Account-limited viewer total 26,800 (UI fixture); owner sees 27,000 incl. org support 500 / rebate −300 | 4 |
| UX-004-S11 | Services page: service → sub-service drill with native units where the registry provides them | `pages/explore/cost/services` | Serverless 1,800 = 700 + 500 + 200 + 200 + 200 shown once | 3 |
| UX-004-S12 | Export actions (CSV via API-102; large → job) | component | Export equals the table for the same publication | 1 |
| UX-004-S13 | High-cardinality path: group by query hash over 365 days → async job via UX-104 | flow | The job result opens in the same explorer layout | 2 |
| UX-004-S14 | Tests: every supported grouping conserves 270/27,000 (service; account + Organization bucket 200; warehouse with unattributed); USD+EUR never combined; pivot change does not change the total; Other for a restricted profile contains only authorized data (Other = visible total − shown rows) | `tests/spec/UX-004/*` | All pass on MSW and staging | 5 |
| UX-004-S15 | Mobile/a11y/screenshots | evidence | Axe clean; 390 px pivot scrolls within its region | 2 |

Task acceptance:
- [ ] Every supported grouping conserves the fixture total, and resource groupings show the substitution banner and the unattributed row.
- [ ] Currencies are never combined. Pivot changes never change the total.
- [ ] Ledger and services pages exist with bucket-grain semantics and org-scope protection.
- [ ] Saved analyses reopen with metric-version migration handling, and sharing never widens data access.

### UX-005 — Warehouse and query deep dives
Release: R1 · Estimate: 38–52 h · Risk: M · Decisions: D-11, D-14, D-20 · Closes: G-UX-04 (p95 labels), G-UX-10 (retention states)
Dependency changes: `−UX-004`, `+UX-002`, `+API-104`, `+WRK-104` (retention tiers), `+FIN-003` (classic); `FIN-004` only if Adaptive is R1* (D-20). Keep the live gate on `API-101`.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| UX-005-S01 | Screen contracts for warehouses, warehouse-detail, warehouse-performance, queries, query-executions, query-detail | contracts | Reviewed | 3 |
| UX-005-S02 | Warehouse list: attributed spend, warehouse_credits, query compute, idle, type/size, utilization (UNSUPPORTED "—") | page | Adaptive rows show idle "—" + CAPABILITY_UNSUPPORTED | 3 |
| UX-005-S03 | Warehouse detail tabs in order cost → attribution/idle → workloads → performance → evidence, type-aware KPIs (classic idle, Adaptive query-hour, QAS) | page | Fixture 200 = 140 + 60 shown as decomposition, not addition | 4 |
| UX-005-S04 | Performance page: queue time, `query_elapsed_p95` and `query_execution_p95` labelled distinctly, spill (capability-gated), failures | page | Labels match registry populations; percentiles never averaged (tier label shown) | 3 |
| UX-005-S05 | Queries overview on family aggregates with tier indicator ("≈" in AGGREGATE tier) | page | 180-day range shows the aggregate-tier label | 3 |
| UX-005-S06 | Execution explorer on `query_executions` records (hot tier; ≤ 31 d sync else job), PRD §76 columns available by capability | page | 45-day request becomes a job; columns without capability are hidden with an explanation | 4 |
| UX-005-S07 | Query detail `/explore/queries/:accountId/:queryId`: compute component scope note, timing breakdown, hash + version, workload, parent/root links, sanitized SQL per privacy mode/capability, per-hour proration (D-14) | page | q_demo_042 shows 0.4 + 0.2 + 11.8 = 12.4 s; METADATA_ONLY tenant shows no SQL with the reason | 4 |
| UX-005-S08 | Retention states: query older than hot tier → "kept 90 days" state linking to family aggregates; operator evidence link only within 14 days (WRK-103, R2 feature-flag) | components | 100-day-old query URL shows the retention state, not 404 | 2 |
| UX-005-S09 | Drill: warehouse → workload/hash → query with scope carried; export | flows | Back restores each level | 2 |
| UX-005-S10 | Tests: missing QAH shows unattributed, never free; metadata-only query shows no compute with reason; parent/child procedure queries not double-counted (parent total = Σ distinct children); long query spanning 3 hours shows proration rows summing to its compute | `tests/spec/UX-005/*` | All pass | 4 |
| UX-005-S11 | Mobile/a11y/screenshots | evidence | Wide execution table scrolls in its region at 390 px | 2 |

Task acceptance:
- [ ] Warehouse 200 = query 140 + idle 60 is displayed as a decomposition. Adaptive idle is unavailable with a reason.
- [ ] Query cost is labelled as excluding cloud services and idle. Elapsed and execution percentiles are distinct.
- [ ] Retention-tier and privacy states are explicit. There are no 404s for expired detail.

### UX-006 — Storage and serverless resource views
Release: R1 · Estimate: 26–38 h · Risk: M · Decisions: D-12 · Closes: G-UX-11
Dependency changes: `−UX-004`, `+UX-002`, `+API-104`; keep `FIN-006`; `FIN-007` narrowed to the R1 serverless services (FIN.md).

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| UX-006-S01 | Screen contracts for storage, storage-detail, serverless, serverless-detail (fix the fixture basis per G-UX-11) | contracts | Reviewed with FIN-006 owner | 2 |
| UX-006-S02 | Storage overview: billed storage trend (`spend` service=storage) separate from byte gauges (`storage_bytes` latest/twa by class) with explicit axis labels | page | No UI computation links bytes to money | 3 |
| UX-006-S03 | Database detail: `attributed_cost` by database (FIN-006 basis) + byte composition (active, time travel, fail-safe, retained-for-clone) + retention settings | page | 840/360 displayed as returned; composition classes sum to the displayed total bytes | 3 |
| UX-006-S04 | Pre-enrollment and dropped objects: "history starts at first observation" state; dropped tables keep cost | components | Dropped database shows its month-to-date cost with a "dropped" badge | 2 |
| UX-006-S05 | Serverless overview per service with native units (tasks, pipes, clustering, search optimization, MV, QAS) and the summary-metering reference labelled "reference, not additive" | page | 1,800 appears once; the summary metering row is not summed | 3 |
| UX-006-S06 | Service detail per resource (pipe, task, table) with history; hidden pipes and unresolved resources as "Unresolved resource" rows | page | Hidden/null resource spend remains visible | 3 |
| UX-006-S07 | Capability panels for services not enabled or not supported | components | Missing permission shows "not visible with current grants", never 0 | 2 |
| UX-006-S08 | Tests: storage 12 (1,200 UI) not derived from bytes; serverless 18 = 5+7+2+2+2; negative credits (adjustments) render; missing detail source shows top-line spend with a limited-detail notice | `tests/spec/UX-006/*` | All pass | 3 |
| UX-006-S09 | Mobile/a11y/screenshots | evidence | Axe clean | 2 |

Task acceptance:
- [ ] Billed storage and bytes are never derived from each other in the UI.
- [ ] Serverless totals appear once, and summary metering is shown as a reference.
- [ ] Unresolved or hidden resources keep their spend visible.

### UX-007 — AI/Cortex and SPCS analytical experiences
Release: R1* (D-20) else R2 · Estimate: 28–40 h · Risk: M · Decisions: D-20 · Closes: —
Dependency changes: `−UX-004`, `+UX-002`, `+API-104`; keep `FIN-018`, `FIN-019`.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| UX-007-S01 | Screen contracts for ai, ai-family, ai-execution, ai-search, ai-analyst, spcs, spcs-pool, spcs-service (bindings to R1* registry metrics, capability flags per family) | contracts | Reviewed with FIN-018/019 owners | 3 |
| UX-007-S02 | AI overview: family spend (billed), native units per family (tokens only where emitted), coverage | page | Families without token units show "—" + CAPABILITY_UNSUPPORTED | 3 |
| UX-007-S03 | Family pages (functions, search, analyst, agents where available) with model/function dims | pages | Function cost 400 + search 150 + analyst 50 = 600 shown once | 4 |
| UX-007-S04 | AI execution detail: parent request cost with child components and residual (10 = 4 + 6) | page | The parent total is not 14; children are labelled as components | 3 |
| UX-007-S05 | Retired-source cutover display (source switch date, gap) | component | Cutover fixture shows the gap with a reason | 2 |
| UX-007-S06 | SPCS overview, pool detail (billed once per pool), service allocation within pool (500 + 300 = 800), utilization only with measured telemetry | pages | 800 remains 800 across pool/service views; utilization "—" when not measured | 5 |
| UX-007-S07 | Deleted app/service handling and exclusive/shared pool labels | components | Deleted service keeps its history | 2 |
| UX-007-S08 | Tests from the task oracle + restricted viewer | `tests/spec/UX-007/*` | All pass | 3 |
| UX-007-S09 | Mobile/a11y/screenshots | evidence | Axe clean | 2 |

Task acceptance:
- [ ] The AI parent total is 10, never 14. SPCS 800 is identical across pool and service views.
- [ ] CPU utilization is never inferred from credits. Retired sources show explicit gaps.

### UX-008 — End-to-end product-state, accessibility and navigation qualification
Release: R1 · Estimate: 38–52 h · Risk: M · Decisions: D-18, D-25 · Closes: G-UX-12 (coverage), G-UX-13 (perf evidence)
Dependency changes: `+UX-102`, `+UX-103`, `+UX-104`, `+WRK-002`, `+WRK-004`, `+GOV-008` (inverted edge, GOV backlog), and per RECONCILIATION C-29 `+UX-003`, `+UX-004`, `+WRK-005`, `+WRK-102`, `+ALC-007`, `+INS-101` (UX-008 qualifies all R1 routes; UX-005/006 no longer depend on UX-004); keep UX-005, UX-006; `UX-007` only if R1*.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| UX-008-S01 | Generate the scenario matrix from the route map: route × persona (owner, FinOps admin, Finance+A1 viewer, auditor, foreign tenant) × state (ready, loading, empty-confirmed, filtered-empty, partial, stale, error, denied) | `tests/e2e/matrix.ts`, `docs/ux/acceptance.md` | Matrix covers all R1 routes; generated, not hand-listed | 3 |
| UX-008-S02 | Staging personas and fixture tenants (A/B) with Cognito test users (SEC-002) and a dedicated synthetic publication | fixtures | Personas log in via the real flow in CI | 3 |
| UX-008-S03 | Numeric agreement suite: KPI = chart total = table total incl. Other = CSV export = Explain root for 20 bindings at one publication | `tests/e2e/numbers.spec.ts` | Zero discrepancies; any discrepancy is logged as release-blocking | 5 |
| UX-008-S04 | Isolation suite: foreign tenant IDs in URLs, autocomplete probing, shared saved view from another tenant, export link reuse by another user | `tests/e2e/isolation.spec.ts` | No foreign names, counts or totals in DOM, network or downloads | 4 |
| UX-008-S05 | Fault injection: slow API (10 s), 503, partial coverage, revocation mid-session, publication change mid-page, network loss during a mutation (draft preserved, idempotent retry) | `tests/e2e/faults.spec.ts` | Every fault renders its documented state; no transient zeros (MutationObserver) | 5 |
| UX-008-S06 | Axe on all R1 routes × (1280, 390) in CI; zero critical/serious | CI job | Report archived | 3 |
| UX-008-S07 | Manual assistive-technology review: NVDA+Firefox and VoiceOver+Safari over 10 page families (shell, table, chart+View data, dialog/drawer, form, wizard, Explain tree, statement, incident timeline, settings) | `docs/evidence/UX-008/<commit>/at-review.md` | Checklist complete; blockers fixed or waived by owner | 5 |
| UX-008-S08 | 200 % zoom and 390 px checks on all R1 routes (automated overflow assertion + visual review sample) | tests + screenshots | No horizontal page overflow; no clipped primary action | 3 |
| UX-008-S09 | Performance: LCP p75, route-change latency, bundle report against budgets on staging | evidence | Targets met or tracked as release blockers | 3 |
| UX-008-S10 | Pseudo-locale run (`en-XA`) over R1 routes | screenshots | No clipped or overlapping text | 2 |
| UX-008-S11 | Evidence pack: screenshots linked to commit, matrix results, defect log | `docs/evidence/UX-008/<commit>/` | Reviewed by UX + QA | 2 |

Task acceptance:
- [ ] Every R1 page × persona × state case has automated evidence, and the numeric views agree at one publication.
- [ ] No foreign names, counts or totals appear anywhere, including exports.
- [ ] There are zero critical accessibility blockers after the manual AT review.
- [ ] Performance budgets are met on staging.

## 5. New tasks required

### UX-101 — Dashboards list and builder
Release: R2 · Estimate: 30–44 h · Risk: M · Decisions: D-17 · Closes: G-UX-01 (dashboards)
Dependency changes: new; depends on `UX-002`, `UX-004` (saved analyses), `CTL-007` (persistence), `API-102` (widget export R2), `RPT-103` (dashboard backend: definition as report layout kind, widget data API under the viewer's scope, sharing, export to report; RECONCILIATION U-01). UX-101 owns the dashboards list, builder UI and widget states; CTL-103 is merged into this task (U-01). Plugs after UX-004; not on the R1 path.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| UX-101-S01 | Screen contracts: dashboards list (owned/shared/private), builder (12-column grid, 1-column mobile) | contracts | Reviewed | 2 |
| UX-101-S02 | Widget model: 8 widget families (KPI, trend, breakdown, table, waterfall, budget, coverage, text) each = semantic request + presentation; validated against the registry (compatible dims only) | `apps/web/src/pages/dashboards/widgets/*` | An invalid widget config cannot be saved | 5 |
| UX-101-S03 | Grid editor (drag/resize with keyboard alternatives: move/resize via arrow keys + dialog) | component | Keyboard-only user can build a dashboard | 6 |
| UX-101-S04 | Dashboard-level scope/period with per-widget overrides; one publication per dashboard load (batch) | hooks | All widgets share the publication | 4 |
| UX-101-S05 | Sharing (tenant members; sharing never grants data access), optimistic concurrency (revision, 409 merge dialog) | flows | A concurrent edit shows a conflict, not an overwrite | 4 |
| UX-101-S06 | Stale/deprecated widget states (metric retired → migration prompt) | components | Retired metric widget shows guidance, not zeros | 2 |
| UX-101-S07 | Entitlement limits (D-17 quotas) | checks | Quota exceeded → explained state | 1 |
| UX-101-S08 | Tests (restricted viewer opening a shared dashboard sees only their scope; widget totals = explorer) + a11y/mobile | tests | All pass | 5 |

Task acceptance:
- [ ] Widgets are registry-validated, share one publication, and never widen data access when shared.
- [ ] The builder is fully keyboard-operable.

### UX-102 — Settings and administration pages (workspace, roles, audit, privacy, support)
Release: R1 · Estimate: 32–46 h · Risk: M · Decisions: D-10, D-25 · Closes: G-UX-01 (settings)
Dependency changes: new; depends on `UX-002`, `SEC-004` (capability matrix, G-SEC-04), `SEC-008` (audit query/export API), `SEC-007` (privacy-mode API), `CTL-003`. `OPS-005` is not a graph edge: only S05 needs OPS-005-S17's `/v1/privacy/requests` API (step-level, feature-flagged; RECONCILIATION C-29). Dependents: UX-008.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| UX-102-S01 | Screen contracts for settings/workspace, roles, audit, privacy, support using PRD role names (G-SEC-04) | contracts | Reviewed with SEC | 3 |
| UX-102-S02 | Workspace settings: tenant name/slug, default currency display, timezone label (UTC fixed), default period, retention plan summary (read-only) | page | Mutations use If-Match; stale revision → 409 dialog | 3 |
| UX-102-S03 | Roles & access scopes: role matrix (read-only from the capability matrix), member grants editor (role + scope clauses per SEC-101 grammar; every dimension explicit) with a "who can see what" preview | page | Omitting a scope dimension is impossible in the form (422 prevented client-side and server-side) | 6 |
| UX-102-S04 | Audit log viewer: filters (actor pseudonym/name per `people.read`, action, object, time), keyset paging, detail drawer with redacted before/after, restricted export (auditor capability) | page | Viewer without the audit capability gets the denied state; exports are audited | 5 |
| UX-102-S05 | Privacy & retention: privacy mode (FULL/SANITIZED/METADATA_ONLY) change with impact text and confirmation (data-visibility change bumps tenant authz epoch per G-SEC-12), retention classes display, D-10 subject access/erasure request flow bound to OPS-005's `POST /v1/privacy/requests` (typed SUBJECT_ACCESS / SUBJECT_ERASURE, approval via SEC-102; RECONCILIATION C-20), feature-flagged until OPS-005-S17 is live | page | Changing privacy mode requires re-auth + confirmation; the audit event is recorded | 5 |
| UX-102-S06 | Support page: create a support request with request IDs and an optional diagnostics bundle (no values, no SQL), links to status page and docs | page | Diagnostics payload scan finds no money values or SQL | 3 |
| UX-102-S07 | Tests: restricted admin cannot grant beyond own scope (delegation rule), audit filters, privacy-mode flip effect on query detail (SQL hidden after METADATA_ONLY) | tests | All pass | 4 |
| UX-102-S08 | Mobile/a11y/screenshots | evidence | Axe clean | 2 |

Task acceptance:
- [ ] Grants cannot be created with implicit or wider-than-delegated scope.
- [ ] The audit log is viewable and exportable only with the proper capability, and viewing is itself audited.
- [ ] A privacy-mode change is confirmed, audited, and takes effect on the next request.

### UX-103 — Integration Health and connection detail
Release: R1 · Estimate: 12–17 h · Risk: M · Decisions: D-08, D-09, D-21 · Closes: G-UX-01 (integrations), G-UX-10 (D-08/D-09 content)
Dependency changes: new; depends on `UX-002`, `CON-005` (capability probes), `CON-006` (links to its connection detail page), `ING-012` (coverage links, Bridge overhead panel). `−GOV-006`: the destination-health UI is GOV-006-S13's (RECONCILIATION U-07, U-22). UX-103 keeps the Integration Health summary, egress-IP and network-policy status, and links to CON-006-S12 and ING-012-S08 (U-22).

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| UX-103-S01 | Screen contracts for the Integration Health summary incl. D-08/D-09 content, with links to CON-006-S12 (connection detail) and ING-012-S08 (Bridge overhead) | contracts | Reviewed with CON owner | 2 |
| UX-103-S02 | Integration Health summary: connections, WIF status, last successful login, capability matrix per source (available/unsupported/permission missing), grant gaps (e.g. warehouses missing MONITOR — WRK G-WRK-09) with generated remediation SQL | page | A missing grant shows the exact GRANT statement to run, not a stack trace | 4 |
| UX-103-S03 | Customer footprint panel: egress IPs to allowlist (D-09), network-policy status, and a link to ING-012-S08's Bridge overhead panel for BRIDGE_FINOPS_WH credits vs quota (D-08; RECONCILIATION U-22) | component | Values come from the CON probe API; unknown → "—" + reason | 2 |
| UX-103-S04 | Moved to CON-006-S12 per RECONCILIATION U-22 (connection detail page incl. pause/resume/revoke) — link to it here | — | — | 0 |
| UX-103-S05 | Moved to GOV-006-S13 per RECONCILIATION U-07, U-22 (destinations health UI) | — | — | 0 |
| UX-103-S06 | Tests + a11y: technical details only in an expandable support section (no role ARNs/Dagster IDs in the primary view) | tests | Primary view contains no ARN/Dagster strings | 3 |

Task acceptance:
- [ ] Customers can see and fix grant gaps and egress allowlisting, and reach Bridge warehouse spend (ING-012-S08) and connection detail (CON-006-S12), without contacting support.
- [ ] No internal infrastructure identifiers appear outside the support detail section.

### UX-104 — Explain drawer, analysis jobs and exports center
Release: R1 · Estimate: 26–36 h · Risk: M · Decisions: — · Closes: G-UX-10 (jobs/exports/Explain)
Dependency changes: new; depends on `UX-002`, `API-004`, `API-005`, `API-102`. Dependents: UX-004 (Explain/export links, feature-flagged until ready), UX-008.

| Step | Micro-task | Deliverable | Done when | h |
|---|---|---|---|---|
| UX-104-S01 | Screen contracts for the Explain drawer and the jobs/exports center | contracts | Reviewed | 2 |
| UX-104-S02 | Explain drawer: root (metric id/version, unit, sign, formula ref, scope, publication, as-of, coverage, rounding), lazy tree with `aria-expanded` tree semantics, REMAINDER/RESTRICTED_REMAINDER/UNAVAILABLE node rendering, copy reference, focus return | `apps/web/src/components/explain/*` | Keyboard tree navigation (arrow keys) works; restricted nodes show no count | 6 |
| UX-104-S03 | Explain evidence export (API-005-S10) and "open related resource" links with scope carried | component | Exported root equals the drawer root | 2 |
| UX-104-S04 | Jobs center `/jobs`: list (status, progress, created, expires), detail, cancel, retry, open result in the originating layout | pages | Cancel shows CANCEL_REQUESTED then CANCELLED; `Retry-After` honored in polling | 5 |
| UX-104-S05 | Exports list and download (authorizing endpoint → 30 s redirect), expired state | pages | Expired export shows the expiry state; revoked user sees denied | 3 |
| UX-104-S06 | Global job-completion toast (poll via TanStack with backoff; no websocket in R1) | component | Completion within the session shows a toast linking to the result | 2 |
| UX-104-S07 | Tests: Explain sums (root = Σ children + remainder at every expanded level for the fixture), foreign ref → not found, job scope change → RESULT_SCOPE_CHANGED state | tests | All pass | 4 |
| UX-104-S08 | Mobile/a11y (drawer full-width at 390 px; tree readable at 200 %) | evidence | Axe clean | 2 |

Task acceptance:
- [ ] Explain reconciles at every expanded level and never reveals restricted counts or names.
- [ ] Jobs and exports can be followed, cancelled and downloaded only by authorized users, with expiry states.

## 6. Estimate summary

| Task | Release | Low h | High h |
|---|---|---:|---:|
| UX-001 | R1 | 42 | 58 |
| UX-002 | R1 | 44 | 60 |
| UX-003 | R1 | 24 | 34 |
| UX-004 | R1 | 48 | 66 |
| UX-005 | R1 | 38 | 52 |
| UX-006 | R1 | 26 | 38 |
| UX-008 | R1 | 38 | 52 |
| UX-102 (new) | R1 | 32 | 46 |
| UX-103 (new) | R1 | 12 | 17 |
| UX-104 (new) | R1 | 26 | 36 |
| UX-007 | R1* (D-20) / else R2 | 28 | 40 |
| UX-101 (new) | R2 | 30 | 44 |
| **Total R1** (excluding R1* UX-007) | | **330** | **459** |
| **Total R2** (UX-101 + UX-007 if not R1*) | | **58** | **84** |

The original plan was 8 tasks × 2–6 h = 16–48 h. The realistic figure is about 10× higher: 20 screens had no owner, and the design system, data layer and qualification were each a multi-week effort presented as three steps.

## 7. Owner questions (only those not already covered by D-01…D-25)

- **Q-UX-1** Do any users belong to several tenants (consultants, resellers, a Bridge internal support persona)? If not, `/select-tenant` and multi-tenant switching can be minimal in R1. The per-request tenant selector (G-API-13) stays either way.
- **Q-UX-2** Browser support matrix: evergreen Chrome/Edge/Firefox/Safari last 2 versions only? This affects `Intl.NumberFormat` string formatting and CSS features.
- **Q-UX-3** Is the 390 px mobile layout a review-only target or a supported use case (e.g. executives on phones)? This changes the effort for mobile table alternatives.
- **Q-UX-4** Dashboards: is the custom builder needed for the first customer (R1), or are saved views + Home + scheduled reports enough?
- **Q-UX-5** Product name, logo and brand colors are final? The amber palette needs the contrast fixes in G-UX-12 whatever the answer.
- **Q-UX-6** Should chargeback recipients see allocation denominators (the other groups' basis) in Explain? The default is off, following allocation.md (API G-API-08).
