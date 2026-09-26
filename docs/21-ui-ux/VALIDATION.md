# UI/UX delivery validation and coherence audit

Date: 2026-09-26 UTC. Scope: detailed designs and an independent synthetic-data React prototype. [Screen catalog](SCREEN_INDEX.md) · [Prototype](../../prototypes/finops-react/README.md) · [Original production validations](../00-project/OPEN_VALIDATIONS.md).

## Coverage and authority

- 87 unique routes, with 26 page-design files. Each route has a dedicated ASCII composition, KPI contract, table schema, interaction/dialog, mobile composition, all 13 required UX fields and a validation checklist.
- 176 labelled metric fixtures, including unavailable values with reasons. Production formulas remain defined by the original semantic/financial contracts.
- The page catalog drives actual route discovery, parent/child navigation, specific rows, metric keys and draft fields. A test verifies every catalog route has a detailed documentation section and every metric key resolves.
- All original 151 implementation tasks remain NOT_STARTED. The original PRD remains byte-for-byte unchanged; its recorded SHA-256 is `9f3a35a96e74df6d29d474dfe032253ec6d2052979cfafd0a36085a3d309a233`.

## Executed checks

| Check | Result | Evidence / scope |
|---|---|---|
| TypeScript | PASS | `npm run build` executes `tsc --noEmit` |
| Vite production bundle | PASS | Separate main and lazy domain/chart bundles; no missing imports |
| Unit / financial / catalog contracts | 9 PASS | `npm test`; exact integer-cent oracles and route/document references |
| Browser suite | 9 PASS | Playwright: all 87 routes plus interaction/state/accessibility cases |
| All-route rendering | PASS | Every route has expected h1 and metric count; no page errors |
| Scope and Explain | PASS | 27,000 organization → 26,800 account; explanation and grouping agree |
| Table interaction | PASS | Search, no matches/reset, sort, columns, density, pagination controls and CSV download |
| Review states | PASS | Loading, empty, partial, stale, error/retry, denied, provisional, final |
| Forms | PASS | Required fields, local persistence after reload, no external mutation requests |
| Allocation / incidents | PASS | Alternative policy amounts and local acknowledgement |
| Navigation | PASS | Page search, scoped hash URL, browser Back and focus restoration |
| Mobile width | PASS | 390px checks on six representative compositions, including wide query table |
| Tablet monetary wrapping | PASS | Targeted rerun after 720px fix; money values remain on one line |
| Automated accessibility | PASS | Axe on Home, Explorer, Budget editor, Allocation, Warehouse detail and Security settings; no enabled WCAG A/AA rule violations in those checks |
| Existing engineering invariants | PASS | Original task DAG, dependencies, required task sections, traceability and 17 numerical oracles retained |
| Relative documentation links | PASS | Final link audit excludes generated build/dependency folders; no broken local links/anchors |

Environment: Node 24.19, React 19.2.8, TypeScript 6.0.3, Vite 8.2.1, Playwright 1.58.2; managed local Chromium supplied through `PLAYWRIGHT_CHROMIUM_EXECUTABLE`. Exact application dependencies are in the lockfile. This is not a cross-browser qualification claim.

## Visual review

Rendered Home, Allocation, Budget detail, dbt invocation, Statement and Query execution at 1440px and 390px. Inspected key desktop/mobile screenshots and the warehouse layout at 720px reflow width. Corrections included readable small text, darker secondary labels, bounded table scrolling, a two-column KPI layout at tablet width, and parallel dbt inputs rather than a false sequential chain. Actual assistive-technology review and full browser zoom qualification remain production UX gates.

The application deliberately presents real fixture amounts without truncating significant digits. Tables can scroll within their own panel; the page body stays within the viewport. Chart data has a table alternative. Financial status labels are text, separate from reconciliation/close/workflow state.

## Coherence corrections made

1. Removed unsupported prior-period change percentages; July comparison is unavailable in the fixture.
2. Kept August ledger, September planning and normalized savings studies explicitly separate.
3. Ensured account scope excludes organization-only support/rebate adjustments.
4. Preserved query attribution inside warehouse compute and service attribution inside SPCS/AI parents.
5. Added missing workload and administrative views identified in the PRD reread: procedures, dynamic tables, Native Apps, custom/ad hoc usage, execution columns, warehouse performance, Cortex Search/Analyst, SPCS service, organizations and role scopes.
6. Made missing utilization, old operator plans and absent application linkage unavailable instead of inventing zero or exact cost.
7. Fixed dialog/table accessibility, allocation-label contrast, tabpanel references and tablet number wrapping.
8. Distinguished an allocation policy simulation from the unchanged published v1 table and immutable issued statements.

## Publication and resume

Files are committed individually through the GitHub API to `main`. The source reference repository is unchanged. Final publication verification compares the Git blob SHA of each local deliverable with the remote tree; generated dependencies/build output are excluded. The [project status](../00-project/STATUS.md) is the durable resume entry point.

## Limits that remain explicit

No production backend, customer Snowflake connection, real credentials, tenant isolation, financial close, provider delivery, AWS deployment or payment is claimed. A denied UI scenario is not a security penetration test. Form schemas beyond required-field validation, server pagination, arbitrary pivots, saved-view reopening, true scheduled reports, actual approval workflows, real multi-tenant data and production observability remain governed by the original task tree. Automated accessibility results are supporting evidence, not certification.
