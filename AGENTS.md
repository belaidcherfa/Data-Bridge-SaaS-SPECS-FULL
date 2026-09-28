# AGENTS.md — rules for every coding agent in this repository

Bridge Data FinOps is a production multi-tenant Snowflake FinOps SaaS built by coding agents under an orchestrator ([ORCHESTRATION](docs/23-agentic-delivery/ORCHESTRATION.md)). These rules are mandatory for implementers, reviewers, verifiers and the orchestrator. When a rule conflicts with a task packet, the rule wins and you escalate.

## 1. Start of every task

1. Read your packet `delivery/packets/<TASK-ID>.md` completely, then the files under **Read first** in order. Do not load the whole repository.
2. The orchestrator dispatches you only when every dependency in `depends_on` is `DONE` (ledger branch `delivery-ledger`, ADR-018 §5). If you were started manually, check with `uv run tools/delivery/next_tasks.py --state <ledger>/delivery/state.json`; if a dependency is not done, stop and report.
3. Work only in your worktree and branch `agt/<task-id>-<slug>`. Never commit to `main`, never force-push, never rewrite shared history.
4. Implement micro-steps **in order**, fixture/test first, one commit per micro-step: `<type>(<domain>): <TASK-ID>-Sxx <summary>` (types: feat, fix, test, docs, refactor, chore, perf, build, ci).

## 2. Sources of truth (in precedence order)

1. Decision record: `docs/22-implementation-readiness/DECISIONS_REQUIRED.md` (D-01…D-38).
2. ADRs: `docs/architecture/adr/` (ADR-001…ADR-018, with amendments; ADR-018 governs this delivery system).
3. Contracts: `contracts/` (start with `contracts/CONVENTIONS.md`), `data/contracts/`, `infra/snowflake/migrations/`, package schemas. Only `ACCEPTED` contracts may be depended on outside their owning task.
4. Reconciliation rulings: `docs/22-implementation-readiness/RECONCILIATION.md`.
5. Your task packet and its backlog section (`docs/22-implementation-readiness/backlog/<DOM>.md`).
6. Canonical domain docs `docs/NN-*/…` (amended 2026-09-28) and the PRD `docs/00-project/PRD.md` (read-only, byte-exact — never edit).

If a backlog path contradicts `contracts/CONVENTIONS.md` or `contracts/README.md`, the conventions win.

## 3. Non-negotiable engineering rules

- **Tenant isolation**: every tenant-owned row has `tenant_id`; PostgreSQL uses transaction-local `app.tenant_id` + FORCE RLS; Snowflake serving reads go through the query broker under a tenant/profile identity with row access policies; API derives the tenant from authenticated membership + `X-Bridge-Tenant` (echoed). Every tenant-scoped change ships foreign-tenant, missing-context and revoked-scope tests.
- **Money**: decimal strings in JSON, `decimal.Decimal` in Python (via `packages/bridge_money`), `NUMBER(38,12)` in Snowflake. No floats, anywhere, ever — including Arrow (`arrow_number_to_decimal=True`) and Parquet. Never sum different currencies. Unknown is `null` + reason, never `0`. The web app never computes financial totals.
- **Time**: UTC everywhere, half-open intervals `[start, end)`, Snowflake sessions `TIMEZONE='UTC'`.
- **Idempotency**: every write and publication has an idempotency identity; retries must not double-count, double-send or double-publish.
- **Secrets**: never read, print, log, commit or paste secrets or credentials. Use WIF/OIDC/Secrets Manager; placeholders like `<AWS_ACCOUNT_ID>` in code and docs.
- **Privacy**: user identifiers are pseudonymized at extraction (D-10); SQL text is sanitized before persistence (ADR-009); logs carry IDs, never personal data or SQL.
- **No shortcuts**: never skip, weaken, xfail or delete a test to get green; never disable a CI check; never mark something done without its oracle passing.
- **Scope**: modify only files matching your packet's `writes`. Need something else? Escalate (skill `escalate`) — do not drive-by refactor.
- **Contracts**: implement against contracts; if a contract is wrong or missing, open a `contract-change` escalation. New error codes, events, capabilities or enums must be added to the owning contract file, not invented inline.
- **Dependencies**: libraries and versions come from `docs/23-agentic-delivery/STACK.md`; adding one requires the `lock:lockfiles` lock and a PR justification.
- **Vendor behavior**: anything marked `TO VERIFY LIVE` must be proven in the test estate before production code relies on it; record the evidence.

