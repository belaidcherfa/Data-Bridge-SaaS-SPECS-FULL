# Engineering foundation and local development

Canonical domain contract. Owner: Tech lead. Implementation state: NOT_STARTED.


## Repository contract

Use the PRD monorepo boundaries: `apps/web`, `apps/api`, `services/extractor`, `services/orchestrator`, `services/intelligence`, `services/reporting`, `data/dbt`, `data/contracts`, `data/fixtures`, `packages`, `infra/terraform`, `tests` and `docs`. Python packages use `src/` layouts; share typed contracts, never import route handlers into workers. A dependency rule checker rejects business imports from Dagster definitions and frontend financial formulas.

Pin Python and Node LTS versions supported by the tested dependency matrix, not arbitrary latest. Use uv and pnpm lockfiles; pin containers by digest and Terraform providers through `.terraform.lock.hcl`. Select dbt Core explicitly; the vendor website may default to dbt v2/Fusion documentation. Bootstrap records the selected Core, dbt-snowflake, connector, Dagster and Arrow versions and proves WIF together.

## Local environments and fixtures

Docker Compose runs PostgreSQL, Redis, API, web and local Dagster. S3-compatible local emulation is only a transport fixture; it cannot certify IAM, KMS, Snowpipe or Cognito. Mock Snowflake adapters read typed synthetic Arrow fixtures. Real SQL runs in isolated staging Snowflake schemas using WIF from an AWS job; no RSA workaround for local convenience. Developers can use approved human SSO for investigation, with no committed session cache.

Fixtures define tenant A with organizations O1/O2 and accounts A1/A2/A3; tenant B has account B1. Reuse query IDs, resource names and account-local identifiers deliberately across tenants. Include a scoped team viewer, revoked member, unsupported source, reseller billing case, negative adjustment, duplicate batch and partial month. All times use UTC and half-open intervals `[start,end)`; browser locale affects formatting only.

## Validation interface

Create a small repository-owned dispatcher: `make bootstrap`, `make up`, `make down`, `make validate-docs`, `make validate-task TASK=FND-001 ENV=local`, `make test-unit`, `make test-contract`, `make test-e2e`. `validate-task` reads a committed validation manifest and dispatches real commands. Unknown task/environment is an error; missing live credentials produce SKIPPED_REQUIRED, never PASS. This specification's commands are contracts to implement, not existing executable tooling.

Evidence manifest fields: task_id, commit, environment, UTC started/ended, tool/image versions, fixture IDs, commands, exit codes, expected/actual summary, artifact checksums, reviewer, required_gates_remaining. Separate documentation status from implementation status.

## Standards and boundaries

Use Ruff, type checking, pytest, ESLint, TypeScript strict, Vitest and Playwright; SQL uses explicit columns, CTE-focused readable transformations and dbt tests. Dates, Decimal, UUIDs and enums cross boundaries through generated OpenAPI/JSON Schema, not untyped dictionaries. Central error taxonomy distinguishes auth, permission, capability, freshness, retryable network, schema, quality and financial mismatch.

Definition changes must update contract version, fixtures and evidence. CI rejects secrets, unsafe dependency licenses, unverifiable schemas, missing task links and duplicated metric IDs. Provide a one-command synthetic demo with stable seed and visible DEMO label.


## Implementation sequence

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [FND-001](../tasks/FND/FND-001.md) | Create monorepo boundaries and dependency rules | None | M0 |
| [FND-002](../tasks/FND/FND-002.md) | Resolve and lock the compatible runtime matrix | FND-001 | M0 |
| [FND-003](../tasks/FND/FND-003.md) | Build safe local Compose and developer onboarding | FND-001, FND-002 | M0 |
| [FND-004](../tasks/FND/FND-004.md) | Create golden synthetic tenant and finance fixtures | FND-003 | M0 |
| [FND-005](../tasks/FND/FND-005.md) | Implement validation dispatcher and evidence schema | FND-004 | M0 |
| [FND-006](../tasks/FND/FND-006.md) | Establish CI quality gates and agent working rules | FND-005 | M0 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.
