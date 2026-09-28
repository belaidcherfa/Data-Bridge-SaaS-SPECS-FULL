# Technology stack, libraries, tools, MCP servers and methodology

Status: ACCEPTED baseline 2026-09-28. Versions below are the **latest stable releases observed on PyPI/npm on 2026-09-28** and are the starting point for FND-002, which locks exact versions (uv.lock, pnpm-lock.yaml, image digests) after compatibility tests (ADR-010). Agents must not introduce libraries outside this list without the `lock:lockfiles` lock and a justification; "Avoid" entries are forbidden.

## 1. Runtimes and package managers

| Item | Baseline | Notes |
|---|---|---|
| Python | **3.13** | Satisfies dagster-dbt (<3.14), numpy/scipy (≥3.12), sqlalchemy 2.1 (≥3.11). Fallback 3.12 if FND-002 finds an incompatibility. |
| uv | 0.12.19 | Python workspaces, lockfile, `uv run` for tools (PEP 723 scripts). |
| Node.js | **24 LTS** (24.21.0 "Krypton") | Vite 8, Vitest 5, ESLint 10, Astro 7 all support ≥22.12/24. |
| pnpm | 12.6.0 | Workspaces; `pnpm-lock.yaml`. |
| TypeScript | **6.0.3** | TypeScript 7.0 (native compiler) is released (7.0.2) but lint/tooling compatibility must be proven first (FND-002 spike); do not adopt 7.x without that evidence. |
| Containers | Docker/BuildKit, distroless or slim Python base images pinned by digest | Non-root, read-only filesystem where possible. |

## 2. Backend (Python)

| Purpose | Library (baseline version) | Rules |
|---|---|---|
| HTTP API | FastAPI 0.141.1, Uvicorn 0.54.0 (+ Gunicorn 26.2.0 workers) | OpenAPI is contract-first (contracts/openapi); FastAPI models must match it (contract tests). |
| Models/validation | Pydantic 2.13.5, pydantic-settings 2.15.0 | Money fields are `Decimal` with string serialization. |
| PostgreSQL | SQLAlchemy 2.1.1 (async), asyncpg 0.31.0, Alembic 1.20.0, psycopg 3.3.6 (tools/migrations) | Transaction-local `app.tenant_id`; no ORM lazy loading across tenants. |
| Redis/Valkey | redis 8.1.0 (client works with ElastiCache Valkey) | Cache only; never durable state or locks of record. |
| HTTP client | httpx 0.28.1 | Timeouts mandatory; SSRF-safe transport for webhooks (GOV). |
| Auth | PyJWT 2.15.0 + cryptography 50.0.1 | Cognito JWKS validation; BFF sessions. |
| AWS | boto3 1.43.x (aioboto3 15.5.0 where async needed) | Credentials from task roles only. |
| Snowflake | snowflake-connector-python 4.7.5 | `authenticator='WORKLOAD_IDENTITY'`, `arrow_number_to_decimal=True`, UTC session. |
| Arrow/Parquet | pyarrow 25.0.1 | Decimal128 for money; ZSTD Parquet. |
| SQL parsing/sanitizer | sqlglot 30.20.0 | Silence the `sqlglot` logger (G-SEC-14); reject `Command` nodes. |
| Transformations | dbt-core 1.12.5, dbt-snowflake 1.12.1 | dbt Core only (no Fusion/Cloud); WIF authenticator (D-21). |
| Orchestration | dagster 1.13.24, dagster-webserver 1.13.24, dagster-postgres / dagster-aws / dagster-dbt 0.29.24 | Custom launcher rules (D-07): Dagster never passes customer roles. |
| Statistics | numpy 2.5.3, scipy 1.18.1 | Forecast/anomaly in `packages/bridge_stats`; no pandas in hot paths (polars 1.44.2 allowed for offline analysis/tests). |
| Logging/telemetry | structlog 26.1.0, opentelemetry-sdk 1.45.0 (+ instrumentation 0.66b0) | Log schema `packages/telemetry/schema/log-event.v1.json`. |
| Retries | tenacity 9.1.4 | Classified transient errors only. |
| IDs | uuid6 2025.0.1 (UUIDv7), python-ulid only if a contract requires it | CONVENTIONS §3. |
| JSON | orjson 3.12.0 | Decimal-safe serializers in `packages/api_contracts`. |
| Reports | Playwright 1.63.0 (Chromium render worker); pypdf 6.19.0 for checks | WeasyPrint 70.0 as fallback only if RPT-002 proves it. |
| Notifications | slack-sdk 3.44.1, standardwebhooks 1.1.0, SES via boto3 | Teams via Workflows webhook (HTTP). |
| Billing (R2) | stripe 15.6.1 | Only for payment-link references in R1 (D-30). |
| Error monitoring (optional) | sentry-sdk 2.70.0 | Only if Sentry is approved as subprocessor (EU region). |
| Product analytics (optional) | posthog 7.60.1 | EU cloud or self-hosted; consent-gated. |

