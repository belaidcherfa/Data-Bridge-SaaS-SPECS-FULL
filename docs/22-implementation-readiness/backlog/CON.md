# CON — Implementation-readiness review and production backlog

Canonical contract: [connectivity.md](../../04-snowflake-connectivity/connectivity.md). Related: [ADR-004](../../architecture/adr/ADR-004-wif-identities.md), [ADR-009](../../architecture/adr/ADR-009-privacy-and-retention.md), [source catalog](../../05-ingestion/source-catalog.md), [RUNBOOKS RB-01](../../16-observability/RUNBOOKS.md), [integrations UI](../../21-ui-ux/pages/integrations.md), PRD §8–§10 and §119–§120. Companion file: [ING.md](ING.md). Tasks reviewed: CON-001, CON-002, CON-003, CON-004, CON-005, CON-006. Reviewer: domain audit agent, 2026-09-27 (vendor checks run 2026-09-28). Status of all tasks: NOT_STARTED.

## 1. Verdict

The domain cannot be implemented safely as specified. The identity principle is sound: WIF only, one AWS role and one Snowflake SERVICE user per connected account, and a reader that never inherits the operator. The contract, however, omits everything that happens *inside the customer's account* and everything between the Bridge control plane and AWS IAM:

- **No customer-side warehouse or credit disclosure.** The bootstrap only says "warehouse usage".
- **No view→database-role map.** The one given hides that QUERY_HISTORY needs GOVERNANCE_VIEWER.
- **No install runner.** Nothing says who runs the script or with which roles.
- **No network path.** There are no fixed egress IPs or network policy, and nothing stops the S3 gateway endpoint policy from silently breaking large result downloads.
- **No IAM provisioning workflow.** Missing: who creates the per-connection role, when, its boundary, quota handling, revocation latency and name reuse.
- **No lifecycle transition table.**

Author first: the exact install/revoke scripts (§3.1), the versioned view→role map (§3.2), the credit estimator (§3.3), the lifecycle transition table (§3.4) and the probe classification table (§3.5). Realistic R1 effort is ≈ 296–434 senior hours. The task files assume 6 × 2–6 h.

## 2. Findings

### G-CON-01 · Customer-side extraction footprint is absent: no warehouse, no quota, no cost disclosure
Severity: BLOCKER · Type: GAP
Evidence: `connectivity.md` — "bootstrap separately grants the role to the user and only required database roles/warehouse usage" (it never says which warehouse, or who pays). `source-catalog.md` QUERY_HISTORY — "15m cadence". Warehouse billing has a 60-second minimum per resume, then per-second billing — VERIFIED (search snippet of docs.snowflake.com/en/user-guide/warehouses-considerations and cost-understanding-compute, 2026-09-28).
Why it matters: every ACCOUNT_USAGE query needs a running warehouse in the *customer* account. Without a dedicated warehouse, the extractor either:
- runs on a customer production warehouse, which pollutes that workload's cost and keeps it awake; or
- fails.

At the catalog's 15-minute QH cadence, 96 resumes/day × 60 s minimum = 1.6 credits/day ≈ 48 credits/month for QH alone. That is before any other source, and it is undisclosed customer spend.
Resolution: D-08 as written, with three refinements.
- (a) The install script creates `BRIDGE_FINOPS_WH` (XSMALL, AUTO_SUSPEND=60, AUTO_RESUME, INITIALLY_SUSPENDED, STATEMENT_TIMEOUT_IN_SECONDS=3600, STATEMENT_QUEUED_TIMEOUT_IN_SECONDS=600) plus resource monitor `BRIDGE_FINOPS_RM`. Default quota: 50 credits/month. Triggers: 80 % notify, 100 % suspend, 110 % suspend-immediate.
- (b) Grant `OPERATE` on that warehouse only. The account-cycle runner then issues `ALTER WAREHOUSE BRIDGE_FINOPS_WH SUSPEND` at cycle end. This cuts billed time from ≈100–130 s to 60 s per hourly cycle (§3.3: ≈12–14 vs 20–27 credits/month).
- (c) The wizard shows the §3.3 estimate and records consent before READY.

Resource-monitor suspension is classified `CUSTOMER_QUOTA_EXHAUSTED`. It is non-retryable until quota or month changes.
Affects: CON-003, CON-006, new CON-101, ING-106, ING-010.

### G-CON-02 · The SNOWFLAKE database-role map is wrong-by-omission; QUERY_HISTORY needs GOVERNANCE_VIEWER
Severity: HIGH · Type: VENDOR-FACT
Evidence: PRD §10 — "Examples may use … USAGE_VIEWER, GOVERNANCE_VIEWER, OBJECT_VIEWER depending on required views". The following role coverage is VERIFIED (search snippets of docs.snowflake.com/en/sql-reference/snowflake-db-roles and the per-view pages, 2026-09-28):

| SNOWFLAKE database role | Covers (verified) |
|---|---|
| GOVERNANCE_VIEWER | ACCESS_HISTORY, QUERY_HISTORY, MASKING_POLICIES, ROW_ACCESS_POLICIES, TAG_REFERENCES, … |
| USAGE_VIEWER | Warehouse metering, storage consumption, compute costs, task history, clustering metrics |
| USAGE_VIEWER or GOVERNANCE_VIEWER | QUERY_ATTRIBUTION_HISTORY and QUERY_METERING_HISTORY |
| SECURITY_VIEWER | LOGIN_HISTORY, SESSIONS, GRANTS_TO_* |
| ORGANIZATION_USAGE_VIEWER / ORGANIZATION_BILLING_VIEWER / ORGANIZATION_ACCOUNTS_VIEWER | Organization Usage views, in the organization account or an ORGADMIN-enabled account |

The ACCOUNT_USAGE `TABLE_STORAGE_METRICS` role mapping could not be verified; the INFORMATION_SCHEMA variant returns no rows for non-ACCOUNTADMIN roles (snippet).
Why it matters:
- A script granting only USAGE_VIEWER makes QUERY_HISTORY fail. A validator that treats "0 rows" as EMPTY then reports a working Queries module with no data.
- GOVERNANCE_VIEWER also exposes QUERY_TEXT, ACCESS_HISTORY and policy metadata. The customer must be told.
- If a required view is covered by no database role, the only fallback is `IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE`, which grants every ACCOUNT_USAGE view.

Resolution: §3.2 module→view→role map, versioned as `data/contracts/snowflake_privilege_map.v1.json`.
- Regenerate it in the OPS-103 synthetic accounts from `SHOW GRANTS TO DATABASE ROLE SNOWFLAKE.<role>` for each role, at every Snowflake BCR bundle.
- TABLE_STORAGE_METRICS stays capability-gated until live verification. If it needs IMPORTED PRIVILEGES, it becomes an opt-in "table-level storage" module with explicit disclosure (owner question Q3).
Affects: CON-003, CON-005, ING-001, ING-103.

### G-CON-03 · Network reachability is undefined; the S3 gateway endpoint policy can break result downloads
Severity: HIGH · Type: GAP
Evidence:
- `platform.md` — "Controlled NAT egress reaches customer Snowflake endpoints … PrivateLink is an optional validated capability". No IP publication, no customer network policy, no failure class.
- The same file plans "S3 gateway endpoints". `SYSTEM$ALLOWLIST` returns the account's STAGE hosts, and S3 gateway endpoint policies must include the Snowflake stage bucket host — VERIFIED (search snippet of docs.snowflake.com/en/sql-reference/functions/system_allowlist, 2026-09-28).
- The connector downloads large result chunks directly from Snowflake's stage storage (connector issue #2317 context).

Why it matters:
- Customers with account-level network policies reject logins from unknown IPs. Without published fixed IPs, onboarding stalls.
- A gateway endpoint policy restricted to Bridge buckets makes large result downloads (customer account in the same region as Bridge) fail while small inline results succeed. That is an intermittent, size-dependent extraction failure.
- PrivateLink-only accounts cannot be reached at all.

Resolution: new CON-102 (D-09).
- Publish two NAT EIPs per environment through `GET /v1/platform/egress-ips`, with a 90-day change notice.
- The install script has an optional user-level network policy block (§3.1). User-level policy takes precedence over account-level policy (documented; TO VERIFY LIVE in CON-102-S06).
- The probe classifies `NETWORK_POLICY_BLOCKED` separately.
- CON-005 captures `SYSTEM$ALLOWLIST` STAGE hosts per account. INF-002's endpoint policy allows those Snowflake stage buckets.
- PrivateLink hosts are rejected in R1 with `CON_PRIVATELINK_R2`. R2 task: CON-103.
Affects: INF-002, CON-002, CON-003, CON-005, CON-006, new CON-102, CON-103.

### G-CON-04 · Per-connection IAM role workflow is unspecified; name reuse and revocation latency are security holes
Severity: HIGH · Type: GAP
Evidence:
- ADR-004 — "Provision an AWS role … per connected account … Verify quotas before tenant admission". CON-001 micro-task 2 — "Provision least-privilege task identity". Nothing states who calls `iam:CreateRole`, when, with which boundary, or how deletion/revocation works.
- Snowflake matches the AWS attestation against the user's `WORKLOAD_IDENTITY ARN`. The assumed-role session form can also be pinned — VERIFIED (search snippet of docs.snowflake.com/en/user-guide/workload-identity-federation, 2026-09-28).
- IAM roles per account: default 1,000. The maximum was raised to 10,000 in May 2026 — VERIFIED (search snippet of aws.amazon.com/about-aws/whats-new/2026/05/aws-iam-increased-quotas, 2026-09-28).
- ECS `TaskOverride.taskRoleArn` requires the caller to hold `iam:PassRole` — VERIFIED (snippet of docs.aws.amazon.com/AmazonECS/latest/APIReference/API_TaskOverride.html).

Why it matters:
- **Name reuse.** If a deleted connection's role name is recreated (same name), the STS assumed-role ARN matches the old Snowflake user's `WORKLOAD_IDENTITY`. A new connection would silently authenticate into another customer's account.
- **Revocation latency.** Detaching a trust policy does not stop a running task. ECS task credentials remain valid until expiry.
- **Admission surprise.** Quota exhaustion surfaces as a 500 at onboarding.
- **IAM path mismatch (TO VERIFY LIVE).** Assumed-role ARNs omit the IAM path. A role ARN registered with a path (`role/bridge/conn/…`) may not match the attestation.

Resolution (CON-001):
- A dedicated `connector-identity-provisioner` creates the role when the connection is created (DRAFT→AWAITING_CUSTOMER_SETUP), because the ARN must appear in the install script.
- Role name `bridge-conn-<env>-<32 hex of connection UUID>` (≤ 64 chars), with **no IAM path**. The name is never reused, because it derives from the UUID.
- The provisioner's own permissions are restricted to `arn:aws:iam::<acct>:role/bridge-conn-<env>-*` with the condition `iam:PermissionsBoundary = bridge-connector-boundary`.
- Revocation attaches an inline explicit `Deny *`. IAM evaluates it per request within seconds, so S3/KMS writes stop immediately. The Snowflake-side session only lets the task read, and it can no longer persist anything.
- Admission gate: refuse new connections at 90 % of the role quota; page at 70 %. Shared quota with SEC-105 tenant-serving roles (G-SEC-22).
- Alternative considered and rejected for R1: a single extractor role that chains into per-connection roles through the connector's `workload_identity_impersonation_path`. It is VERIFIED to exist in snowflake-connector-python `wif_util.py`/`connection.py` main, 2026-09-28, but it concentrates cross-customer reach in every extractor process.
Affects: CON-001, CON-006, INF-005, SEC-105, ING-106.

