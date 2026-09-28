# CI checks and branch protection

Status: DRAFT (owner_task AGT-004; FND-003 extends it with product checks). The owner applies the GitHub settings below (human checkpoint H1 in [HUMAN_CHECKPOINTS](../23-agentic-delivery/HUMAN_CHECKPOINTS.md)).

## Required status checks on `main`

| Check (workflow / job) | Introduced by | Blocks |
|---|---|---|
| `delivery / delivery-check` | AGT-002 | Contract parse/schema/SQL errors, packet drift, invalid state |
| `delivery / scope-guard` | AGT-004 | Agent PR touching files outside its packet `writes`, lock paths without the lock, protected files |
| `delivery / secrets` | AGT-004 | Secrets in the diff (gitleaks; organization-owned repositories need a `GITLEAKS_LICENSE` secret) |
| `delivery / protected-files` | AGT-004 | Any change to the PRD or other checksummed files |
| `ci / lint`, `ci / typecheck`, `ci / test-unit`, `ci / test-contract` | FND-003 | Code quality and unit/contract tests |
| `ci / test-integration-pg`, `ci / test-security` | FND-003 / SEC-101 | RLS, tenant isolation, attack catalog |
| `ci / test-financial` | FIN-001 | Golden financial fixtures, conservation invariants |
| `ci / dbt-build-fixtures` | DBT-001 | dbt compile/build on fixtures, contracts enforced |
| `ci / test-web`, `ci / a11y`, `ci / e2e-affected` | UX-001 | Web unit tests, axe, affected Playwright suites |
| `ci / infra-validate` | INF-102 | fmt/validate/tflint/trivy/conftest |
| `ci / supply-chain` | FND-004 | SBOM, licenses, pip-audit/pnpm audit, image scan |
| `ci / evidence` | FND-005 | Evidence manifest present and schema-valid for `agt/*` PRs |

## Branch protection / rulesets

- `main`: pull request required; 1 approving review (2 for paths owned by CODEOWNERS groups `@security`, `@finance` — tier-A paths); dismiss stale approvals; required checks above; **merge queue** (squash, build concurrency 3); linear history; no force push; no deletion; bypass: nobody.
- `delivery-ledger`: only the orchestrator identity (GitHub App or machine user) may push; no force push; no deletion (ADR-018 §5).
- `agt/*`: pushed by workers; force push allowed only to the orchestrator identity (rebases).
- Repository variables: `DELIVERY_MODE` (`B` default, `C` to enable the GitHub-hosted agent workflows). Secrets (environment-scoped `agents` / `orchestrator`): `ANTHROPIC_API_KEY`, `ORCHESTRATOR_GITHUB_TOKEN` (GitHub App token allowed to merge through the queue). Never production cloud credentials.
- Labels used by the delivery system: `agent`, `tier-A`, `tier-B`, `tier-C`, `lane-<X>`, `needs-human`, `contract-change`, `escalation`, `revert`, `delivery-pause`, `lock:<name>`.
