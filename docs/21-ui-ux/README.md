# Bridge Data FinOps — UI/UX design workbench

This extension adds detailed ASCII screen specifications and a standalone React design prototype. The product contracts remain authoritative: [product](../10-frontend/product.md), [metrics](../09-api/semantic-api.md), [ledger](../08-finops-ledger/ledger.md), [allocation](../11-allocation/allocation.md). Prototype completion does not complete the 151 production implementation tasks.

## Read and review

1. Read `FOUNDATIONS.md` for identity, geometry, interactions and financial states.
2. Use the screen index added with each page-design delivery. Each page includes its subordinate routes, KPIs, detailed ASCII composition, interactions, permission policy and acceptance scenarios.
3. Review the clean application in `prototypes/finops-react` as it is published. It uses synthetic fixtures; no customer connection, real notification or financial close is performed.
4. Review the coverage/audit report when the screen catalog and prototype are complete.

## Scope of this phase

Include the full customer journey: sign-in and onboarding; organization/account context; executive overview; service/resource/workload exploration; tagging and allocation; showback and statements; budgets, forecasts, monitors and incidents; reports and dashboards; optimization, actions and savings; data/integration health; people, security, audit, privacy, billing and support settings.

Desktop ASCII uses bounded panels rather than representing every pixel. Each interactive region names its actual component and navigation destination. Mobile contracts explain reflow and table scrolling. Detailed production behaviors are specified even when a prototype interaction is explicitly simulated.

## Publication discipline

Documents and source files are published sequentially to main through the GitHub API. During this delivery, an unpublished file named in prose is planned work, not a working link. Completed indexes link only to published units. The final audit verifies every relative link and every documented route.