## 4. Repository map

`docs/` specifications (PRD read-only) · `contracts/` executable contracts · `data/contracts/`, `data/dbt/`, `data/fixtures/` data layer · `services/` Python services (api, query broker, extractor, orchestrator, intelligence, governance, reporting, workers) · `apps/web` React app · `packages/` shared libraries · `infra/` Terraform, Snowflake migrations, observability · `config/environments/` owner-supplied non-secret identifiers · `delivery/` packets, state, reports, escalations · `tools/` repository tooling · `tests/` cross-cutting suites (security, e2e, perf, spec/<TASK-ID>).

## 5. Commands

Use the repository `make` targets; a target that does not exist yet is created by the FND task that owns it — if you need it before then, run the underlying tool directly as listed in `docs/23-agentic-delivery/STACK.md` §Commands.

`make bootstrap` · `make up` / `make down` · `make lint` · `make typecheck` · `make test-unit` · `make test-contract` · `make test-integration-pg` · `make test-security` · `make test-financial` · `make dbt-build-fixtures` · `make test-web` · `make test-e2e-affected` · `make a11y` · `make contracts-check` · `make infra-validate` · `make validate-task TASK=<ID> ENV=local|staging` · `make packets` · `make next-tasks`.

## 6. Definition of done (every task)

- [ ] All micro-step oracles pass; each micro-step ticked in the PR description with the commit that did it.
- [ ] Packet `checks` green locally and in CI; coverage of changed lines ≥ 85 % Python / 80 % TypeScript (or justified).
- [ ] Contracts respected; contract tests added or updated; no drift reported by `make contracts-check`.
- [ ] Tenant-isolation, money, privacy and UX-state rules satisfied where applicable (reviewer rubric: ORCHESTRATION §7).
- [ ] Observability: metrics/log fields from `packages/telemetry` registries; no PII in logs.
- [ ] Runbook/docs updated where the packet says so.
- [ ] Evidence manifest `docs/evidence/<TASK-ID>/<short-sha>/index.json` (fields: task_id, commit, environment, started/ended UTC, tool versions, fixture IDs, commands + exit codes, expected vs observed, artifact checksums, model used, reviewer, remaining gates).
- [ ] Human and live gates prepared and listed in the PR; nothing requiring a human is claimed as passed.

## 7. Pull requests

Title `<TASK-ID>: <title>` (slices: `<TASK-ID> [slice n/m]: …`). Body uses `.github/pull_request_template.md`: packet link, micro-steps checklist, oracle results (expected vs observed), tests added, contracts touched, risks, gates, evidence link, model and budget used. Keep PRs ≤ ~800 changed lines excluding generated files; split into slices otherwise. Labels: `agent`, `tier-A|B|C`, `lane-<X>`, `needs-human` (if a human gate applies), `contract-change` (if a contract changes).

## 8. Escalate instead of guessing

Escalate (write `delivery/escalations/<UTC-timestamp>-<TASK-ID>.md` with context, options, recommendation, impact; see `docs/23-agentic-delivery/STATE_AND_REPORTING.md`) when: a decision or contract is missing/contradictory; an ACCEPTED contract must change; a vendor behavior differs from the spec; credentials, access or budget are needed; the change would leave your `writes`; two attempts failed; or a security or financial invariant might be violated. Then continue with independent micro-steps, or stop.

## 9. Forbidden (hooks and CI enforce these)

Push to `main`; force push; `git reset --hard` on shared branches; `terraform apply` outside DEV; production credentials; `rm -rf` outside your worktree; editing `docs/00-project/PRD.md`, `.claude/settings.json` hooks or CI required checks; committing `.env`, keys, tokens or real customer data; disabling RLS, row access policies or authorization checks; sending notifications/e-mails to real recipients outside approved test destinations.
