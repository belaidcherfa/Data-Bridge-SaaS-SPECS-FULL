---
name: react-screen
description: Build a Bridge web screen in apps/web (React 19, TanStack Router/Query/Table, shadcn/Tailwind, generated OpenAPI client) from its screen contract — all UX states, tenant-safe routing and caching, i18n, accessibility, charts with table alternatives, no client-side financial math, tests and Playwright evidence. Use for UX and any task that adds or changes UI.
---

# React screen

Read: `docs/21-ui-ux/` (FOUNDATIONS, screen contracts, UX states), the screen's contract, the OpenAPI operations it calls, and `apps/web/src/` conventions (created by UX foundation tasks).

## Structure
- Route `apps/web/src/routes/t/$tenantSlug/<area>/...` (TanStack Router file routes). Search params (filters, period, scope, sort, cursor) validated with zod and treated as the source of truth; shareable URLs reproduce the view.
- Data via generated client (`openapi-fetch`) wrapped in TanStack Query hooks in `apps/web/src/api/<domain>.ts`. Query keys: `[tenantId, profileId, epoch, publicationId, operationId, params]`. Tenant switch or epoch change clears tenant-scoped caches.
- Every request sends `X-Bridge-Tenant`; the client rejects a response whose echo differs and shows the tab-safety error.
- Components from `apps/web/src/components/ui` (shadcn) and design tokens; no ad-hoc colors/spacing.

## States (all mandatory, each with a test and a story/fixture)
`loading` (skeleton, no layout shift) · `empty` (authorized, no data, with next action) · `partial` (coverage + warnings from `meta`) · `stale`/`provisional` (data_status badge, as-of time) · `unknown` (null + reason rendered as "—" with reason tooltip, never 0) · `error` (problem `code` → i18n message, request_id copyable, retry if `retryable`) · `forbidden` (capability missing, no data leak) · `not-found` (non-enumerating).

## Money and numbers
- Display server decimal strings with `Intl.NumberFormat` via `formatMoney` (decimal.js for parsing only). No sums, averages, percentages or currency conversion in the browser — request them from the API.
- Multi-currency responses render one total per currency.

## Charts and tables
- Recharts by default; every chart has an accessible table alternative and a text summary; colors not the only signal.
- Tables: TanStack Table with server-side sort/pagination via cursors; virtualization above 100 rows.

## i18n and a11y
- Every string through i18next keys (`<area>.<screen>.<key>`), EN in R1, FR in R2 (D-18); ICU plurals; dates/numbers via Intl with tenant locale.
- WCAG 2.2 AA: keyboard path, focus management on route change and dialogs, labelled controls, `aria-live` for async results; `make a11y` (axe) with zero serious/critical violations.

## Tests and evidence
- Vitest + Testing Library for components and hooks (MSW handlers generated from OpenAPI examples), including every state above and the tenant-echo mismatch.
- Playwright e2e for the main user path of the screen (`tests/e2e/<area>/`), run against the local stack with fixture tenants.
- Use the playwright MCP server to open the screen, capture screenshots of each state for the evidence manifest.
- `make lint typecheck test-web a11y test-e2e-affected` green.