## 3. Frontend (React)

| Purpose | Library (baseline) | Rules |
|---|---|---|
| Framework | React 19.3.0, React DOM 19.3.0 | |
| Build | Vite 8.3.1, @vitejs/plugin-react 6.1.1 | SPA served from S3 + CloudFront (D-28). |
| Routing | @tanstack/react-router 1.170.x | URL is the source of truth for scope/filters; `/t/:tenantSlug/...`. |
| Data fetching | @tanstack/react-query 5.104.0, openapi-typescript 7.13.0 + openapi-fetch 0.17.0 | Query keys include tenant, profile, epoch, publication_id. |
| Tables | @tanstack/react-table 9.2.4 (verify v9 API in FND-002; fall back to 8.21.x if needed), @tanstack/react-virtual 3.14.x | Server-side pagination only. |
| UI kit | shadcn 4.21.0 (CLI) + radix-ui 1.6.7, Tailwind CSS 4.3.3 (@tailwindcss/vite), class-variance-authority 0.7.1, lucide-react 1.48.0 | Design tokens from docs/21-ui-ux/FOUNDATIONS.md. |
| Charts | Recharts 3.10.1 (default); ECharts 6.1.0 only for dense series if a screen contract requires it | Every chart has a tabular alternative. |
| Forms | react-hook-form 7.89.0, zod 4.6.5, @hookform/resolvers 5.9.1 | |
| i18n | i18next 26.4.2 + react-i18next 17.0.15 (ICU plugin) | All strings externalized from day 1 (D-18). |
| Numbers/dates | Intl APIs; decimal.js 10.6.0 for formatting decimal strings only; date-fns 4.4.0 + @date-fns/tz 1.5.0 | No client-side financial arithmetic. |
| Tests | Vitest 5.0.2, @testing-library/react 16.3.3, MSW 2.15.0, @playwright/test 1.63.0, @axe-core/playwright 4.13.0 | |
| Lint/format | ESLint 10.11.0, typescript-eslint 8.70.1, eslint-plugin-boundaries 7.2.0, Prettier 3.9.9, knip 6.38.0 | |
| Error monitoring (optional) | @sentry/react 11.0.0 | Same approval as backend. |

## 4. Infrastructure, CI/CD and supply chain

| Purpose | Tool | Notes |
|---|---|---|
| IaC | Terraform ≥ 1.9 (exact version pinned in FND-002; registry not reachable from the review sandbox), providers `hashicorp/aws`, `snowflakedb/snowflake` (account objects only; pipes/stages via migrations per G-INF-03) | State per env/stack, S3 backend with lockfile (INF-102). |
| Snowflake migrations | Repository migration runner (INF-104) over `infra/snowflake/migrations/` | Versioned `V<NNNN>__*.sql`, grant audit. |
| CI | GitHub Actions with OIDC to AWS; self-hosted ephemeral runners inside the VPC for live gates (G-INF-04) | Required checks listed in `docs/development/ci-checks.md`. |
| Supply chain | Syft (SBOM), Cosign (signing), Trivy (image/IaC scan), gitleaks (secrets), pip-audit 2.10.1, pnpm audit, Renovate 44.x (dependency PRs, grouped, weekly) | Renovate PRs are tier-C tasks for agents. |
| Policy | Checkov or Trivy config for Terraform; conftest (OPA) plan policy (INF-102) | |
| Code quality | Ruff 0.16.9, mypy 2.3.1 (strict), import-linter 2.15, deptry 0.25.1, sqlfluff 4.3.0 (+ dbt templater), pre-commit 4.6.2 | |
| Testing | pytest 9.1.1, pytest-asyncio 1.4.0, Hypothesis 6.168.x, testcontainers 4.15.0 (PostgreSQL, Valkey, MinIO), moto 5.2.3 (unit only), Schemathesis 4.28.0 (API fuzz from OpenAPI) | |
| API docs | Redocly CLI 2.54.x (bundle/lint), Spectral 6.16.3 (rules in contracts/.spectral.yaml) | |
| Docs & marketing sites | Astro 7.3.x + Starlight 0.42.x (static, S3 + CloudFront) | Public docs, API reference, changelog, status links (SAS tasks). |

