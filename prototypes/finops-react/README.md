# Bridge Data FinOps — React design prototype

A clean, standalone React + TypeScript application covering **87 screens** from the authoritative Bridge specs. Light/amber identity is inspired by `belaidcherfa/snowbridge-finops-mvp`; this project imports no Base44 SDK, customer data, backend logic or application code from that repository.

## Run locally

Use Node 22.13+ (verified with Node 24.19) and npm.

```sh
cd prototypes/finops-react
npm ci
npm run dev
```

Open `http://127.0.0.1:5173`. Start at `#/home`; page search exposes all detail routes. `#/explorer?account=production&state=ready` is a shareable scoped demo URL. This uses hash navigation, so a static preview needs no server route rewrites.

```sh
npm test
npm run build
npm exec playwright install chromium
npm run test:e2e
```

If a managed environment provides Chromium, set `PLAYWRIGHT_CHROMIUM_EXECUTABLE` to that approved local executable for browser tests. This is optional; ordinary Playwright installation is the default. The mockup listens on localhost. Static build output is `dist/`; this phase does not publish a live site or deploy AWS infrastructure.

## What is interactive

- All 87 routes, grouped navigation, ancestor breadcrumbs, page search and browser Back.
- Account scope on overview/explorer/ledger/services, consistent totals, service/account grouping and financial Explain dialogs.
- Shared tables: search, sorting, column visibility, density, pagination, and filtered/visible-column CSV with formula-prefix protection.
- Chart data tables; budget actual/forecast distinction; allocation policy simulation; dbt/task node selection; warehouse tabs; onboarding stage navigation.
- Local incident acknowledgement, required-field draft forms, saved current-view URL, review reason capture, printable internal statement.
- Every route supports review scenarios: ready, loading, empty, partial, stale, error/retry, denied, provisional and final.

## Deliberate boundaries

All data and identities are synthetic. No Cognito login, WIF connection, backend, real permissions, Snowflake query, AWS operation, payment or message delivery occurs. Fixed entity/study/planning scopes are labelled. August ledger, September budget and independent savings study are separate fixtures. Period/currency selection, arbitrary pivots, server filtering, saved-view reopening, real approvals and scheduled PDFs remain production implementation work. Required-only form validation previews layout; domain validation is specified in the canonical tasks.

Browser drafts use `bridge-design:` keys. Do not enter credentials or real personal information. To reset demo state, remove only keys beginning with this prefix in browser developer tools.

## Source layout

```text
prototypes/finops-react/
  index.html
  package.json + package-lock.json
  vite.config.ts + tsconfig.json + playwright.config.ts
  src/
    main.tsx                  React / Query providers and CSS imports
    types.ts                  screen, metric, scope and review types
    app/
      App.tsx                 route content and view lifecycle
      navigation.ts           hash URL scope and browser history
    catalog/
      screens.json            page composition, rows, links, forms
      metrics.json            labelled synthetic metric fixtures
    data/
      financial.ts            integer-cent fixture arithmetic / CSV
      catalog.ts              typed registry and derived metrics
    components/
      AppShell.tsx            navigation, scope, command search
      ui.tsx                  buttons, badges, panels, dialogs, forms
      MetricStrip.tsx          KPI values and evidence dialogs
      DataTable.tsx           reusable TanStack table
      Charts.tsx              Recharts spend / forecast and data views
    pages/
      DomainPanels.tsx        domain-specific compositions
    styles/
      tokens.css              reference-inspired identity
      app.css                 desktop, mobile, print, reduced motion
  tests/
    financial.test.ts         conservation, fixtures, catalog contracts
    e2e/prototype.spec.ts     route/state/interaction/browser checks
```

Shared components are already imported and used. `screens.json` is a bounded design catalog rather than a production API schema. Adding a new screen requires a documented route, compatible metric keys, evidence-qualified rows, explicit scope, parent/children links and browser coverage.

## Design and validation

- [87-screen ASCII catalog](../../docs/21-ui-ux/SCREEN_INDEX.md)
- [Visual foundations](../../docs/21-ui-ux/FOUNDATIONS.md)
- [Components and behavior](../../docs/21-ui-ux/COMPONENTS.md)
- [Financial fixture scope](../../docs/21-ui-ux/FIXTURES_AND_SCOPE.md)

This prototype extends the design workstream. It does not mark the original production implementation tasks complete. Lockfile versions are intentionally fixed; framework majors should be reviewed explicitly before production adoption.
