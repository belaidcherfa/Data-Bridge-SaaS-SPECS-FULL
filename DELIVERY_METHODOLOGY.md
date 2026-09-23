# Delivery methodology

## How an implementation session starts

1. Read [the master plan](PROJECT_MASTER_PLAN.md) and `docs/00-project/STATUS.md` when available.
2. Load the task index. Select the earliest `NOT_STARTED` task whose dependencies have accepted implementation evidence. Documentation publication is not dependency completion.
3. Read that task, its canonical domain contract and linked ADRs. Do not load the whole repository as a substitute for explicit dependencies.
4. Inspect current code and tests. Record baseline commit, task owner, assumptions and worktree. Never overwrite unrelated work.
5. Set implementation state to `IN_PROGRESS`, record the next micro-task and evidence paths. Only one owner changes an interface at a time.

## Task sizing and hierarchy

Domain defines a boundary; epic defines an outcome; feature defines a capability; user story defines persona and value. Tasks deliver one independently provable change. Each task has numbered micro-tasks with observable outputs and exact test oracles. Target one focused implementation session per task (typically 2–6 engineering hours); split a task if migrations, interfaces or evidence cannot be reviewed independently. Estimates are planning bounds, not promises.

Micro-tasks cover contract/fixture, smallest implementation slice, failure/retry behavior, authorization, observability and proof. No task is done because it compiles. Do not implement later features opportunistically while prerequisite evidence is absent.

## Required task record

Record ID, domain/epic/feature/story, milestone, owner, dependencies, objective, rationale, inputs, outputs and likely paths. Then define data model, API/interface, security/isolation, idempotency, failure cases, observability, customer UX, local validation, AWS/Snowflake validation, acceptance checklist, operational impact, documentation impact and rollback.

Customer-facing features include persona, goal, entry point, happy path, empty/loading/partial/error/denied/success states, drilldowns, primary actions and acceptance criteria. Internal tasks explicitly identify their customer-visible health impact.

## Validation and evidence contract

Implementation evidence lives under `docs/evidence/<task-id>/<commit>/` with an index containing environment, versions, UTC execution time, fixture IDs, commands, exit codes, expected/observed results and redacted artifacts. Large screenshots/reports/logs belong in controlled artifact storage; commit manifests and checksums, not customer data or secrets.

Use unit and contract tests for pure behavior; PostgreSQL integration for transactions/RLS; dbt fixtures and live Snowflake for SQL; AWS integration for IAM/network/events; security and tenant tests across every boundary; performance for explicit budgets; failure/recovery for durable work; E2E and visual acceptance for UX; financial reconciliation for monetary outputs. State `NOT_APPLICABLE` with a reason when a level has no relevant behavior.

## Financial review protocol

Write the grain and inclusion rule before SQL. Identify whether an amount is an additive billable row, a decomposition, an adjustment, an estimate or a reconciliation reference. Choose exact decimal arithmetic and currency. Create a numerical fixture with expected totals before implementing. Test negative adjustments, no data, missing sources, duplicate inputs, revised billing and currency separation. Finance and data reviewers approve the same fixture output.

## Security review protocol

Use two tenants, two organizations, multiple accounts, one same-tenant restricted user and a revoked membership. Attempt foreign IDs, forged filters, stale cache entries, asynchronous result retrieval, exports and object URLs. Deny by default at API, PostgreSQL RLS and Snowflake security boundaries. A test that only verifies a UI button is hidden is insufficient.

## Restart and failure protocol

Never rely on chat memory. Record last completed micro-task, files changed, redacted command output, failed attempts and exact next action. A task interrupted after an external side effect must discover the durable outcome before retrying. Every API write and data publication has an idempotency identity. A retry must neither double bill nor double publish.

Stop only the affected task when an external gate is missing. Record blocker, owner, smallest required evidence and safe independent next task. Do not substitute credentials, disable isolation or weaken acceptance to make progress.

## Source and decision control

Vendor claims require official links and a verification date. A source contract is executable only after live schema/privilege validation against a pinned stack. Exact versions are resolved and locked during bootstrap, using compatibility tests; never use an unpinned `latest` image. New evidence may supersede an ADR through a linked replacement, not an undocumented rewrite.

## Documentation and Git discipline

This specification is published directly to `main` as requested, file by file. Future product implementation uses short-lived task branches and gated review unless the owner separately chooses another policy. Before each specification publication, check PRD alignment and known links/dependencies; before each domain checkpoint update indexes and status. Use `docs(<domain>): <specific outcome>` commits. Final corrections use current blob SHAs through the API; never force-push over concurrent changes.

## Global Definition of Done

- [ ] Task-specific deterministic assertions pass; evidence references exact commit and environment.
- [ ] No boundary violation or undocumented monetary formula; input/output schemas versioned.
- [ ] Unauthorized and cross-tenant attempts fail; sensitive text absent from logs/artifacts.
- [ ] Retry, duplicate, interruption and recovery behavior proved where state changes exist.
- [ ] SLO/limits and operator diagnostics exist; customer UX states are complete.
- [ ] Migration/rollback/replay path is documented and exercised where relevant.
- [ ] API/schema/documentation changes are synchronized; dependencies and task index updated.
- [ ] Named reviewer accepts evidence. Remaining live or business gates are visible and prevent release where required.