## 5. Agent tooling

| Tool | Version | Use |
|---|---|---|
| Claude Code CLI | `@anthropic-ai/claude-code` 2.1.283 (Node ≥ 22) | Orchestrator (interactive) and headless workers (`claude -p`). |
| Claude Agent SDK (Python) | `claude-agent-sdk` 0.2.160 | Headless orchestrator loop (AGT-003). |
| Anthropic SDK | `anthropic` 1.8.0 | Only for non-agent utilities (e.g. report summarization) if needed. |
| GitHub CLI | latest stable | PRs, labels, merge queue from the orchestrator. |
| GitHub Action | `anthropics/claude-code-action@v1` | Mode C (CI-hosted workers) and scheduled ticks. |

Models: orchestrator and reviewers **Opus 5.5** (`claude-opus-5-5`) or **Fable 5.1** (`claude-fable-5-1`); workers **Sonnet 5** (`claude-sonnet-5`) or Opus 5.5 for tier-A tasks; mechanical tasks may use **Haiku 4.5** (`claude-haiku-4-5-20251001`).

## 6. MCP servers (`.mcp.json`)

Enabled by default (no credentials, low risk):

| Server | Package | Purpose |
|---|---|---|
| playwright | `@playwright/mcp` 0.0.82 | Drive the local web app, verify UI states, capture screenshots for evidence. |
| context7 | `@upstash/context7-mcp` 4.1.1 | Up-to-date library documentation for pinned versions. |
| aws-docs | `awslabs.aws-documentation-mcp-server` 1.2.1 (via `uvx`) | Official AWS documentation lookup. |
| terraform | `awslabs.terraform-mcp-server` 1.0.18 (via `uvx`) | Provider/resource documentation and Terraform best practices. |

Optional, enabled per environment with least-privilege credentials from environment variables (never committed):

| Server | Package | Guardrails |
|---|---|---|
| github | GitHub's official MCP server (remote) or the `gh` CLI | Fine-grained token or GitHub App limited to this repository; cannot bypass branch protection. |
| snowflake-dev | `snowflake-labs-mcp` 1.4.2 (via `uvx`) | DEV sandbox account only, read-mostly role, never the central PROD/STAGING accounts or customer accounts. |
| postgres-local | `postgres-mcp` 0.3.0 | Local Compose database only, restricted mode. |
| aws-api-dev | `awslabs.aws-api-mcp-server` 1.5.5 | DEV account read-only profile. |
| cloudwatch-dev | `awslabs.cloudwatch-mcp-server` 0.3.1 | DEV/STAGING logs and metrics read-only. |
| linear / notion | Owner's connectors | Posting daily reports and escalations if the owner wants them there. |

Never configure an MCP server with production credentials or customer data access.

## 7. Methodology

- **Contract-first, fixture-first**: author/accept the contract, write the failing test from the golden fixture, implement the smallest slice, then edge cases, authorization, observability, docs, evidence (the micro-step order in every packet).
- **Trunk-based with short-lived agent branches**, squash merges through a merge queue, main always green, revert-first on breakage.
- **Evidence-driven Definition of Done** (AGENTS.md §6) and independent verification by a different agent than the implementer.
- **Security by design**: threat model per boundary (SEC-001), attack catalog tests in CI, least privilege, secrets never in code.
- **Financial correctness by construction**: exact decimals, conservation invariants as tests, golden fixtures reviewed by the FinOps reviewer.
- **Observability as a feature**: SLOs from day one (OPS re-milestoned), every alert has an owner and a runbook.
- **Small batches**: PRs ≤ ~800 lines, tasks ≤ ~24 h per slice.
- **Architecture decisions** through ADRs; no silent deviations; escalate instead of improvising.
- **DORA-style metrics** for the delivery system itself (lead time, change failure rate, time to restore) in weekly reports.

## 8. Commands (until the `make` dispatcher exists)

| Target | Underlying command |
|---|---|
| `make packets` | `uv run tools/delivery/build_packets.py` |
| `make next-tasks` | `uv run tools/delivery/next_tasks.py` |
| `make contracts-check` | `uv run tools/contracts/check.py` (JSON/YAML parse, JSON Schema meta-validation, examples, SQL parse, Spectral) |
| `make lint` | `uv run ruff check . && pnpm -r lint` |
| `make typecheck` | `uv run mypy . && pnpm -r typecheck` |
| `make test-unit` | `uv run pytest -m "not integration and not live" && pnpm -r test` |
