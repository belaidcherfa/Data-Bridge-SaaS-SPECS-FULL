# Financial fixtures, scope and design-only boundaries

[Canonical ledger](../08-finops-ledger/ledger.md) · [Semantic metrics](../09-api/semantic-api.md) · [Allocation](../11-allocation/allocation.md) · [Governance](../12-budgets-monitoring/governance.md).

## The main visual fixture

Use the canonical 270 USD ledger fixture multiplied by 100 to make realistic dashboard-sized figures. The visual period is August 2026; all names, times and activity quantities are synthetic. This is a presentation fixture, not historical data from a customer or from the reference repository.

| Charge | USD |
|---|---:|
| Warehouse compute | 20,000.00 |
| Net cloud services | 1,000.00 |
| Storage | 1,200.00 |
| Serverless | 1,800.00 |
| AI / Cortex | 600.00 |
| SPCS | 800.00 |
| Data transfer | 400.00 |
| Application fees | 1,000.00 |
| Organization support | 500.00 |
| Organization rebate | -300.00 |
| **Organization total** | **27,000.00** |

Account PRODUCTION = 26,800.00. Organization-only net adjustments = 200.00. The account scope excludes those adjustments; it does not copy them to the account. No FX is performed. No prior-period change percentage is shown without a comparison fixture.

Query compute 14,000 + classic idle 6,000 = warehouse 20,000. Finance dbt 8,400 + Marketing Power BI 5,600 = query compute 14,000. Their representative executions are included in these parent amounts, not extra charges. SPCS service 500 + other service 300 = pool 800. Cortex functions 400 + Search 150 + Analyst 50 = 600. AI parent 10 includes child 4 and residual 6.

Daily chart cents are allocated across 31 synthetic weights using deterministic largest remainder; every rendered daily series sums exactly to its scoped ledger total. It illustrates visual behavior and is not inferred source history. July comparison is unavailable.

## Independent fixtures never added to the main total

| Fixture | Expected result | Boundary |
|---|---|---|
| Teams warehouse allocation | Finance 12,000; Marketing 8,000 | One book over 20,000 warehouse charge |
| Platform-idle alternative | Finance 8,400; Marketing 5,600; Platform 6,000 | Separate policy, also 20,000 |
| Reconciliation mismatch | 27,000 − 27,100 = -100, FAILED | Alternative scenario; baseline remains matched |
| Storage correction | 27,000 − 1,200 + 1,100 = 26,900 | Hypothetical revision; does not rewrite closed v1 |
| September budget | Budget 28,000, actual 15,000, remaining 13,000 | Separate September period, 15 complete days |
| Forecast | Burn 1,000/day; actual 15,000 + remaining estimate 15,000 = 30,000 | Run-rate fallback, no calibrated interval |
| Forecast variance | +2,000 / 28,000 = +7.142857…% | Forecast estimate versus plan |
| Savings study | Baseline 20,000 / 100 units; post 120 units → expected 24,000; observed 18,000 → realized 6,000 | Separate study windows; estimate 8,000 is not additive |
| Adverse savings | Expected 24,000 − observed 26,000 = -2,000 | Keep negative; do not clamp |
| Equal thirds | 1.00 → .34/.33/.33; -1.00 → -.34/-.33/-.33 | Stable target order resolves ties |

## Prototype data boundaries

The React application contains a synthetic screen catalog and metric fixture dictionary. Arithmetic lives in one financial fixture module. It does not introduce an analytical PostgreSQL mirror, bypass Snowflake authorization, or implement cloud orchestration. UI review states are visual scenarios; they are not proof of actual tenant isolation. Browser drafts and acknowledgements are local only.

Production integration must replace synthetic reads with authorized semantic API responses carrying exact money, null reasons, scope, dataset/metric version, maturity, coverage and as-of. Every existing backend/security/data task remains subject to its documented live validation gates.

## Known-data and no-data cases

Do not fabricate procedure/custom-app/ad-hoc/dynamic-table attribution, old operator plans, utilization, token input/output splits, Cortex Search indexed bytes or Cortex Analyst request counts. Their dedicated views show unavailable evidence with an explicit reason. Counts such as zero failures are used only for explicitly complete observed fixtures.
