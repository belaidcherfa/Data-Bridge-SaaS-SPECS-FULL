# FND — Implementation-readiness review and production backlog

Canonical contract: [engineering foundation](../../01-architecture/engineering.md). Tasks reviewed: FND-001, FND-002, FND-003, FND-004, FND-005, FND-006 (plus cross-reading of ADR-004, ADR-010, ADR-011, DELIVERY_METHODOLOGY, validation-strategy, readiness, RUNBOOKS, ARCHITECTURE_OVERVIEW, PRD §2, §5, §6, §129–§137, `prototypes/finops-react/package.json`). Reviewer: domain audit agent, 2026-09-27. Status of all tasks: NOT_STARTED.

## 1. Verdict

The foundation contract is directionally right (uv/pnpm locks, digest pinning, WIF-only, dispatcher with SKIPPED_REQUIRED), but it cannot be implemented without re-deriving the design. The six tasks are a strictly serial chain, and INF-001 waits for all of them. Neither is necessary: FND-004 and FND-005 do not need Compose, and AWS bootstrap does not need CI rules. Three gaps block productive engineering. (1) There is no **developer inner loop** for dbt/SQL against Snowflake ("no RSA workaround" is stated, but no mechanism is given). (2) There is no **recorded-fixture strategy**, so the mock adapters will drift from live views. (3) There is no **contract codegen / Decimal-as-string enforcement**, although engineering.md relies on generated types. FND-003's oracle ("reaches the seeded demo … login") cannot be met at M0 because auth/UI arrive in SEC-002/UX-002. The evidence contract ("evidence lives under `docs/evidence/<task>/<commit>/`") has a self-reference problem that must be fixed before FND-005 is coded. The version matrix can be pinned today: the constraints below are verified on PyPI. Author first: package/boundary map, version matrix, fixture manifest schema, evidence schema, and the dev-access decision record (FND-101).

## 2. Findings

### G-FND-01 · FND chain and INF-001 edge are over-serialized
Severity: HIGH · Type: RISK
Evidence: `docs/01-architecture/engineering.md` implementation table — "FND-004 … Dependencies FND-003", "FND-005 … FND-004", "FND-006 … FND-005"; `docs/tasks/INF/INF-001.md` — "Dependencies: FND-006".
Why it matters: Six M0 tasks (~200 h realistic) run one after another, and AWS account creation waits for all of them. AWS account creation has calendar lead time (organization authority, quota requests, SES/Snowflake commercial steps). The fixture generator (FND-004) needs pinned pyarrow (FND-002), not Compose (FND-003). The dispatcher (FND-005) needs no fixtures; its own tests use synthetic manifests. INF-001 needs only the `infra/terraform` directory convention from FND-001.
Resolution: New edges: FND-004 = {FND-001, FND-002} (−FND-003). FND-005 = {FND-001, FND-002} (−FND-004). FND-006 = {FND-002, FND-005}. INF-001 = {FND-001} (−FND-006). UX-001 = {FND-001, FND-002} (−FND-003; the component system needs the pnpm workspace, not Compose). The FND/INF longest chain becomes FND-001→FND-002→FND-005→FND-006 (4 tasks), and INF runs in parallel from week 1.
Affects: FND-003, FND-004, FND-005, FND-006, INF-001, UX-001.

### G-FND-02 · Developer inner loop for Snowflake SQL/dbt is undefined
Severity: HIGH · Type: GAP
Evidence: `engineering.md` — "Real SQL runs in isolated staging Snowflake schemas using WIF from an AWS job; no RSA workaround for local convenience. Developers can use approved human SSO for investigation, with no committed session cache." No task creates human users, an SSO integration, personal schemas, a DEV account or CI ephemeral schemas. INF-008 creates only service users.
Why it matters: Every dbt/FIN/ALC engineer would need a full CI round-trip through a staging AWS job to run one model. Staging would fill with human experiments, which contaminates live gates. Coding agents (D-19) cannot do browser SSO at all. Snowflake WIF binds only `TYPE=SERVICE`/`LEGACY_SERVICE` users (VERIFIED: snowflakedb/terraform-provider-snowflake `docs/resources/service_user.md`, "Only applicable for service users and legacy service users", 2026-09-28). "WIF from laptops" would therefore make humans impersonate service users and break per-human audit.
Resolution: New task FND-101. Humans get `TYPE=PERSON` users only in the **BRIDGE_DEV** Snowflake account. They authenticate with `authenticator=externalbrowser` through a SAML2 security integration to the company IdP; IAM Identity Center as a custom SAML app is the default if the IdP is undecided. The account authentication policy allows humans SAML only (MFA at the IdP) and service users WORKLOAD_IDENTITY only. Each developer gets a personal role `DEV_U_<user>` that owns `BRIDGE_DEV_SANDBOX.DEV_<user>` and a personal XSMALL warehouse with a 20-credit/month resource monitor. Access to `BRIDGE_FIXTURES` (synthetic RAW-shaped data loaded by CI from FND-004) is read-only. There are no human users in STAGING. PROD has named break-glass only. Coding agents and all automated runs use CI ephemeral schemas `BRIDGE_CI.CI_PR_<n>_<sha7>` via WIF on an in-VPC runner, dropped after 48 h. Laptop WIF through AWS-SSO roles is rejected: SERVICE-type misuse, and the unstable `AWSReservedSSO_*_<hash>` role name. Revisit only if no SAML IdP exists.
Affects: FND-101 (new), FND-003, DBT-001, INF-008.

### G-FND-03 · FND-003 oracle is unachievable at M0; local auth and emulators unspecified
Severity: HIGH · Type: CONTRADICTION
Evidence: `FND-003` micro-task 3 — "first-run instructions … through login to the synthetic demo"; oracle — "A second developer reaches the seeded demo from a clean checkout"; `engineering.md` — "Provide a one-command synthetic demo with stable seed and visible DEMO label". Cognito login is SEC-002 (M1) and the product shell is UX-002 (M5). Cognito cannot be emulated locally.
Why it matters: FND-003 either stays open until M5 or someone fakes a login. Without a local OIDC issuer, SEC-002 has no local test path. Without an issuer allowlist per environment, a local mock issuer could be accepted in cloud environments, which is an authentication bypass.
Resolution: Narrow the FND-003 oracle to three checks: health-checked PG/Valkey/S3-SQS emulator/mock-OIDC/Dagster; API `/healthz` plus the web shell rendering a mock-login persona; and restart persistence plus reset refusal. Move "one-command synthetic demo" to UX-008/ONB-001 and name it explicitly there. Add a mock OIDC issuer container (pinned by digest) with the deterministic personas A-admin, A-reader-A1, A-team-reader, B-admin and revoked-member. The API accepts that issuer only when `BRIDGE_ENV=local` (SEC-002 adds a negative test in cloud envs). For S3/SQS/SNS emulation, prefer moto server (Apache-2.0). MinIO/LocalStack community distribution and licensing terms changed in 2025–2026 and are TO VERIFY LIVE in the FND-002 license review.
Affects: FND-003, SEC-002, UX-008, ONB-001.