### G-CON-05 · Nobody is told who runs the install script, and "idempotent" is not achievable with naive CREATE IF NOT EXISTS
Severity: HIGH · Type: GAP
Evidence: CON-003 — "Generate idempotent create-if-absent/alter/grant statements … never default runtime to ACCOUNTADMIN". `onboarding.md` — "Installation is executed by the customer's authorized Snowflake administrator". Several statements need a specific privilege:
- CREATE RESOURCE MONITOR needs ACCOUNTADMIN.
- GRANT DATABASE ROLE SNOWFLAKE.* is normally done by ACCOUNTADMIN.
- CREATE USER/ROLE needs USERADMIN.
- CREATE NETWORK POLICY needs SECURITYADMIN.

All are TO VERIFY LIVE.
Why it matters:
- `CREATE USER IF NOT EXISTS` does not converge an existing user's `WORKLOAD_IDENTITY`, `DEFAULT_ROLE` or `DEFAULT_SECONDARY_ROLES`. On a reconnect the old ARN stays bound and validation fails with a misleading "wrong principal".
- A same-named user that is not Bridge-managed would be hijacked.
- New users default to `DEFAULT_SECONDARY_ROLES=('ALL')` since the 2024_08 bundle (TO VERIFY LIVE; also raised in G-SEC-01). Any role a customer later grants to the service user becomes active in Bridge sessions.
- `MAX_CLUSTER_COUNT` fails on Standard edition.

Resolution: §3.1 script.
- Role-sectioned `USE ROLE` blocks, stated up front as "run as a user able to assume ACCOUNTADMIN once; runtime never uses it".
- A precheck block aborts before any change if a `BRIDGE_*` object lacks the `bridge_finops_managed:v1:` comment marker.
- CREATE IF NOT EXISTS is followed by ALTER … SET for every converged property.
- `DEFAULT_SECONDARY_ROLES = ()`.
- Edition-dependent clauses are omitted.
- Every statement has a human explanation.
- The revoke script disables first, then revokes and drops, marker-guarded.
Affects: CON-003, CON-006.

### G-CON-06 · Account identity key and rename/move semantics are ambiguous
Severity: MEDIUM · Type: AMBIGUITY
Evidence:
- `connectivity.md` — "validated account identifier, locator, region"; CON-004 — "rename preserves account ID".
- A rename creates a new URL; the old URL is saved by default but can be dropped (`ALTER ACCOUNT … DROP OLD URL`). The account locator cannot be changed once created. Both VERIFIED (snippets of docs.snowflake.com organizations-manage-accounts-rename and admin-account-identifier, 2026-09-28).
- Locators are unique only within a region (CON-004 failure list: "duplicate locators in different regions").

Why it matters: keying on account name breaks history on rename. Keying on locator alone merges two accounts in different regions. Connecting through the org-account URL fails after `DROP OLD URL`.
Resolution: the stable Snowflake identity is `(snowflake_region, account_locator)`, verified in every session via `CURRENT_REGION()` and `CURRENT_ACCOUNT()`.
- Connection endpoint: the `<org>-<account>` identifier. It is updated automatically (audited revision, no customer action) when discovery observes a new name for the same `(region, locator)`.
- Organization moves (`SYSTEM$INITIATE_MOVE_ORGANIZATION_ACCOUNT`) are membership history, not new accounts.
- A region migration (replication/failover to a new account) is a **new account** with an optional support-linked `predecessor_account_id`.
Affects: CON-001, CON-002, CON-004.

### G-CON-07 · Inverted dependency: CON-005 consumes registry metadata that ING-001 is only allowed to build after CON-005
Severity: MEDIUM · Type: CONTRADICTION
Evidence: CON-005 micro-task 1 — "Use source registry metadata to query explicit minimal columns". task-index — `ING-001 dependencies: CON-005, FND-004`.
Why it matters: CON-005 cannot be built without the registry. This edge also puts the whole ING chain behind the CON wizard on the critical path.
Resolution: ING-001 becomes the registry *framework* (schema, loader, query builder, no live data): −CON-005, +FND-004 only. CON-005 +ING-001. Live source activation moves to ING-101…104, which depend on CON-005 and CON-002.
Affects: CON-005, ING-001, ING-101…104.

### G-CON-08 · Probe outcomes conflate "not authorized", "does not exist" and "silently empty"
Severity: MEDIUM · Type: AMBIGUITY
Evidence: `connectivity.md` — "Each source probe records AVAILABLE, EMPTY, DENIED, NOT_SUPPORTED, NOT_ENABLED, SCHEMA_MISMATCH or TRANSIENT_ERROR … Empty is not denied". Snowflake's "does not exist or not authorized" error does not distinguish the two (exact error code TO VERIFY LIVE). Some metadata surfaces return zero rows instead of an error for under-privileged roles (INFORMATION_SCHEMA.TABLE_STORAGE_METRICS snippet, G-CON-02).
Why it matters: an under-privileged but syntactically successful probe produces EMPTY. Downstream it becomes a zero-cost claim or a wiped complete partition (G-ING-07).
Resolution: §3.5 classification.
- Add `DENIED_OR_UNAVAILABLE`, used when the error is ambiguous and the edition is unknown. The remediation text covers both causes.
- Add `SUSPECT_EMPTY`, used when a source expected to be non-empty returns 0 rows.
- **Canary rule:** QUERY_HISTORY must contain Bridge's own verification query (its QUERY_ID is known) once 45 min + margin have passed. Absence means SUSPECT_EMPTY or DENIED, never AVAILABLE_EMPTY. The canary also measures observed source latency.
Affects: CON-005, ING-008, ING-012.

### G-CON-09 · Lifecycle states exist but transitions, guards and fencing do not
Severity: MEDIUM · Type: GAP
Evidence: `connectivity.md` — "DRAFT → AWAITING_CUSTOMER_SETUP → VALIDATING → READY → SYNCING → ACTIVE; side states DEGRADED, PAUSED, REVOKED, DELETING … Pause stops new jobs and safely fences old workers".
Why it matters: the text leaves these questions open:
- Which events can move ACTIVE→DEGRADED?
- Does resume go straight to ACTIVE?
- What stops a cycle that already started?

Without answers, there will be races between revoke and task start (CON-006 failure list).
Resolution: §3.4 transition table.
- A `connection_epoch` (bigint) increments on pause, revoke, identity revision and delete. Every lease and cycle carries it.
- The runner checks it before each source and before each manifest publish.
- Resume always goes through VALIDATING.
- Revoke = epoch++ + IAM explicit deny (G-CON-04).
Affects: CON-006, ING-106, SEC-006.

### G-CON-10 · Organization-scoped sources need their own connection, warehouse and cycle, but no task owns them
Severity: MEDIUM · Type: GAP
Evidence: `connectivity.md` — "Organization discovery is a separate connection capability"; source catalog OU.USAGE_IN_CURRENCY_DAILY — "Complete organization/day snapshot"; manifest `"account_id": "uuid-or-null-for-org-scope"`; CON-003 — "separate organization and account scripts".
Why it matters: OU billing (the invoice reference, R1-critical for reconciliation) is extracted from the organization account (or an ORGADMIN-enabled account) through a different Snowflake user, role and warehouse. It needs its own IAM role and its own daily cycle. No task builds the org-scope connection, its warehouse footprint or its extraction cycle.
Resolution:
- Connection `scope ∈ {ACCOUNT, ORGANIZATION}`, each with its own IAM role (CON-001).
- An org script with `BRIDGE_FINOPS_ORG_READER`/`_ORG_WH`/`_ORG_USER` (CON-003).
- Org discovery (CON-004).
- An org cycle, daily at 06:10 UTC plus open-month anti-entropy passes (ING-106). It costs ≈ 0.5–1 credit/month in the org account (§3.3).
Affects: CON-001, CON-003, CON-004, ING-106.

### G-CON-11 · "Bridge overhead" labelling must use identity, not QUERY_TAG, and must run before pseudonymization
Severity: MEDIUM · Type: RISK
Evidence: D-08 — "extractor sets QUERY_TAG `bridge_finops:<component>`; product labels Bridge's own queries". ADR-005 — "QUERY_TAG … are audit metadata, not trusted identity". D-10 / G-SEC-16 pseudonymize `USER_NAME` at extraction.
Why it matters: any customer user can set `QUERY_TAG='bridge_finops:…'` and hide spend under "Bridge overhead". After pseudonymization, dbt can no longer compare USER_NAME to `BRIDGE_FINOPS_READER_USER`.
Resolution:
- The extractor computes `is_bridge_overhead = (WAREHOUSE_NAME = 'BRIDGE_FINOPS_WH' AND USER_NAME = 'BRIDGE_FINOPS_READER_USER')` from plaintext before pseudonymization, and emits it as a transport column.
- QUERY_TAG is only a secondary diagnostic.
- Warehouse-level Bridge overhead (idle included) comes from WMH rows where `WAREHOUSE_NAME='BRIDGE_FINOPS_WH'`.
- Bridge overhead credits are never excluded from totals. They are shown as a workload.
Affects: new CON-101, ING-107, WRK-001, FIN-021.

### G-CON-12 · Task sizing and hidden work
Severity: MEDIUM · Type: RISK
Evidence: each CON task has 3 micro-steps (for example CON-006: "Build stepper … Fence active jobs … Distinguish disconnect, revoke identity and delete"). DELIVERY_METHODOLOGY — 2–6 h per task.
Why it matters: CON-006 alone is a wizard with 8 steps, a state machine, pause/revoke fencing and a deletion workflow entry: 64–96 h. Planning on 2–6 h misstates M2 by roughly 10×.
Resolution: §4/§5 decomposition, 296–434 h R1.
Affects: all CON tasks.

## 3. Contract-first artifacts to author before coding

| Artifact | Exact content required | Produced by (task/micro-task) |
|---|---|---|
| PG DDL `connection.*` | See the table list after this one. | CON-001-S01, CON-004-S01, CON-005-S01, CON-006-S01 |
| IAM templates | Connector role trust policy: principal `ecs-tasks.amazonaws.com`, conditions `aws:SourceAccount` and `aws:SourceArn` = `arn:aws:ecs:<region>:<acct>:*`. Permission policy that enumerates, per active (source, schema_major), `landing/source=<S>/schema_major=<n>/tenant_id=<t>/organization_id=<o>/account_id=<a>/*` and `manifests/…/account_id=<a>/*` for `s3:PutObject` and `s3:GetObjectAttributes`, plus `kms:GenerateDataKey` on the landing key. No wildcard before `tenant_id=`. Permissions boundary `bridge-connector-boundary`. Revoked-deny inline policy. | CON-001-S03 |
| Install and revoke scripts | §3.1 templates (account and org variants), `script_version`, per-statement explanation strings, render validators | CON-003-S02…S06 |
| Privilege map | `data/contracts/snowflake_privilege_map.v1.json`: module → sources → view → database role → verification record (account, bundle, date, `SHOW GRANTS` hash) | CON-003-S01 |
| Credit estimator | `packages/connections/cost_estimate.py` formula and parameters (§3.3), with a unit test that pins the arithmetic | CON-101-S01 |
| Lifecycle machine | §3.4 transitions, guards and side effects; `connection_epoch` rules | CON-006-S01 |
| Probe contract | JSON Schema `data/contracts/capability.json` (§3.5 statuses, remediation code, `schema_hash`, `observed_latency_s`, `stage_hosts[]`, `edition`, `bcr_bundles[]`); error classification table | CON-005-S01…S03 |
| OpenAPI | Paths listed below this table. All mutations take `Idempotency-Key` and `If-Match: <revision>`. | CON-001-S07, CON-003-S07, CON-004-S09, CON-005-S11, CON-006-S09…S11, CON-102-S01 |
| Error codes | `CON_IDENTITY_IMMUTABLE`, `CON_ACCOUNT_MISMATCH`, `CON_AWAITING_SETUP`, `CON_WRONG_PRINCIPAL`, `CON_USER_DISABLED`, `CON_NETWORK_POLICY_BLOCKED`, `CON_PRIVATELINK_R2`, `CON_GRANT_MISSING`, `CON_EXCESS_PRIVILEGE`, `CON_CUSTOMER_QUOTA_EXHAUSTED`, `CON_CAPACITY` (IAM quota), `CON_STALE_SCRIPT`, `CON_REVISION_CONFLICT` | CON-002-S05, CON-005-S03 |
| Egress IP publication | Versioned static config: `{environment, ips[], effective_from, previous_ips_until}` | CON-102-S01 |

