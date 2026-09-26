# Bridge Data FinOps — UI/UX design workbench

**Design and standalone prototype delivered: 2026-09-26.** 87 routes in 26 detailed page documents, with desktop ASCII, KPI contracts, table columns, dialogs, mobile composition, 13 explicit UX requirements per screen and acceptance checklists.

## Open the deliverables

- [Complete screen catalog](SCREEN_INDEX.md) — every page and subordinate route.
- [Identity and application foundations](FOUNDATIONS.md) — light/amber identity, shell, scope, financial status and accessibility.
- [Shared components](COMPONENTS.md) — reusable contracts and interaction boundaries.
- [Financial fixtures and scope](FIXTURES_AND_SCOPE.md) — exact numerical examples and independent study/plan contexts.
- [React prototype and local run instructions](../../prototypes/finops-react/README.md).
- [Validation and coherence audit](VALIDATION.md).

## What the screens cover

Access and onboarding; organization/account context; executive overview; service/resource/workload exploration; dbt, Power BI, native tasks/procedures/dynamic tables, Native Apps, custom/ad hoc usage; tagging and allocation; showback and statements; budgets, forecasts, monitors and incidents; reports and dashboards; optimization, actions and savings; data/integration health; people, roles, organizations, security, audit, privacy, billing and support.

The reference repository supplied visual inspiration only. The clean React project contains shared primitives, charts, tables, navigation, domain panels and synthetic data; no Base44 backend or reference customer data is imported. [Decision and alternatives](../architecture/adr/ADR-013-ui-design-prototype.md).

## Authority and completion boundaries

The original [product](../10-frontend/product.md), [metrics](../09-api/semantic-api.md), [ledger](../08-finops-ledger/ledger.md) and [allocation](../11-allocation/allocation.md) contracts remain authoritative. Prototype completion does not complete the 151 production implementation tasks. UI review modes do not prove real RBAC, tenant isolation, WIF, financial close or delivery.

ASCII panels describe structure, component roles and evidence. The React application demonstrates the rendered identity and implemented interactions. Advanced server features and real integrations are identified explicitly in the component matrix and prototype README.