### G-FND-04 · Runtime matrix: verified constraints that fix the Python/Node pins
Severity: MEDIUM · Type: VENDOR-FACT
Evidence (all VERIFIED on pypi.org JSON, 2026-09-28):
- dagster-dbt 0.29.24 has `requires_python <3.14` and `dbt-core<1.13,>=1.7`. dagster 1.13.24 has `<3.15`.
- dbt-core 1.12.5 has `>=3.10`.
- dbt-snowflake 1.12.1 (2026-09-16) requires `snowflake-connector-python[secure-local-storage]>=4.2.0,<5` and `dbt-core>=1.10`.
- snowflake-connector-python 4.7.5 (2026-09-21) caps `pyarrow<24` only for Python ≥3.14.
- dbt-snowflake reads `authenticator: workload_identity` + `workload_identity_provider: AWS` and exposes no impersonation-path field. VERIFIED in github.com/dbt-labs/dbt-adapters `dbt-snowflake/src/dbt/adapters/snowflake/connections.py` (main).
- The Python connector itself supports `workload_identity_impersonation_path` for AWS through `sts:AssumeRole` with fixed `RoleSessionName="identity-federation-session"`. VERIFIED in github.com/snowflakedb/snowflake-connector-python `wif_util.py` (main).
- The prototype declares `"node": ">=22.13.0"`, and its README says "verified with Node 24.19".
Why it matters: Choosing Python 3.14 breaks dagster-dbt. The `secure-local-storage` extra pulls `keyring` into server images. Because dbt cannot chain roles, each dbt identity must be the task role itself (one task definition per dbt identity). Because the session name is fixed, Snowflake WIF bindings for chained identities (D-02 serving roles) must match on role ARN, not session name.
Resolution: Pin Python 3.12.x (3.13 allowed after the compat suite passes), dbt-core 1.12.x, dbt-snowflake 1.12.1, connector 4.7.x (≥4.7.1 keeps JWT mode possible), dagster 1.13.x/dagster-dbt 0.29.x/dagster-aws 0.29.x, pyarrow 25.x, Node 24 LTS, and pnpm pinned through `packageManager`. Record the matrix in `docs/development/versions.md` with the evidence URLs. V01 stays OPEN until INF-008-S11 (central) and CON-002 (customer side) run live.
Affects: FND-002, DBT-001, CON-002, SEC-005, API-002.

### G-FND-05 · Evidence-in-repo has a commit self-reference problem and no freshness rule
Severity: HIGH · Type: CONTRADICTION
Evidence: `DELIVERY_METHODOLOGY.md` — "Implementation evidence lives under `docs/evidence/<task-id>/<commit>/`"; `FND-005` failure list — "stale evidence from a different commit"; `readiness.md` — "evidence freshness".
Why it matters: Evidence for commit X can only be committed in a later commit Y, so "evidence references exact commit" is always about a non-HEAD commit. Nothing defines when X-evidence is still valid for HEAD. The result is either endless re-runs or stale evidence silently accepted for a changed security contract. Committing large logs to `main` also bloats the repo, and redaction mistakes become permanent Git history.
Resolution: Store artifacts in CI artifacts plus an S3 evidence bucket (Object Lock governance mode, created in INF-003). The repo holds only append-only index lines `docs/evidence/index/<TASK>.jsonl` = {task_id, commit, env, result, gates[], artifact_uri, artifact_sha256, reviewer}. Freshness rule: evidence is valid for HEAD iff `git merge-base --is-ancestor <commit> HEAD` holds and `git diff --name-only <commit>..HEAD -- <task watch paths>` is empty. Watch paths are declared per task in the validation manifest. Otherwise the result is STALE and counts as not DONE.
Affects: FND-005, FND-006, REL-001, every task's DoD.

### G-FND-06 · No task produces contract codegen or enforces Decimal-as-string
Severity: HIGH · Type: GAP
Evidence: `engineering.md` — "Dates, Decimal, UUIDs and enums cross boundaries through generated OpenAPI/JSON Schema, not untyped dictionaries"; `semantic-api.md` — "Decimal money is a JSON string". No FND/API task creates the generator, the drift gate or the lint.
Why it matters: Without a gate, one `type: number` money field reintroduces float arithmetic in the React client. That breaks "React … never computes alternative financial totals" and exact-cents fixtures such as the 1.00 → 0.34/0.33/0.33 split.
Resolution: New task FND-103: committed `apps/api/openapi.json` export; Spectral ruleset rejecting `type: number` for properties matching `amount|cost|credits|price|rate|total|delta` and requiring `type: string, format: decimal, pattern ^-?\d{1,20}(\.\d{1,9})?$`; `openapi-typescript` → `packages/api-types`, a branded `DecimalString` type and an ESLint ban on `Number()`/`parseFloat`/unary `+` over it; regenerate-and-diff CI gate; oasdiff breaking-change gate.
Affects: FND-103 (new), API-001..006, UX-002+.

### G-FND-07 · Boundary rules are not executable as written
Severity: MEDIUM · Type: AMBIGUITY
Evidence: `FND-001` micro-task 2 — "orchestrator may invoke extractor/dbt/intelligence interfaces but must not define financial formulas"; `engineering.md` — "A dependency rule checker rejects business imports from Dagster definitions and frontend financial formulas".
Why it matters: An import linter can forbid *imports*, but it cannot detect a formula *defined* inside `services/orchestrator`. "Frontend financial formulas" is not a dependency property at all, so the rule becomes aspirational.
Resolution: Three concrete mechanisms, each with a failing fixture:
- (a) `import-linter` (2.15, VERIFIED on pypi.org, 2026-09-28) contracts: `forbidden` orchestrator→`bridge_api`, api→`bridge_orchestrator`, api/workers→dbt internals. `independence` among `services/*`. `layers` per service (`entrypoints > application > domain > adapters`).
- (b) An AST scanner `tools/boundaries/orchestrator_purity.py`. It fails if `services/orchestrator/**` contains SQL keyword string literals (`SELECT|INSERT|MERGE|UPDATE|DELETE|CREATE`), imports `decimal`, or performs arithmetic on names matching `*cost*|*credit*|*amount*`.
- (c) Web: `eslint-plugin-boundaries` element rules, plus `no-restricted-imports` banning `big.js`, `decimal.js` and `bignumber.js` in `apps/web`. The DecimalString arithmetic ban comes from FND-103.
Affects: FND-001, FND-103.

### G-FND-08 · No recorded-fixture strategy for Snowflake adapter contract tests
Severity: HIGH · Type: GAP
Evidence: `engineering.md` — "Mock Snowflake adapters read typed synthetic Arrow fixtures"; PRD §133 — "CI compares Snowflake adapters against a versioned source contract"; `validation-strategy.md` — contract layer "Source projections/types/grain".
Why it matters: Hand-written Arrow fixtures encode the author's belief about a view's types. R14 (CREDITS_USED as VARCHAR) and R15 (FLOAT/VARIANT fields) show that beliefs and reality diverge. Mocks built from belief pass CI and then fail live, or silently cast decimal precision. ACCOUNT_USAGE latency (45 min to 8 h per R03/R04) makes live-only tests slow and non-deterministic.
Resolution: New task FND-102 (recorder plus replay plus weekly drift job) against the INF-101 test estate. Recorded fixtures are *adapter/contract inputs only*. Monetary oracles remain the synthetic F-270 family, because live amounts are not stable.
Affects: FND-102 (new), ING-001, ING-003, CON-005, INF-101.