PG tables in `connection.*`, all tenant-scoped with RLS (SEC-004):
- `connections(tenant_id, id, scope ENUM(ACCOUNT, ORGANIZATION), organization_id, account_id NULL, account_identifier_normalized, snowflake_region NULL, account_locator NULL, iam_role_arn UNIQUE, snowflake_user, reader_role, warehouse, wif_mode ENUM(AWS_ATTESTATION, AWS_OUTBOUND_JWT), state, connection_epoch bigint, revision bigint, script_version, modules text[], network_policy_opt_in bool, credit_quota int, created_at, updated_at)`.
  - `UNIQUE(environment, snowflake_region, account_locator) WHERE state <> 'DELETED'`. One tenant per Snowflake account (owner question Q1).
  - No password, private-key or token column. A catalog lint enforces this.
- `aws_identities(connection_id, role_name, role_arn, role_id, created_at, revoked_at, deleted_at)`. `role_name` is never reused: unique over all time.
- `state_transitions(connection_id, from, to, event, actor, reason_code, epoch, at)`.
- `organizations`, `accounts(tenant_id, id, snowflake_region, account_locator, current_name, org_name, edition, status ENUM(CANDIDATE, CONNECTED, MISSING_UNCONFIRMED, MISSING, DELETED), predecessor_account_id)`.
- `account_identity_history`, `discovery_snapshots`.
- `capability_observations(connection_id, connection_revision, probe_version, source_id, status, schema_hash, observed_latency_s, remediation_code, checked_at)`.
- `setup_scripts(connection_id, script_version, modules, sha256, rendered_at)`.

OpenAPI paths:
- `POST /v1/connections`
- `GET /v1/connections/{id}`
- `GET /v1/connections/{id}/setup` (script, org script, explanations, estimate)
- `POST /v1/connections/{id}/validate` (async job)
- `POST /v1/connections/{id}/capabilities`
- `GET /v1/connections/{id}/capabilities`
- `POST /v1/connections/{id}/pause`
- `POST /v1/connections/{id}/resume`
- `POST /v1/connections/{id}/revoke`
- `POST /v1/connections/{id}/disconnect`
- `POST /v1/connections/{id}/deletion-requests`
- `GET /v1/connections/{id}/revoke-script`
- `POST /v1/organizations/{id}/discover`
- `GET /v1/organizations/{id}/accounts`
- `GET /v1/platform/egress-ips`

### 3.1 Account installation script (template, rendered per connection; syntax items marked are TO VERIFY LIVE in CON-003-S10)

```sql
-- Bridge FinOps — ACCOUNT installation script  script_version=acct-v1
-- connection=<connection_uuid> revision=<n> modules=<CORE_COST,QUERIES,STORAGE,SERVERLESS> sha256=<digest>
-- WHO RUNS THIS: a Snowflake administrator who can USE ROLE ACCOUNTADMIN, once, interactively.
-- Bridge's runtime never uses ACCOUNTADMIN. Re-running is safe. Nothing is changed if the precheck fails.

-- 0. PRECHECK (Snowflake Scripting; TO VERIFY LIVE: SHOW + RESULT_SCAN inside EXECUTE IMMEDIATE)
EXECUTE IMMEDIATE $$
DECLARE foreign_count INTEGER DEFAULT 0;
BEGIN
  SHOW USERS LIKE 'BRIDGE_FINOPS_READER_USER';
  SELECT COUNT(*) INTO :foreign_count FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
   WHERE COALESCE("comment",'') NOT LIKE 'bridge_finops_managed:v1:%';
  IF (foreign_count > 0) THEN
    RETURN 'ABORTED: BRIDGE_FINOPS_READER_USER exists and is not Bridge-managed. No changes made.';
  END IF;
  -- identical checks: SHOW ROLES LIKE 'BRIDGE_FINOPS_READER'; SHOW WAREHOUSES LIKE 'BRIDGE_FINOPS_WH';
  -- SHOW RESOURCE MONITORS LIKE 'BRIDGE_FINOPS_RM'; SHOW NETWORK POLICIES (name BRIDGE_FINOPS_NP)
  RETURN 'PRECHECK_OK';
END;
$$;
-- Stop here if the result is not PRECHECK_OK.

-- 1. ROLE (USERADMIN)
USE ROLE USERADMIN;
CREATE ROLE IF NOT EXISTS BRIDGE_FINOPS_READER COMMENT = 'bridge_finops_managed:v1:<connection_uuid>';

-- 2. DEDICATED WAREHOUSE (SYSADMIN). No multi-cluster clauses: they fail on Standard edition.
USE ROLE SYSADMIN;
CREATE WAREHOUSE IF NOT EXISTS BRIDGE_FINOPS_WH
  WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  STATEMENT_TIMEOUT_IN_SECONDS = 3600 STATEMENT_QUEUED_TIMEOUT_IN_SECONDS = 600
  COMMENT = 'bridge_finops_managed:v1:<connection_uuid>';
ALTER WAREHOUSE BRIDGE_FINOPS_WH SET WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE
  STATEMENT_TIMEOUT_IN_SECONDS = 3600 STATEMENT_QUEUED_TIMEOUT_IN_SECONDS = 600;

-- 3. CREDIT CAP + GRANTS (ACCOUNTADMIN)
USE ROLE ACCOUNTADMIN;
CREATE RESOURCE MONITOR IF NOT EXISTS BRIDGE_FINOPS_RM WITH           -- TO VERIFY LIVE: IF NOT EXISTS support
  CREDIT_QUOTA = <customer_quota_int> FREQUENCY = MONTHLY START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 80 PERCENT DO NOTIFY ON 100 PERCENT DO SUSPEND ON 110 PERCENT DO SUSPEND_IMMEDIATE;
ALTER RESOURCE MONITOR BRIDGE_FINOPS_RM SET CREDIT_QUOTA = <customer_quota_int>;
ALTER WAREHOUSE BRIDGE_FINOPS_WH SET RESOURCE_MONITOR = BRIDGE_FINOPS_RM;
GRANT USAGE, OPERATE ON WAREHOUSE BRIDGE_FINOPS_WH TO ROLE BRIDGE_FINOPS_READER; -- OPERATE only for suspend-after-cycle
-- Module grants (rendered from snowflake_privilege_map.v1.json; one line per required database role):
GRANT DATABASE ROLE SNOWFLAKE.USAGE_VIEWER      TO ROLE BRIDGE_FINOPS_READER; -- metering, storage, serverless, QAH
GRANT DATABASE ROLE SNOWFLAKE.GOVERNANCE_VIEWER TO ROLE BRIDGE_FINOPS_READER; -- QUERIES module: QUERY_HISTORY incl. QUERY_TEXT (sanitized before storage)
GRANT DATABASE ROLE SNOWFLAKE.OBJECT_VIEWER     TO ROLE BRIDGE_FINOPS_READER; -- database owners for storage allocation (AU.DATABASES)

-- 4. SERVICE USER (USERADMIN). WIF only: no password, key pair or PAT exists.
USE ROLE USERADMIN;
CREATE USER IF NOT EXISTS BRIDGE_FINOPS_READER_USER
  TYPE = SERVICE
  WORKLOAD_IDENTITY = (TYPE = AWS ARN = 'arn:aws:iam::<bridge_aws_account_id>:role/bridge-conn-<env>-<32hex>')
  DEFAULT_ROLE = BRIDGE_FINOPS_READER DEFAULT_WAREHOUSE = BRIDGE_FINOPS_WH
  DEFAULT_SECONDARY_ROLES = ()
  COMMENT = 'bridge_finops_managed:v1:<connection_uuid>';
ALTER USER BRIDGE_FINOPS_READER_USER SET                              -- converges a pre-existing Bridge user (reconnect)
  TYPE = SERVICE
  WORKLOAD_IDENTITY = (TYPE = AWS ARN = 'arn:aws:iam::<bridge_aws_account_id>:role/bridge-conn-<env>-<32hex>')
  DEFAULT_ROLE = BRIDGE_FINOPS_READER DEFAULT_WAREHOUSE = BRIDGE_FINOPS_WH DEFAULT_SECONDARY_ROLES = ();
GRANT ROLE BRIDGE_FINOPS_READER TO USER BRIDGE_FINOPS_READER_USER;

-- 5. OPTIONAL NETWORK POLICY (SECURITYADMIN) — rendered only if the customer opts in (D-09)
USE ROLE SECURITYADMIN;
CREATE NETWORK POLICY IF NOT EXISTS BRIDGE_FINOPS_NP
  ALLOWED_IP_LIST = ('<eip_a>/32','<eip_b>/32') COMMENT = 'bridge_finops_managed:v1:<connection_uuid>';
ALTER NETWORK POLICY BRIDGE_FINOPS_NP SET ALLOWED_IP_LIST = ('<eip_a>/32','<eip_b>/32');
ALTER USER BRIDGE_FINOPS_READER_USER SET NETWORK_POLICY = BRIDGE_FINOPS_NP;

-- 6. READ-ONLY CONFIRMATION (paste the output into the wizard only if asked by support)
SHOW GRANTS TO ROLE BRIDGE_FINOPS_READER;
DESCRIBE USER BRIDGE_FINOPS_READER_USER;
```

The **organization script** (`org-v1`) is identical in shape. It uses `BRIDGE_FINOPS_ORG_READER`, `BRIDGE_FINOPS_ORG_WH` (same parameters, default quota 10) and `BRIDGE_FINOPS_ORG_USER`, bound to the *org* connection's IAM role. It grants `SNOWFLAKE.ORGANIZATION_BILLING_VIEWER` (USAGE_IN_CURRENCY_DAILY, RATE_SHEET_DAILY), `SNOWFLAKE.ORGANIZATION_USAGE_VIEWER` and `SNOWFLAKE.ORGANIZATION_ACCOUNTS_VIEWER` (ACCOUNTS). The per-view mapping is TO VERIFY LIVE. The script is rendered in two variants: *organization account* and *ORGADMIN-enabled regular account*.

The **revoke script** (`acct-revoke-v1`) runs the same precheck (it refuses to touch unmarked objects), then:
1. `ALTER USER BRIDGE_FINOPS_READER_USER SET DISABLED = TRUE` (blocks new logins; effect on running queries TO VERIFY LIVE).
2. `REVOKE DATABASE ROLE SNOWFLAKE.<r> FROM ROLE BRIDGE_FINOPS_READER` for each role.
3. `DROP USER IF EXISTS BRIDGE_FINOPS_READER_USER`.
4. `DROP ROLE IF EXISTS BRIDGE_FINOPS_READER`.
5. `DROP NETWORK POLICY IF EXISTS BRIDGE_FINOPS_NP`.
6. Optionally, behind a separate checkbox: `DROP WAREHOUSE IF EXISTS BRIDGE_FINOPS_WH` and `DROP RESOURCE MONITOR IF EXISTS BRIDGE_FINOPS_RM`.

