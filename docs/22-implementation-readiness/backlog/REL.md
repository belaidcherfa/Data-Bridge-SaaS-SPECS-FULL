# REL — Implementation-readiness review and production backlog

Canonical contract: [readiness.md](../../19-production-readiness/readiness.md), [CHECKLIST.md](../../19-production-readiness/CHECKLIST.md), [ADR-010](../../architecture/adr/ADR-010-versions-and-release.md), [RUNBOOKS RB-13](../../16-observability/RUNBOOKS.md). Tasks reviewed: REL-001, REL-002, REL-003, REL-004. Reviewer: domain audit agent, 2026-09-27. Status of all tasks: NOT_STARTED.

## 1. Verdict

Partially implementable. The promotion contract (build once, immutable digests, expand → migrate → contract, candidate revisions behind a publication pointer, NO-GO on missing evidence) is sound, but everything lands at M10: the first migration safety gate, the first production environment, the first rollback rehearsal and the first definition of which code version may read which publication. Migrations start at CTL-002 (M1) and publications at ORC-005/DBT-006 (M3–M4), so eight milestones would ship without the guard rails. Deployment strategy per service, feature flags/kill switches, release cadence and a month-close change freeze are absent. Author first: release manifest v1, migration policy + linter (REL-101), serving-schema compatibility contract (REL-103), and a continuously deployed "dark production" from M5 (REL-104).

## 2. Findings

### G-REL-01 · Production is first provisioned at M10
Severity: HIGH · Type: RISK
Evidence: `REL-002` micro-task 1 — "Provision final production configuration through Terraform and verify DNS/TLS/WAF/private endpoints/secrets/quotas"; `OPEN_VALIDATIONS.md` V02 — "M1 and M10"; `INF-007` — "keep production deployment an explicit release action".
Why it matters: production-only differences (separate AWS account quotas, IAM role count for per-tenant principals under D-02, SES production access, Cognito production pool, WAF rules, central production Snowflake account and its WIF trust, NAT Elastic IPs published to customers under D-09) surface two milestones before the first customer, with no time to fix. The external pentest (OPS-107) and production canaries (OPS-103) also need a production-equivalent target.
Resolution: new REL-104 "dark production" at M5: production stacks deployed by the same pipeline for every weekly candidate, `signup.enabled=false`, only canary tenants, production probes and paging live. REL-002 then rehearses on an environment that has existed for months. The NAT Elastic IPs (D-09) are allocated once in REL-104 and never replaced (customers allowlist them).
Affects: REL-002, new REL-104, OPS-103, OPS-107.

