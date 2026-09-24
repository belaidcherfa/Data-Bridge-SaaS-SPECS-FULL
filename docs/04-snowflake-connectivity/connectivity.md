# Snowflake WIF, discovery and capability onboarding

Canonical domain contract. Owner: Snowflake. Implementation state: NOT_STARTED.


## Identity and connection contract

A connection is a tenant-owned logical link to one customer account: internal UUID, organization/account UUIDs, validated account identifier, locator, region, cloud, service user, reader role, IAM role ARN, WIF mode, network policy prerequisites, capability version and lifecycle revision. No password, PAT or private-key column exists. Organization discovery is a separate connection capability; it does not grant access to every discovered account.

AWS WIF is documented for the Python connector from 3.17.0; the newer JWT mode requires 4.7.1+ and account outbound federation plus user ISSUER configuration. Pin a proven full adapter matrix; select JWT only when it works through each required adapter, otherwise explicitly select documented GetCallerIdentity attestation. Both remain WIF; no credential fallback. [Official WIF guide](https://docs.snowflake.com/en/user-guide/workload-identity-federation).

Illustrative bootstrap syntax (identifiers generated and safely quoted; do not blindly CREATE OR REPLACE existing users):

```sql
CREATE USER BRIDGE_FINOPS_READER_USER
  TYPE = SERVICE
  WORKLOAD_IDENTITY = (TYPE = AWS ARN = '<registered-account-role-arn>')
  DEFAULT_ROLE = BRIDGE_FINOPS_READER;
```

JWT mode adds the verified issuer and matching connector option. A role/default role is not a grant; bootstrap separately grants the role to the user and only required database roles/warehouse usage. Existing installations use discovery and grant diffs; revocation is an explicit separate script. Reader never inherits operator.

## WIF verification

Launch a short-lived Fargate task with the exact registered role. Connect with `authenticator='WORKLOAD_IDENTITY'`, `workload_identity_provider='AWS'`, explicit account/role/warehouse and UTC session. Compare CURRENT_ACCOUNT/CURRENT_REGION/CURRENT_ORGANIZATION_NAME with expected discovery identity, not only successful SELECT 1. Reject hostnames outside validated Snowflake endpoints and block private/link-local destination resolution to prevent SSRF. Log safe query IDs, never AWS attestation or session tokens.

Probe expired credentials, wrong role ARN, wrong user, revoked grant, blocked network and account mismatch. Authenticate central dbt Core through the same tested matrix before M4. A successful Python connector test alone does not prove dbt adapter compatibility.

## Organization and source capability discovery

Support organization accounts and ORGADMIN-enabled account modes using their documented database roles. In an organization account, grants differ from legacy organization access. Consult the live view-to-role mapping; do not grant ACCOUNTADMIN to the runtime service or assume USAGE_VIEWER covers all views. [Organization Usage privileges](https://docs.snowflake.com/en/sql-reference/organization-usage).

Discover through ORGANIZATION_USAGE.ACCOUNTS where authorized; standalone/manual account enrollment remains valid and records organization visibility as incomplete. Newly discovered accounts are candidates, not automatically authorized connections. Account rename/deletion/transfer uses CTL identity history. A transient discovery failure never deletes accounts.

Each source probe records AVAILABLE, EMPTY, DENIED, NOT_SUPPORTED, NOT_ENABLED, SCHEMA_MISMATCH or TRANSIENT_ERROR, with last checked, safe remediation, required grant set, actual schema hash and freshness metadata. Use explicit bounded minimal projections, not SELECT * or expensive full scans. Empty is not denied. Edition/cloud/region/retention limits are feature capability facts, not fatal global account errors.

Billing access may be unavailable for reseller customers; support an explicitly imported customer billing statement/approved contract rate with provenance and approval. This does not manufacture invoice reconciliation. Organization-level fees remain organization-scoped; discovered unconnected accounts contribute to billing totals but show detail coverage gaps.

## Lifecycle and UX

DRAFT → AWAITING_CUSTOMER_SETUP → VALIDATING → READY → SYNCING → ACTIVE; side states DEGRADED, PAUSED, REVOKED, DELETING. Save configuration separately from successful validation. Each change increments revision and invalidates stale probes. Pause stops new jobs and safely fences old workers; revocation blocks credential use. Removing an integration and deleting retained data are separate clearly explained operations.


## Implementation sequence

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