The script never revokes grants it did not render (unrelated grants are preserved).

### 3.2 Module → source → database role map (seed for `snowflake_privilege_map.v1.json`)

| Module (R1 unless noted) | Views | Database role | Verification status |
|---|---|---|---|
| CORE_COST | AU.WAREHOUSE_METERING_HISTORY, METERING_HISTORY, METERING_DAILY_HISTORY | USAGE_VIEWER | Category VERIFIED (snippet); per-view TO VERIFY LIVE |
| QUERY_COST | AU.QUERY_ATTRIBUTION_HISTORY; AU.QUERY_METERING_HISTORY (Adaptive, D-20) | USAGE_VIEWER *or* GOVERNANCE_VIEWER | VERIFIED (per-view page snippets) |
| QUERIES | AU.QUERY_HISTORY | GOVERNANCE_VIEWER | VERIFIED (snippet) |
| STORAGE | AU.STORAGE_USAGE, DATABASE_STORAGE_USAGE_HISTORY | USAGE_VIEWER | Category VERIFIED; TO VERIFY LIVE |
| STORAGE (owners) | AU.DATABASES | OBJECT_VIEWER | TO VERIFY LIVE |
| STORAGE_TABLES (opt-in) | AU.TABLE_STORAGE_METRICS | Unknown; possibly IMPORTED PRIVILEGES | TO VERIFY LIVE (G-CON-02) |
| SERVERLESS | AU.AUTOMATIC_CLUSTERING_HISTORY, SERVERLESS_TASK_HISTORY, PIPE_USAGE_HISTORY | USAGE_VIEWER | Category VERIFIED; TO VERIFY LIVE |
| TRANSFER | AU.DATA_TRANSFER_HISTORY | USAGE_VIEWER | TO VERIFY LIVE |
| GOVERNANCE (R2) | AU.ACCESS_HISTORY | GOVERNANCE_VIEWER (Enterprise+) | VERIFIED (snippet) |
| SESSIONS (R2) | AU.SESSIONS, LOGIN_HISTORY | SECURITY_VIEWER | VERIFIED (snippet) |
| ORG_BILLING | OU.USAGE_IN_CURRENCY_DAILY, RATE_SHEET_DAILY | ORGANIZATION_BILLING_VIEWER | Role VERIFIED; per-view TO VERIFY LIVE |
| ORG_INVENTORY | OU.ACCOUNTS | ORGANIZATION_ACCOUNTS_VIEWER | Role VERIFIED; per-view TO VERIFY LIVE |

### 3.3 Customer credit estimate (D-08). Arithmetic is shown; the Snowflake rate is the customer's contract rate.

Assumptions: XSMALL = 1 credit/hour. The billed time of a resume is max(60 s, active + idle-until-suspend) — 60-second minimum VERIFIED (G-CON-01). Hourly account-cycle: ≈14 bounded queries of 1–4 s each (two passes of QH, QAH, WMH, MH plus AC, STH, PIPE). Active time is ≈ 15–40 s. That duration is an ASSUMPTION, TO VERIFY LIVE in CON-101-S07.

| Mode | Per cycle billed | Per day | Per month (30 d) |
|---|---|---|---|
| Hourly, explicit `SUSPEND` after cycle (recommended, needs OPERATE) | max(60, 15–40) = 60 s | 24 × 60 s = 1,440 s = 0.40 cr | 12.0 cr |
| Hourly, AUTO_SUSPEND=60 only | 40 + 60 (+0–30 lag) = 100–130 s | 2,400–3,120 s = 0.67–0.87 cr | 20.0–26.0 cr |
| + daily sources (MDH, storage, DBs, transfer, DESCRIBE schema checks) | +60–120 s once per day | +0.017–0.033 cr | +0.5–1.0 cr |
| + weekly anti-entropy aggregates (30-day QH/QAH counts) | +60–120 s per week | — | +0.1–0.2 cr |
| Org connection, daily cycle (once per organization) | 60–120 s | 0.017–0.033 cr | 0.5–1.0 cr |
| **Default total per connected account** | | | **≈ 12.6–13.2 cr (explicit suspend) / 20.6–27.2 cr (auto-suspend)** |
| Catalog 15-min QH cadence (rejected default) | +72 extra resumes/day × 60 s | +1.2 cr | +36 cr |
| One-time backfill, 1M queries/day account (G-ING-09) | ≈730 day-chunks × 20–60 s | — | 4–12 cr + ≈2 cr other sources |

At a contract rate of USD 2–4 per credit, the recommended default costs ≈ USD 25–53 per month per account. OPS-103's independent estimate of "≈150 s/h ≈ 30 credits/month" (auto-suspend, no explicit suspend) is consistent with the second row.

### 3.4 Connection lifecycle transition table

| From | Event | Guard | To | Side effects |
|---|---|---|---|---|
| — | create | RBAC `connection.manage`; entitlement `connected_accounts` (D-17) not exceeded; IAM quota < 90 % | DRAFT | row + audit + outbox `provision_identity` |
| DRAFT | identity_provisioned | IAM role exists + boundary attached | AWAITING_CUSTOMER_SETUP | script rendered (`script_version`, sha256) |
| AWAITING_CUSTOMER_SETUP, READY, DEGRADED | validate | no validation in flight for this revision | VALIDATING | verifier task launched with epoch |
| VALIDATING | probes_ok | identity matches `(region, locator)`; all *required* module sources ∈ {AVAILABLE, AVAILABLE_EMPTY}; no `CON_EXCESS_PRIVILEGE` of write class | READY | capability snapshot bound to revision |
| VALIDATING | probes_failed | — | AWAITING_CUSTOMER_SETUP | remediation list; no scheduling |
| READY | history_consented | estimate shown + consent recorded (actor, quota, cadence, history range) | SYNCING | steady cycles enabled; backfill plan submitted |
| SYNCING | coverage_complete | every required source contiguous from available start to settle horizon | ACTIVE | onboarding step updated |
| SYNCING, ACTIVE | required_source_failing | ≥ 3 consecutive failed cycles, or a non-retryable class | DEGRADED | Data Health reason; other sources continue |
| DEGRADED | recovered | the failing sources succeed for 2 consecutive cycles | previous (SYNCING/ACTIVE) | — |
| READY, SYNCING, ACTIVE, DEGRADED | pause | RBAC; `If-Match` revision | PAUSED | epoch++; leases fenced; no new cycles |
| PAUSED | resume | — | VALIDATING | re-probe before any scheduling |
| any except DELETING/DELETED | revoke | RBAC + typed confirmation | REVOKED | epoch++; IAM inline Deny attached ≤ 60 s; revoke script offered |
| REVOKED | reconnect | new script run by customer | VALIDATING | Deny removed only after successful identity probe |
| PAUSED, REVOKED, AWAITING_CUSTOMER_SETUP | delete_requested | RBAC + typed confirmation + retention policy shown | DELETING | OPS-005 workflow; IAM role deleted after completion + 7 days |
| DELETING | deletion_completed | OPS-005 evidence | DELETED (terminal tombstone) | role name retired forever |
| any non-terminal | identifier_revision | endpoint change (rename) or customer edit | VALIDATING | epoch++; identity immutable (region, locator, ARN) |

### 3.5 Probe statuses and error classification

| Observation | Status | Remediation code |
|---|---|---|
| Rows returned with required columns and compatible types | AVAILABLE | — |
| 0 rows on a source that can legitimately be empty (serverless, transfer) in a 48 h bounded probe | AVAILABLE_EMPTY | — |
| 0 rows on QUERY_HISTORY although Bridge's own canary QUERY_ID is ≥ 3 h old; or 0 rows where the previous observation was > 0 | SUSPECT_EMPTY | `CHECK_GRANT_OR_LATENCY` |
| Insufficient-privileges error | DENIED | `GRANT_<ROLE>` (exact statement) |
| "Does not exist or not authorized" and the edition is unknown | DENIED_OR_UNAVAILABLE | grant statement + "if already granted, this view is not available for your edition/region" |
| Same error, but the edition is known (OU.ACCOUNTS) to lack the feature | NOT_SUPPORTED | none (feature-gated) |
| Feature-dependent view present but no feature usage (for example no Adaptive warehouse, so QMH is empty) | NOT_ENABLED | none |
| Required column missing, or incompatible type/scale | SCHEMA_MISMATCH | Bridge-side action (ING-009) |
| Timeout, 5xx, throttling | TRANSIENT_ERROR | auto-retry |
| Warehouse suspended by resource monitor | CUSTOMER_QUOTA_EXHAUSTED | raise the quota or wait for month rollover |
| Login rejected by network policy | NETWORK_POLICY_BLOCKED | add egress IPs |

Exact Snowflake error codes are captured live in CON-002-S05 and CON-005-S03 and recorded in this table. They are not invented here.

## 4. Revised production backlog