### G-REL-02 · No migration safety gate until M10
Severity: HIGH · Type: GAP
Evidence: `readiness.md` — "Use expand → deploy compatible readers/writers → migrate/backfill → verify → contract"; qualified only in `REL-001` (M10); first migrations in `CTL-002` (M1); rolling deploys with two versions live from `INF-007` (M1).
Why it matters: a single `ALTER TABLE … ADD COLUMN … NOT NULL` without default, an index build without `CONCURRENTLY`, or a column rename deployed while N-1 tasks are still draining causes an outage or a failed rollback; with FORCE RLS on every tenant table, a new table without policy is a disclosure risk.
Resolution: new REL-101 at M1: forward-only migrations (no `downgrade` in production), a Postgres migration linter in CI (e.g. squawk) with a forbidden-operation list, `lock_timeout=5s` and per-migration `statement_timeout`, migrations run as a one-off ECS task holding an advisory lock before service deploy, an N-1 compatibility job (previous release's integration tests against the new schema), a catalog check that every new tenant table has `tenant_id`, FORCE RLS and policies, and "contract" migrations allowed only when no N-1 task definition is deployed in any environment.
Affects: new REL-101, REL-001; cross-domain CTL-002.

### G-REL-03 · Code rollback and data publication rollback are not coupled by any compatibility rule
Severity: HIGH · Type: GAP
Evidence: `readiness.md` — "Rollback options are previous application digest, previous compatible publication, paused ingestion, or a forward data repair"; `RUNBOOKS.md` RB-13 — "restore previous publication if safe"; no artifact defines "compatible" or "safe".
Why it matters: release N adds a serving column and publishes tenants on the new serving schema; rolling back the API to N-1 makes the broker query a view shape it does not understand (errors or silently wrong mapping). Conversely, repointing a publication to an older revision can present an older serving schema to newer code.
Resolution: new REL-103: serving views namespaced by version (`SERVING_V<n>`), publication manifest carries `serving_schema_version`, each API build declares `supported_serving_schema_versions` (always {n−1, n}), a pre-deploy check refuses a digest that cannot read every tenant's current publication, the publisher refuses to advance a tenant to schema n+1 while the fleet lacks support, and serving contract changes ship in two releases (expand: add V<n+1>; contract: drop V<n−1> after all pointers moved and one release has passed). Row access policies attach to every new view version automatically.
Affects: REL-001, REL-002, new REL-103; cross-domain DBT-006, API-001, ORC-005.

### G-REL-04 · Deployment strategy per service is unspecified
Severity: MEDIUM · Type: GAP / VENDOR-FACT
Evidence: `INF-005` — "Verify restart/backoff, deployment circuit breaker"; `REL-001` — "rolling API/worker updates"; `orchestration.md` — "one active daemon".
Why it matters: rolling updates of the API expose users to the new version before any smoke test; a rolling update of the Dagster daemon briefly runs two daemons (double scheduling); worker generations can overlap on leases.
Resolution: Amazon ECS supports built-in blue/green deployments with lifecycle hooks, test listeners and bake time since July 2025, with canary/linear strategies added later — VERIFIED (aws.amazon.com/about-aws/whats-new/2025/07/amazon-ecs-built-in-blue-green-deployments, search snippet 2026-09-27). Strategy table (normative for REL-002): API, query broker, web BFF → ECS built-in blue/green, test-listener smoke hook (synthetic login, isolation probe, 270 fixture query on canary tenant), bake 10 min, rollback on 5xx/p95/probe alarms; extraction launcher, monitor/report/intelligence workers → rolling (min 100 %, max 200 %) with SIGTERM drain: stop claiming leases, finish or release within `stopTimeout` 120 s, lease epoch fencing; Dagster daemon → stop-then-start (`minimumHealthyPercent=0`, `maximumPercent=100`), accepted ≤ 2 min scheduling gap; Dagster code locations → rolling; per-run ECS tasks → new runs use the new image, in-flight runs finish on theirs; dbt → project version pinned in run config.
Affects: REL-002.

### G-REL-05 · No feature flags or operational kill switches
Severity: MEDIUM · Type: GAP
Evidence: `RUNBOOKS.md` RB-09 — "Disable vulnerable path/principal"; RB-15 — "Lower affected admission quota"; grep "feature flag" in `docs/**` → no hits.
Why it matters: without switches, containment means an emergency deploy; with ad-hoc switches, a flag can accidentally bypass authorization.
Resolution: new REL-102 (M3): `control.feature_flags` with scope (global/tenant), owner, reason, `expires_at`; server-side evaluation after authorization; kill switches `extraction.source.<id>.enabled`, `extraction.tenant.<id>.paused`, `publication.tenant.<id>.frozen`, `delivery.channel.<type>.enabled`, `api.route.<id>.enabled`, `signup.enabled`; audited changes via ops API; flag snapshot in the release manifest.
Affects: new REL-102, REL-004 (NO-GO leaves `signup.enabled=false`).

### G-REL-06 · No release cadence, change calendar or month-close freeze
Severity: MEDIUM · Type: GAP
Evidence: `launch.md` — "monitor before expanding"; D-13 — "month considered billing-stable after month_end+N days (N configurable, default 5)"; no cadence in any spec.
Why it matters: finance users close and issue chargeback statements in the first days of the month; a ledger/allocation change deployed then can trigger restatements (FIN-010) exactly when customers read the numbers.
Resolution: weekly production train Tuesday–Thursday within on-call hours; hotfix path with the same gates but a reduced live suite (security fixes always run the isolation suite); financial-logic freeze from the last business day of month M to month_end + 5 days for paths tagged `financial-logic` (dbt ledger/allocation models, rate/FX, close logic) unless FinOps owner approves; enforced by the pipeline (REL-001-S12).
Affects: REL-001.

### G-REL-07 · Evidence freshness rule is undefined
Severity: MEDIUM · Type: AMBIGUITY
Evidence: `REL-004` — "rerun only checks affected by changes since accepted evidence"; `CHECKLIST.md` — "Recheck evidence after material source/library/infrastructure changes".
Why it matters: either everything is rerun (live suites cost credits and hours) or nothing is (stale evidence passes).
Resolution: `evidence-impact.yaml` maps path globs to evidence classes (e.g. `data/dbt/models/ledger/**` → financial fixtures + live dbt; `apps/api/auth/**` → auth security suite; `infra/iam/**` → isolation + IaC scan) and sets absolute maximum ages: live Snowflake suite 7 days, isolation suite 30 days, restore drills 90 days, capacity C1 90 days or any change to lanes/quotas, external pentest 12 months.
Affects: REL-001, REL-004.

### G-REL-08 · Release manifest omits artifacts that determine behaviour
Severity: MEDIUM · Type: GAP
Evidence: `readiness.md` — "Release manifest image/schema/dbt/config versions, SBOM, attestations".
Why it matters: Dagster code-location images, dbt package lock, source/metric registry versions, serving schema version, migration head, Terraform plan digests and the flag snapshot all change behaviour; missing any makes "the same candidate" unverifiable and rollback incomplete.
Resolution: manifest v1 in §3 lists all of them; deploy steps refuse a component whose version is not in the manifest.
Affects: REL-001, REL-004.

## 3. Contract-first artifacts to author before coding

| Artifact | Exact content required | Produced by |
|---|---|---|
| `docs/releases/release-manifest.v1.json` (JSON Schema) | `version`, `commit`, `images[{service, digest, sbom_ref, signature_ref}]` (API, broker, BFF, workers, extractor, Dagster webserver/daemon/code locations, report renderer), `migration_head`, `dbt{project_version, manifest_sha, packages_lock_sha}`, `serving_schema_version`, `registry_versions{source, metric, gate_catalog}`, `terraform[{stack, plan_digest}]`, `feature_flag_snapshot_sha`, `evidence_matrix_ref`, `created_at` | REL-001-S01 |
| `docs/releases/migration-policy.md` + linter config | Forward-only; forbidden in one release: DROP/RENAME column or table, NOT NULL without default on existing table, type narrowing, non-concurrent index on tables > 10 k rows; `lock_timeout=5s`; batched backfill pattern; contract step gating rule | REL-101-S01 |
| `docs/releases/deploy-strategies.md` | Service → strategy table from G-REL-04 with hook, bake time, alarms, drain timeout | REL-002-S02 |
| `docs/releases/evidence-impact.yaml` | path glob → evidence classes; evidence class → max age | REL-001-S06 |
| `docs/releases/deployment-record.v1.json` | `deployment_id, env, old_manifest, new_manifest, publication_versions_before/after, started_at, ended_at, thresholds, alarms_triggered, decision (COMPLETED/ROLLED_BACK/FORWARD_FIXED), duration_s, operator` | REL-002-S13 |
| DDL `control.feature_flags` + `docs/releases/kill-switches.md` | Columns `key, scope_type, scope_id, value, owner, reason, expires_at, revision, updated_by, updated_at`; kill-switch catalogue with effect and expected propagation time (≤ 60 s) | REL-102-S01 |
| `docs/releases/serving-compatibility.md` | Versioning rules, manifest field, API support declaration, pre-deploy/pre-publish checks, two-release change procedure | REL-103-S01 |
| `docs/production/go-no-go.yaml` | CHECKLIST template with 14 gates, evidence refs, approvals, risk acceptances (scope, compensating control, owner, expiry), forbidden-waiver list | REL-004-S06 |

## 4. Revised production backlog

### 4.0 Re-milestoning and dependency corrections

| Task | Milestone | Dependencies now → proposed | Reason |
|---|---|---|---|
| REL-101 (new) | M1 | CTL-002, INF-007 | first migrations |
| REL-102 (new) | M3 | CTL-004, CTL-006, OPS-106 | containment switches needed when ingestion goes live |
| REL-103 (new) | M5 | DBT-006, API-001, ORC-005 | first serving schema |
| REL-104 (new) | M5 | INF-007, INF-008, OPS-102, OPS-103 | dark production |
| REL-001 | M10 | INF-007, OPS-011 → +REL-101, +REL-103 | final qualification |
| REL-002 | M10 | REL-001, OPS-010 → +REL-102, +REL-104 | rehearse on existing prod |
| REL-003 | M10 | REL-002, OPS-009 → +LCH-001, +LCH-102, +LCH-104, +OPS-107 | pack needs commercial/legal/support/pentest inputs (reverses LCH-001 → REL-003) |
| REL-004 | M10 | REL-003 | unchanged |

### REL-001 — Qualify complete CI/CD promotion, provenance and schema compatibility
Release: R1 · Estimate: 40–60 h · Risk: M · Decisions: D-21, D-25 · Closes: G-REL-06, G-REL-07, G-REL-08
Dependency changes: `+REL-101`, `+REL-103`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| REL-001-S01 | Author release manifest v1 (§3) and a generator that fills it from the build. | `docs/releases/release-manifest.v1.json`, `tools/release/manifest.py` | Generated manifest validates; missing component fails the build. | 3 |
| REL-001-S02 | Build once per commit: push images by digest, sign keyless with cosign via GitHub OIDC, attach SBOM and provenance attestations. | `.github/workflows/build.yml` | `cosign verify` succeeds for each digest with the expected workflow identity. | 4 |
| REL-001-S03 | Verify at deploy: the deploy job resolves images only from the manifest and verifies signature + digest; tags are rejected. | `.github/workflows/deploy.yml`, `tools/release/verify.py` | Deploying `:latest` or an unsigned digest fails. | 3 |
| REL-001-S04 | Harden OIDC trust: production apply/deploy roles require `sub = repo:<org>/<repo>:environment:production` and `aud = sts.amazonaws.com`; GitHub environment protection (required reviewers, `main` only; plan availability TO VERIFY LIVE). | `infra/cicd/oidc.tf` | Token from a fork or another branch is denied (live test). | 3 |
| REL-001-S05 | Wire required checks: unit/contract, dbt `state:modified+` in isolated CI schema with golden fixtures, OpenAPI breaking-change diff (e.g. oasdiff), REL-101 migration gate, security scans, OPS-011 evidence gate. | branch protection + `promotion-gate` job | Removing any check result blocks promotion. | 5 |
| REL-001-S06 | Author `evidence-impact.yaml` and implement freshness evaluation (path impact + max age). | `docs/releases/evidence-impact.yaml`, `tools/release/freshness.py` | Changing `data/dbt/models/ledger/x.sql` marks financial + live dbt evidence stale; 8-day-old live suite stale. | 4 |
| REL-001-S07 | Staging flow: auto-deploy on merge to `main`; nightly live suite; production promotion requires approval and all checks green for that digest. | workflows | A digest with a red nightly cannot be promoted. | 3 |
| REL-001-S08 | Rolling-compatibility rehearsal: run API N−1 and N simultaneously on the expanded schema; run frontend bundle N−1 against API N. | `tests/compat/` | Contract tests of N−1 pass against N. | 5 |
| REL-001-S09 | Candidate publication during rollout: API pinned to P1 while P2 publishes; confirm N−1 reads P2 only if REL-103 allows. | `tests/compat/test_publication_rollout.py` | Incompatible combination refused by pre-publish check. | 3 |
| REL-001-S10 | Negative tests: mutable tag, fork OIDC token, non-main branch, evidence from another commit, migration head mismatch, unsigned image. | `tests/spec/REL-001/negative/` | All six denied with explicit reason. | 4 |
| REL-001-S11 | Terraform: apply only the reviewed saved plan (digest pinned in manifest); nightly drift detection per stack. | `infra/cicd/terraform-apply.yml` | Apply with a different plan digest refused; drift alarm fires on manual console change. | 3 |
| REL-001-S12 | Enforce the change calendar: production deploys touching `financial-logic` paths during the month-close window require a FinOps approval label. | `tools/release/freeze.py` | Fixture deploy on day 2 of month without label blocked. | 2 |
| REL-001-S13 | Evidence. | `docs/evidence/REL-001/<commit>/` | Includes negative-test outputs and a verified manifest. | 2 |
Task acceptance:
- [ ] The same signed digest reaches staging and production; tags and unsigned images cannot deploy.
- [ ] Missing or stale required evidence blocks production promotion.
- [ ] N−1 clients work against N during rollout; incompatible publication/code pairs are refused.
- [ ] Financial-logic changes are blocked during the month-close window without approval.

### REL-002 — Rehearse production deployment and rollback (code, publication, forward fix)
Release: R1 · Estimate: 36–56 h · Risk: H · Decisions: D-05, D-07, D-09, D-22 · Closes: G-REL-01, G-REL-04
Dependency changes: `+REL-102`, `+REL-104`; production provisioning moves to REL-104.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| REL-002-S01 | Diff production vs staging configuration (DNS/TLS/WAF/endpoints/secrets) and check quotas: ECS tasks, IAM roles (per-tenant principals D-02), SES production access, Cognito limits. | `docs/releases/prod-config-diff.md` | Every difference justified; quota headroom ≥ 2× C1 needs. | 3 |
| REL-002-S02 | Configure ECS built-in blue/green for API/broker/BFF: test listener rule restricted to probes, pre-traffic lifecycle hook running smoke tests, bake 10 min, rollback alarms (5xx, p95, probe). | `infra/deploy/bluegreen.tf`, `docs/releases/deploy-strategies.md` | Green receives no production traffic until hook passes. | 5 |
| REL-002-S03 | Implement worker SIGTERM drain: stop claiming, finish or release leases within 120 s; lease epoch fencing. | `packages/runtime/drain.py` | Rolling deploy under load: 0 lost leases, 0 double commits. | 4 |
| REL-002-S04 | Deploy Dagster daemon stop-then-start and code locations rolling; heartbeat check proves a single daemon. | ECS service settings | Never two daemon heartbeats within the same minute. | 3 |
| REL-002-S05 | Add the migration job step (REL-101 runner) before service deploy; expand-only in the same release. | pipeline step | Deploy aborts if migration fails; services untouched. | 2 |
| REL-002-S06 | Build the production smoke suite: canary login, isolation probe, 270 fixture query on canary tenant, report download, alarm test. | `tests/smoke/production/` | Suite green on dark production. | 4 |
| REL-002-S07 | Rehearsal A (staging): green fails health threshold → automatic rollback. | evidence | Rollback time recorded; blue untouched. | 3 |
| REL-002-S08 | Rehearsal B: image healthy but smoke hook fails → never receives traffic. | evidence | 0 production requests served by green. | 2 |
| REL-002-S09 | Rehearsal C: p95 regression during bake → rollback to blue. | evidence | Rollback ≤ 5 min after alarm. | 3 |
| REL-002-S10 | Rehearsal D: publication rollback — repoint a canary tenant to the prior compatible revision via `bridge-admin` manifest (RB-07). | evidence | API serves prior totals with its as-of; closed statements unchanged. | 3 |
| REL-002-S11 | Rehearsal E: irreversible change handled by forward fix (e.g. column type change with batched backfill). | evidence | No downgrade used; data consistent. | 3 |
| REL-002-S12 | Verify a control mutation made during rollout (budget created) survives rollback and the ledger stays 270. | `tests/smoke/test_rollback_preserves.py` | Budget present; no duplicate 270 rows. | 2 |
| REL-002-S13 | Write deployment records automatically (schema §3). | `tools/release/deployment_record.py` | Every rehearsal has a record with duration and decision. | 2 |
| REL-002-S14 | Update RB-13 with measured durations and exact commands. | `docs/runbooks/RB-13-rollback.md` | Second engineer performs Rehearsal A from RB-13. | 2 |
Task acceptance:
- [ ] New API versions receive production traffic only after the smoke hook passes; bake-time regressions roll back automatically.
- [ ] Worker and daemon deployments never run two lease owners or two daemons concurrently.
- [ ] Code rollback, publication rollback and forward fix each rehearsed with measured duration.
- [ ] Rollback preserves control mutations and accepted ledger totals.

### REL-003 — Assemble operational, commercial and support readiness pack
Release: R1 · Estimate: 22–34 h · Risk: M · Decisions: D-17, D-25 · Closes: G-REL-07
Dependency changes: `+LCH-001`, `+LCH-102`, `+LCH-104`, `+OPS-107`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| REL-003-S01 | Create the checklist data model (item, gate, owner, evidence URI, commit, environment, date, result, risk acceptance with expiry). | `docs/production/checklist.yaml` | Schema-valid, 14 gates present. | 2 |
| REL-003-S02 | Collect and verify evidence: OPS-004 + OPS-107 (security), OPS-006/007 drills ≤ 90 days, OPS-008 C1, OPS-011 matrix, OPS-009 economics; check commit/environment match. | checklist entries | Every gate has evidence or NOT_RUN. | 4 |
| REL-003-S03 | Index customer documentation from ONB-002/ONB-102 (install/uninstall, capability and retention disclosures, offboarding). | `docs/customer/index.md` | Links resolve to versioned guides. | 2 |
| REL-003-S04 | Record commercial readiness: plan/entitlement definition (LCH-001), invoicing setup (LCH-103), legal pack approvals (LCH-102). | checklist entries | Named human approvals recorded or item NOT_RUN. | 2 |
| REL-003-S05 | Record support readiness: rota named (OPS-102), status page, intake tested, support policy (LCH-104). | checklist entries | Test ticket handled end-to-end. | 2 |
| REL-003-S06 | Turn the limitations register into customer-facing wording. | `docs/customer/known-limitations.md` | Every limitation has wording and owner. | 2 |
| REL-003-S07 | Tabletop 1: first-customer onboarding including network allowlist, reseller (no ORGANIZATION_USAGE) and PrivateLink-only refusal (D-09). | tabletop record | Every blocker has an owner and documented customer message. | 3 |
| REL-003-S08 | Tabletop 2: tenant deletion request followed by a restore. | tabletop record | Tombstone replay step identified in both runbooks. | 2 |
| REL-003-S09 | Tabletop 3: billing dispute (credit note, PAST_DUE grace, data access during dispute). | tabletop record | Policy answers exist for each question. | 2 |
| REL-003-S10 | Assign unresolved items; blocking items feed NO-GO. | issue list | No unowned item. | 2 |
Task acceptance:
- [ ] Every blocking checklist item has accepted, fresh evidence or the pack states NO-GO.
- [ ] Legal/commercial items carry named human approvals, never engineering approval.
- [ ] No production alarm or recovery procedure is unowned.

### REL-004 — Approve immutable release candidate and production gate
Release: R1 · Estimate: 12–18 h · Risk: M · Decisions: D-25 · Closes: G-REL-07
Dependency changes: none.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| REL-004-S01 | Tag `vX.Y.Z-rc.N` and freeze the manifest (immutable object, SHA recorded). | `docs/releases/rc-manifest/` | Manifest SHA recorded in go/no-go file. | 1 |
| REL-004-S02 | Evaluate freshness via the impact map; rerun stale checks. | freshness report | No stale required evidence. | 3 |
| REL-004-S03 | Collect engineering, security, FinOps and operations approvals with evidence links; security approver is not the implementer of the security suite. | approval records | Four approvals with links. | 2 |
| REL-004-S04 | Verify the rollback owner can execute RB-13 in production (dry run). | dry-run output | Dry run succeeds. | 1 |
| REL-004-S05 | Record residual risks with owner/expiry; reject forbidden waivers (tenant exposure, fabricated financial result, core boundary). | risk register | Waiver on a forbidden class fails validation. | 1 |
| REL-004-S06 | Fill `go-no-go.yaml`; a NO-GO keeps `signup.enabled=false` and production onboarding disabled. | `docs/production/go-no-go.yaml` | Flag state matches decision. | 2 |
| REL-004-S07 | Test: one failed isolation or financial invariant computes NO_GO automatically. | `tests/spec/REL-004/` | Decision computed NO_GO. | 2 |
| REL-004-S08 | Evidence. | `docs/evidence/REL-004/<commit>/` | – | 1 |
Task acceptance:
- [ ] One failed tenant-isolation or financial invariant yields NO_GO without human override.
- [ ] The approved candidate names exact digests, rollback owner and limitations.

## 5. New tasks required

### REL-101 — Migration safety gate and expand/contract harness
Release: R1 · Estimate: 20–30 h · Risk: M · Decisions: none · Closes: G-REL-02
Why / where: first migrations and rolling deploys happen at M1; plugs in after CTL-002/INF-007; REL-001 depends on it.
Dependency changes: new; deps CTL-002, INF-007.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| REL-101-S01 | Write the migration policy (§3). | `docs/releases/migration-policy.md` | Reviewed by backend + DevOps. | 2 |
| REL-101-S02 | Run a Postgres migration linter on Alembic offline SQL in CI with the forbidden-operation list. | `.github/workflows/migrations.yml`, linter config | Fixture `ADD COLUMN x int NOT NULL` without default fails. | 3 |
| REL-101-S03 | Implement the migration runner as a one-off ECS task: advisory lock, `lock_timeout=5s`, statement timeout, records head in manifest. | `tools/migrate/runner.py`, task definition | Two concurrent runners: second waits/aborts, no double apply. | 3 |
| REL-101-S04 | N−1 compatibility job: check out previous release tag, run its integration tests against the DB migrated to the new head. | `.github/workflows/n-minus-1.yml` | A rename migration fails the job. | 5 |
| REL-101-S05 | Provide the batched backfill template (chunked, resumable, throttled). | `tools/migrate/backfill_template.py` | 1 M-row fixture backfill resumable after kill. | 2 |
| REL-101-S06 | Gate contract migrations: allowed only when no N−1 task definition is active in any environment. | `tools/migrate/contract_gate.py` | Contract migration blocked while staging runs N−1. | 2 |
| REL-101-S07 | Catalog guard: new tenant tables must have `tenant_id`, composite FKs, FORCE RLS and policies. | `tests/migrations/test_rls_guard.py` | Fixture table without FORCE RLS fails CI. | 2 |
| REL-101-S08 | Negative fixtures for missing `lock_timeout` and non-concurrent index. | fixtures | Both fail. | 1 |
| REL-101-S09 | Evidence. | `docs/evidence/REL-101/<commit>/` | – | 1 |
Task acceptance:
- [ ] Unsafe migrations fail CI before merge.
- [ ] Previous release's tests pass against every new schema head.
- [ ] No tenant table can ship without FORCE RLS.

### REL-102 — Feature flags and operational kill switches
Release: R1 · Estimate: 20–30 h · Risk: M · Decisions: D-07, D-17 · Closes: G-REL-05
Why / where: containment for RB-02/05/09/15 and dark launch; plugs in at M3 after CTL-004/CTL-006 and OPS-106 (ops API).
Dependency changes: new; deps CTL-004, CTL-006, OPS-106; REL-002 depends on it.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| REL-102-S01 | Create `control.feature_flags` and audit events. | migration | Every change audited with reason. | 2 |
| REL-102-S02 | Build the evaluation library: server-side, 30 s cache with revision check; release flags default off on error; kill switches keep last known value on error. | `packages/flags/` | Fault test: DB unavailable → release flags off, kill switches unchanged. | 3 |
| REL-102-S03 | Wire kill switches into extraction launcher (source/tenant/account), publisher (tenant freeze), dispatcher (channel), API router (route), signup. | service changes | Each switch has a test. | 5 |
| REL-102-S04 | Ops API/CLI commands to set flags with reason and ticket. | `apps/admin_cli/flags.py` | Change without reason rejected. | 3 |
| REL-102-S05 | Test authorization ordering: flags cannot expose a route to an unauthorized role. | `tests/security/test_flags_authz.py` | Viewer still 403 with flag on. | 2 |
| REL-102-S06 | Stale-flag lint: release flags need `expires_at` ≤ 90 days; CI warns at expiry. | lint | Expired flag reported. | 1 |
| REL-102-S07 | Include the flag snapshot hash in the release manifest. | manifest field | Present. | 1 |
| REL-102-S08 | Propagation tests: tenant extraction pause stops new account-cycles within 60 s while in-flight finish; publication freeze holds the pointer. | `tests/spec/REL-102/` | Measured ≤ 60 s. | 3 |
| REL-102-S09 | Docs and evidence. | `docs/releases/kill-switches.md` | – | 2 |
Task acceptance:
- [ ] Every runbook containment action has a kill switch with measured propagation ≤ 60 s.
- [ ] Flags never widen authorization.

### REL-103 — Serving schema versioning and code/publication compatibility
Release: R1 · Estimate: 26–40 h · Risk: H · Decisions: D-05, D-22 · Closes: G-REL-03
Why / where: first serving schema at M4/M5; plugs in after DBT-006, API-001, ORC-005; REL-001/REL-002 depend on it.
Dependency changes: new; deps DBT-006, API-001, ORC-005.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| REL-103-S01 | Write the compatibility contract (§3). | `docs/releases/serving-compatibility.md` | Reviewed by DBT/API owners. | 3 |
| REL-103-S02 | Generate serving views per version namespace in dbt; keep V<n−1> until all pointers moved and one release passed. | `data/dbt/models/serving/v<n>/` | Both versions queryable during transition. | 4 |
| REL-103-S03 | Broker selects namespace from the tenant publication's `serving_schema_version`; unsupported → 503 `SERVING_SCHEMA_UNSUPPORTED` + alarm. | broker change | Fixture unsupported version → 503 and alarm. | 3 |
| REL-103-S04 | Pre-deploy check: candidate API digest must support every tenant's current publication version. | `tools/release/check_serving_compat.py` | Incompatible digest blocked. | 3 |
| REL-103-S05 | Pre-publish check: publisher refuses advancing a tenant to n+1 while deployed fleet lacks support. | publisher change | Advance refused with reason. | 3 |
| REL-103-S06 | Align metric registry versions (API-001): breaking metric change → new metric version. | registry rule | Contract test detects breaking change. | 2 |
| REL-103-S07 | Encode rollback rules for code and publication. | RB-07/RB-13 updates | Rules referenced by CLI dry-run manifests. | 2 |
| REL-103-S08 | Rehearse a two-release serving column rename in staging. | evidence | No request fails during either release. | 4 |
| REL-103-S09 | Security test: row access policies attached to every new view version. | `tests/isolation/test_new_view_policies.py` | Unattached view fails CI. | 2 |
| REL-103-S10 | Docs and evidence. | `docs/evidence/REL-103/<commit>/` | – | 2 |
Task acceptance:
- [ ] No deployed API version can face a publication schema it cannot read.
- [ ] Serving contract changes complete in two releases without failed requests.
- [ ] New view versions are never readable without row access policies.

### REL-104 — Dark production environment from M5
Release: R1 · Estimate: 22–34 h · Risk: M · Decisions: D-09, D-23 · Closes: G-REL-01
Why / where: production-only differences must surface early; plugs in at M5 after INF-007/INF-008, OPS-102, OPS-103; REL-002 and OPS-107 depend on it.
Dependency changes: new; deps INF-007, INF-008, OPS-102, OPS-103.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| REL-104-S01 | Provision production AWS stacks and the production central Snowflake account through the pipeline. | Terraform state per prod stack | Second apply no-op. | 5 |
| REL-104-S02 | Production-only configuration: secrets, SES production access request (lead time), Cognito production pool, WAF rules, quota increases; allocate NAT Elastic IPs once (D-09) and publish them in the wizard config. | config records | SES out of sandbox; EIPs recorded as permanent. | 4 |
| REL-104-S03 | Set `signup.enabled=false`; only canary tenants; public hostname shows maintenance page to non-allowlisted users. | flag state | Anonymous signup returns closed page. | 2 |
| REL-104-S04 | Deploy every weekly candidate to production after staging, running the smoke suite. | pipeline | Four consecutive weekly deploys recorded. | 3 |
| REL-104-S05 | Enable production canary tenants and probes (OPS-103/OPS-003). | probes | Probes green 7 days. | 2 |
| REL-104-S06 | Enable paging on production alarms (OPS-102). | routing | Test page received. | 1 |
| REL-104-S07 | Nightly drift detection on production stacks. | workflow | Manual change detected. | 2 |
| REL-104-S08 | Cost guards: AWS Budgets alarms and Snowflake resource monitors on production. | budgets | Alarm test fires. | 2 |
| REL-104-S09 | Evidence. | `docs/evidence/REL-104/<commit>/` | – | 1 |
Task acceptance:
- [ ] Production has run every candidate since M5 with green smoke tests.
- [ ] NAT Elastic IPs are fixed and published before any customer allowlists them.
- [ ] Signup stays disabled until REL-004 GO.

## 6. Estimate summary

| Task | Release | Low h | High h |
|---|---|---:|---:|
| REL-001 | R1 | 40 | 60 |
| REL-002 | R1 | 36 | 56 |
| REL-003 | R1 | 22 | 34 |
| REL-004 | R1 | 12 | 18 |
| REL-101 | R1 | 20 | 30 |
| REL-102 | R1 | 20 | 30 |
| REL-103 | R1 | 26 | 40 |
| REL-104 | R1 | 22 | 34 |
| **Total R1** | | **198** | **302** |
| **Total R2** | | **0** | **0** |

## 7. Owner questions (only those not already covered by D-01…D-25)

1. Release window and time zone for the weekly production train; is a ≤ 2-minute Dagster scheduling gap per deploy acceptable?
2. GitHub plan: environment protection rules with required reviewers on private repositories depend on the plan tier (TO VERIFY LIVE) — which plan will the organization use?
3. Month-close freeze length: default month_end + 5 days (D-13) or aligned to the first customer's close calendar?
