# Snowflake WIF, discovery and capability onboarding

Canonical domain contract. Owner: Snowflake. Implementation state: NOT_STARTED.


## Identity and connection contract

A connection is a tenant-owned logical link to one customer account: internal UUID, organization/account UUIDs, validated account identifier, locator, region, cloud, service user, reader role, IAM role ARN, WIF mode, network policy prerequisites, capability version and lifecycle revision. No password, PAT or private-key column exists. Organization discovery is a separate connection capability; it does not grant access to every discovered account. (amended 2026-09-28, G-CON-04, C-11, U-02) The IAM role `bridge-<env>-conn-<32 hex of the connection UUID>` (no IAM path; never reused) is created by the single runtime IAM provisioner INF-103 when the connection is created, because its ARN appears in the install script; revocation attaches an explicit inline Deny within 60 s; new connections are refused at 80 % of the IAM role quota (alarm at 70 %). (amended 2026-09-28, D-35) A connection records a `TRIAL_ACCOUNT` capability flag detected at probe time (signals TO VERIFY LIVE): trial accounts are demonstration-only, labelled as demonstration data and excluded from paid entitlements, reconciliation claims, close and chargeback ([ADR-016](../architecture/adr/ADR-016-customer-coverage-residency-reachability.md)).

AWS WIF is documented for the Python connector from 3.17.0; the newer JWT mode requires 4.7.1+ and account outbound federation plus user ISSUER configuration. Pin a proven full adapter matrix; select JWT only when it works through each required adapter, otherwise explicitly select documented GetCallerIdentity attestation. Both remain WIF; no credential fallback. [Official WIF guide](https://docs.snowflake.com/en/user-guide/workload-identity-federation). (amended 2026-09-28, D-21) dbt Core uses dbt-snowflake ≥ 1.12 (WIF support, dbt-adapters PR #1316); extractor connections set `arrow_number_to_decimal=True`.

Illustrative bootstrap syntax (identifiers generated and safely quoted; do not blindly CREATE OR REPLACE existing users):

```sql
CREATE USER BRIDGE_FINOPS_READER_USER
  TYPE = SERVICE
  WORKLOAD_IDENTITY = (TYPE = AWS ARN = '<registered-account-role-arn>')
  DEFAULT_ROLE = BRIDGE_FINOPS_READER
  DEFAULT_WAREHOUSE = BRIDGE_FINOPS_WH      -- amended 2026-09-28 (D-08)
  DEFAULT_SECONDARY_ROLES = ();             -- amended 2026-09-28 (D-02/G-CON-05: new users default to ('ALL'))
```

(amended 2026-09-28, D-08, D-09, G-CON-01, G-CON-05) The complete versioned install script (`acct-v1`, template in [CON backlog](../22-implementation-readiness/backlog/CON.md) §3.1) is run once by a customer administrator able to use ACCOUNTADMIN; Bridge's runtime never uses it. Sections: a precheck that aborts if any `BRIDGE_*` object lacks the `bridge_finops_managed:v1:` comment marker; the reader role (USERADMIN); the dedicated warehouse **`BRIDGE_FINOPS_WH`** (XSMALL, `AUTO_SUSPEND=60`, `AUTO_RESUME`, `INITIALLY_SUSPENDED`, statement and queue timeouts, no multi-cluster clauses); the resource monitor **`BRIDGE_FINOPS_RM`** with the customer's monthly quota (default 50 credits; notify 80 %, suspend 100 %, suspend immediately 110 %); `GRANT USAGE, OPERATE ON WAREHOUSE BRIDGE_FINOPS_WH` (OPERATE only so each account-cycle suspends the warehouse explicitly); module database-role grants; the WIF user converged by `ALTER USER … SET` after `CREATE … IF NOT EXISTS`; an optional user-level network policy allowing Bridge's published egress IPs (SECURITYADMIN, D-09). Organization accounts use a separate `org-v1` script with organization database roles; the revoke script disables first, then revokes and drops only marker-guarded objects. The wizard shows the estimated monthly credits (≈ 12.6–13.2 per account with explicit suspend; §3.3 of the CON backlog) before consent.

JWT mode adds the verified issuer and matching connector option. A role/default role is not a grant; bootstrap separately grants the role to the user and only required database roles/warehouse usage. Existing installations use discovery and grant diffs; revocation is an explicit separate script. Reader never inherits operator.

## WIF verification

Launch a short-lived Fargate task with the exact registered role. Connect with `authenticator='WORKLOAD_IDENTITY'`, `workload_identity_provider='AWS'`, explicit account/role/warehouse and UTC session. Compare CURRENT_ACCOUNT/CURRENT_REGION/CURRENT_ORGANIZATION_NAME with expected discovery identity, not only successful SELECT 1. Reject hostnames outside validated Snowflake endpoints and block private/link-local destination resolution to prevent SSRF. Log safe query IDs, never AWS attestation or session tokens.

Probe expired credentials, wrong role ARN, wrong user, revoked grant, blocked network and account mismatch. (amended 2026-09-28, D-09) Verify that `SELECT CURRENT_IP_ADDRESS()` from the WIF session is one of the published egress IPs; a login rejected by a network policy is classified `NETWORK_POLICY_BLOCKED` with the egress-IP remediation; PrivateLink-only accounts are refused in R1 with `CON_PRIVATELINK_R2`. Authenticate central dbt Core through the same tested matrix before M4. A successful Python connector test alone does not prove dbt adapter compatibility.

## Organization and source capability discovery

Support organization accounts and ORGADMIN-enabled account modes using their documented database roles. In an organization account, grants differ from legacy organization access. Consult the live view-to-role mapping; do not grant ACCOUNTADMIN to the runtime service or assume USAGE_VIEWER covers all views. (amended 2026-09-28, G-CON-02) ACCOUNT_USAGE.QUERY_HISTORY requires **GOVERNANCE_VIEWER** (VERIFIED), which also exposes query text, ACCESS_HISTORY and policy metadata and is disclosed to the customer; QUERY_ATTRIBUTION_HISTORY and QUERY_METERING_HISTORY accept USAGE_VIEWER or GOVERNANCE_VIEWER; database owners need OBJECT_VIEWER; organization billing and inventory use ORGANIZATION_BILLING_VIEWER, ORGANIZATION_USAGE_VIEWER and ORGANIZATION_ACCOUNTS_VIEWER. The module → view → database-role map is versioned as `snowflake_privilege_map.v1.json` ([CON backlog](../22-implementation-readiness/backlog/CON.md) §3.2) and regenerated on the test estate at each behavior-change bundle; TABLE_STORAGE_METRICS stays capability-gated until its role is verified live. [Organization Usage privileges](https://docs.snowflake.com/en/sql-reference/organization-usage).

Discover through ORGANIZATION_USAGE.ACCOUNTS where authorized; standalone/manual account enrollment remains valid and records organization visibility as incomplete. Newly discovered accounts are candidates, not automatically authorized connections. Account rename/deletion/transfer uses CTL identity history. A transient discovery failure never deletes accounts.

Each source probe records AVAILABLE, EMPTY, DENIED, NOT_SUPPORTED, NOT_ENABLED, SCHEMA_MISMATCH or TRANSIENT_ERROR, with last checked, safe remediation, required grant set, actual schema hash and freshness metadata. (amended 2026-09-28, G-CON-08, D-08, D-09) Add AVAILABLE_EMPTY (legitimately empty in a bounded probe), SUSPECT_EMPTY (0 rows where Bridge's own canary query or the previous observation proves rows should exist — some metadata surfaces return 0 rows rather than an error to under-privileged roles), DENIED_OR_UNAVAILABLE (edition unknown), NETWORK_POLICY_BLOCKED and CUSTOMER_QUOTA_EXHAUSTED (resource monitor suspension; non-retryable until quota or month changes). Probes also detect Adaptive warehouses (automatic D-20 flag for FIN-004), the `TRIAL_ACCOUNT` flag and the `SYSTEM$ALLOWLIST` stage hosts used by the S3 gateway endpoint policy. Use explicit bounded minimal projections, not SELECT * or expensive full scans. Empty is not denied. Edition/cloud/region/retention limits are feature capability facts, not fatal global account errors.

Billing access may be unavailable for reseller customers; support an explicitly imported customer billing statement/approved contract rate with provenance and approval. (amended 2026-09-28, G-FIN-13, D-20) Snowflake's `SNOWFLAKE.BILLING` partner views are readable only by resellers and carry the reseller's price, not the customer's; tenants without billing access are priced with versioned, maker-checker customer-approved rate tables (FIN-105, `price_basis=CUSTOMER_APPROVED_RATE`) and reconciled against a reseller invoice reference (FIN-101). This does not manufacture invoice reconciliation. Organization-level fees remain organization-scoped; discovered unconnected accounts contribute to billing totals but show detail coverage gaps.

## Lifecycle and UX

DRAFT → AWAITING_CUSTOMER_SETUP → VALIDATING → READY → SYNCING → ACTIVE; side states DEGRADED, PAUSED, REVOKED, DELETING. (amended 2026-09-28, G-CON-09) Guards and side effects are normative in the transition table of the [CON backlog](../22-implementation-readiness/backlog/CON.md) §3.4: DRAFT requires the connected-accounts entitlement (LCH-101) and IAM quota headroom; READY → SYNCING requires recorded consent to the credit estimate, cadence and history range; SYNCING starts steady-state cycles immediately and the historical backfill in the background (D-29); DEGRADED after 3 consecutive failed cycles of a required source; pause and revoke bump the connection epoch and fence leases; DELETED is a terminal tombstone and the role name is retired forever. Save configuration separately from successful validation. Each change increments revision and invalidates stale probes. Pause stops new jobs and safely fences old workers; revocation blocks credential use. Removing an integration and deleting retained data are separate clearly explained operations.


## Implementation sequence

(amended 2026-09-28) The dependency and gate columns below are the original index. Execution follows the revised graph ([revised-task-graph.json](../22-implementation-readiness/revised-task-graph.json), [revised critical path](../22-implementation-readiness/REVISED_CRITICAL_PATH.md)) and phases P0–P6 of the [release plan](../22-implementation-readiness/RELEASE_PLAN.md); new tasks, revised steps, dependencies and task acceptance are in [backlog/CON.md](../22-implementation-readiness/backlog/CON.md).

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [CON-001](../tasks/CON/CON-001.md) | Register account identities and controlled WIF task roles | CTL-001, INF-008, SEC-004 | M2 |
| [CON-002](../tasks/CON/CON-002.md) | Prove WIF connector and dbt compatibility live | CON-001, FND-002 | M2 |
| [CON-003](../tasks/CON/CON-003.md) | Generate least-privilege installation and revoke scripts | CON-002 | M2 |
| [CON-004](../tasks/CON/CON-004.md) | Discover organizations, accounts and lifecycle changes | CON-003, CTL-001, UX-001 | M2 |
| [CON-005](../tasks/CON/CON-005.md) | Probe capabilities, source schemas and permission gaps | CON-004, SEC-007 | M2 |
| [CON-006](../tasks/CON/CON-006.md) | Build connection wizard, pause, revoke and recovery UX | CON-005, SEC-006, UX-001 | M2 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.