### CON-001 — Register account identities and controlled WIF task roles
Release: R1 · Estimate: 40–56 h · Risk: H · Decisions: D-02 (shared IAM quota), D-07, D-17 · Closes: G-CON-04, G-CON-06 (identity key), G-CON-10 (scope)
Dependency changes: `+INF-005 (launcher PassRole, ECS task definition)`, `+INF-003 (landing bucket/KMS for prefix policy)`, `−INF-008 (central Snowflake is needed by CON-002, not here)`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| CON-001-S01 | Write the Alembic migration for `connection.connections`, `connection.aws_identities` and `connection.state_transitions` per §3. Constraints: scope enum; `UNIQUE(environment, snowflake_region, account_locator) WHERE state<>'DELETED'`; `aws_identities.role_name` unique across all rows ever; composite `(tenant_id, id)` FKs; RLS FORCE. | `apps/api/migrations/xxxx_connection_identity.py` | A catalog lint finds no column matching `password\|private_key\|token\|secret`. Inserting a second live row for the same (region, locator) fails. A foreign-tenant SELECT under the runtime role returns 0 rows. | 3 |
| CON-001-S02 | Implement `normalize_account_identifier(raw)`. Accept `org-account`, `org.account`, `locator.region[.cloud]` and `https://<id>.snowflakecomputing.com[/]`. Reject userinfo, ports, paths, IP literals, non-`snowflakecomputing.com` hosts and `privatelink` hosts (reject with `CON_PRIVATELINK_R2`). Return `{identifier, host}`; the host is derived only from the normalized identifier. | `packages/connections/identifiers.py` | Property tests over 10k fuzzed inputs pass. `https://evil.com/.snowflakecomputing.com`, `acme-prod@10.0.0.1` and `acme.privatelink.snowflakecomputing.com` are rejected with distinct codes. | 3 |
| CON-001-S03 | Author the IAM templates: trust policy (`ecs-tasks.amazonaws.com`, `aws:SourceAccount`, `aws:SourceArn` scoped to the cluster ARN pattern); permission policy enumerating `landing/source=<S>/schema_major=<n>/tenant_id=<t>/organization_id=<o>/account_id=<a>/*` and the matching `manifests/` prefix per registered source; `bridge-connector-boundary` (S3 landing/manifests + KMS landing key only, no `iam:*`/`sts:AssumeRole`); inline `bridge-revoked-deny`. | `infra/terraform/modules/connector_identity_boundary/`, `packages/connections/iam_templates.py` | IAM Access Analyzer `ValidatePolicy` shows 0 errors or security warnings in CI. The rendered policy contains no `*` before `tenant_id=`. | 4 |
| CON-001-S04 | Build the outbox-driven `connector-identity-provisioner` worker. It creates role `bridge-conn-<env>-<uuid32>` (no path) with the boundary, puts the inline policy and tags `bridge:connection_id`/`bridge:tenant_id`. It is idempotent: on `EntityAlreadyExists` it compares tags and adopts or fails. It waits for propagation (GetRole + `SimulatePrincipalPolicy` succeeds, max 60 s). | `services/identity_provisioner/connector_roles.py` | The same outbox event delivered 3× leaves one role and one `aws_identities` row. A crash between CreateRole and PutRolePolicy, followed by retry, converges. | 4 |
| CON-001-S05 | Give the provisioner its own least privilege: `iam:CreateRole` on `role/bridge-conn-<env>-*` only with `iam:PermissionsBoundary` = boundary ARN; `iam:PutRolePolicy`/`DeleteRolePolicy`/`TagRole`/`DeleteRole`/`GetRole` on the same pattern; explicit Deny on `iam:DeleteRolePermissionsBoundary` and `iam:PutRolePermissionsBoundary`. | `infra/terraform/modules/identity_provisioner/` | Staging tests. CreateRole without the boundary fails with AccessDenied. CreateRole named `admin-x` fails with AccessDenied. Removing the boundary from an existing connector role fails with AccessDenied. | 3 |
| CON-001-S06 | Restrict the launcher: `iam:PassRole` on `role/bridge-conn-<env>-*` with `iam:PassedToService = ecs-tasks.amazonaws.com`; `ecs:RunTask` only on the approved extractor/verifier task-definition families. The launch API takes `connection_id` only and resolves the ARN server-side from PG. | `infra/terraform/modules/launcher/`, `services/launcher/resolve.py` | A request body containing `role_arn` returns 400 `CON_FIELD_NOT_ALLOWED`. The API task role calling PassRole gets AccessDenied. | 3 |
| CON-001-S07 | Implement `POST /v1/connections`: body `{scope, organization_id, account_identifier, modules[], credit_quota, network_policy_opt_in}`; `Idempotency-Key`; RBAC `connection.manage`; entitlement check (D-17); IAM quota gate (`CON_CAPACITY` at ≥ 90 %). Returns `{connection_id, state, iam_role_arn, revision}` after provisioning, or 202 with state DRAFT while provisioning. | `apps/api/connections/routes.py`, OpenAPI | Same key and body returns the same id. Same key with a different body returns 409. A tenant-B admin POSTing tenant-A's `organization_id` gets a non-enumerating 404. | 4 |
| CON-001-S08 | Enforce identity immutability. PATCH of `tenant_id`, `iam_role_arn`, `snowflake_region` or `account_locator` returns 409 `CON_IDENTITY_IMMUTABLE`. An identifier (endpoint) change creates revision n+1, sets state VALIDATING and increments the epoch. | `apps/api/connections/revisions.py` | The API test matrix covers all four immutable fields. A revision bump invalidates capability observations of revision n (GET shows `stale=true`). | 3 |
| CON-001-S09 | Implement revoke and delete at the IAM level. Revoke attaches `bridge-revoked-deny` within 60 s. Delete (after DELETING completes + 7 days) detaches the boundary/policies, deletes the role and keeps the `aws_identities` row with `deleted_at`. Creating a role with a retired name is refused. | `services/identity_provisioner/lifecycle.py` | Staging: a running task's S3 PutObject fails with AccessDenied ≤ 60 s after revoke. Re-creating the connection yields a different role name. | 4 |
| CON-001-S10 | Build the quota monitor: a daily job reads the Service Quotas `L-FE177D64` (IAM roles) value and the role count; metric `iam_roles_used_ratio`; alarm at 0.70 (page) and at 0.90 (admission blocked). SEC-105 tenant-serving roles are counted in the same metric. | `services/identity_provisioner/quota.py`, CloudWatch alarm | With a fixture quota of 100 and 91 roles, create returns `CON_CAPACITY` and the alarm is in ALARM state. | 2 |
| CON-001-S11 | Run the tenant-isolation attack suite. (a) The launcher is asked to run tenant A's cycle with B's connection: refused. (b) A task with A's role PUTs to B's prefix: AccessDenied. (c) A task with A's role PUTs `landing/source=QH/schema_major=1/tenant_id=A/…/account_id=a/../tenant_id=B/x.parquet`: rejected by key-grammar validation (ING-005) and never loaded (pipe PATTERN, ING-006). (d) The API role PassRole attempt: AccessDenied. | `tests/security/con_001_isolation.py` | 4/4 attacks denied, each with an audit event. The evidence contains the CloudTrail event IDs. | 4 |
| CON-001-S12 | Add observability: metrics `connector_identity_provision_seconds`, `connector_identity_provision_failures_total{reason}`, `iam_roles_used_ratio`; log fields `connection_id`, `role_name`, `outbox_event_id` (never the policy JSON); extend RB-01 with "IAM role missing/propagating/revoked" diagnosis. | `docs/16-observability/RUNBOOKS.md` addition (new file in implementation repo), dashboards | The alarm routes to on-call in staging. An RB-01 dry run with a deliberately deleted role reaches the right diagnosis in ≤ 10 min. | 2 |
| CON-001-S13 | Capture staging evidence: 3 connections (2 tenants, 1 org scope); provisioning latency p95; attack-suite results. | `docs/evidence/CON-001/<commit>/` | Evidence record fields complete (validation-strategy) and reviewed. | 2 |
Task acceptance:
- [ ] A connection can never launch under another connection's IAM role, and the ARN never comes from a request.
- [ ] Role names derive from UUIDs, carry no IAM path and are never reused; re-creation yields a new ARN.
- [ ] Revoke blocks S3/KMS writes of running tasks within 60 s.
- [ ] Admission blocks at 90 % IAM role quota with `CON_CAPACITY`; alarm at 70 %.
- [ ] No credential-bearing column exists in `connection.*`.