### G-FND-09 · "Identical checksums" is not achievable over Parquet bytes; dbt seeds infer floats
Severity: MEDIUM · Type: RISK
Evidence: `FND-004` oracle — "Regenerating fixtures produces identical checksums"; loader emits "typed Arrow, PostgreSQL seed records and dbt seeds from one manifest".
Why it matters: Parquet files embed `created_by` (writer library and version) and row-group layout, so any pyarrow bump changes every checksum and invalidates evidence. dbt seeds infer column types from CSV. `12.00` becomes a FLOAT or `NUMBER(38,0)`-like type unless declared, which defeats exact decimal fixtures such as −1.00 → −0.34/−0.33/−0.33.
Resolution: Take the canonical checksum over a normalized serialization: rows sorted by the declared natural key, Arrow IPC stream with explicit schema, no metadata, then SHA-256. Parquet files carry their own content hash only as transport. Every dbt seed declares `column_types` (e.g. `amount: number(38,9)`, `usage_date: date`, timestamps `timestamp_ntz(9)` with UTC semantics documented). CI fails if a seed column lacks an explicit type.
Affects: FND-004, DBT-001, DBT-005.

### G-FND-10 · CI supply-chain and fork isolation are named but not specified
Severity: HIGH · Type: GAP
Evidence: `FND-006` — "Separate untrusted fork jobs from authenticated integration jobs"; oracle — "Untrusted code receives no cloud credential"; `readiness.md` — "GitHub Actions uses OIDC with repository/ref/environment conditions".
Why it matters: Common real breaches come from mutable action tags (tj-actions/changed-files compromise, CVE-2025-30066, March 2025), `pull_request_target` checking out PR code with secrets, default write `GITHUB_TOKEN`, and `id-token: write` granted workflow-wide. Two tooling facts matter: GitHub push protection on private repos needs a paid Secret Protection/Advanced Security plan, and gitleaks-action requires a license key for organizations. Both are owner or plan questions (TO VERIFY LIVE).
Resolution (FND-006):
- Top-level `permissions: {}` with per-job minimal permissions.
- All `uses:` pinned by 40-char SHA, with Renovate updating them.
- `pull_request_target` banned by a lint (`zizmor` or `actionlint` plus a custom grep).
- `id-token: write` only in jobs bound to GitHub environments, which run only on `push` to `main`/`merge_group`.
- gitleaks CLI pinned by checksum (MIT) in pre-commit and CI, with a full-history scan nightly.
- osv-scanner on `uv.lock`/`pnpm-lock.yaml`.
- A license allowlist.
- The OIDC `sub` customized to include `repository_owner_id` and `repository_id`. This resists repo-rename/resurrection; the trust conditions are in INF-102.
Affects: FND-006, INF-102, INF-007.

### G-FND-11 · Prototype uses npm while the contract mandates pnpm
Severity: LOW · Type: CONTRADICTION
Evidence: `prototypes/finops-react/README.md` — "Use Node 22.13+ (verified with Node 24.19) and npm"; `package-lock.json` present; `engineering.md` — "Use uv and pnpm lockfiles".
Why it matters: Adding the prototype to the pnpm workspace would re-resolve its dependencies (React 19.2.8, Vite 8.2.1, TypeScript 6.0.3) and couple a design artifact to the product lockfile. Leaving it unmentioned creates a second, unscanned lockfile.
Resolution: Exclude `prototypes/**` from `pnpm-workspace.yaml`. Keep its npm lock and give it a separate non-required CI job (`npm ci && npm test && npm run build`) that is still covered by osv-scanner and license scan. `apps/web` starts from the prototype's exact versions as its initial pins. Components are copied, not imported.
Affects: FND-001, FND-006, UX-001.

## 3. Contract-first artifacts to author before coding

| Artifact | Exact content required | Produced by |
|---|---|---|
| `docs/development/packages.yaml` + `layout.md` | Every workspace package: name, path, language, owner, public interface module, allowed dependencies (edges), forbidden dependencies; CI fails on undeclared packages | FND-001-S01 |
| `.importlinter` + `apps/web/eslint.config.js` boundaries | Contracts listed in G-FND-07 with names; one failing fixture per contract | FND-001-S04/S05 |
| `docs/development/versions.md` + `infra/images.lock.json` | Matrix per G-FND-04: exact version, sha256/digest, license, upstream URL, evidence URL, review date, V01 status | FND-002-S01/S05 |
| `compose.yaml` topology + `docs/development/ports.md` | Services, images by digest, health checks, host ports (55432 PG, 56379 Valkey, 55000 moto, 58080 mock-OIDC, 53000 Dagster, 58000 API, 55173 web, 58025 mail), volumes, reset guard rules | FND-003-S01/S02 |
| `data/fixtures/manifest.schema.json` (fixture v1) | fixture_id, version, clock_utc, tenants/orgs/accounts/users/grants with UUIDv5 derivation rule, source rows per source, expected values as decimal strings with currency, privacy cases, variant catalog, canonical checksum algorithm | FND-004-S01 |
| `tools/validation/manifest.schema.json` | Per task: gates[{id, level, env ∈ {local, ci, dev, staging}, argv[], requires{aws_account?, snowflake_identity?}, required, timeout_s, min_tests}], watch_paths[] | FND-005-S01 |
| `docs/evidence/schema/evidence.schema.json` + index line format | Fields from engineering.md, plus status enum and aggregate rule, freshness rule (G-FND-05), redaction version | FND-005-S04/S06 |
| Required-checks list (`docs/development/ci-checks.md`) | Check name → job → owner → blocking/advisory → trusted/untrusted context | FND-006-S01/S03 |
| `AGENTS.md` | Claim/checkpoint/blocker protocol, stop conditions, forbidden actions (edit ADR, weaken tests, obtain credentials) | FND-006-S08 |
| `docs/development/snowflake-dev-access.md` | Decision record G-FND-02: identities per environment, auth policies, personal objects, CI schemas, janitor, quotas | FND-101-S01 |
| `data/fixtures/recorded/meta.schema.json` | Recorded fixture metadata (FND-102-S01) | FND-102-S01 |
| `contracts/.spectral.yaml` + API conventions doc | Decimal/UUID/date/enum rules, error envelope schema reference, pagination cursor type | FND-103-S01/S02 |

## 4. Revised production backlog