### CON-002 — Prove WIF connector and dbt compatibility live
Release: R1 · Estimate: 36–52 h · Risk: H · Decisions: D-21, D-09 · Closes: G-CON-06 (verification), G-CON-03 (part), G-ING-02 (connector flags)
Dependency changes: `+INF-008 (central dbt WIF identity)`, `+INF-002 (NAT egress)`, `+OPS-103 (synthetic Snowflake accounts; replaces ad-hoc staging accounts)`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| CON-002-S01 | Pin the runtime matrix entry: `snowflake-connector-python` (≥ 3.17 for AWS attestation; outbound-JWT option `workload_identity_aws_use_outbound_token` present in main, VERIFIED 2026-09-28), `pyarrow`, `dbt-core`, `dbt-snowflake ≥ 1.12` (PR #1316); record exact hashes. | `docs/development/versions.md`, lockfiles | CI fails if an unpinned Snowflake/Arrow/dbt dependency appears. | 2 |
| CON-002-S02 | Implement `connect(ctx)` with: `authenticator='WORKLOAD_IDENTITY'`, `workload_identity_provider='AWS'`, account = normalized identifier, role, warehouse, `arrow_number_to_decimal=True`, `login_timeout=30`, `network_timeout=120`. Session parameters: `TIMEZONE='UTC'`, `QUERY_TAG='bridge_finops:v1:<component>:<cycle_id>'`, `STATEMENT_TIMEOUT_IN_SECONDS` (900 steady / 3600 backfill), `ABORT_DETACHED_QUERY=TRUE` (semantics TO VERIFY LIVE). The function signature has no password/key/token parameters. | `packages/snowflake_client/wif.py` | A unit test introspects the signature and the connect kwargs: no `password`, `private_key`, `token` or `authenticator='snowflake'` path. Mutation test: setting `arrow_number_to_decimal=False` fails the decimal contract test. | 3 |
| CON-002-S03 | Implement `verify_identity(session, expected)`: `SELECT CURRENT_ACCOUNT(), CURRENT_REGION(), CURRENT_ORGANIZATION_NAME(), CURRENT_ACCOUNT_NAME(), CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE()`. Compare `(region, locator)`, user and role to `expected`. On mismatch, close the session and raise `CON_ACCOUNT_MISMATCH`. | `packages/snowflake_client/identity.py` | A synthetic mismatch (login succeeds to account B while A was expected) is rejected before any source query. The log contains the query ID only. | 2 |
| CON-002-S04 | Build the verifier: ECS task family `bridge-wif-verifier`, launched with `taskRoleArn` override = the connection role, which writes a result JSON to `probes/tenant_id=<t>/…/probe_id=<uuid>.json` (If-None-Match). The control plane reads the result and times out after 120 s. | `services/extractor/verifier.py`, task definition | Round trip ≤ 90 s p95 in staging. The result contains no AWS attestation or session token (grep test on the output). | 4 |
| CON-002-S05 | Capture the error-classification table live: user does not exist (script not yet run), wrong principal, user disabled, network policy denial, role not granted, warehouse suspended by resource monitor, DNS failure, TLS failure → map exact codes/messages to §3.5 statuses and `CON_*` codes. | `packages/snowflake_client/errors.py`, table in §3.5 of implementation docs | Every case is reproduced in an OPS-103 account and maps to exactly one code. Unknown codes map to `TRANSIENT_ERROR` plus an alarm `unclassified_snowflake_error_total`. | 4 |
| CON-002-S06 | Run positive live tests in 2 synthetic accounts (Enterprise, Standard; different regions) and 1 organization account through the NAT path. | `tests/live/wif/test_positive.py` | 3/3 authenticate; identity matches the expected `(region, locator)`. | 3 |
| CON-002-S07 | Run negative live tests: (a) A's role connecting as B's user; (b) disabled user; (c) `REVOKE ROLE` mid-session followed by the next query; (d) network policy excluding the EIPs; (e) a deleted IAM role. | `tests/live/wif/test_negative.py` | All 5 fail with the expected class. (c) fails on the next statement, not at reconnect. | 4 |
| CON-002-S08 | Handle long sessions: run a 5-hour synthetic backfill session that forces a session/token expiry; implement reconnect-and-resume at window granularity on session-expired errors (codes captured in S05). | `packages/snowflake_client/reconnect.py` | The run completes. The window in flight at expiry is restarted, and no window is duplicated in accepted coverage. | 3 |
| CON-002-S09 | Evaluate AWS outbound-JWT mode. Enable IAM outbound web identity federation in staging, configure the Snowflake user issuer, run the connector with `workload_identity_aws_use_outbound_token=True` and dbt parameter forwarding. Decide between `AWS_ATTESTATION` (default) and `AWS_OUTBOUND_JWT`, and record an ADR-004 amendment. | `docs/architecture/adr/ADR-004` amendment PR (implementation repo), evidence | The decision record lists both modes' pass/fail per adapter. No RSA/PAT path exists in either. | 4 |
| CON-002-S10 | Wire central dbt WIF: `profiles.yml` target with the WIF authenticator (dbt-snowflake 1.12 parameter names, TO VERIFY LIVE); `dbt debug` plus one tiny model and one test under the central transformer identity; wrong-role denial. | `data/dbt/profiles/`, `tests/live/dbt_wif/` | `dbt debug` exits 0. The model builds. Swapping to the reader role fails with an authorization error. | 3 |
| CON-002-S11 | Prove large-result download through the private path: a > 150 MB Arrow result from a customer-like account in the same AWS region as Bridge must download through the S3 gateway endpoint with the INF-002 policy that includes the `SYSTEM$ALLOWLIST` STAGE hosts. | `tests/live/wif/test_result_download.py` | 150 MB are fetched with `fetch_arrow_batches`. With the stage host removed from the endpoint policy, the same test fails with a classified `STAGE_DOWNLOAD_BLOCKED` (no hang: timeout ≤ 120 s). | 3 |
| CON-002-S12 | Record the evidence and version matrix. | `docs/evidence/CON-002/<commit>/`, `versions.md` | V01 is updated to PASS/FAIL per adapter with query IDs. | 2 |
Task acceptance:
- [ ] Extractor and dbt authenticate only through WIF, with the exact version matrix recorded.
- [ ] A successful login to the wrong account is rejected by `(region, locator)` verification.
- [ ] 8 failure classes are reproduced live and mapped to codes; unknown errors alarm.
- [ ] Large result downloads work through the gateway endpoint; the blocked case fails fast and classified.
- [ ] Session expiry during a 5 h backfill resumes at window granularity without duplicate coverage.

### CON-003 — Generate least-privilege installation and revoke scripts
Release: R1 · Estimate: 44–64 h · Risk: H · Decisions: D-08, D-09, D-11 (QUERIES disclosure) · Closes: G-CON-01 (script part), G-CON-02, G-CON-05, G-CON-10 (org script)
Dependency changes: `+ING-001 (module → source map from registry)`, `+CON-101 (estimate/quota parameters)`, `+CON-102 (egress IPs)`, `+OPS-103 (synthetic accounts)`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| CON-003-S01 | Generate the privilege map. In OPS-103 accounts (Standard and Enterprise, plus an org account), run `SHOW GRANTS TO DATABASE ROLE SNOWFLAKE.<r>` for USAGE_VIEWER, GOVERNANCE_VIEWER, OBJECT_VIEWER, SECURITY_VIEWER and the ORGANIZATION_* roles. Build module→view→role (§3.2) with a verification record (account, edition, BCR bundle, sha256 of the grant listing). | `data/contracts/snowflake_privilege_map.v1.json`, `tools/privilege_map/refresh.py` | Every R1 source maps to exactly one minimal role, or is marked `UNMAPPED` with a decision. A CI check fails if an active registry source has no mapping. | 5 |
| CON-003-S02 | Write the account template (§3.1) with role-sectioned `USE ROLE` blocks. Rendering accepts only: connection UUID (regex), ARN (regex `^arn:aws:iam::\d{12}:role/bridge-conn-(dev\|stg\|prod)-[0-9a-f]{32}$`), quota (int 1–10000), CIDRs (`/32` IPv4 from the published list only), module enum. | `apps/api/connections/bootstrap/templates/account_v1.sql.j2`, `render.py` | Injection tests fail validation before rendering: quota `"1; DROP USER X"`, ARN containing `'`, CIDR `0.0.0.0/0`. | 4 |
| CON-003-S03 | Implement the precheck block (Snowflake Scripting) for user, role, warehouse, resource monitor and network policy, using the marker comment. | template section 0 | Live test: a pre-created unmarked `BRIDGE_FINOPS_READER_USER` returns ABORTED with 0 changes (object list diff before/after is empty). | 3 |
| CON-003-S04 | Add convergence: `CREATE … IF NOT EXISTS` followed by `ALTER … SET` for warehouse size/suspend/timeouts, user TYPE/WORKLOAD_IDENTITY/DEFAULT_ROLE/DEFAULT_WAREHOUSE/`DEFAULT_SECONDARY_ROLES=()`, monitor quota. Edition-aware rendering: omit multi-cluster clauses. | template sections 1–4 | Live: run v1 with ARN X, then v1 with ARN Y (reconnect). `DESCRIBE USER` shows ARN Y and secondary roles empty. On Standard edition the script runs with no errors. | 4 |
| CON-003-S05 | Write the org templates (organization-account and ORGADMIN-enabled variants) with ORGANIZATION_* database roles, org warehouse and org user bound to the org connection's IAM role. | `templates/org_v1_orgaccount.sql.j2`, `org_v1_orgadmin.sql.j2` | Live in the OPS-103 org account: the `OU.USAGE_IN_CURRENCY_DAILY` bounded probe returns AVAILABLE (or a documented reseller DENIED). | 4 |
| CON-003-S06 | Write the revoke templates (account, org): precheck; disable user; revoke only rendered roles; drop user, role and network policy; optional warehouse/monitor drop behind a flag. | `templates/revoke_*_v1.sql.j2` | Live: fixture with an unrelated `ANALYST` role granted USAGE_VIEWER. After revoke, `ANALYST`'s grant is unchanged and the Bridge objects are absent. | 3 |
| CON-003-S07 | Implement `GET /v1/connections/{id}/setup`: `{script, org_script?, script_version, sha256, statements:[{sql, explanation, privilege_exposed}], estimate}`. `setup_scripts` row per render. Stale detection: validation with a script version older than the current one returns `CON_STALE_SCRIPT` with a diff. | `apps/api/connections/setup.py` | Two renders with identical inputs have the same sha256. A module change produces a new version and marks old validations stale. | 3 |
| CON-003-S08 | Implement the grant-diff validator. From the reader session: `SHOW GRANTS TO ROLE BRIDGE_FINOPS_READER` and `SHOW GRANTS TO USER BRIDGE_FINOPS_READER_USER`. Compute missing grants (emit the exact single statement each) and excess grants. Write-class privileges (OWNERSHIP, CREATE *, MODIFY, INSERT, any account role granted *to* the reader) produce `CON_EXCESS_PRIVILEGE`, which blocks READY. Read-class extras produce a warning. | `apps/api/connections/grant_diff.py` | Live: remove USAGE_VIEWER and the validator emits exactly `GRANT DATABASE ROLE SNOWFLAKE.USAGE_VIEWER TO ROLE BRIDGE_FINOPS_READER;`. Grant SYSADMIN to the reader and READY is blocked. | 5 |
| CON-003-S09 | Separate the reader and operator planes. The renderer has no template path that emits OPERATE on non-Bridge warehouses, MODIFY or any write privilege. The operator plane (R2) is a different template family with a separate IAM role, user and version namespace. | renderer allowlist + unit test | A static test scans the rendered reader script for `OPERATE ON WAREHOUSE` other than `BRIDGE_FINOPS_WH` and for `MODIFY`/`OWNERSHIP`/`CREATE` grants: 0 occurrences. | 2 |
| CON-003-S10 | Run the live idempotency matrix (Standard, Enterprise, org). Run twice: the second run produces an empty grant/object diff. Drop one grant and get targeted remediation. Run revoke, then re-install. Record every "TO VERIFY LIVE" syntax item in §3.1 as confirmed or amended. | `tests/live/bootstrap/`, evidence | 3 editions × 4 scenarios pass. The §3.1 annotations are updated with evidence references. | 6 |
| CON-003-S11 | Write the customer setup guide: who runs it (ACCOUNTADMIN once), what each database role exposes (GOVERNANCE_VIEWER → query text, sanitized before storage per ADR-009), the credit estimate table, network options, the revoke procedure and the PrivateLink R1 limitation. | `docs/customer/snowflake-setup.md` | Reviewed by Security plus one external Snowflake admin (usability): they can execute it without Bridge support. | 3 |
| CON-003-S12 | Write the audit and observability: `setup_script_rendered`, `validation_grant_diff{missing,excess}` metrics; audit events for render, download and validation outcome. | audit catalog entries | Audit rows appear for render and download. No SQL text in logs beyond the template ID and version. | 2 |
Task acceptance:
- [ ] A second run is a no-op; a reconnect converges WORKLOAD_IDENTITY and user defaults.
- [ ] The precheck aborts on unmarked same-named objects with zero changes.
- [ ] Revoke removes only Bridge-managed objects and grants.
- [ ] The QUERIES module visibly discloses GOVERNANCE_VIEWER exposure; TABLE_STORAGE_METRICS is gated per the live mapping.
- [ ] The reader script can never contain write privileges or grants on customer warehouses.

### CON-004 — Discover organizations, accounts and lifecycle changes
Release: R1 · Estimate: 32–46 h · Risk: M · Decisions: D-20 · Closes: G-CON-06, G-CON-10 (discovery)
Dependency changes: none (CON-003, CTL-001, UX-001 retained). UX-001 is needed only for S12.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| CON-004-S01 | Write the migration for `connection.organizations`, `connection.accounts` (§3), `account_identity_history(account_id, name, url, org_name, observed_at, source)` and `discovery_snapshots(id, org_connection_id, started_at, finished_at, status, row_count, error_class)`. | migration | Unique `(tenant_id, snowflake_region, account_locator)`. Two accounts with the same locator in different regions coexist. | 3 |
| CON-004-S02 | Detect org mode in the org connection session: `CURRENT_ORGANIZATION_NAME()`; the bounded probe of `OU.ACCOUNTS` succeeds or fails, which classifies ORG_ACCOUNT, ORGADMIN_ENABLED or NO_ORG_ACCESS. | `services/extractor/discovery.py::detect_mode` | Three OPS-103/fixture cases classify correctly. NO_ORG_ACCESS never errors the tenant; it sets `org_visibility=INCOMPLETE`. | 3 |
| CON-004-S03 | Write the `OU.ACCOUNTS` contract (projection verified live: organization name, account name, locator, region, edition, created/deleted timestamps, org-admin flag; exact columns TO VERIFY LIVE) and a normalizer. | `data/contracts/sources/ou_accounts.v1.json` | The live DESCRIBE matches the contract. Unknown columns are ignored. | 3 |
| CON-004-S04 | Implement the upsert keyed by `(region, locator)`. A new account becomes CANDIDATE. A name/url change writes a history row. After 1 successful snapshot missing the account → MISSING_UNCONFIRMED; after 3 consecutive snapshots spanning ≥ 24 h → MISSING. DELETED only from an explicit deleted timestamp. A snapshot with errors, or with 0 rows when the previous count was > 0, is recorded FAILED/SUSPECT and applies **no** changes. | `services/extractor/discovery.py::apply_snapshot` | Fixtures: rename ×2 keeps one account id with 2 history rows. A transient 0-row snapshot causes no status change. The deleted flag → DELETED. | 4 |
| CON-004-S05 | Selection creates connections. `POST /v1/organizations/{id}/accounts/{aid}/connect` creates an ACCOUNT-scope DRAFT connection (CON-001). Discovery itself never schedules extraction. | route + test | Discovering 10 accounts creates 0 cycles. Selecting 2 creates 2 DRAFT connections and 0 cycles until READY and consent. | 2 |
| CON-004-S06 | Support manual enrollment: a standalone account connection without an org connection. On first validation, record `CURRENT_ORGANIZATION_NAME()` and `(region, locator)`; `org_visibility=INCOMPLETE`; group by org name for display only. | `apps/api/organizations/manual.py` | A standalone account reaches READY. The UI shows the "organization billing not visible" limitation. | 3 |
| CON-004-S07 | Handle endpoint maintenance on rename. When discovery sees a new name for a connected `(region, locator)`, create an audited connection revision with the new `<org>-<account>` identifier (epoch++), then re-validate automatically. | `apps/api/connections/endpoint_update.py` | Live (OPS-103 rename with SAVE_OLD_URL=FALSE): extraction resumes within one cycle after rename, with no duplicate account. | 3 |
| CON-004-S08 | Handle org and region moves. An org move shows up as the same `(region, locator)` under a different org name, which becomes a membership-history row and is reflected in the tenant organization. A region move shows up as a new locator: new CANDIDATE plus a support action to link `predecessor_account_id`, with no automatic merge. | `discovery.py::apply_membership` | Fixture tests pass. The linked predecessor appears in account detail. Charges are never merged. | 3 |
| CON-004-S09 | Implement the discovery API: `POST /v1/organizations/{id}/discover` (async job, idempotency key, 1 in flight per org); `GET /v1/organizations/{id}/accounts?status=` with keyset pagination. RBAC `connection.manage`/`connection.read`. | routes + OpenAPI | Foreign org id → 404. Concurrent discover requests → 1 job (second returns the same job id). | 3 |
| CON-004-S10 | Handle reseller/no-billing: OU billing view denied → org capability `BILLING_UNAVAILABLE`; inventory still works. Record the reseller flag for FIN (imported statement path). | capability record | Fixture with billing denied and ACCOUNTS allowed → inventory OK, billing gap visible. | 2 |
| CON-004-S11 | Schedule discovery: 4×/day in the org cycle; on-demand refresh is rate-limited to 1 per 10 min per org. | ORC schedule config | The schedule exists. A 5th on-demand request inside 10 min returns 429 with Retry-After. | 2 |
| CON-004-S12 | Build the UI `/settings/connections/organization`: separate lists Discovered / Connected / Inaccessible / Missing; manual add; refresh; states per the task UX table. | `apps/web/connections/organization/` | Playwright: empty (no org access → manual path), loading, partial, denied (403 page with no names), success. | 4 |
| CON-004-S13 | Capture evidence and a runbook entry: "account missing from discovery". | evidence, runbook | Reviewed. | 1 |
Task acceptance:
- [ ] Discovery alone never starts extraction.
- [ ] A rename keeps the account id and updates the connection endpoint through an audited revision.
- [ ] Transient errors or empty snapshots never change account status.
- [ ] Same locator in two regions yields two accounts; a region move yields a new account with an optional predecessor link.
- [ ] Manual/standalone enrollment works with explicit `org_visibility=INCOMPLETE`.

### CON-005 — Probe capabilities, source schemas and permission gaps
Release: R1 · Estimate: 40–56 h · Risk: H · Decisions: D-08, D-09, D-20 · Closes: G-CON-07, G-CON-08, G-CON-03 (stage hosts)
Dependency changes: `+ING-001 (registry metadata and query builder)`, `+CON-101 (probes run inside one warehouse resume)`, `+OPS-103`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| CON-005-S01 | Author `data/contracts/capability.json` (JSON Schema): status enum per §3.5, `remediation_code`, `schema_hash`, `observed_latency_s`, `edition`, `stage_hosts[]`, `bcr_bundles[]`, `probe_version`, `connection_revision`. | contract file | Positive and negative payload fixtures validate or fail as expected. | 2 |
| CON-005-S02 | Build the probe from the registry. (a) `DESCRIBE VIEW <fq view>` (schema; TO VERIFY LIVE whether it runs without a warehouse). (b) A bounded data probe using the registry's predicate template over the last 48 h, with required projection only and `LIMIT 1`. (c) For snapshot sources, `SELECT COUNT(*)` with the registry filter. All statements get a 30 s timeout. | `services/extractor/capabilities.py` | No generated SQL contains `SELECT *` or lacks a time/limit bound (static test over all registry sources). | 5 |
| CON-005-S03 | Classify errors using the table captured in CON-002-S05, adding `DENIED_OR_UNAVAILABLE` and `NOT_SUPPORTED` (edition known from OU.ACCOUNTS, or `UNKNOWN`). | `capabilities.py::classify` | Unit table test covers all §3.5 rows. The live fixture for missing GOVERNANCE_VIEWER yields DENIED or DENIED_OR_UNAVAILABLE with the exact GRANT remediation. | 3 |
| CON-005-S04 | Compare schemas: required fields present; type family and scale compatible with the registry (NUMBER(38,s) with the same s; TIMESTAMP scale ≥ registry); nullability recorded. Hash = sha256 over sorted `(name_upper, type, scale, nullable)`. | `capabilities.py::compare_schema` | Removing a required column in a fixture view gives SCHEMA_MISMATCH. An added column changes nothing except the stored "observed extra columns" list. | 3 |
| CON-005-S05 | Implement the canary and latency rule. Record Bridge's verification QUERY_ID and time; later probes look for it in AU.QUERY_HISTORY. Found → `observed_latency_s`. Not found after 3 h → SUSPECT_EMPTY. Emit metric `source_latency_observed_seconds{source}` (bounded label set). | `capabilities.py::canary` | Live: the canary is found and latency recorded (≤ 45 min expected per docs). With the grant removed, the result is DENIED, not EMPTY. | 4 |
| CON-005-S06 | Capture account facts: edition/region/cloud (OU.ACCOUNTS when visible, else `UNKNOWN`); Adaptive presence (QMH rows > 0 in 7 d → flag D-20 "FIN-004 required", per G-FIN-07); `SYSTEM$ALLOWLIST()` STAGE hosts; BCR bundle statuses (`SYSTEM$BEHAVIOR_CHANGE_BUNDLE_STATUS`, privilege TO VERIFY LIVE). | `capabilities.py::account_facts` | Facts are stored per revision. Stage hosts feed the INF-002 allowlist job (CON-102-S05). | 4 |
| CON-005-S07 | Define required vs optional per module and the READY guard: identity OK AND ∀ required sources ∈ {AVAILABLE, AVAILABLE_EMPTY} AND no write-class excess privilege. Optional failures disable only the dependent features. | `packages/connections/readiness.py` | Fixture: ACCESS_HISTORY DENIED (optional) plus core OK gives READY with a Governance gap. QH DENIED (QUERIES required) gives no READY. | 3 |
| CON-005-S08 | Bind probes to revisions: key observations by `(connection_revision, probe_version, source_id)`. A revision or probe_version change marks older observations stale; the scheduler reads only fresh ones. | migration + query | After a revision bump, `GET /capabilities` shows `stale=true` until re-probed. | 2 |
| CON-005-S09 | Bound probe cost: run all probes in one warehouse resume, sequentially, with a total budget of 90 s. Bridge issues `SUSPEND` at the end (CON-101). Record `probe_active_seconds`. | `capabilities.py::run_all` | Live: WMH for BRIDGE_FINOPS_WH during the probe hour ≤ 0.03 credits. | 2 |
| CON-005-S10 | Build the fixture matrix: Standard (no ACCESS_HISTORY), Enterprise, trial, Adaptive absent/present, reseller (OU billing denied), grant revoked between probe and extraction (extraction gets DENIED with the source state updated; no crash). | `tests/spec/CON-005/` | 6 fixtures pass; the revoked-between case produces a Data Health reason within 1 cycle. | 5 |
| CON-005-S11 | Implement the API: `POST /v1/connections/{id}/capabilities` (async, idempotent per revision+probe_version); `GET` returns the matrix with remediation text and never includes SQL, hostnames or query text. | routes + OpenAPI | A response scan for `snowflakecomputing.com`, `SELECT`, ARNs finds 0 matches. Foreign id → 404. | 3 |
| CON-005-S12 | Add a daily re-probe (in the 03:00 UTC account cycle) and trigger on auth/grant errors; diff against the previous status and emit the event `capability_changed`. | schedule + event | A grant removal detected in the next daily or error-triggered probe updates Data Health. | 2 |
| CON-005-S13 | Capture live evidence in OPS-103 accounts. | `docs/evidence/CON-005/<commit>/` | Reviewed. | 2 |
Task acceptance:
- [ ] Empty, denied, ambiguous-denied, unsupported, not enabled and suspect-empty are distinct and each has exact remediation.
- [ ] The QUERY_HISTORY canary proves visibility and measures observed latency.
- [ ] Missing optional access leaves other sources active; schema mismatch blocks only that source.
- [ ] Probes cost ≤ 90 s of warehouse time per validation.
- [ ] Stage hosts, edition, Adaptive presence and BCR status are captured per revision.

### CON-006 — Build connection wizard, pause, revoke and recovery UX
Release: R1 · Estimate: 64–96 h · Risk: H · Decisions: D-08, D-09, D-17, D-18 · Closes: G-CON-09, G-CON-01 (consent)
Dependency changes: `+CON-101`, `+CON-102`. The history step captures the requested horizon and consent only; the plan preview is wired by ING-010/ONB-001 (this removes the implicit cycle ING-010→CON-006→history plan).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| CON-006-S01 | Implement the lifecycle machine (§3.4): transition table as data; guards as pure functions; every transition writes `state_transitions`, audit and outbox in one transaction; epoch rules. | `apps/api/connections/lifecycle.py` | Property test: random event sequences never reach an undefined state. Every PAUSED/REVOKED transition increments the epoch. | 6 |
| CON-006-S02 | Wizard step 1 (account): identifier input with live normalization preview; scope (account/org); PrivateLink blocker message; manual vs discovered entry. | `apps/web/connections/new/StepAccount.tsx` | Invalid inputs from CON-001-S02 show field errors. A PrivateLink host shows the R2 message with a support link. | 4 |
| CON-006-S03 | Wizard step 2 (modules): module cards with required database role and exposure text (e.g. QUERIES → "query text is read, sanitized before storage; user names pseudonymized"); required/optional markers. | `StepModules.tsx` | Keyboard-only selection works. Each module shows the role from `snowflake_privilege_map`. | 4 |
| CON-006-S04 | Wizard step 3 (cost and quota): §3.3 estimate from the CON-101 API; quota input (default 50); cadence (hourly default); consent checkbox recorded with actor and time. | `StepCost.tsx`, consent record | Consent is stored with the estimate version. Changing the quota re-renders the script version. | 4 |
| CON-006-S05 | Wizard step 4 (network): show EIPs from `/v1/platform/egress-ips`; opt-in toggle for the network policy block; explanation of user-level vs account-level policy. | `StepNetwork.tsx` | The toggle changes the rendered script (section 5 present/absent). | 2 |
| CON-006-S06 | Wizard step 5 (script review): syntax-highlighted script; per-statement explanation; copy/download (`.sql` with sha256 in header); an explicit "must be run by an ACCOUNTADMIN-capable admin, once" banner; separate org script tab. | `StepScript.tsx` | The downloaded file sha256 equals the API `sha256`. A screen reader announces statement explanations. | 5 |
| CON-006-S07 | Wizard step 6 (validate): async validation with progress (identity → grants → per-source probes); results matrix with per-row remediation (copy exact GRANT); `CON_STALE_SCRIPT` handling (regenerate). | `StepValidate.tsx` | Browser close and reopen resumes the same validation job. A missing grant shows exactly one remediation statement. | 6 |
| CON-006-S08 | Wizard step 7 (history): requested horizon (default 365 d); display "available per source" once ING-010 supplies it (feature-flagged); consent to start → READY→SYNCING. | `StepHistory.tsx` | Starting sync is impossible before READY (button disabled plus a server 409). | 3 |
| CON-006-S09 | Implement pause/resume APIs with `If-Match` revision and `Idempotency-Key`. Pause: epoch++, cancel queued cycles, active cycle aborts at the next fence check. Resume: state → VALIDATING (re-probe) before scheduling. | `apps/api/connections/routes_lifecycle.py` | Staging: pause during an active cycle means no manifest is published after the next fence check (≤ 1 source duration). Resume without re-probe is impossible. | 5 |
| CON-006-S10 | Implement revoke (Bridge-side): typed confirmation; epoch++; IAM deny (CON-001-S09); show and download the customer revoke script. Race test: revoke issued between the launcher's epoch read and RunTask means the task starts, reads the epoch at the first fence and exits with 0 S3 writes. | routes + launcher check | Race test passes 50/50 randomized runs. | 5 |
| CON-006-S11 | Separate disconnect, revoke and delete. "Disconnect" = pause + revoke with data retained; "Delete retained data" = DELETING via OPS-005 with an impact preview (datasets, retention, irreversibility) and typed confirmation; both audited. | `DangerZone.tsx`, routes | Delete cannot be triggered from pause/disconnect screens. The audit shows distinct event types. | 4 |
| CON-006-S12 | Build the connection detail page (`/integrations/connection-detail`): state, epoch-safe actions, capability matrix, estimate vs actual Bridge overhead (CON-101), last validation, script version. | `apps/web/connections/detail/` | Values match the API fixtures. Actions are hidden or disabled for read-only roles. The server returns 403 regardless. | 6 |
| CON-006-S13 | Handle permission loss mid-wizard: a user losing `connection.manage` gets 403 on the next mutation. The draft is kept server-side; no client-only state claims success. | tests | Playwright: revoke the role in a second session, then the next click shows the permission-denied state. | 2 |
| CON-006-S14 | Run the UX state matrix (empty, loading, partial, error, denied, success) at 390 px and desktop; keyboard path; i18n externalized strings (D-18). | Playwright specs, a11y report | All states asserted. axe shows 0 serious violations. No hard-coded user-visible strings (lint). | 6 |
| CON-006-S15 | Capture evidence: an end-to-end wizard run against an OPS-103 account to READY→SYNCING. | `docs/evidence/CON-006/<commit>/` | Reviewed. | 2 |
Task acceptance:
- [ ] READY requires identity + required-source probes + no write-class excess privilege; consent to cost is recorded before SYNCING.
- [ ] A revoked or paused connection publishes no manifest after the next fence check; resume always re-probes.
- [ ] Disconnect, revoke and delete are distinct, audited and clearly worded.
- [ ] Script download is integrity-checked (sha256) and the stale-script path is handled.
- [ ] The customer sees history availability and cost before starting.

## 5. New tasks required

### CON-101 — Customer-side extraction footprint, credit estimator and Bridge-overhead labelling
Release: R1 · Estimate: 24–36 h · Risk: M · Decisions: D-08, D-10 · Closes: G-CON-01, G-CON-11
Plugs in after CON-002; feeds CON-003, CON-005, CON-006, ING-106, ING-010. Why: D-08 has no owning task. The customer pays for extraction, so the product must estimate the cost, cap it, measure it and label it.
Dependency changes: `+CON-002`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| CON-101-S01 | Implement `estimate_monthly_credits(cadence, sources, suspend_mode, backfill_profile)` per §3.3, with parameters in versioned config. | `packages/connections/cost_estimate.py` | Unit tests pin: hourly + explicit suspend = 24 × 60 s × 30 / 3600 = 12.0 credits; auto-suspend with 100–130 s = 20.0–26.0; 15-min QH adds 36.0. | 4 |
| CON-101-S02 | Implement `GET /v1/connections/{id}/estimate` and include the estimate in `/setup`. | route | Response carries `estimate_version`, credits range and assumptions text. | 2 |
| CON-101-S03 | Implement suspend-after-cycle: at cycle end, if the account holds no other active Bridge lease (backfill or probe), run `ALTER WAREHOUSE BRIDGE_FINOPS_WH SUSPEND`. If a concurrent lease exists, skip the suspend. | `services/extractor/warehouse.py` | Live: 24 cycles → WMH for BRIDGE_FINOPS_WH ≤ 24 × 70 s. With concurrent backfill, no suspend error or query abort. | 3 |
| CON-101-S04 | Classify resource-monitor suspension as `CUSTOMER_QUOTA_EXHAUSTED` (exact message/code captured live). Stop retries until month rollover or a quota change (detected by re-probe). Customer notification. | `packages/snowflake_client/errors.py` addition | Live: set quota 1, exhaust it → cycles stop with 0 retries; after raising the quota, the re-probe resumes. | 3 |
| CON-101-S05 | Add the extractor flag `is_bridge_overhead`, computed on plaintext `WAREHOUSE_NAME='BRIDGE_FINOPS_WH' AND USER_NAME='BRIDGE_FINOPS_READER_USER'` before pseudonymization (ING-107). Transport column added to the QH/QAH registry contracts. | registry + extractor hook | Fixture: a customer query with `QUERY_TAG='bridge_finops:x'` has `is_bridge_overhead=false`. Bridge's own query is true. | 4 |
| CON-101-S06 | Measure actual overhead: a daily job computes Bridge credits (WMH where `WAREHOUSE_NAME='BRIDGE_FINOPS_WH'`) month-to-date → Data Health "Bridge overhead" panel. Alarm if > 1.5 × estimate. | `services/ingestion/overhead.py`, API field | The panel value equals a manual WMH sum on a fixture month. | 3 |
| CON-101-S07 | Calibrate live: 48 hourly cycles in OPS-103 accounts with explicit suspend, then 48 without. Measure active seconds per cycle and billed seconds (WMH); update the §3.3 assumptions. | evidence + config update | Estimator error ≤ 20 % against measured. | 4 |
| CON-101-S08 | Define the QUERY_TAG format `bridge_finops:v1:<component>:<cycle_id>` (no tenant or customer identifiers, ≤ 200 chars) and document that it is diagnostic only. | `packages/snowflake_client/tags.py` | Unit test enforces the regex and length. | 1 |
Task acceptance:
- [ ] The wizard shows a credit estimate whose method is unit-tested and calibrated to ≤ 20 % live error.
- [ ] Explicit suspend works without aborting concurrent Bridge queries.
- [ ] Resource-monitor suspension is non-retryable and customer-visible.
- [ ] Bridge overhead is labelled by identity, not by tag, and is never excluded from totals.

### CON-102 — Network reachability: fixed egress IPs, network policy, stage-host allowlisting, PrivateLink blocker
Release: R1 · Estimate: 16–28 h · Risk: M · Decisions: D-09 · Closes: G-CON-03
Plugs in after INF-002 and CON-002; feeds CON-003, CON-005, CON-006.
Dependency changes: `+INF-002`, `+CON-002`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| CON-102-S01 | Ensure all extractor/verifier egress uses 2 NAT EIPs per environment (one per AZ; no IPv6 egress path). Publish them via `GET /v1/platform/egress-ips` from versioned config with `effective_from`/`previous_ips_until`. | INF-002 change request, `apps/api/platform/egress.py` | Egress observed by a test endpoint equals the published IPs from both AZ subnets. | 3 |
| CON-102-S02 | Write the change procedure for new IPs: publish ≥ 90 days ahead; both sets are valid during overlap; customer notification; the wizard shows both. | runbook | Tabletop exercise done. | 1 |
| CON-102-S03 | Classify network-policy login denial (code from CON-002-S05) → `NETWORK_POLICY_BLOCKED` with remediation listing the EIPs. | error map | The live denial maps correctly. | 2 |
| CON-102-S04 | Detect PrivateLink: identifiers containing `privatelink` are rejected. If login is denied and the customer declares a PrivateLink-only account, record `CON_PRIVATELINK_R2` and a support ticket; no retries. | wizard + API | Fixture paths show the explicit R1 blocker message. | 2 |
| CON-102-S05 | Build the stage-host allowlist job: collect `SYSTEM$ALLOWLIST` STAGE hosts from CON-005 facts. For same-region S3 stage buckets, update the INF-002 S3 gateway endpoint policy (Terraform-managed list, reviewed PR); if a domain firewall exists, update its allowlist. | `infra/terraform/modules/vpc_endpoints/snowflake_stage_buckets.auto.tfvars.json`, generator | A new customer account in eu-west-1 gets its stage bucket permitted before its first backfill (CON-002-S11 test passes). | 4 |
| CON-102-S06 | Run live tests: a user-level policy allowing only the EIPs passes; a policy excluding them gives BLOCKED; an account-level restrictive policy plus a user-level allow policy passes (precedence TO VERIFY LIVE). | `tests/live/network/` | 3 scenarios pass with evidence. | 4 |
Task acceptance:
- [ ] Customers can allowlist two published IPs per environment, with ≥ 90-day change notice.
- [ ] Network-policy denial is a distinct, non-retrying state with exact remediation.
- [ ] Large result downloads never fail because of the gateway endpoint policy.
- [ ] PrivateLink-only accounts get an explicit R1 blocker, not a generic error.

### CON-103 — PrivateLink onboarding (R2)
Release: R2 · Estimate: 40–80 h · Risk: H · Decisions: D-09, D-23 · Closes: G-CON-03 (R2 part)
Plugs in after CON-102. Why: Business-Critical customers that block public access need AWS PrivateLink from the Bridge VPC to the customer's Snowflake region (same-region constraint, Snowflake-side authorization of the Bridge AWS account). Both are TO VERIFY with Snowflake support.
Dependency changes: `+CON-102`, `+INF-002`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| CON-103-S01 | Produce a feasibility memo: customer edition requirement, authorization flow for the Bridge AWS account ID, per-region VPC endpoint cost, DNS (private hosted zones per customer account), cross-region impossibility. | memo | Reviewed by Security and Finance. | 6 |
| CON-103-S02 | Build Terraform for per-region interface endpoints and private DNS records per customer account. | module | Staging endpoint resolves privately. | 12 |
| CON-103-S03 | Extend the identifier normalizer to accept `privatelink` hosts when the connection has `network_mode=PRIVATELINK`, and route those accounts to tasks in the matching VPC. | code | Live test with a Snowflake PrivateLink sandbox. | 10 |
| CON-103-S04 | Handle stage access over PrivateLink (internal-stage private endpoints) for result downloads. | config | 150 MB result download over the private path. | 8 |
| CON-103-S05 | Write the wizard branch and runbook. | UI + runbook | End-to-end in staging. | 8 |
Task acceptance:
- [ ] A PrivateLink-only account completes validation and a 150 MB extraction with no public-network path.

## 6. Estimate summary

| Task | Release | Low h | High h |
|---|---|---:|---:|
| CON-001 | R1 | 40 | 56 |
| CON-002 | R1 | 36 | 52 |
| CON-003 | R1 | 44 | 64 |
| CON-004 | R1 | 32 | 46 |
| CON-005 | R1 | 40 | 56 |
| CON-006 | R1 | 64 | 96 |
| CON-101 | R1 | 24 | 36 |
| CON-102 | R1 | 16 | 28 |
| CON-103 | R2 | 40 | 80 |
| **Total R1** | | **296** | **434** |
| **Total R2** | | **40** | **80** |

## 7. Owner questions

1. **Q1 — Tenancy of a Snowflake account.** May the same Snowflake account (same region and locator) be connected by more than one Bridge tenant, for example a consultancy plus the end customer? The default in this backlog is no: unique per environment, with a support override.
2. **Q2 — OPERATE on the dedicated warehouse.** Should Bridge request `OPERATE` on `BRIDGE_FINOPS_WH` only? It enables explicit suspend and costs ≈ 12 vs 20–27 credits per month per account. The alternative is to accept the higher cost with fewer privileges.
3. **Q3 — Broad grant for table-level storage.** If ACCOUNT_USAGE.TABLE_STORAGE_METRICS requires `IMPORTED PRIVILEGES` (the whole ACCOUNT_USAGE schema), is table-level storage an opt-in module in R1, or deferred to R2?
4. **Q4 — Default resource-monitor quota.** Proposed default: 50 credits/month per account, 10 for the org connection. Is the product allowed to recommend a quota change automatically after backfill?
5. **Q5 — Egress IP change notice.** Is the 90-day notice period for egress IP changes acceptable as a contractual commitment?