### FND-001 — Create monorepo boundaries and dependency rules
Release: R1 · Estimate: 18–26 h · Risk: L · Decisions: D-19 · Closes: G-FND-07, G-FND-11
Dependency changes: none (root).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FND-001-S01 | Write the package map from engineering.md (apps/web, apps/api, services/{extractor,orchestrator,intelligence,reporting,identity_provisioner,query_broker}, data/{dbt,contracts,fixtures}, packages/*, infra/terraform, tools, tests, docs) with owner, public interface and allowed edges | `docs/development/packages.yaml`, `docs/development/layout.md` | YAML validates against a small JSON Schema; every directory created has exactly one entry | 2 |
| FND-001-S02 | Create uv workspace root (`[tool.uv.workspace] members`), one `src/`-layout package per Python member with `py.typed`, names `bridge-<name>`, Python `requires-python = ">=3.12,<3.14"` | `pyproject.toml`, `*/pyproject.toml`, `uv.lock` | `uv sync --frozen` succeeds on clean checkout; `uv sync --package bridge-extractor --frozen` installs only that member's deps | 3 |
| FND-001-S03 | Create pnpm workspace (`apps/web`, `packages/*-ts`), exclude `prototypes/**`, set `packageManager` field, `.npmrc` with `engine-strict=true` | `package.json`, `pnpm-workspace.yaml`, `.npmrc`, `pnpm-lock.yaml` | `pnpm install --frozen-lockfile` succeeds; prototype's `package-lock.json` untouched | 2 |
| FND-001-S04 | Author import-linter contracts: forbidden orchestrator→api, api→orchestrator, api→`data/dbt` internals; independence among services; layers per service | `.importlinter` | `lint-imports` passes on skeleton; contract names listed in layout.md | 3 |
| FND-001-S05 | Configure eslint-plugin-boundaries (web may import `packages/api-types`, `packages/ui` only) and `no-restricted-imports` for `big.js`, `decimal.js`, `bignumber.js` in `apps/web` | `eslint.config.js` | ESLint passes on skeleton | 2 |
| FND-001-S06 | Write orchestrator-purity AST scanner (SQL keyword literals, `decimal` import, arithmetic on cost-like names under `services/orchestrator/**`) | `tools/boundaries/orchestrator_purity.py` + tests | Scanner unit tests: 3 violating snippets fail, 3 clean snippets pass | 2 |
| FND-001-S07 | Add violation fixtures (Python orchestrator→api import, orchestrator SQL literal, web `import Big from "big.js"`, package cycle A→B→A) executed in a temp copy by a test | `tests/spec/FND-001/fixtures/*`, `tests/spec/FND-001/test_boundaries.py` | Each fixture makes `make lint-boundaries` exit ≠0 and the message contains the offending file path | 2 |
| FND-001-S08 | Add cycle detection for TS (`dependency-cruiser --validate` with `no-circular`) and `independence` contract for Python | `.dependency-cruiser.cjs` | Cycle fixture fails; skeleton passes | 2 |
| FND-001-S09 | Generated-code policy: `generated/` directories, `.gitattributes linguist-generated`, lint/type excludes, CODEOWNERS entry | `.gitattributes`, `ruff.toml`, `tsconfig.base.json` | A hand edit to a generated file is caught by FND-103 drift gate (placeholder test until FND-103) | 1 |
| FND-001-S10 | Baseline standards: `.editorconfig`, Ruff rules, mypy `--strict` config, TS `strict: true`, `noUncheckedIndexedAccess` | config files | `make lint type` passes on skeleton with zero suppressions | 2 |
| FND-001-S11 | `make bootstrap` with repo-root guard (fails with explicit message outside root) and idempotency; undeclared-package check against `packages.yaml` | `Makefile`, `tools/boundaries/declared_packages.py` | Running bootstrap twice yields no diff; a new undeclared `services/foo` fails CI | 2 |
| FND-001-S12 | Record evidence (commands, versions, failing-fixture outputs) | `docs/evidence/index/FND-001.jsonl` entry + artifact | Evidence validates against FND-005 schema (or schema draft if FND-005 not yet merged) | 1 |
Task acceptance:
- [ ] Clean checkout: `make bootstrap` installs from locks with no network resolution (`--frozen`).
- [ ] Four deliberate violations (import, SQL-in-orchestrator, web money library, cycle) each fail with file path in output.
- [ ] Every package directory is declared in `packages.yaml` with owner and public interface.
- [ ] `prototypes/finops-react` is outside the pnpm workspace and unchanged.

### FND-002 — Resolve and lock the compatible runtime matrix
Release: R1 · Estimate: 22–32 h · Risk: M · Decisions: D-21, D-19 · Closes: G-FND-04
Dependency changes: none (FND-001).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FND-002-S01 | Write candidate matrix from verified constraints (Python 3.12.x; dbt-core 1.12.x; dbt-snowflake 1.12.1; connector 4.7.x; dagster 1.13.x; dagster-dbt/aws 0.29.x; pyarrow 25.x; Node 24 LTS; pnpm; PG major = Aurora major; Valkey 8; Terraform ≥1.11; snowflakedb/snowflake provider 2.21.x) with evidence URLs | `docs/development/versions.md` | Each row has version, source URL, verification date, license | 3 |
| FND-002-S02 | Resolve with `uv lock`; inspect transitive conflicts (protobuf/grpcio from dagster, keyring from `secure-local-storage`); decide keep/override and record reason | `uv.lock`, `versions.md#transitives` | `uv lock --check` clean; transitive count and overrides recorded | 3 |
| FND-002-S03 | Read pinned adapter source and record exact WIF parameters: dbt `authenticator: workload_identity`, `workload_identity_provider: AWS`; connector `authenticator='WORKLOAD_IDENTITY'`, `workload_identity_provider='AWS'`, `workload_identity_impersonation_path` | `versions.md#wif-parameters`, unit test asserting fields exist on pinned classes | Test fails if a dependency bump removes `workload_identity_provider` from dbt credentials | 3 |
| FND-002-S04 | Add Fusion guard: CI asserts `dbt --version` reports Core and no `dbtf`/`dbt-fusion` binary in images | `tools/compat/check_dbt_core.sh` | Guard fails when a fake `dbtf` binary is on PATH in test | 1 |
| FND-002-S05 | Pin base images by digest for linux/arm64 and linux/amd64 (python slim or distroless, node 24) and record in lock file; Renovate digest config | `infra/images.lock.json`, `renovate.json` | No `:latest`/tag-only reference anywhere (`grep` gate); both arch digests recorded | 3 |
| FND-002-S06 | Verify binary wheels exist for both arches (pyarrow, snowflake-connector-python, psycopg, cryptography) with `--only-binary :all:` builds | CI job `wheel-matrix` | Both arch builds complete without compiling from source | 2 |
| FND-002-S07 | Smoke inside built image: import all packages, `dbt parse` on 1-model skeleton, `dagster definitions validate` on skeleton code location | `tests/spec/FND-002/test_smoke.py` | All three succeed in container on both arches | 3 |
| FND-002-S08 | License inventory for Python and JS runtime deps; allowlist (MIT, BSD-2/3, Apache-2.0, ISC, PSF, MPL-2.0 unmodified); deny AGPL/SSPL/BUSL for shipped deps; tool exceptions list (e.g., Terraform BUSL as build tool only; not legal advice) | `tools/licenses/allowlist.yaml`, report artifact | Report has zero unknown licenses; exception list reviewed by owner | 3 |
| FND-002-S09 | Write WIF compatibility probe (connector session identity query and `dbt debug`) with modes `--mode aws-attestation / aws-jwt`; register V01 as OPEN gate for staging | `tools/compat/wif_probe.py`, validation manifest entry | Locally returns SKIPPED_REQUIRED (no identity); never PASS without live run | 3 |
| FND-002-S10 | Dependency update policy: grouped Renovate PRs must pass compat suite; failing WIF-field test blocks merge | `renovate.json`, `docs/development/versions.md#update-policy` | Simulated bump removing WIF field is blocked | 2 |
| FND-002-S11 | Record evidence | index entry | Evidence lists exact versions and digests | 1 |
Task acceptance:
- [ ] `versions.md`, `uv.lock`, `pnpm-lock.yaml` and `images.lock.json` agree; no floating tags.
- [ ] Python <3.14 and dbt-core <1.13 constraints documented with PyPI evidence.
- [ ] WIF parameter names asserted by tests against the pinned packages.
- [ ] V01 remains OPEN (SKIPPED_REQUIRED) until INF-008-S11 and CON-002 live runs.

### FND-003 — Build safe local Compose and developer onboarding
Release: R1 · Estimate: 22–32 h · Risk: M · Decisions: D-18 · Closes: G-FND-03
Dependency changes: none (FND-001, FND-002). Oracle narrowed: seeded product demo moves to UX-008/ONB-001.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FND-003-S01 | Define Compose services with digest-pinned images and health checks: postgres (Aurora major), valkey 8, moto server (S3/SQS/SNS), mock OIDC issuer, mailpit, api skeleton (`/healthz`), web skeleton, dagster webserver+daemon on `dagster_meta` | `compose.yaml` | `make up` → all services healthy within 120 s on a clean machine | 4 |
| FND-003-S02 | Port registry with non-default host ports; collision diagnosis prints owning process and override variable | `docs/development/ports.md`, `tools/dev/check_ports.sh` | Occupying 55432 before `make up` prints a clear conflict message and exits 1 | 2 |
| FND-003-S03 | Init SQL mirroring INF-004 roles: databases `bridge_control`, `dagster_meta`; roles `bridge_migrator` (owner), `bridge_api`/`bridge_worker` (NOBYPASSRLS, non-owner), `dagster_rt` | `infra/local/postgres/init/*.sql` | `SELECT rolbypassrls FROM pg_roles WHERE rolname='bridge_api'` = false; api role cannot `CREATE TABLE` | 3 |
| FND-003-S04 | `.env.example` with non-secret values only; guard refuses `.env` containing `AWS_SECRET_ACCESS_KEY`, `*PASSWORD*` for Snowflake, `PRIVATE_KEY`, `PAT` keys | `.env.example`, `tools/dev/env_guard.py` | Planting `SNOWFLAKE_PRIVATE_KEY=...` makes `make up` exit ≠0 | 2 |
| FND-003-S05 | Disable external side effects by default: SES/Slack/Teams/webhook endpoints route to mailpit or a local sink; optional live mode documented as FND-101 SSO only | compose profiles, `docs/development/quickstart.md#live` | Default profile has no outbound network calls except package registries (verified with `docker network` egress disabled test) | 2 |
| FND-003-S06 | Reset guard: `make reset-local` requires host in {localhost, 127.0.0.1, compose service names}, DB name suffix `_local` and marker row `bridge_meta.environment='local'` | `tools/dev/reset_local.py` | `DATABASE_URL` pointing at `x.cluster-abc.eu-west-1.rds.amazonaws.com` → exit 3 "refused: non-local target"; marker missing → refused | 3 |
| FND-003-S07 | Migrations run only via one-shot `migrate` service; API never migrates on start; `depends_on: service_completed_successfully` | `compose.yaml`, `Makefile` | Starting two API replicas concurrently causes no migration race (no DDL from API logs) | 2 |
| FND-003-S08 | Persistence test: create control record, `make down && make up` → exists; `make reset-local` → empty then reseeded | `tests/spec/FND-003/test_persistence.sh` | Script exits 0 with the three assertions | 2 |
| FND-003-S09 | Configure mock OIDC with deterministic personas (A-admin, A-reader-A1, A-team-reader, B-admin, revoked) and document that the API accepts this issuer only when `BRIDGE_ENV=local` (enforced in SEC-002) | `infra/local/oidc/personas.json`, quickstart section | Token for each persona obtainable via `make token PERSONA=a-admin`; issuer URL recorded for SEC-002 negative test | 3 |
| FND-003-S10 | Quickstart from clean machine (macOS arm64, Linux x86_64) to API `/healthz` and web shell with persona login stub; second developer timed run | `docs/development/quickstart.md` | Second developer completes in ≤30 min; timing and OS recorded | 3 |
| FND-003-S11 | Record evidence | index entry | Includes images digests and timing | 1 |
Task acceptance:
- [ ] All Compose images pinned by digest; all health checks green.
- [ ] Reset refuses any non-local host or unmarked database.
- [ ] Runtime DB role is non-owner and NOBYPASSRLS locally, mirroring cloud.
- [ ] No secret-like keys accepted in `.env`; default profile makes no external deliveries.

### FND-004 — Create golden synthetic tenant and finance fixtures
Release: R1 · Estimate: 30–44 h · Risk: M · Decisions: D-10, D-12, D-13 · Closes: G-FND-09
Dependency changes: `−FND-003` (Compose not needed to generate fixtures; PG seed validated with a throwaway container in tests), `+FND-002` (pinned pyarrow).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FND-004-S01 | Write fixture manifest JSON Schema (G-FND-09 checksum rule, decimal strings, UUIDv5 namespace) | `data/fixtures/manifest.schema.json` | Schema rejects a manifest with a numeric (non-string) amount | 3 |
| FND-004-S02 | Identity fixture: tenant A (orgs O1/O2, accounts A1/A2/A3), tenant B (B1); personas incl. revoked member; UUIDv5 from fixed namespace; colliding account-local IDs (`ANALYTICS_WH`, database `SALES`, query_id Q1 identical string in A1 and B1) | `data/fixtures/identity/v1.json` | Test: (tenant, account, query_id) unique; query_id alone not unique (2 rows) | 3 |
| FND-004-S03 | Encode F-270 component rows and expected totals exactly as validation-strategy: 200.00 + 10.00 + 12.00 + 18.00 + 6.00 + 8.00 + 4.00 + 10.00 + 5.00 − 3.00 = 270.00; account components 268.00; org fee net 2.00 (account null); EUR 20.00 separate; storage correction 12→11 → 269.00; duplicate replay still 269.00; invoice 271.00 → delta −1.00 FAILED | `data/fixtures/finance/f270/*.json` | Independent pure-Decimal test recomputes 270.00, 268.00, 269.00, −1.00 | 4 |
| FND-004-S04 | Warehouse and allocation oracles: 100 credits = 70 query + 30 idle at fixture-only $2 → 140.00/60.00; books A (Finance 120.00/Marketing 80.00) and B (84.00/56.00/Platform 60.00); rounding 1.00 → 0.34/0.33/0.33 and −1.00 → −0.34/−0.33/−0.33 by recipient ID tie-break | `data/fixtures/finance/allocation/*.json` | Oracle test asserts each book sums 200.00 and never 400.00 | 3 |
| FND-004-S05 | Source-row fixtures per core source in RAW shape (WMH hourly, QAH with Q1 in A1 and B1, METERING_DAILY 15 gross −10 adjustment, USAGE_IN_CURRENCY_DAILY incl. account-null org fee and −3 rebate), UTC half-open windows, partial month 2026-09-01..2026-09-16 | `data/fixtures/sources/*/v1.*` | Rows validate against draft source contracts; all timestamps tz-aware UTC | 4 |
| FND-004-S06 | Privacy cases: SQL with literals, emails, comments; tags with emails; USER_NAME values for D-10 pseudonymization; expected sanitized strings | `data/fixtures/privacy/v1.json` | Each case has input and expected output; no real domains (only `example.com`, `.test`) | 3 |
| FND-004-S07 | Variant generator with fixed seed `20260927`: duplicate batch, out-of-order, late correction, partial batch (2 of 3 files), empty window, unsupported source, malformed SQL, missing price, two currencies | `tools/fixtures/generate.py` | Two runs produce identical canonical checksums; sorted-key JSON; no set iteration | 4 |
| FND-004-S08 | Loaders: Arrow IPC and Parquet (decimal128 preserved), PostgreSQL seed SQL, dbt seeds with explicit `column_types` for every column | `tools/fixtures/load_*.py`, `data/dbt/seeds/*.yml` | CI check: every seed column has explicit type; PG seed loads into throwaway container | 4 |
| FND-004-S09 | Determinism and PII tests: run under `TZ=Pacific/Kiritimati` and `TZ=America/Los_Angeles` → same outputs; PII scanner (emails outside allowed domains, real-looking account locators) → zero hits | `tests/fixtures/test_determinism.py`, `tools/fixtures/pii_scan.py` | Both pass; planted `john@acme.com` fails the scan | 3 |
| FND-004-S10 | Independent oracle suite in pure Python Decimal, not importing product code (import-linter contract forbids it) | `tests/fixtures/test_oracles.py` | Import of `bridge_*` from this suite fails lint | 3 |
| FND-004-S11 | Fixture README and evidence | `data/fixtures/README.md`, index entry | README lists every fixture ID and its consumers | 2 |
Task acceptance:
- [ ] Canonical checksums are identical across two regenerations and two timezones.
- [ ] Q1 exists in A1 and B1 without identity collision under the composite key.
- [ ] 70 + 30 = 100 credits (140.00 + 60.00 = 200.00), never 200 credits or 400.00.
- [ ] Every monetary value in fixtures is a decimal string with currency; every dbt seed column typed.

### FND-005 — Implement validation dispatcher and evidence schema
Release: R1 · Estimate: 26–38 h · Risk: M · Decisions: D-25 · Closes: G-FND-05
Dependency changes: `−FND-004` (dispatcher tests use synthetic manifests), `+FND-002`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FND-005-S01 | Write validation manifest schema (gates, env allowlist {local, ci, dev, staging}, argv arrays, requires, required, timeout_s, min_tests, watch_paths) | `tools/validation/manifest.schema.json`, `tests/spec/*/validation.yaml` template | A manifest with a shell string command or `env: prod` fails schema | 3 |
| FND-005-S02 | Implement dispatcher: task ID regex `^[A-Z]{2,4}-\d{3}$`, unknown task → exit 2, `subprocess.run(argv, shell=False)`, per-gate timeout | `tools/validation/validate_task.py`, `Makefile` target | `make validate-task TASK='FND-001; rm -rf /'` → exit 2 before any execution | 3 |
| FND-005-S03 | Environment gate: verify identity (`aws sts get-caller-identity` account equals `infra/environments/<env>.json`), Snowflake identity presence; refuse any account ID listed in prod manifest | `tools/validation/env_gate.py` | Missing identity → gate SKIPPED_REQUIRED; prod account → exit 4 | 3 |
| FND-005-S04 | Evidence schema and aggregate rule: task PASS only if every required gate PASS; NOT_APPLICABLE requires non-empty reason; SKIPPED_REQUIRED blocks DONE | `docs/evidence/schema/evidence.schema.json` | Aggregate unit tests over 6 gate combinations | 3 |
| FND-005-S05 | Redactor for stdout/stderr (AWS key IDs `AKIA…`/`ASIA…`, secret-like 40-char base64, JWT `eyJ…`, PEM blocks, `password=`, Snowflake tokens) plus entropy check | `tools/validation/redact.py` | 10 planted secrets redacted; redaction version recorded in evidence | 3 |
| FND-005-S06 | Evidence storage: local `.evidence/`; CI uploads artifacts to S3 evidence bucket (INF-003) or CI artifacts; repo appends index line only | `tools/validation/publish_evidence.py`, `docs/evidence/index/` | Index line validates; artifact sha256 matches uploaded object | 3 |
| FND-005-S07 | Freshness rule: ancestor check plus watch-path diff → VALID or STALE | `tools/validation/freshness.py` | Changing a watched file after evidence commit yields STALE; unrelated change keeps VALID | 3 |
| FND-005-S08 | Empty-suite and silent-skip detection: pytest exit 5 → FAIL; junit test count < `min_tests` → FAIL; vitest `--passWithNoTests` forbidden | dispatcher checks | Empty test dir yields FAIL, not PASS | 2 |
| FND-005-S09 | Integrity: `make validate-evidence` recomputes artifact hashes and rejects truncated JSON | `tools/validation/verify.py` | Truncated evidence file → FAIL with path | 2 |
| FND-005-S10 | Scenario tests: pass, fail, SKIPPED_REQUIRED, injection, stale | `tests/validation/test_dispatcher.py` | All five scenarios assert expected status and exit codes | 3 |
| FND-005-S11 | `make validate-docs`: link check, task-index schema, duplicate task/metric IDs, dependency acyclicity | `tools/validation/validate_docs.py` | Planted broken link and duplicate ID each fail | 3 |
| FND-005-S12 | Evidence README | `docs/evidence/README.md` | Documents storage, freshness, redaction | 1 |
Task acceptance:
- [ ] Deliberately failing assertion → FAIL; missing staging identity → SKIPPED_REQUIRED and task not DONE.
- [ ] No shell interpretation of any manifest value; prod targets refused.
- [ ] Evidence freshness computed, not assumed; stale evidence cannot satisfy a gate.
- [ ] Planted secrets never reach artifacts.

### FND-006 — Establish CI quality gates and agent working rules
Release: R1 · Estimate: 22–34 h · Risk: M · Decisions: D-19, D-25 · Closes: G-FND-10
Dependency changes: `−` implicit FND-004 chain; deps = FND-002, FND-005. INF-001 no longer depends on FND-006.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FND-006-S01 | Design `checks.yml` DAG: setup → lint (ruff, eslint, sqlfluff for dbt) → type (mypy, tsc) → boundaries → unit (pytest, vitest) → contracts (FND-103 drift) → docs → security (gitleaks, osv-scanner, licenses) → `dbt parse` (no credentials) | `.github/workflows/checks.yml`, `docs/development/ci-checks.md` | Every job listed with owner and blocking flag | 4 |
| FND-006-S02 | Harden workflows: `permissions: {}` top-level; SHA-pinned actions; `persist-credentials: false`; ban `pull_request_target` via `zizmor`/`actionlint` job; `id-token: write` only in environment-bound jobs on `push`/`merge_group` | workflow files, `.github/workflows/lint-workflows.yml` | Lint fails on a planted `uses: actions/checkout@v4` (tag) and on `pull_request_target` | 3 |
| FND-006-S03 | Branch ruleset for `main`: required checks, CODEOWNERS review, merge queue, linear history, no force-push | ruleset JSON export in `docs/development/ci-checks.md` | Direct push to main rejected (recorded) | 2 |
| FND-006-S04 | CODEOWNERS by path (infra/**, data/contracts/**, data/dbt/models/ledger/**, apps/api/auth/**, docs/architecture/adr/**) | `.github/CODEOWNERS` | Every required check and sensitive path has a named owner | 1 |
| FND-006-S05 | Secret scanning: gitleaks CLI (checksum-verified) in pre-commit and CI; custom rules for `connections.toml` tokens and PEM keys; nightly full-history scan | `.gitleaks.toml`, `.pre-commit-config.yaml` | Planted fake PEM in a test branch fails CI | 3 |
| FND-006-S06 | Vulnerability and license gates from FND-002 allowlist (osv-scanner, license report) | CI job `supply-chain` | Planted AGPL dependency in test branch fails | 2 |
| FND-006-S07 | Silent-skip guard: collected test count per suite compared with main baseline (drop >20% fails unless label `tests-removed`) | `tools/ci/test_count_guard.py` | Deleting a test file without label fails | 2 |
| FND-006-S08 | AGENTS.md: claim protocol (branch `task/<ID>-<slug>`, draft PR with task ID, STATUS line), read order, checkpoint format, stop conditions (SKIPPED_REQUIRED, ADR conflict), forbidden actions (edit ADR outside ADR PR, weaken tests, obtain cloud credentials) | `AGENTS.md` | Reviewed by tech lead; referenced from README | 3 |
| FND-006-S09 | Agent runbook: resume from checkpoint, blocker template, handoff record | `docs/development/agent-runbook.md` | Contains filled example for a blocked live gate | 2 |
| FND-006-S10 | Negative validation: broken link, duplicate task ID, secret-like fixture, failing finance oracle — each in an isolated branch | CI run links in evidence | All four rejected with remediation text | 3 |
| FND-006-S11 | Fork simulation: PR from a fork receives no OIDC token and no secrets | evidence of workflow run | Job requesting `id-token` is not scheduled for fork PR; recorded | 2 |
| FND-006-S12 | Record evidence | index entry | Complete | 1 |
Task acceptance:
- [ ] No workflow references an action by tag; no `pull_request_target`; default token permissions empty.
- [ ] Fork PRs cannot obtain cloud credentials (proved by run).
- [ ] Every required check has an owner; the four deliberate violations are rejected.
- [ ] AGENTS.md defines claim, checkpoint and stop rules consumed by coding agents.

## 5. New tasks required

### FND-101 — Developer Snowflake inner loop (DEV SSO, personal schemas, CI ephemeral schemas)
Release: R1 · Estimate: 15–22 h · Risk: M · Decisions: D-21, D-19, D-25 · Closes: G-FND-02
Why: The engineering contract forbids RSA shortcuts but gives no working path; without one, all SQL work routes through staging. Plugs in: deps FND-002, FND-004, INF-008 (DEV account + SAML integration + IaC identity); blocks DBT-001 (developer use), FIN-* SQL work. dbt CI (schema naming, fixture load, baseline, deferral, janitor) is DBT-102's and `profiles.yml` is DBT-001's; this task keeps the human inner loop only (RECONCILIATION U-15, C-18).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FND-101-S01 | Write decision record: humans TYPE=PERSON + SAML SSO in BRIDGE_DEV only; STAGING none; PROD named break-glass; coding agents get no Snowflake identity; rejected alternatives (key pair, PAT, laptop WIF as SERVICE user) with reasons | `docs/development/snowflake-dev-access.md` | Approved by security owner | 2 |
| FND-101-S02 | Terraform developer users from `infra/snowflake/dev-users.yaml` (`snowflake_user` TYPE=PERSON, login_name=IdP email, no password, DEFAULT_ROLE `DEV_U_<user>`, DEFAULT_SECONDARY_ROLES empty) | `infra/terraform/stacks/70-snowflake/dev_users.tf` | Plan shows no password attribute; apply creates users | 3 |
| FND-101-S03 | Per-developer role owning `BRIDGE_DEV_SANDBOX.DEV_<USER>` schema and warehouse `DEV_WH_<USER>` (XSMALL, AUTO_SUSPEND=60, STATEMENT_TIMEOUT_IN_SECONDS=900) with 20-credit monthly resource monitor (notify 80%, suspend 100%) | same stack | Role can create in own schema; cannot in another developer's schema | 2 |
| FND-101-S04 | Moved to DBT-102-S03/S04 per RECONCILIATION U-15 (fixture load and baseline under the WIF CI user) — consume its output here | — | — | 0 |
| FND-101-S05 | Contribute the `dev` target to DBT-001-S03's `profiles.yml` (`authenticator: externalbrowser`, personal schema via the dev branch of DBT-102-S01's `generate_schema_name`) and the laptop refusal of `staging`/`prod` unless `BRIDGE_RUNTIME=aws`; the `ci` target and CI schema naming are DBT-001-S03/DBT-102-S01 (RECONCILIATION U-15, C-18) | `data/dbt/profiles.yml` (dev target), `data/dbt/macros/generate_schema_name.sql` (dev branch) | `dbt debug --target dev` opens browser SSO; `--target prod` on laptop exits with refusal | 2 |
| FND-101-S06 | Python dev connection factory `connect_dev()` (externalbrowser) that refuses account identifiers not equal to the DEV locator in the env manifest | `packages/snowflake_client/dev.py` | Passing STAGING identifier raises `NonDevTargetRefused` | 2 |
| FND-101-S07 | Moved to DBT-102-S01/S05/S06 per RECONCILIATION U-15, C-18 (schema `CI_PR<nr>_<sha7>_<layer>` in `BRIDGE_CI`, 24 h janitor, INF-002-S09 in-VPC runner) — consume its output here | — | — | 0 |
| FND-101-S08 | Guardrails: account authentication policies (PERSON → SAML only; SERVICE → WORKLOAD_IDENTITY only); DEV account has no network policy for humans; per-user monitors | `infra/terraform/stacks/70-snowflake/auth_policies.tf` | Password login attempt for a PERSON user fails; service user SAML attempt fails | 2 |
| FND-101-S09 | Session-cache hygiene: `.gitignore` for local Snowflake config; gitleaks rule for `token`/`password` in `connections.toml`; `client_store_temporary_credential` only with OS keyring | `.gitignore`, `.gitleaks.toml` | Planted `connections.toml` with token fails pre-commit | 1 |
| FND-101-S10 | Negative tests: dev user login to STAGING fails (no user); dev role cannot read `BRIDGE_CI` other PR schemas; cannot write fixtures; `make dbt-dev` with STAGING locator refused | `tests/live/dev_access/*.py` | All four denials recorded | 2 |
| FND-101-S11 | Snowflake quickstart (≤15 min: SSO login, run one model into personal schema) validated by second developer | `docs/development/snowflake-quickstart.md` | Timed run recorded | 2 |
| FND-101-S12 | Record evidence | index entry | Complete | 1 |
Task acceptance:
- [ ] A developer runs one dbt model in a personal DEV schema via SSO without any key file, password or PAT.
- [ ] PR builds in ephemeral CI schemas are delivered by DBT-102 (RECONCILIATION U-15); developer roles cannot read or write them.
- [ ] No human identity exists in STAGING; PROD human access is named break-glass only.
- [ ] Per-developer spend is capped by a resource monitor.

### FND-102 — Recorded Snowflake fixtures and adapter replay harness
Release: R1 · Estimate: 20–30 h · Risk: M · Decisions: D-13, D-10 · Closes: G-FND-08
Why: This keeps mock adapters faithful to live view schemas and makes BCR/schema drift visible weekly. Plugs in: deps FND-005, INF-101 (test estate), INF-008 (runner identity); consumed by ING-001, ING-003, CON-005.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FND-102-S01 | Define recorded fixture metadata schema: source_id, contract_version, account_alias, edition, cloud/region, window [start,end) UTC, projection_sql_sha256, cursor description (name, type_code, precision, scale, null_ok), schema_fingerprint, row_count, parquet_sha256, connector_version, recorded_at, recorder_git_sha, sanitizer_version | `data/fixtures/recorded/meta.schema.json` | Schema validates a sample record | 2 |
| FND-102-S02 | Build recorder CLI: runs adapter projection SQL (bootstrap list: QUERY_HISTORY, WAREHOUSE_METERING_HISTORY, METERING_DAILY_HISTORY, QUERY_ATTRIBUTION_HISTORY, ORGANIZATION_USAGE.ACCOUNTS until ING-001 registry exists) for a closed window older than the D-13 horizon, writes ZSTD Parquet preserving decimal128 precision/scale | `tools/sf_recorder/` | Recording from test-estate A1 produces Parquet whose Arrow schema equals cursor description types | 4 |
| FND-102-S03 | Size and privacy policy: ≤2,000 rows and ≤5 MB per fixture; text columns passed through SEC-007 sanitizer (or dropped until SEC-007 lands); PII scan zero hits; storage in S3 fixtures bucket with committed sha256 manifest and `make fixtures-pull` | `data/fixtures/recorded/manifest.json` | Pull verifies checksums; oversize fixture rejected | 2 |
| FND-102-S04 | Replay fake implementing the connector subset used by adapters (`execute`, `description`, `fetch_arrow_batches`, `sfqid`) including recorded errors (002003 object does not exist, 003001 insufficient privileges) | `packages/snowflake_client/testing/recorded.py` | Adapter unit test runs identically against replay and live (schema equality) | 4 |
| FND-102-S05 | Weekly drift workflow re-records into a temp prefix and compares schema_fingerprint and column set; on drift fails `contract-drift` check and opens an issue with the diff; never overwrites committed fixtures | `.github/workflows/sf-contract-drift.yml` | Simulated added column produces issue and failing check | 3 |
| FND-102-S06 | Lint: recorded fixtures cannot be referenced from `tests/financial/**` (money oracles stay synthetic) | import/path lint rule | Planted reference fails lint | 1 |
| FND-102-S07 | Tests: mutated fixture (scale 9→6 on CREDITS column) fails the contract test with explicit field message | `tests/contracts/test_recorded_replay.py` | Failure message names source, column, expected/actual type | 3 |
| FND-102-S08 | Runbook for re-recording and approving drift (links RB-04) | `data/fixtures/recorded/README.md` | Reviewed | 1 |
| FND-102-S09 | Record evidence | index entry | Complete | 1 |
Task acceptance:
- [ ] At least 5 core sources recorded from ≥2 test-estate accounts (Enterprise and Standard).
- [ ] Replay and live runs produce identical Arrow schemas for the same projection.
- [ ] Weekly drift job detects a schema change without human polling.
- [ ] No recorded fixture is used as a financial oracle.

### FND-103 — Contract codegen and Decimal/UUID/date enforcement
Release: R1 · Estimate: 14–22 h · Risk: L · Decisions: D-12, D-18 · Closes: G-FND-06
Why: Generated types across boundaries are a contract requirement with no owning task. Plugs in: deps FND-001, FND-002, FIN-106 (money JSON grammar `money.schema.json` from FIN-106-S04; RECONCILIATION U-20); blocks API-001 and UX-002.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| FND-103-S01 | Define contract sources: FastAPI OpenAPI 3.1 export `make openapi` → committed `apps/api/openapi.json`; event/config JSON Schemas under `data/contracts/` | Makefile target, directory README | Export deterministic (two runs identical bytes) | 2 |
| FND-103-S02 | Conventions + Spectral ruleset: money `type: string`, `format: decimal`, pattern imported from FIN-106-S04 `money.schema.json` (`^-?(0\|[1-9][0-9]{0,25})(\.[0-9]{1,12})?$`, internal NUMBER(38,12); RECONCILIATION C-14, U-20); UUID `format: uuid`; dates `format: date` (UTC), timestamps `date-time` with `Z`; enums as string enums; ban `type: number` on money-like names | `contracts/.spectral.yaml`, `docs/development/api-conventions.md` | Planted `amount: {type: number}` fails lint | 3 |
| FND-103-S03 | TS generation (`openapi-typescript`) into `packages/api-types`, typed client (`openapi-fetch`), branded `DecimalString`; ESLint rule bans `Number()`, `parseFloat`, unary `+` on DecimalString | `packages/api-types/`, `eslint-rules/no-decimal-arithmetic.js` | Planted `Number(row.amount)` in apps/web fails lint | 3 |
| FND-103-S04 | Python models from JSON Schemas for events/config (datamodel-code-generator) with `Decimal` fields | `packages/contracts_py/generated/` | Generated model parses `"-0.10"` to `Decimal("-0.10")` | 2 |
| FND-103-S05 | Drift and breaking-change gates: regenerate + `git diff --exit-code`; oasdiff breaking check vs main requiring label `api-breaking` | CI jobs | Hand edit of generated file fails; removing a response field fails without label | 3 |
| FND-103-S06 | Round-trip tests: `"-0.10"` stays `"-0.10"`; `"1E+2"` rejected; unknown enum value handled per contract; UUID uppercase normalized or rejected per rule | `tests/contracts/test_roundtrip.py` | All cases pass | 2 |
| FND-103-S07 | Documentation of client usage and formatting helpers (locale-aware formatting only, D-18) | `packages/api-types/README.md` | Reviewed | 2 |
| FND-103-S08 | Record evidence | index entry | Complete | 1 |
Task acceptance:
- [ ] No money field in OpenAPI or JSON Schemas is `type: number`.
- [ ] Generated TS/Python artifacts cannot drift from sources without failing CI.
- [ ] Web code cannot perform arithmetic on DecimalString values.

## 6. Estimate summary

| Task | Release | Low h | High h |
|---|---|---:|---:|
| FND-001 | R1 | 18 | 26 |
| FND-002 | R1 | 22 | 32 |
| FND-003 | R1 | 22 | 32 |
| FND-004 | R1 | 30 | 44 |
| FND-005 | R1 | 26 | 38 |
| FND-006 | R1 | 22 | 34 |
| FND-101 (new) | R1 | 15 | 22 |
| FND-102 (new) | R1 | 20 | 30 |
| FND-103 (new) | R1 | 14 | 22 |
| **Total R1** | | **189** | **280** |
| **Total R2** | | **0** | **0** |

The original methodology implies 6 tasks × 2–6 h = 12–36 h for FND. The realistic figure is about 6–8× higher, before the three new tasks.

## 7. Owner questions

1. Which identity provider will staff use for Snowflake DEV SSO and AWS: IAM Identity Center, Okta, Entra ID or Google? This decides the SAML integration and whether SCIM provisioning is available. The default assumed is IAM Identity Center as SAML IdP with Terraform-managed users.
2. Which GitHub plan applies to this repository (Team, Enterprise Cloud, Secret Protection/Advanced Security)? It decides push protection and private-repo artifact attestations; otherwise the gitleaks CLI plus KMS-signed cosign is used.
3. Confirm that coding agents receive no Snowflake/AWS identity and use only CI ephemeral schemas (recommended).
4. Supported developer OSes: macOS arm64 and Linux x86_64 are assumed; is Windows via WSL2 required?
5. Is `prototypes/finops-react` a frozen reference (recommended) or the seed of `apps/web` to be migrated under pnpm?
