# INF — Implementation-readiness review and production backlog

Canonical contract: [AWS platform, networking and deployment foundation](../../17-devops/platform.md). Tasks reviewed: INF-001, INF-002, INF-003, INF-004, INF-005, INF-006, INF-007, INF-008 (plus cross-reading of ADR-004, ADR-005, ADR-010, ADR-011, security.md, connectivity.md, ingestion.md, orchestration.md, operations.md, RUNBOOKS, readiness.md, validation-strategy.md, PRD §5, §6, §9–§16, §129–§138, and the CON-001/002, SEC-002/005, ING-006, ORC-001, OPS-009 task files). Reviewer: domain audit agent, 2026-09-27. Status of all tasks: NOT_STARTED.

## 1. Verdict

INF is not implementable as specified. The platform contract lists the right AWS primitives, but six production-critical parts are missing or one-line:
1. The **Snowflake test estate** that every live gate presupposes: "Dedicated synthetic accounts". No task creates them.
2. The **runtime IAM provisioning** of per-connection (ADR-004) and per-tenant (D-02) roles. CON-001 points to a Terraform module, which cannot run per API request.
3. **Central Snowflake IaC**. INF-008 is three lines. The Snowflake Terraform provider still marks pipes and generic stages Preview, and it does not read WIF bindings back (VERIFIED).
4. **In-VPC CI execution**. GitHub-hosted runners cannot reach private Aurora or pass Snowflake network policies.
5. **Cost guardrails**. There are no budgets or anomaly alarms, and there are several unbounded cost traps.
6. **Ordering**. Terraform CI (INF-007) comes after the infrastructure it should apply.

The chain is also over-serialized: INF-001 waits for FND-006, SEC-002 waits for INF-006 edge/DNS, and CON-001 waits for INF-008. Decide or author first: the AWS org/SCP layout, environment manifest, IAM templates plus permission boundaries, the Snowflake object/role/grant manifest, the test-estate spec and the cost baseline. Two edge decisions are made here and challenge the current contracts: CloudFront **VPC origins** to an internal ALB (verified), and the SPA served from S3+OAC. Private Dagster access uses SSM port-forwarding.

## 2. Findings

### G-INF-01 · No task provisions the Snowflake test estate that live gates require
Severity: BLOCKER · Type: GAP
Evidence: `docs/15-testing/validation-strategy.md` — Snowflake live layer: "Dedicated synthetic accounts; exact connector/adapter/version evidence"; `docs/tasks/OPS/OPS-003.md` failure list — "synthetic account expired"; `connectivity.md` — "Support organization accounts and ORGADMIN-enabled account modes". CON-002 ("Prove WIF connector … live") depends only on CON-001 and FND-002. INF-008 creates only Bridge's central account.
Why it matters: CON-002..005, ING-001 ("every enabled source has a live verified schema"), ING-006, FND-102 and OPS-003 have no customer-side Snowflake to run against. Three properties matter:
- ACCOUNT_USAGE latency is 45 min to 8 h (R03/R04) and ORGANIZATION_USAGE currency up to 72 h (R09). A workload generated at test time is invisible to the test, so the estate must run continuously and ahead of the gates.
- An organization account requires Enterprise edition, and CREATE ORGANIZATION ACCOUNT needs ADMIN_PASSWORD or ADMIN_RSA_PUBLIC_KEY at creation. VERIFIED via search snippet of docs.snowflake.com/en/user-guide/organization-accounts and /sql-reference/sql/create-organization-account, 2026-09-28.
- If synthetic customer accounts lived in Bridge's own Snowflake org, ORGANIZATION_USAGE would mix Bridge's central spend into "customer" fixtures. The test ORGADMIN would also sit in the production org.
Resolution: New task INF-101 builds three things:
- **Org T-A** (separate on-demand org): an organization account (Enterprise), A1 (Enterprise, AWS eu-west-1), A2 (Enterprise, Azure westeurope, for the non-AWS/NAT path; R1 — unconditional since D-20, 2026-09-28), and A3 (Enterprise, idle, "discovered but not connected").
- **Org T-B**: B1 (Standard, standalone enrollment, colliding names).
- A continuous workload generator with deterministic QUERY_TAGs and a RUN_LOG table.

Live oracles are **parity** checks: direct view query equals Bridge journal/RAW for windows older than the D-13 horizon. They are not fixed amounts, because live credits are not deterministic; F-270 stays synthetic. Budget: ≈103 credits/month for the estate, capped at 150 credits by resource monitors (arithmetic in INF-101).
Affects: INF-101 (new), CON-002, CON-003, CON-004, CON-005, ING-001, ING-006, FND-102, OPS-003.

### G-INF-02 · Runtime creation of per-connection and per-tenant IAM roles is undefined
Severity: BLOCKER · Type: GAP
Evidence: ADR-004 — "Provision an AWS role and Snowflake SERVICE reader per connected account … iam:PassRole is restricted … Verify quotas before tenant admission"; `CON-001` outputs — "`infra/terraform/modules/connector_identity`"; D-02 — "one WIF SERVICE user + IAM role **per tenant**"; OPEN_VALIDATIONS V02 — "IAM role quotas".
Why it matters: Running Terraform per customer connection from the API would need a per-connection state and a highly privileged apply role reachable from the product. It would also take minutes of synchronous latency. Nothing defines permission boundaries, naming, PassRole scoping or quota admission. Vendor facts:
- The IAM "Roles per account" default is 1,000. The maximum was raised from 5,000 to 10,000 on 2026-05-05. VERIFIED (aws.amazon.com/about-aws/whats-new/2026/05/aws-iam-increased-quotas, search snippet, 2026-09-28).
- Arithmetic: 100 tenants × 5 accounts = 500 connector roles + 100 serving roles + ~40 platform roles = 640 (64% of default). At 150 tenants × 5, 940 roles (94%) exceeds a safe threshold.
- The Python connector can chain into a tenant role with `workload_identity_impersonation_path` using a fixed `RoleSessionName="identity-federation-session"`. VERIFIED (github.com/snowflakedb/snowflake-connector-python `src/snowflake/connector/wif_util.py`, main, 2026-09-28). So the D-02 serving roles need **no AWS permissions at all**; they are pure identities.
Resolution: New task INF-103 builds a privileged `identity-provisioner` service with its own task role, driven by outbox events:
- **Names:** `bridge-<env>-conn-<connection_uuid>` (53 chars) and `bridge-<env>-srv-<tenant_uuid>`. No IAM path, because Snowflake's assumed-role→role ARN mapping with paths is TO VERIFY LIVE.
- **Boundaries:** a mandatory permissions boundary per kind. The provisioner may create or modify only those name prefixes and only with the boundary condition `iam:PermissionsBoundary`; an SCP backstop enforces the same.
- **PassRole:** only the extraction launcher has `iam:PassRole` on `role/bridge-<env>-conn-*`, with `iam:PassedToService=ecs-tasks.amazonaws.com`.
- **Quota:** a guard refuses tenant admission at 80% of the quota and alarms at 70%.

CON-001 consumes INF-103 and drops `infra/terraform/modules/connector_identity`.
Affects: INF-103 (new), INF-005, CON-001, SEC-005, API-002, ONB-003.

### G-INF-03 · Central Snowflake provisioning (INF-008) is under-specified, and the tool split is undecided
Severity: HIGH · Type: GAP
Evidence: `INF-008` — three micro-tasks; API — "Reviewed idempotent DDL runner authenticates with human SSO for initial trust, then central WIF". No tool, identity model, object manifest, drift detection or resource-monitor policy is named. snowflakedb/snowflake provider facts, VERIFIED (github.com/snowflakedb/terraform-provider-snowflake `docs/`, main; v2.21.0 released 2026-09-10; read 2026-09-28):
- The `WORKLOAD_IDENTITY` authenticator was added in v2.10.0.
- Service-user WIF was added in v2.13.0. `default_workload_identity` "can be only used when `USER_ENABLE_DEFAULT_WORKLOAD_IDENTITY` option is specified … The provider will not get WIF information from Snowflake", and "External changes to `default_workload_identity.aws` … are not currently handled".
- Stable resources include `database`, `schema`, `account_role`, `grant_privileges_to_account_role`, `warehouse`, `resource_monitor`, `network_policy`, `row_access_policy`, `storage_integration_aws` and `stage_external_s3`. **Preview** resources include `pipe`, `stage` and `storage_integration`.
Why it matters: Without a split, teams will manage pipes and policies through Preview resources or ad-hoc SQL. WIF-binding drift, where a user is re-bound to another role ARN, would go undetected by `terraform plan`. Extra grants added out-of-band are also invisible to Terraform's grant resources. Two further hazards: a PROD resource monitor with SUSPEND on the serving warehouse is an outage switch, and an account network policy blocks GitHub-hosted runners (see G-INF-04).
Resolution:
- **Terraform** (Stable resources only, provider pinned 2.21.x, the single allowed experimental flag above) for account objects, roles, grants, warehouses, monitors, network/auth policies, storage integration and external stage, and central service users.
- A **versioned SQL migration runner** (INF-104; schemachange 4.3.3 is on PyPI, 2026-04-20) for tables in SECURITY/CONFIG/RAW/OPS_META, pipes (ING-006) and row-access-policy bodies/attachments (SEC-005).
- **dbt** only for STAGING→SERVING models.
- A nightly grant-audit job that diffs the manifest against actual grants, and a WIF-binding checker.
- PROD monitors are notify-only on the serving warehouse and suspend at 110% only for dbt/engine.
- INF-008 is decomposed into 17 steps. INF-008-S11 runs central WIF (connector plus `dbt debug`) early, which narrows V01 at M1 rather than M2.
Affects: INF-008, INF-104 (new), ING-006, SEC-005, DBT-001.

### G-INF-04 · GitHub-hosted runners cannot reach private data stores or pass Snowflake network policies
Severity: HIGH · Type: GAP
Evidence: `platform.md` — "ECS tasks have no public IP; Aurora/Redis have no public endpoint"; ADR-010 — "GitHub Actions OIDC to AWS is the CI default"; D-09 fixed egress IPs; INF-008 "central WIF"; CTL-002 — "Alembic migration runner is a single deployment task".
Why it matters: Several jobs cannot run from GitHub-hosted runners, whose IPs are large and changing:
- DB role bootstrap and migrations (Aurora is private).
- Snowflake Terraform and migrations, if central accounts have network policies (they should).
- dbt CI against the DEV account.
- Live gates that must appear to Snowflake from the published EIPs.

Opening the network policies to those ranges defeats D-09. Alternatively, teams run applies from laptops.
Resolution: Every job that touches Aurora, Valkey or Snowflake runs on **ephemeral in-VPC runners**: CodeBuild-hosted GitHub Actions runners in each environment's app subnets, egressing through that environment's NAT EIPs (TO VERIFY LIVE runner configuration). Alternatively, the pipeline triggers an ECS one-off task. GitHub-hosted runners keep lint, unit and build jobs. Runner roles are per environment and bound through OIDC environment conditions. Provisioned in INF-002-S09.
Affects: INF-002, INF-004, INF-007, INF-008, FND-101, INF-101.

### G-INF-05 · Terraform CI arrives after the infrastructure it should apply; PR plans can exfiltrate state
Severity: HIGH · Type: CONTRADICTION
Evidence: `platform.md` — "least-privilege apply roles, reviewed plans and drift detection"; `INF-007` (the OIDC pipeline) depends on INF-005 and INF-006, so INF-002..006 are applied before any CI apply role exists. `platform.md` — "State can contain secrets".
Why it matters: Five infra tasks would be applied from laptops with admin credentials. There would be no reviewed plan and no evidence trail, which contradicts D-25's change-evidence control. A PR-triggered `terraform plan` executes provider and data-source code with state-read access, so a malicious internal PR can exfiltrate any secret in state.
Resolution: New task INF-102 (Terraform delivery) lands right after INF-001: per-environment plan/apply roles, a saved-plan apply, an OPA/conftest destroy guard and nightly drift detection. Secrets are kept out of state. Aurora uses `manage_master_user_password = true`, so the secret lives in Secrets Manager. Runtime database and Valkey users use IAM auth. No `random_password` resource is allowed, and a state/plan scan fails on disallowed sensitive attributes. PR plans are allowed only for DEV/STAGING; PROD plans run on `main` under environment protection. INF-002..006 then depend on INF-102.
Affects: INF-102 (new), INF-001..INF-008.

### G-INF-06 · No cost guardrails; quantified cost traps and per-environment baseline
Severity: HIGH · Type: GAP
Evidence: `platform.md` — "Start with explicit small nonzero service minima in staging/prod and a documented budget"; PRD §138 "Your own SaaS needs FinOps". No task creates AWS Budgets, Cost Anomaly Detection, CUR export or cost policy checks. OPS-009 (M9) needs CUR but nothing exports it.
Why it matters: The traps are below. Unit prices are approximate eu-west-1 list prices, TO VERIFY with the AWS Pricing Calculator: NAT $0.048/h + $0.048/GB; interface endpoint $0.011/h per AZ ≈ $8.03/month; public IPv4 $0.005/h; Config $0.003 per configuration item.
1. **Interface endpoints × AZ × environment.** 11 endpoints × 3 AZ × 3 environments = 99 endpoint-AZs ≈ $795/month before any traffic. The recommended plan is 9 endpoints, PROD 2 AZ ($145), STAGING 1 AZ ($72), DEV none (NAT): ≈ $217/month.
2. **AWS Config recording ENIs at D-07 scale.** Each Fargate task creates and deletes an ENI, so 2 configuration items per task. 500 accounts × 24 cycles/day × 2 × 30 = 720,000 items/month ≈ $2,160/month. For the first customer (5 accounts) it is ≈ $22. Mitigation: exclude `AWS::EC2::NetworkInterface`.
3. **NAT processing at benchmark scale.** 500 accounts × 1M rows/day × 0.5–2 KB/row = 0.25–1 TB/day ≈ 7.5–30 TB/month × $0.048 ≈ $360–1,440/month.
4. **IAM Access Analyzer unused-access** at about $0.20 per role per month (TO VERIFY) × 700 roles ≈ $140/month. Use the external-access analyzer only.
5. **VPC Flow Logs and verbose application logs to CloudWatch** at $0.57/GB. Send Flow Logs to S3 instead.
6. **SSE-KMS buckets without Bucket Key**, which causes one KMS request per object operation.
7. **AWS Private CA for D-22 mTLS** (TO VERIFY; general-purpose CA historically $400/month per CA).
8. **Snowflake extraction cadence (D-08)**: hourly on XSMALL with the 60 s minimum resume billing ≈ 24 × (45 s + 60 s) = 42 min/day ≈ 0.7 credits/day ≈ 21 credits/month per customer account, which the customer pays.

**Baseline monthly AWS estimate (list, eu-west-1, before scale; TO VERIFY):**

| Line item | DEV | STAGING | PROD |
|---|---|---|---|
| NAT gateways + EIPs (+ processing) | 1 NAT + 1 EIP ≈ $39 | 2 + 2 ≈ $77 | 2 + 2 ≈ $77 + $10–60 |
| Interface endpoints (9) | $0 (via NAT) | 1 AZ ≈ $72 | 2 AZ ≈ $145 |
| Internal ALB | ≈ $22 | $25–30 | $30–45 |
| Aurora PostgreSQL | Serverless v2 auto-pause $5–60 | 2 × t4g.medium $135–150 | 2 × t4g.large → r7g.large $280–550 |
| ElastiCache Valkey | Serverless $7–15 | 2 × t4g.small $45–55 | 2 × t4g.small–medium $50–105 |
| Fargate always-on (ARM) | office hours $40–120 | ~12 tasks $175–235 | ~16 tasks (≈10 vCPU/20 GB) + runs $320–490 |
| CloudFront + WAF | $12–20 | $15–25 | $20–50 |
| CloudWatch logs/metrics/traces | $15–50 | $40–100 | $80–250 |
| KMS, Secrets, Route 53, ECR, SES | $13–20 | $20–30 | $25–45 |
| GuardDuty, Security Hub, Config (ENI excluded) | $15–40 | $30–80 | $60–200 |
| In-VPC runners, VPC Lattice (D-22) | $5–20 | $30–70 | $30–70 |
| Backups beyond PITR | $0 | $0–10 | $20–60 |
| **Total** | **≈ $175–430** | **≈ $665–935** | **≈ $1,150–2,150** |

Add the org, security, log-archive and shared-services accounts at ≈ $40–120. **The AWS total is ≈ $2,000–3,650/month** before customer scale. Snowflake non-production (central DEV/STAGING plus test estate) ≈ 250–375 credits/month, capped at 500 credits by monitors. At $3.0–3.9/credit (Enterprise, TO VERIFY contract rate) that is ≈ $760–1,460/month, with a hard ceiling of ≈ $1,500–1,950.
Resolution: New task INF-105 (M0): budgets per account, anomaly monitors, cost-allocation tags, a CUR 2.0 Parquet export for OPS-009, conftest cost-trap rules on every Terraform plan, and DEV off-hours scale-to-zero.
Affects: INF-105 (new), INF-001, INF-002, INF-005, OPS-009, D-08 wizard estimate.

### G-INF-07 · The source-first S3 prefix lets a tenant's IAM wildcard write keys that begin with another tenant's path
Severity: HIGH · Type: RISK
Evidence: `ingestion.md` — "`landing/source=<registry_id>/schema_major=<n>/tenant_id=<uuid>/organization_id=<uuid>/account_id=<uuid-or-org>/…`"; `INF-003` oracle — "Tenant A role cannot write/read B prefix"; `ingestion.md` — "verify row tenant/account values agree with the authorized prefix".
Why it matters: A per-connection policy scoped with wildcards before the tenant segment is `…/landing/source=*/schema_major=*/tenant_id=TA/organization_id=OA/account_id=AA/*`. S3 ARN `*` matches `/`, so this policy **allows**:
`landing/source=x/schema_major=1/tenant_id=TB/organization_id=OB/account_id=AB/extraction_date=2026-09-01/batch_id=Z/y/schema_major=1/tenant_id=TA/organization_id=OA/account_id=AA/part-000.parquet`
The first `*` absorbs everything through `batch_id=Z/y`. Any consumer that derives tenant from the first `tenant_id=` segment (Snowpipe METADATA$FILENAME parsing, receipt consumer, dbt staging) attributes the rows to tenant B. That is a cross-tenant injection.
Resolution:
- (1) The IAM resource ARNs enumerate **literal** `source=<id>/schema_major=<n>` pairs generated from the source registry. Size check: each ARN ≈ 226 characters, so ≈ 40 pairs fit under the 10,240-character aggregate inline role policy limit. Above that, split into customer-managed policies.
- (2) Acceptance, receipt and dbt staging parse keys with one anchored regex: `^landing/source=[a-z0-9_]+/schema_major=\d+/tenant_id=<uuid>/organization_id=<uuid>/account_id=<uuid>/extraction_date=\d{4}-\d{2}-\d{2}/batch_id=<uuid>/part-\d{3}\.parquet$`, exactly 8 segments. Non-matching keys are quarantined with alarm `landing_key_violation`.
- (3) Tenant identity in dbt staging comes from the receipt joined on the exact key, and must equal the row's `tenant_id`.

INF-003-S09 contains the attack test.
Affects: INF-003, INF-103, CON-001, ING-005, ING-006, ING-007, DBT-002, SEC-008.

### G-INF-08 · Whoever launches extraction tasks holds a PassRole superpower; RunTask overrides are not IAM-restrictable
Severity: HIGH · Type: RISK
Evidence: ARCHITECTURE_OVERVIEW — "The launcher can pass only explicitly registered roles to approved task definitions. Web requests cannot supply arbitrary IAM ARNs … or Dagster run configuration"; `orchestration.md` — "Use the OSS ECS run launcher"; D-07 — one ECS task per account-cycle launched with that account's role. ECS `RunTask` has `overrides.taskRoleArn`, and `containerOverrides` can override command and environment. VERIFIED (github.com/boto/botocore `data/ecs/2014-11-13/service-2.json`, TaskOverride members, 2026-09-28).
Why it matters: If Dagster's daemon or run launcher starts account-cycle tasks with per-connection `taskRoleArn` overrides, the Dagster roles need `iam:PassRole` on **every** `bridge-<env>-conn-*` role. Anyone who can launch a Dagster run then holds every customer's WIF identity: through the Dagster UI, through code-location code, or by editing run config. IAM cannot constrain override contents beyond the PassRole resource.
Resolution: A dedicated **extraction launcher** (a small service with its own task role) is the only principal with `ecs:RunTask` on `task-definition/bridge-<env>-extractor:*` and `iam:PassRole` on conn roles. Dagster enqueues validated `(connection_id, cycle_id)` jobs and never passes roles. The launcher resolves connection_id → role ARN from PG (server-side) and sets `clientToken` = cycle idempotency key. It denies ECS Exec on extractor tasks. The extractor task definition's default task role has no permissions. Dagster roles are negatively tested for PassRole denial (INF-005-S13).
Affects: INF-005, ORC-001, ORC-003, ING-003, CON-001.

### G-INF-09 · "Controlled egress" is undefined; endpoint-policy traps; D-09 fixed IPs not published
Severity: MEDIUM · Type: GAP
Evidence: `platform.md` — "Controlled NAT egress reaches customer Snowflake endpoints … Use S3 gateway endpoints and appropriate private endpoints"; `INF-002` — "Enumerate Snowflake, OCSP/certificate and AWS endpoints required by the pinned connector".
Why it matters:
- (a) NAT does not restrict destinations.
- (b) Route 53 Resolver DNS Firewall rule groups associate per **VPC**, not per subnet. A strict allowlist would also block customer webhook destinations handled by notification workers.
- (c) A common S3 gateway-endpoint hardening ("only our buckets") breaks ECR image pulls. ECR layers live in the AWS-owned `prod-<region>-starport-layer-bucket`, documented in the ECR VPC-endpoint guide; the exact ARN is TO VERIFY LIVE. The same hardening can break Snowflake connector downloads of large result chunks from Snowflake-owned stage buckets in eu-west-1 (TO VERIFY LIVE).
- (d) Fixed NAT EIPs per D-09 are not produced as a publishable artifact. Customer allowlists break if an EIP is replaced.
Resolution: The gateway endpoint policy allows `s3:GetObject` broadly and restricts `PutObject`/`DeleteObject` to `s3:ResourceAccount` ∈ Bridge accounts. That blocks exfiltration writes and keeps third-party reads working. DNS Firewall runs VPC-wide in BLOCK mode for AWS-managed threat lists, with the custom allowlist in ALERT mode. Destination control for extractors is enforced in application code (validated Snowflake hosts, private/link-local IPs blocked per connectivity.md) plus SG egress 443 only. Network Firewall with SNI allowlists goes to R2 (INF-106). EIPs are allocated with `prevent_destroy`, published to `infra/environments/<env>.egress.json` and SSM, and changed only after ≥30 days of dual publication. The oracle is `SELECT CURRENT_IP_ADDRESS()` from a WIF session ∈ published EIPs.
Affects: INF-002, CON-003, CON-006, ING-003, RPT/GOV notification workers.

### G-INF-10 · Edge: use CloudFront VPC origins to an internal ALB and S3+OAC for the SPA (challenges platform.md and PRD §5)
Severity: MEDIUM · Type: CONTRADICTION
Evidence: `platform.md` — "public ALB/NAT subnets … Restrict ALB origin access using AWS-supported origin controls, secret header plus network controls and rotation"; PRD §5 lists `frontend` as an ECS Fargate service. CloudFront VPC origins support ALBs in private subnets; the VPC needs an internet gateway only "as a marker", and the SG allows the CloudFront managed prefix list. VERIFIED (docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html, search snippet, 2026-09-28).
Why it matters: A public ALB with a secret header is bypassable if the header leaks, needs rotation machinery and pays for public IPv4 per AZ. A Fargate container serving static Vite assets adds a service, patching and cost for no benefit. Several resources are us-east-1-only: the CloudFront certificate and the Cognito custom-domain certificate (both ACM us-east-1), the CLOUDFRONT-scope WAF, and CloudFront metrics/alarms. A naive region-deny SCP breaks all of them.
Resolution: **Challenges platform.md §"public ALB" and PRD §5 "frontend"**: the ALB is internal only, CloudFront uses a VPC origin for `/api/*`, and the SPA is served from S3 with OAC. The secret-header scheme is dropped. The region SCP allowlists us-east-1 for `acm`, `wafv2`, `cloudfront`, `cloudwatch`, `sns` (alarm topic) and global services. Origin TLS between CloudFront and the internal ALB (certificate name matching for VPC origins) is TO VERIFY LIVE.
Affects: INF-002, INF-006, INF-001 (SCP), SEC-002.

### G-INF-11 · Private Dagster access: mechanism not chosen; Dagster OSS has no authentication
Severity: MEDIUM · Type: AMBIGUITY
Evidence: `platform.md` — "Keep Dagster internal behind authenticated operations access"; PRD §6 — "Dagster UI is: private or admin-only"; `INF-006` micro-task 3 — "Provide a private authenticated path to Dagster and Aurora diagnostics".
Why it matters: The OSS webserver has no authN/authZ, so any network path to it grants full control: launching runs with arbitrary config and wiping partitions. The options cost very different amounts. Client VPN is ≈ $73/month per subnet association plus connection-hours, and Verified Access ≈ $0.27/h per app (TO VERIFY). An internal ALB with Cognito still needs a network path into the VPC.
Resolution: **Pick SSM Session Manager port-forwarding through a dedicated `ops-bastion` Fargate task.** ECS Exec is enabled only on that task family. Its task role has SSM messages only, and its SG egress is limited to dagster-web:3000 and aurora:5432. It is started on demand by `bridge-admin ops-tunnel --env <env>` under the Identity Center permission set `BridgeOperator` (MFA at the IdP), with CloudTrail and session start/stop logged, and auto-stops after 8 h. The Dagster webserver runs `--read-only` by default; a write-enabled instance runs only under break-glass. The SG on dagster-web admits only the bastion SG. Idle cost ≈ $0.
Affects: INF-006, ORC-001, OPS-010.

### G-INF-12 · The AWS organization, SCP and identity layout is conditional and undefined
Severity: MEDIUM · Type: GAP
Evidence: `platform.md` — "plus a security/log archive account when organizational ownership allows"; `INF-001` micro-task 1 — "Document human bootstrap permissions, organizational account creation and billing owners".
Why it matters: Without an org baseline there is no guardrail against leaving the org, disabling CloudTrail, creating long-lived IAM users, launching in other regions, or creating runtime roles without boundaries. Without Identity Center there is no auditable, short-lived human path (D-25).
Resolution: **AWS Organizations managed by Terraform, without Control Tower for R1.** Control Tower adds ClickOps, governs every region's Config (cost) and an AFT pipeline; revisit at SOC 2 timing (D-25).
- **Accounts:** management (billing only), security (GuardDuty/Security Hub delegated admin), log-archive (org CloudTrail and Config aggregator), shared-services (ECR, signing KMS key, apex Route 53 zone, release bucket), dev, staging, prod.
- **SCPs:** deny leaving the org; deny stopping or deleting CloudTrail, GuardDuty, Security Hub and the Config recorder; region deny except eu-west-1 plus the us-east-1 exemptions (G-INF-10); deny root actions; deny `iam:CreateUser`/`CreateAccessKey` except break-glass; on the prod OU, deny `ecs:ExecuteCommand` except the ops-bastion family; deny `kms:ScheduleKeyDeletion` except break-glass; deny role create/modify on `bridge-*-conn-*`/`bridge-*-srv-*` without the matching permissions boundary.
- **Identity Center permission sets:** BridgeAdmin (1 h), BridgeOperator (4 h), BridgeDeveloper (8 h, DEV write, STAGING read), BridgeReadOnly and BridgeBilling.
Affects: INF-001, INF-103, INF-006.

### G-INF-13 · Aurora and Valkey budgets and auth modes are not computed; DB bootstrap has no network path
Severity: MEDIUM · Type: GAP
Evidence: `INF-004` — "per-component pool budget <=70% tested connection limit"; "short-lived DB authentication or rotated app secret"; `CTL-002` — "Load maximum replica pools".
Why it matters: Aurora PostgreSQL `max_connections` derives from instance memory. On db.t4g.medium (4 GiB), 4,294,967,296 / 9,531,392 ≈ 450, minus reserved; TO VERIFY with `SHOW max_connections`. The 70% budget is then ≈ 300 connections. An illustrative sum: API (6 replicas × 10) + Dagster web/daemon/code locations (3 × 10) + Dagster run workers (concurrency 12 × 5) + workers (4 × 5) + outbox/provisioner/migrator (≈15) = 185. That fits t4g.medium, but a Dagster concurrency raise to 40 adds 140 and breaks it. A second issue: IAM DB-auth tokens rotate every 15 min and need a connect hook, and dagster-postgres configuration expects a static credential (TO VERIFY). Role bootstrap (`CREATE ROLE`, `REVOKE … FROM PUBLIC`) cannot run from GitHub-hosted runners.
Resolution: INF-004 commits `infra/capacity/pg-pool-budget.yaml`, and a CI checker fails when Σ(max_replicas × (pool_size + max_overflow)) exceeds floor(0.7 × (max_connections − reserved)). API and workers use IAM DB auth through a SQLAlchemy/psycopg connect hook. Dagster uses a Secrets Manager password with the multi-user rotation Lambda. DB bootstrap SQL runs as an idempotent job on the in-VPC runner (G-INF-04).
Affects: INF-004, CTL-002, ORC-001.

### G-INF-14 · Image signing, SBOM and provenance mechanics are unspecified; keyless signing leaks private metadata
Severity: MEDIUM · Type: GAP
Evidence: `readiness.md` — "image/SBOM/signature validation"; `INF-007` — "Build signed/scanned images"; `REL-001` — "SBOM, attestations".
Why it matters: Cosign keyless signing from GitHub OIDC writes the certificate (repository URL, workflow ref, commit) into the **public** Rekor transparency log, which discloses private-repo metadata. ECS has no admission controller, so a signature that is never verified at deploy time is decorative. GitHub artifact attestations for private repositories depend on the plan (TO VERIFY).
Resolution: Cosign uses an AWS KMS asymmetric key (ECC_NIST_P256) in shared-services. The key policy allows Sign only to the build role and GetPublicKey/Verify to the deploy roles. `--tlog-upload=false`. The SBOM is syft SPDX-JSON, attached with `cosign attest`. An in-toto SLSA provenance predicate carries builder, SHA, workflow ref and run ID. The deploy job runs `cosign verify` and `verify-attestation` on every digest before registering task definitions. ECR tags are immutable, and deployments reference digests only.
Affects: INF-007, REL-001.

### G-INF-15 · SES, Cognito custom-domain and DMARC prerequisites have no owner
Severity: MEDIUM · Type: GAP
Evidence: PRD §5 lists "SES"; OPEN_VALIDATIONS V08 — "SES sending approval"; security.md — Cognito hosted login; no INF task creates the SES identity, DKIM/MAIL FROM/DMARC records or the Cognito custom-domain certificate (us-east-1).
Why it matters: SES production access, which lifts sandbox recipients, is a manual AWS review with lead time. Deliverability needs DNS records under the product domain. Without them, M7 report/monitor delivery is blocked late in the programme.
Resolution: INF-006-S11/S12 create the SES domain identity (Easy DKIM, custom MAIL FROM with MX/SPF, DMARC `p=none` → `quarantine` after 30 clean days), a configuration set with bounce/complaint → SNS → SQS, and the production-access request at M1. They also create the `auth.<domain>` ACM certificate in us-east-1 and the alias record for SEC-002.
Affects: INF-006, SEC-002, GOV/RPT delivery tasks.

### G-INF-16 · D-22 transport: mTLS through a private CA is a cost trap; SigV4 via VPC Lattice is the cleaner choice
Severity: MEDIUM · Type: RISK
Evidence: D-22 — "API talks to it over private mTLS/SigV4"; `SEC-005` — "Broker accepts server-signed authorized query plan".
Why it matters: mTLS needs a private CA and certificate rotation in every environment (AWS Private CA pricing TO VERIFY, historically $400/month per general-purpose CA). A per-request KMS `Sign` for plans costs about $0.15 per 10k requests (TO VERIFY); at 100 req/s that is ≈ 26M/month ≈ $390/month.
Resolution: Expose the broker as a **VPC Lattice service with an IAM auth policy** that allows only the API task role (SigV4 by the AWS SDK). This matches the D-22 "SigV4" option; ECS↔Lattice integration is TO VERIFY LIVE, at ≈ $18/month per service plus requests. The fallback is Service Connect plus an SG restricted to the API SG. Plan signing uses an HMAC key derived from a KMS data key cached ≤1 h, not per-request KMS calls. No private CA in R1.
Affects: INF-005, SEC-005, API-002.

### G-INF-17 · PRD §134 says "Snowflake databases" per environment; the architecture says accounts
Severity: LOW · Type: CONTRADICTION
Evidence: PRD §134 — "Separate: AWS accounts / Snowflake databases / …"; ARCHITECTURE_OVERVIEW — "Use a central Snowflake account per environment for strong separation"; `INF-008` data model — "Separate environment accounts".
Why it matters: Shared-account environments share ACCOUNTADMIN, network and authentication policies, and ACCOUNT_USAGE. A DEV human could see STAGING query text, and STAGING live gates would see DEV noise.
Resolution: Separate accounts: BRIDGE_DEV, BRIDGE_STAGING and BRIDGE_PROD (Enterprise, AWS eu-west-1) in Bridge's Snowflake org, with the test estate in separate orgs (G-INF-01). Treat PRD §134 as the minimum and the architecture as the decision. Accounts carry no fixed fee on usage-based contracts (TO VERIFY contract).
Affects: INF-008.

## 3. Contract-first artifacts to author before coding

| Artifact | Exact content required | Produced by |
|---|---|---|
| `infra/environments/<env>.json` + schema | aws_account_id, region, az_ids, vpc_cidr, dns_zone, state_bucket, state_kms_arn, snowflake {org, account_locator, account_url}, egress_ips (generated), ci_oidc_subjects, budget_usd, allowed_instance_classes; placeholders `REQUIRED_INPUT` rejected at apply | INF-001-S01 |
| Org and SCP set | OU tree, account list, SCP JSON files (8 policies in G-INF-12) with test matrix of denied/allowed calls | INF-001-S02..S04 |
| Terraform state layout | Per account `bridge-tfstate-<env>-<account>-euw1`; keys `<stack>/terraform.tfstate`; stacks `00-bootstrap, 10-baseline, 20-network, 30-data, 40-databases, 50-compute, 60-edge, 70-snowflake, 80-observability`; `use_lockfile = true`; cross-stack outputs via SSM `/bridge/<env>/<stack>/<key>` | INF-001-S08/S09 |
| CIDR/subnet/SG matrix | CIDRs per environment, subnets per AZ, route tables, SG rules (source SG → port → dest SG), reachability expectations | INF-002-S01/S06 |
| Egress publication format | `infra/environments/<env>.egress.json` {env, ips[], effective_from, previous_ips[], retire_after} + customer network-policy snippet | INF-002-S03/S13 + CON-102-S01 (customer-facing API; ≥ 90-day notice — RECONCILIATION U-24, C-13) |
| Storage/messaging catalog | Bucket → purpose, KMS key, versioning, Object Lock, lifecycle, writers, readers, notifications; queue → producer, consumer, visibility, maxReceiveCount, retention, DLQ | INF-003-S01 |
| Landing key grammar | Anchored regex (G-INF-07), segment order, UUID format, file naming; shared by IAM generator, receipt consumer and dbt staging | ING-005-S01 (INF-003-S04 consumes it; RECONCILIATION §5.2) |
| IAM policy templates | Connector role (trust + inline S3/KMS), serving role (trust only), boundaries, provisioner, launcher, Dagster roles; each with simulate-principal-policy test cases | INF-103-S01..S05, INF-005-S06/S08 |
| Service catalog `infra/services.yaml` | Per service: image repo, cpu/mem, min/max per env, ports, health check, task/execution role, secrets ARNs, SGs, autoscaling metric, stopTimeout, ephemeral storage, spot eligibility | INF-005-S01 |
| PG pool budget manifest | Service → max replicas × (pool_size + overflow); measured max_connections; budget formula | INF-004-S04 |
| Release manifest schema | release_id, git_sha, images[{name, digest, sbom_digest, provenance_digest}], alembic_head, snowflake_migration_version, dbt_manifest_sha256, tf_plan_sha256 per stack, config versions, approvals | INF-007-S01 |
| Snowflake object/role/grant manifest | Accounts, databases/schemas (managed access, retention), roles, grants, warehouses, monitors, service users ↔ AWS role ARNs, authentication/network policies | INF-008-S01/S07/S08 |
| Test-estate specification | Orgs/accounts/editions/regions, scenarios, QUERY_TAG grammar, RUN_LOG schema, caps, consumers | INF-101-S01 |
| Cost baseline and budgets | Table from G-INF-06 with owner-approved ceilings per account; anomaly thresholds | INF-105-S01 |

## 4. Revised production backlog

### INF-001 — Bootstrap AWS organization, accounts, state and environment guards
Release: R1 · Estimate: 34–48 h · Risk: M · Decisions: D-23, D-25 · Closes: G-INF-12 (and part of G-INF-06)
Dependency changes: `−FND-006` (needs only repo layout), `+FND-001`. Milestone moves to M0 (MILESTONES M0 requires "CI identities and bootstrap plan verified").
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| INF-001-S01 | Write environment manifest schema and files for management, security, log-archive, shared-services, dev, staging, prod with `REQUIRED_INPUT` placeholders; validator fails apply when the target env has placeholders | `infra/environments/*.json`, `infra/environments/schema.json`, `tools/tf/validate_env.py` | Validator rejects a placeholder in `prod.json`; accepts complete `dev.json` | 3 |
| INF-001-S02 | Write the org design record: OUs, accounts, root email aliases, billing owner, break-glass holders, "no Control Tower in R1" rationale | `docs/runbooks/aws-organization.md` | Owner sign-off recorded | 3 |
| INF-001-S03 | Management-account `org` stack: OUs, `aws_organizations_account` (prevent_destroy, close_on_deletion=false), delegated admins (GuardDuty, Security Hub, Config aggregator → security) | `infra/terraform/org/` | Accounts exist; second plan shows no changes | 4 |
| INF-001-S04 | Author SCPs (leave-org deny, security-service tamper deny, region deny with us-east-1 exemptions, root deny, IAM user/key deny, prod ECS Exec deny, KMS deletion deny, runtime-role boundary enforcement); attach per OU | `infra/terraform/org/scp/*.json` | From a DEV test role: `ec2 run-instances --dry-run` in us-west-2 → explicit deny; `iam create-user` → deny; `acm request-certificate` in us-east-1 → allowed | 4 |
| INF-001-S05 | IAM Identity Center permission sets (BridgeAdmin 1 h, BridgeOperator 4 h, BridgeDeveloper 8 h, BridgeReadOnly, BridgeBilling) and group assignments; MFA required at IdP | `infra/terraform/org/identity_center.tf` | Developer group can write DEV and only read STAGING (recorded denied call) | 3 |
| INF-001-S06 | Org CloudTrail (all regions, log file validation, KMS) to log-archive bucket; EventBridge alarms on root login and SCP/trail changes | `infra/terraform/org/cloudtrail.tf` | Test root-login event (DEV) triggers alarm; `validate-logs` succeeds | 3 |
| INF-001-S07 | Security baseline per account: GuardDuty (S3 protection; ECS runtime monitoring on prod after cost check), Security Hub FSBP standard, Config recorder **excluding `AWS::EC2::NetworkInterface`**, IAM Access Analyzer external-access only | `infra/terraform/stacks/10-baseline/` | Config recorder resource list excludes ENI; Security Hub score exported | 4 |
| INF-001-S08 | Per-account state bootstrap (KMS key, versioned SSE-KMS bucket, public block, TLS-only, principal allowlist, noncurrent expiry 90 d); apply with local state then `terraform init -migrate-state` into itself | `infra/terraform/stacks/00-bootstrap/` | State object present in bucket; local state file deleted; re-plan no changes | 3 |
| INF-001-S09 | Backend and guards: `backend.hcl` per env/stack with `use_lockfile = true` (Terraform ≥1.11; S3-native locking GA, VERIFIED github.com/hashicorp/terraform CHANGELOG v1.11, 2026-09-28); `allowed_account_ids`; region precondition; `tools/tf/tf.sh` compares `sts get-caller-identity` to manifest; `-target` refused on prod unless `BREAKGLASS=1` | `infra/terraform/stacks/*/backend.hcl`, `tools/tf/tf.sh` | Wrapper run with staging profile against prod stack exits before `init` | 3 |
| INF-001-S10 | Negative tests: wrong account profile → provider error before any mutation; wrong region → precondition failure; two concurrent applies → second fails acquiring `<key>.tflock` | evidence artifacts | Three failures recorded with exact error text | 2 |
| INF-001-S11 | State recovery drill in DEV: restore prior state object version; verify `serial`/`lineage`; document `force-unlock` only with incident ID | `docs/runbooks/terraform.md#recovery` | Restored state plans with expected drift only | 2 |
| INF-001-S12 | Service quotas: record/request Fargate On-Demand vCPU, EIPs per region (default 5), interface endpoints per VPC, IAM roles per account (monitor), ECS limits | `docs/runbooks/quotas.md` | `service-quotas get-service-quota` outputs stored for each env (V02) | 2 |
| INF-001-S13 | Root and break-glass hardening: hardware MFA on roots, no root access keys, break-glass role with alarm on assume | runbook section, EventBridge rule | Security Hub IAM.4/IAM.6-type controls pass; test assume triggers alarm | 2 |
| INF-001-S14 | Terraform runbook and evidence | `docs/runbooks/terraform.md`, index entry | Reviewed | 2 |
Task acceptance:
- [ ] All seven accounts exist under the org with SCPs attached; denied calls recorded per SCP.
- [ ] Every stack uses S3-native locking and account/region guards; wrong-target applies abort before mutation.
- [ ] Config recorder excludes ENIs; org CloudTrail validated.
- [ ] State recovery from a prior version rehearsed in DEV.

### INF-002 — Create VPC, endpoints, controlled egress and in-VPC runners
Release: R1 · Estimate: 32–44 h · Risk: M · Decisions: D-09, D-23 · Closes: G-INF-04, G-INF-09
Dependency changes: `+INF-102` (applied through the Terraform pipeline).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| INF-002-S01 | CIDR plan and validator: DEV 10.10.0.0/16, STAGING 10.20.0.0/16, PROD 10.30.0.0/16, shared 10.40.0.0/16, 10.50–10.99 reserved for D-23 regions; per AZ public /24 (NAT only), app /20, data /24; AZ-c reserved | `infra/network/cidr-plan.yaml`, `tools/network/validate_cidrs.py` | Validator rejects overlap and 172.16.0.0/12 use | 2 |
| INF-002-S02 | VPC module: IGW, subnets, route tables; data subnets without default route; outputs to SSM | `infra/terraform/modules/network/` | `describe-route-tables` shows no 0.0.0.0/0 on data subnets | 3 |
| INF-002-S03 | NAT per AZ (STAGING/PROD 2, DEV 1) with EIPs `prevent_destroy`, tag `bridge:egress-published=true`; generate `<env>.egress.json` and SSM `/bridge/<env>/egress/ips`; production EIPs are allocated in this module and applied by REL-104; the runbook adopts CON-102-S02's ≥ 90-day dual-publication change rule (customer-facing API is CON-102-S01; RECONCILIATION C-13, U-24) | module + generated file | `terraform plan -destroy` on EIP blocked; egress file matches `describe-addresses` | 3 |
| INF-002-S04 | S3 gateway endpoint policy: Get broadly; Put/Delete only where `s3:ResourceAccount` ∈ Bridge accounts | endpoint policy JSON | ECR pull through endpoint works (starport bucket read); Put to foreign bucket via endpoint → AccessDenied | 3 |
| INF-002-S05 | Interface endpoints (STAGING 1 AZ, PROD 2 AZ, DEV none): ecr.api, ecr.dkr, logs, sts, secretsmanager, kms, sqs, ssmmessages, xray; private DNS; SG 443 from app subnets; resource-account policies where supported | module | Count = 9 × AZs; conftest cost rule (INF-105) passes | 3 |
| INF-002-S06 | SG matrix module (alb-internal, api, broker, dagster-web, dagster-daemon, workers, extractor, launcher, identity-provisioner, ops-bastion, aurora, valkey, endpoints, runners) and generated markdown matrix | `infra/terraform/modules/security_groups/`, `docs/runbooks/sg-matrix.md` | Matrix doc generated from code; no `0.0.0.0/0` ingress anywhere | 3 |
| INF-002-S07 | Route 53 Resolver DNS Firewall: AWS-managed threat lists BLOCK; custom allowlist ALERT (VPC-wide); resolver query logs to S3 | module | Query to a managed-list test domain blocked; unknown domain logged as ALERT | 3 |
| INF-002-S08 | VPC Flow Logs to S3 (Parquet, 10-min aggregation, 30-day lifecycle); no CloudWatch destination | module | Flow log objects appear; conftest forbids CloudWatch destination | 1 |
| INF-002-S09 | In-VPC ephemeral CI runners per env (CodeBuild-hosted GitHub Actions runners in app subnets, per-env role, labels `bridge-<env>-vpc`); TO VERIFY LIVE runner configuration | `infra/terraform/modules/ci_runners/` | Test workflow job on `bridge-staging-vpc` prints the staging EIP from `checkip.amazonaws.com` | 4 |
| INF-002-S10 | VPC Reachability Analyzer paths: IGW→aurora-subnet (not reachable), extractor ENI→aurora:5432 (not reachable), api→aurora:5432 (reachable), data subnet→IGW (not reachable) | analysis IDs in evidence | Four expected results recorded | 3 |
| INF-002-S11 | Egress probe from runner: TLS to test-estate `*.snowflakecomputing.com` host and to endpoints from `SYSTEM$ALLOWLIST()` (incl. OCSP/CRL for pinned connector, TO VERIFY LIVE); after INF-008: `SELECT CURRENT_IP_ADDRESS()` ∈ published EIPs | `tests/aws/network/egress_probe.py` | All hosts handshake; IP oracle holds | 3 |
| INF-002-S12 | Failure drills (STAGING): remove AZ-a NAT route → probe returns `EGRESS_UNAVAILABLE`, no public IP assigned (Security Hub ECS.2 stays passing); bad resolver rule → `DNS_FAILURE` classified; restore | drill record | Classified errors observed; restoration verified | 3 |
| INF-002-S13 | D-09 customer allowlisting doc and snippet (`CREATE NETWORK RULE … MODE = INGRESS TYPE = IPV4 VALUE_LIST = (…)`, `CREATE NETWORK POLICY … ALLOWED_NETWORK_RULE_LIST = (…)`, `ALTER USER … SET NETWORK_POLICY = …`) handed to CON-003 | `docs/runbooks/customer-network-policy.md` | CON owner acknowledges; snippet parameterized by egress file | 2 |
| INF-002-S14 | Runbook and evidence | `docs/runbooks/network.md` | Reviewed | 2 |
Task acceptance:
- [ ] No data-subnet default route; no public DB/cache endpoint; no public IP on any task.
- [ ] Published EIPs equal the IP Snowflake observes; EIPs cannot be destroyed by a routine apply.
- [ ] Gateway endpoint blocks writes to foreign buckets while ECR pulls work.
- [ ] In-VPC runners exist per environment and egress through the published EIPs.

### INF-003 — Provision KMS, buckets, queues and retention boundaries
Release: R1 · Estimate: 28–38 h · Risk: M · Decisions: D-03, D-10, D-11 · Closes: G-INF-07
Dependency changes: `−INF-002` (S3/SQS/KMS need no VPC); `+INF-102`. Step S08 needs INF-002 endpoint IDs (step-level).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| INF-003-S01 | Storage and messaging catalog (landing, reports, audit, recovery, evidence, access-logs buckets; receipts/notify/report/identity queues) with retention and principals | `docs/runbooks/storage-catalog.md` | Every bucket/queue in Terraform maps to one row | 2 |
| INF-003-S02 | KMS keys per purpose (landing, reports, audit, recovery, evidence, aurora, valkey, logs, sns) with key policies (no blanket `kms:*` beyond admin; `kms:ViaService` conditions; Snowflake integration role decrypt on landing); annual rotation | `infra/terraform/modules/kms/` | `get-key-policy` diff matches matrix; rotation enabled | 3 |
| INF-003-S03 | Landing bucket: SSE-KMS with Bucket Key, versioning, public block, TLS-only, deny wrong key, abort MPU 1 d, noncurrent 7 d, current expiry and transitions per registry `retention_class` as generated by ING-005-S04 and applied here (D-26: FINANCIAL = billing/metering/storage sources 400 d; QUERY_GRAIN 90 d; RECONCILIATION C-02), event notification prefix `landing/` suffix `.parquet` → SNS; conditional-write enforcement via `s3:if-none-match` condition (TO VERIFY LIVE) | `infra/terraform/modules/storage/landing.tf` | Lifecycle JSON asserted by test (a FINANCIAL source prefix expires at 400 d, a QUERY_GRAIN prefix at 90 d); overwrite of existing key returns 412 (or the documented fallback) | 4 |
| INF-003-S04 | Connector write-scope template for INF-103: literal `source=<id>/schema_major=<n>` enumeration from the registry, size assertion (≤10,240 aggregate inline), consuming the anchored landing-key grammar authored in ING-005-S01 (RECONCILIATION §5.2) | `infra/iam/templates/connector_s3.json.j2` (reads `data/contracts/landing_key.regex` from ING-005-S01) | Generator test: 40 pairs fit; 45 pairs trigger split | 3 |
| INF-003-S05 | Reports, audit (Object Lock governance, retention per owner policy), recovery (ADR-011, 35 d, separate key, delete denied except lifecycle), evidence (Object Lock governance 400 d, for FND-005), access-logs buckets | modules | Delete of locked audit object by non-break-glass → denied | 3 |
| INF-003-S06 | SNS `landing-events` (CMK with S3 publish permission; policy for `aws:SourceArn` = landing bucket; Snowflake subscription statement placeholder for ING-006); TO VERIFY LIVE Snowpipe SQS subscription with CMK topic, fallback unencrypted topic (payload = keys only) | `infra/terraform/modules/messaging/sns.tf` | Test object upload produces SNS message | 3 |
| INF-003-S07 | SQS pairs: `landing-receipts` (visibility 300 s, maxReceiveCount 5, retention 4 d; DLQ 14 d), `notify-delivery`, `report-jobs`, `identity-requests`; SSE-SQS; queue policies allow only SNS topic ARN or named roles | `infra/terraform/modules/messaging/sqs.tf` | `get-queue-attributes` shows redrive and encryption | 3 |
| INF-003-S08 | Bucket policies deny Bridge principals outside `aws:SourceVpce` (env endpoint) **except** the Snowflake storage-integration role and S3 service principals | bucket policy JSON | Snowflake-role simulated read allowed; Bridge role from outside VPC denied | 2 |
| INF-003-S09 | Attack tests: tenant A connector policy `PutObject` on B's exact prefix → implicitDeny (`simulate-principal-policy`); prefix-escape key from G-INF-07 → documented IAM allow plus regex rejection unit test; HTTP request → deny; unencrypted Put → deny | `tests/aws/storage/test_isolation.py` | All four outcomes asserted | 3 |
| INF-003-S10 | Poison/duplicate: duplicate S3 event and malformed JSON to `landing-receipts` → harness fails 5 times → DLQ; bounded redrive via `StartMessageMoveTask`; no infinite loop | `tests/aws/messaging/test_dlq.py` | DLQ count = 1 poison; duplicates handled idempotently by harness | 3 |
| INF-003-S11 | Alarms: DLQ visible >0 for 5 min; receipts oldest age >900 s; CloudTrail metric filter KMS AccessDenied; landing 4xx spike | `infra/terraform/modules/messaging/alarms.tf` | Alarm test fires on synthetic DLQ message | 2 |
| INF-003-S12 | Runbook and evidence | index entry | Reviewed | 1 |
Task acceptance:
- [ ] Tenant A connector identity cannot write or read tenant B's exact prefix; prefix-escape keys are rejected by the shared anchored regex.
- [ ] Non-TLS and unencrypted access denied; locked audit/evidence objects cannot be deleted.
- [ ] Poison event reaches DLQ after 5 receives; redrive is bounded.
- [ ] Snowflake integration role can read landing despite VPCE restrictions.

### INF-004 — Provision Aurora and Valkey with safe resource budgets
Release: R1 · Estimate: 28–40 h · Risk: M · Decisions: D-25 · Closes: G-INF-13
Dependency changes: none (INF-002, INF-003); `+INF-102`.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| INF-004-S01 | Choose Aurora PostgreSQL major equal to local Compose (TO VERIFY eu-west-1 availability); parameter groups: `rds.force_ssl=1`, `idle_in_transaction_session_timeout=60000`, `log_min_duration_statement=500`, `pg_stat_statements`, `log_lock_waits=on` | `infra/terraform/modules/aurora/params.tf` | `SHOW rds.force_ssl` = 1 | 2 |
| INF-004-S02 | Cluster per env (DEV Serverless v2 min 0 ACU auto-pause; STAGING 2 × t4g.medium; PROD 2 × t4g.large or r7g.large per owner budget) across 2 AZs; KMS; 35-day backups; deletion protection; IAM auth; `manage_master_user_password = true` | `infra/terraform/modules/aurora/` | State scan finds no password; deletion without flag blocked | 3 |
| INF-004-S03 | Idempotent role/database bootstrap job on in-VPC runner: `bridge_control`, `dagster_meta`; `bridge_migrator` (owner, IAM login), `bridge_api`/`bridge_worker`/`bridge_outbox` (NOBYPASSRLS, non-owner), `dagster_rt`, `ops_readonly`; `REVOKE CREATE ON SCHEMA public FROM PUBLIC`; per-role `statement_timeout` (api 15 s, worker 300 s) | `infra/db/bootstrap/*.sql`, workflow job | Second run no-ops; `rolbypassrls` false for runtime roles | 3 |
| INF-004-S04 | Connection budget manifest and CI checker: measured `max_connections`, budget floor(0.7 × (max − reserved)), Σ per service ≤ budget | `infra/capacity/pg-pool-budget.yaml`, `tools/capacity/check_pg_budget.py` | Raising Dagster run concurrency to 40 in manifest fails CI | 3 |
| INF-004-S05 | Auth modes: IAM token connect hook for API/workers (psycopg/SQLAlchemy); Dagster password in Secrets Manager with multi-user rotation Lambda in data subnet | `packages/db_auth/`, rotation module | API connects with token; Dagster connects with secret | 3 |
| INF-004-S06 | Valkey 8 replication group: TLS, at-rest KMS, RBAC users (IAM auth for app users TO VERIFY client), `maxmemory-policy allkeys-lru`, Multi-AZ failover in STAGING/PROD; DEV Serverless | `infra/terraform/modules/valkey/` | Non-TLS connect refused; default user disabled | 3 |
| INF-004-S07 | Rotation test: rotate Dagster secret while daemon runs → reconnect with zero failed runs | drill record | Run history shows no failure attributable to rotation | 3 |
| INF-004-S08 | Aurora failover drill: probe writes idempotent rows every 100 ms through writer endpoint with jittered reconnect; `failover-db-cluster`; measure unavailability; compare committed probe log with table | `tests/aws/db/failover_probe.py` | Zero lost acknowledged writes; unavailability window recorded (target set from measurement) | 3 |
| INF-004-S09 | Valkey drill: `test-failover` and `FLUSHALL` with probe client → reconnect time and cache-miss-only behavior (full product oracle in CTL-006) | drill record | Probe recovers without errors beyond retry budget | 2 |
| INF-004-S10 | Negative tests: `bridge_api` `CREATE TABLE` denied; API task role cannot read migrator/master secrets; Reachability Analyzer: only allowed SGs reach 5432/6379 | evidence | Denials recorded | 3 |
| INF-004-S11 | Alarms: DatabaseConnections >80% budget, CPU >80% 15 min, FreeableMemory, AuroraReplicaLag >1 s, Deadlocks; Valkey Evictions sustained, CurrConnections, EngineCPU | alarms module | Synthetic threshold breach fires alarm | 2 |
| INF-004-S12 | Database runbook (links RB-10, RB-12) and evidence | `docs/runbooks/database.md` | Reviewed | 2 |
Task acceptance:
- [ ] No database password in Terraform state; runtime roles are non-owner NOBYPASSRLS.
- [ ] Configured pools cannot exceed 70% of measured `max_connections` (CI-enforced).
- [ ] Aurora failover loses no acknowledged write; measured window recorded.
- [ ] Secret rotation and Valkey failover complete without failed runs.

### INF-005 — Build ECS base services, launcher isolation and role separation
Release: R1 · Estimate: 36–50 h · Risk: H · Decisions: D-07, D-22, D-02 · Closes: G-INF-08, G-INF-16
Dependency changes: `−INF-004` (cluster/ECR/roles need no DB); deps INF-002, INF-003, INF-102.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| INF-005-S01 | Service catalog schema and file (fields in §3) including launcher, broker, identity-provisioner, receipt-consumer, config-publisher, outbox-dispatcher, ops-bastion | `infra/services.yaml`, `infra/services.schema.json` | Schema validation in CI; Terraform generated with `for_each` | 3 |
| INF-005-S02 | ECR in shared-services: repo per image, immutable tags, scan on push, lifecycle; repository policy for env execution roles (`aws:PrincipalOrgID` + name pattern) | `infra/terraform/stacks/shared/ecr.tf` | Push of existing tag fails; env execution role pull succeeds | 2 |
| INF-005-S03 | Cluster per env: FARGATE and FARGATE_SPOT (Spot only for backfill/run-worker classes), Container Insights standard, ECS Exec off except ops-bastion, Service Connect namespace | `infra/terraform/modules/ecs/cluster.tf` | Cluster settings asserted | 2 |
| INF-005-S04 | Placeholder image (distroless, uid 10001, `/healthz`, flags `--crash`, `--oom`, `--echo-principal`) built and pushed by digest | `tools/placeholder/` | Image digest recorded; runs read-only rootfs | 3 |
| INF-005-S05 | Execution roles per family: pull only own repos, logs only own group, `secretsmanager:GetSecretValue` on listed ARNs, `kms:Decrypt` with `kms:ViaService` | `infra/iam/policies/exec-*.json` | Simulation: API exec role cannot read report-worker secret | 3 |
| INF-005-S06 | Task-role policies per service committed as JSON with `simulate-principal-policy` test cases (api, broker, dagster-web none, dagster-daemon, run-worker-dbt, run-worker-python, launcher, extractor-null, identity-provisioner, receipt-consumer, config-publisher, outbox-dispatcher, report/monitor/insight workers, ops-bastion) | `infra/iam/policies/task-*.json`, `tests/aws/iam/test_task_roles.py` | All allow/deny cases pass | 4 |
| INF-005-S07 | Trust policies: `ecs-tasks.amazonaws.com` with `aws:SourceAccount` and `aws:SourceArn` = `arn:aws:ecs:eu-west-1:<acct>:*` | trust templates | Trust diff check in CI | 1 |
| INF-005-S08 | Extraction launcher IAM: `ecs:RunTask` only on `task-definition/bridge-<env>-extractor:*` with `ecs:cluster` condition; `iam:PassRole` only on `role/bridge-<env>-conn-*` and extractor execution role with `iam:PassedToService`; deny ECS Exec enable (condition key TO VERIFY); `clientToken` = cycle idempotency key; extractor default task role `bridge-<env>-extractor-null` (no permissions); Dagster roles have no conn PassRole | `infra/iam/policies/task-launcher.json` | Launcher starts extractor with conn role override; same call with `bridge-<env>-api` role → AccessDenied | 3 |
| INF-005-S09 | Task definition template: readonlyRootFilesystem, user 10001, initProcessEnabled, tmpfs for `/tmp`, ephemeral storage per service (extractor 50 GiB), stopTimeout 120, health checks; KMS log groups with retention DEV 7 d, STAGING 30 d, PROD 90 d | `infra/terraform/modules/ecs/taskdef.tf` | Rendered definitions pass policy check (no root, no writable rootfs) | 3 |
| INF-005-S10 | Deployment config: circuit breaker + rollback; API/broker min 100 / max 200; Dagster daemon desired 1 with min 0 / max 100 (never two active); autoscaling (API CPU 60%, workers by SQS backlog per task) | services module | Daemon redeploy shows old task stopped before new started | 3 |
| INF-005-S11 | D-22 transport: broker as VPC Lattice service with IAM auth policy allowing only API task role (TO VERIFY LIVE ECS integration); fallback Service Connect + SG; no private CA | `infra/terraform/modules/broker_network/` | Unsigned request → 403; request signed by worker role → 403; by API role → 200 | 3 |
| INF-005-S12 | Failure drills with placeholder in STAGING: crash loop → circuit-breaker rollback; OOM → stop reason `OutOfMemoryError`; pull denied → classified; SIGTERM → graceful exit within stopTimeout | drill record | Four outcomes recorded with ECS events | 3 |
| INF-005-S13 | Negative IAM: API `ecs:RunTask` denied; API `iam:PassRole` denied; launcher RunTask foreign family denied; daemon PassRole on conn role denied; any principal `sts:AssumeRole` on conn role denied | `tests/aws/iam/test_negative.py` | Five denials recorded | 3 |
| INF-005-S14 | Alarms: RunningTaskCount < desired; deployment failure (EventBridge); stopped-reason metric; Fargate vCPU quota usage >70% | alarms module | Synthetic crash loop raises alarm | 2 |
| INF-005-S15 | Runbook and evidence | `docs/runbooks/ecs.md` | Reviewed | 2 |
Task acceptance:
- [ ] Only the launcher can pass connector roles, only to the extractor family, and never with ECS Exec.
- [ ] API role cannot assume or pass any customer identity or launch tasks.
- [ ] An unhealthy deployment rolls back automatically; the daemon is never double-active.
- [ ] The broker accepts calls only from the API identity.

### INF-006 — Configure edge, DNS, TLS, email domain and private operations access
Release: R1 · Estimate: 32–44 h · Risk: M · Decisions: D-18, D-25 · Closes: G-INF-10, G-INF-11, G-INF-15
Dependency changes: `−INF-005` (edge needs only VPC/ALB subnets and log buckets); deps INF-002, INF-003, INF-102; step S13 needs INF-005 (step-level).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| INF-006-S01 | DNS map (app, auth, mail incl. sending subdomain `notify.<domain>`, env subzones) and delegation from apex zone in shared-services | `infra/environments/*.json#dns`, `infra/terraform/modules/dns/` | `dig NS staging.<domain>` returns env zone | 2 |
| INF-006-S02 | ACM: us-east-1 certificates (app, auth) and eu-west-1 certificate (ALB origin name); DNS validation; DaysToExpiry alarms in each region | `infra/terraform/modules/certs/` | Certificates ISSUED; alarm exists in us-east-1 | 2 |
| INF-006-S03 | Internal ALB: HTTPS listener, default fixed 404, `/api/*` → API TG, `routing.http.drop_invalid_header_fields.enabled=true`, `desync_mitigation_mode=strictest`, `xff_header_processing.mode=append`, access logs to S3 | `infra/terraform/modules/edge/alb.tf` | ALB scheme internal; no public IPv4 | 3 |
| INF-006-S04 | SPA origin: S3 bucket with OAC; `/assets/*` immutable 1-year cache; `index.html` no-store; SPA fallback only for the S3 origin | `infra/terraform/modules/edge/spa.tf` | Direct S3 URL → 403; CloudFront serves index | 3 |
| INF-006-S05 | CloudFront: VPC origin → internal ALB for `/api/*` (CachingDisabled, AllViewerExceptHostHeader, `CloudFront-Viewer-Address`), response headers policy (HSTS 2 y, CSP report-only then enforce, nosniff, frame-ancestors none, strict referrer), TLSv1.2_2021, PriceClass_100, origin read timeout 30 s | `infra/terraform/modules/edge/cloudfront.tf` | `/api/healthz` via CloudFront → 200 with `x-cache: Miss` | 4 |
| INF-006-S06 | WAF (us-east-1, CLOUDFRONT scope): AWSManagedRulesCommonRuleSet, KnownBadInputs, AmazonIpReputationList, AnonymousIpList (count), rate rules (auth paths 300/5 min/IP, `/api/*` 2,000/5 min/IP), body ≤64 KB on `/api/*` with oversize MATCH; logging to `aws-waf-logs-*` with `authorization`, `cookie`, `x-csrf-token` redacted | `infra/terraform/modules/edge/waf.tf` | Sample log shows redacted fields | 3 |
| INF-006-S07 | Origin bypass proof: external request to ALB name → unresolvable/private; ALB SG allows only CloudFront origin-facing prefix list (TO VERIFY LIVE list for VPC origins) | evidence | External curl times out/fails; CloudFront path works | 2 |
| INF-006-S08 | Header trust test with echo placeholder: spoofed `X-Forwarded-For` does not change app-derived client IP; app reads only `CloudFront-Viewer-Address` | `tests/aws/edge/test_headers.py` | Spoof has no effect | 2 |
| INF-006-S09 | Cache isolation test: persona A then B request same `/api/...` URL → each receives own principal echo; responses carry `Cache-Control: private, no-store`; `x-cache` Miss | `tests/aws/edge/test_cache.py` | No cross-principal response | 2 |
| INF-006-S10 | Oversize/timeouts: 70 KB body → 403 (WAF); origin delay 35 s → 504 at CloudFront; API hard deadline 15 s documented | tests | Both outcomes recorded | 2 |
| INF-006-S11 | SES (single owner; GOV-102 consumes it, RECONCILIATION U-07): domain identity for `notify.<domain>` with Easy DKIM, custom MAIL FROM (MX + SPF), DMARC `p=none` then `quarantine` after 30 clean days; configuration set → SNS → SQS bounces/complaints; production access request filed | `infra/terraform/modules/ses/` | DKIM verified; request ID recorded | 3 |
| INF-006-S12 | Cognito custom-domain prerequisites for SEC-002: `auth.<domain>` certificate (us-east-1) and alias record | module outputs | Output consumed by SEC-002 | 1 |
| INF-006-S13 | Ops access: `ops-bastion` task (ECS Exec only here, SSM-only role, SG egress to dagster-web:3000 and aurora:5432), `bridge-admin ops-tunnel` wrapper using `AWS-StartPortForwardingSessionToRemoteHost`, BridgeOperator scoped to this family, session logging, auto-stop 8 h; Dagster webserver `--read-only` default | `tools/bridge_admin/ops_tunnel.py`, module | Operator reaches Dagster UI on localhost; developer permission set → AccessDenied | 4 |
| INF-006-S14 | Public exposure scan from GitHub-hosted runner: only CloudFront answers; Dagster and Aurora names unresolvable publicly | evidence | Scan output recorded | 2 |
| INF-006-S15 | Alarms (CloudFront 5xx >1% for 5 min in us-east-1; WAF BlockedRequests spike; cert expiry <30 d; origin latency p95) and `docs/runbooks/access.md` | alarms, runbook | Synthetic 5xx triggers alarm | 3 |
Task acceptance:
- [ ] No public ALB exists; the API is reachable only through CloudFront and WAF.
- [ ] Authenticated API responses are never cached; A→B request reuse proves isolation.
- [ ] Dagster UI and Aurora reachable only through the audited SSM tunnel; Dagster read-only by default.
- [ ] SES identity verified and production access requested; Cognito domain certificate ready.

### INF-007 — Create container build, signing, deployment pipeline and staged rollback
Release: R1 · Estimate: 36–50 h · Risk: H · Decisions: D-25 · Closes: G-INF-14
Dependency changes: `−INF-006` (container deploy does not need edge; STAGING smoke via CloudFront is step-level), `+INF-102`; deps INF-005, INF-102.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| INF-007-S01 | Release manifest JSON Schema (§3) | `infra/release/release-manifest.schema.json` | Sample manifest validates | 2 |
| INF-007-S02 | Build workflow: buildx linux/arm64, one image per service using `uv sync --package <svc> --frozen`, base images by digest; push to shared ECR with OIDC role bound to `ref:refs/heads/main` + environment `build` | `.github/workflows/build.yml`, `docker/*.Dockerfile` | Digests emitted as job outputs; no tag-only reference | 4 |
| INF-007-S03 | SBOM (syft SPDX-JSON) and vulnerability gate (grype): fail on Critical with fix available; expiring allowlist | build job steps, `security/vuln-allowlist.yaml` | Planted vulnerable package fails build | 3 |
| INF-007-S04 | Signing: cosign with `awskms:///alias/bridge-image-signing` (ECC_NIST_P256), `--tlog-upload=false`; attest SBOM and SLSA provenance (builder, SHA, workflow ref, run ID) | build job steps, KMS key in shared-services | `cosign verify --key …` passes; public Rekor has no entry | 3 |
| INF-007-S05 | Reusable deploy workflow on in-VPC runner: verify signature and both attestations for every digest, render task definitions from `services.yaml` with digests, register | `.github/workflows/deploy.yml` | Unsigned digest → deploy fails before registration | 4 |
| INF-007-S06 | Migration gating: Alembic revisions tagged `phase=expand/contract`; automated deploys run expand only; contract requires separate release flag; `migrate` one-off task as `bridge_migrator` with advisory lock; Snowflake migrations (INF-104) run in same stage | pipeline steps, `tools/release/check_migration_phase.py` | Contract migration in auto deploy → blocked | 3 |
| INF-007-S07 | Ordered rollout (broker → api → workers → Dagster code locations → daemon) with `ecs wait services-stable` timeouts and smoke suite (`/healthz`, queue round-trip, Snowflake WIF probe) | `tools/release/rollout.py` | Smoke failure stops rollout and marks release FAILED | 3 |
| INF-007-S08 | Promotion: DEV auto; STAGING auto after DEV smoke; PROD `workflow_dispatch(release_id)` under environment `prod` with reviewer ≠ author; PROD requires STAGING evidence for identical manifest digest | workflow + environment config | PROD dispatch with a manifest never deployed to STAGING → refused | 3 |
| INF-007-S09 | Deploy OIDC roles per env and negative tests (fork, other repo, wrong environment, non-main branch) | `infra/terraform/stacks/10-baseline/ci_deploy_roles.tf` | Four AccessDenied results recorded | 2 |
| INF-007-S10 | Idempotency: redeploy identical manifest → no new task-definition revision (canonical container-definition hash compare) and no service update | `tools/release/diff_taskdefs.py` | Second deploy logs "no-op" | 2 |
| INF-007-S11 | Rollback rehearsal (STAGING): release N with failing smoke → blocked; `rollback --to N-1` redeploys N-1 digests with schema at N (expand-compatible); control-plane marker rows preserved; duration recorded | `tools/release/rollback.py`, drill record | Marker counts unchanged; rollback time recorded | 4 |
| INF-007-S12 | Evidence retention: manifests and deploy logs to `bridge-shared-releases` (Object Lock governance 400 d); GitHub release links | bucket + workflow step | Rollback does not delete prior evidence | 2 |
| INF-007-S13 | Workflow hygiene: SHA-pinned actions, `permissions: {}`, per-env concurrency group (no parallel deploys), Renovate | workflow files | Lint job passes; concurrent deploy queued not parallel | 2 |
| INF-007-S14 | Notifications and alarms: deploy start/success/fail to chat via SNS; ECS deployment-failure EventBridge rule | module | Failed STAGING deploy posts message | 2 |
| INF-007-S15 | Deploy runbook (RB-13 mapping) and evidence | `docs/runbooks/deploy.md` | Reviewed | 2 |
Task acceptance:
- [ ] Only signed, attested, digest-pinned images can be deployed; verification happens before task-definition registration.
- [ ] Foreign repository, fork, wrong-environment and non-main OIDC tokens are denied.
- [ ] Identical release is a no-op; failed STAGING smoke blocks promotion.
- [ ] Rollback to N-1 preserves data and evidence; duration measured.

### INF-008 — Provision central Snowflake accounts, IaC identity, objects and service roles
Release: R1 · Estimate: 40–56 h · Risk: H · Decisions: D-21, D-04, D-05, D-22, D-23 · Closes: G-INF-03, G-INF-17
Dependency changes: `−INF-007` (Snowflake IaC does not need the container pipeline); deps INF-001, INF-102, INF-002 (EIPs + in-VPC runner), INF-003 (storage integration step S12).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| INF-008-S01 | Decision record: tool split (Terraform Stable resources / INF-104 migrations / dbt), object ownership matrix, provider pin 2.21.x, allowed experimental flag `USER_ENABLE_DEFAULT_WORKLOAD_IDENTITY` only | `docs/development/snowflake-iac.md` | Approved by data platform and security | 3 |
| INF-008-S02 | Create or confirm BRIDGE_DEV, BRIDGE_STAGING, BRIDGE_PROD (Enterprise, AWS eu-west-1) via ORGADMIN/GLOBALORGADMIN; record identifiers; capability check (create/attach row access policy on temp table; multi-cluster warehouse allowed) | env manifests, SQL transcript | Capability queries succeed in each account | 3 |
| INF-008-S03 | SAML2 SSO per account; admin PERSON users; ACCOUNTADMIN held by two named humans; authentication policies (PERSON → SAML, SERVICE → WORKLOAD_IDENTITY); disable the bootstrap admin password set at account creation | `infra/snowflake/bootstrap/01_sso.sql` | Password login of admin fails after cut-over | 3 |
| INF-008-S04 | One-time trust SQL (human, audited): role `BRIDGE_IAC_ADMIN` with required account privileges; SERVICE user `SVC_IAC` bound to `arn:aws:iam::<acct>:role/bridge-<env>-snowflake-iac`; user network policy = env EIPs | `infra/snowflake/bootstrap/00_trust.sql` | Query IDs recorded; no key or password on SVC_IAC | 2 |
| INF-008-S05 | Terraform stack `70-snowflake` with provider `authenticator = "WORKLOAD_IDENTITY"`, `workload_identity_provider = "AWS"`, run on in-VPC runner under the IaC role; import pre-existing objects | `infra/terraform/stacks/70-snowflake/` | `plan` authenticates via WIF; no private key variables exist | 3 |
| INF-008-S06 | Account parameters: `TIMEZONE='UTC'`, `REQUIRE_STORAGE_INTEGRATION_FOR_STAGE_CREATION=TRUE`, `REQUIRE_STORAGE_INTEGRATION_FOR_STAGE_OPERATION=TRUE`, `PREVENT_UNLOAD_TO_INLINE_URL=TRUE`, default `STATEMENT_TIMEOUT_IN_SECONDS=3600`; account network policy on STAGING/PROD (env EIPs), none on DEV (humans via SSO) | `account.tf` | `SHOW PARAMETERS IN ACCOUNT` matches manifest | 2 |
| INF-008-S07 | Database `BRIDGE` with schemas SECURITY, CONFIG, RAW, STAGING, INTERMEDIATE, LEDGER, PY, MART, SERVING, OPS_META, INTERNAL_COST; managed access on SECURITY/CONFIG/SERVING; STAGING/INTERMEDIATE transient; retention LEDGER/CONFIG/SECURITY 7 d PROD, 1 d elsewhere (review with D-05 storage churn); DEV adds BRIDGE_CI, BRIDGE_DEV_SANDBOX, BRIDGE_FIXTURES | `databases.tf` | `SHOW SCHEMAS` matches manifest incl. managed-access flags | 3 |
| INF-008-S08 | Roles and grants from manifest: BRIDGE_IAC_ADMIN, BRIDGE_MIGRATOR, BRIDGE_SECURITY_ADMIN, BRIDGE_TRANSFORMER, BRIDGE_INGEST_OBSERVER, BRIDGE_CONFIG_PUBLISHER (INSERT only on CONFIG), BRIDGE_ENGINE, BRIDGE_PROVISIONER, BRIDGE_COST_READER, BRIDGE_OPS_READONLY, database role SERVING_READER_BASE; future grants; revoke PUBLIC; `DEFAULT_SECONDARY_ROLES = ()` for service users | `infra/snowflake/grants.yaml`, `roles.tf` | Manifest-to-SHOW GRANTS diff empty | 4 |
| INF-008-S09 | Warehouses and monitors: WH_ADMIN_XS, WH_DBT_S, WH_ENGINE_XS, WH_INGEST_XS, WH_SERVING_XS (multi-cluster 1–3, `STATEMENT_TIMEOUT_IN_SECONDS=15`, `STATEMENT_QUEUED_TIMEOUT_IN_SECONDS=5`), AUTO_SUSPEND 60; monitors: account-level DEV 150 and STAGING 200 credits/month, suspend at 100%; PROD dbt/engine suspend at 110%; PROD serving notify-only | `warehouses.tf` | Monitor config matches; PROD serving has no suspend trigger | 3 |
| INF-008-S10 | Central service users (SVC_MIGRATOR, SVC_DBT, SVC_INGEST, SVC_CONFIG_PUB, SVC_ENGINE, SVC_PROVISIONER, SVC_COST_READER) via `snowflake_service_user.default_workload_identity.aws.arn` bound to their task-role ARNs (no IAM paths; path handling TO VERIFY LIVE); user network policies = env EIPs | `service_users.tf` | Users exist TYPE=SERVICE with no password/key/PAT | 3 |
| INF-008-S11 | Early V01 proof from STAGING ECS one-off task as `bridge-staging-run-worker-dbt`: connector WIF session (`CURRENT_USER()`, `CURRENT_ROLE()`, `CURRENT_ACCOUNT()`, `CURRENT_REGION()`, `CURRENT_IP_ADDRESS()`) and `dbt debug` with dbt-snowflake 1.12.1 `authenticator: workload_identity`; wrong-role task → authentication failure | `tests/live/central_wif/`, evidence | Both succeed; negative fails; versions recorded | 3 |
| INF-008-S12 | Storage integration (`snowflake_storage_integration_aws`) and external stage (`snowflake_stage_external_s3`) for landing; two-phase apply feeding `STORAGE_AWS_IAM_USER_ARN`/`STORAGE_AWS_EXTERNAL_ID` into AWS role trust and KMS/bucket statements (INF-003) | `ingestion_integration.tf` | `LIST @stage` works; wrong external ID trust test fails | 3 |
| INF-008-S13 | Idempotency: second apply `plan -detailed-exitcode` = 0 | evidence | Exit code 0 | 1 |
| INF-008-S14 | Negative grant suite run as each service user: SVC_DBT cannot CREATE USER/ROLE or read SECURITY.*; SVC_INGEST cannot write LEDGER; SVC_CONFIG_PUB cannot UPDATE/DELETE CONFIG; PUBLIC holds no privilege on BRIDGE; `USE SECONDARY ROLES ALL` has no effect | `tests/live/snowflake_grants/*.sql` | All denials recorded with error codes | 3 |
| INF-008-S15 | Drift: nightly Terraform plan and WIF-binding checker comparing bound ARNs to manifest (provider does not read WIF back; exact SHOW/DESCRIBE command TO VERIFY LIVE); grant audit delegated to INF-104 | `tools/snowflake/check_wif_bindings.py` | Manual re-bind in DEV detected next run | 2 |
| INF-008-S16 | Monitor notification routing (email integration to ops alias) and link to INF-105 channel | `notifications.tf` | Test notification received | 1 |
| INF-008-S17 | Snowflake bootstrap runbook (break-glass, WIF re-bind, recreate objects in a new account for RB-11/ADR-011) | `docs/runbooks/snowflake-bootstrap.md` | Reviewed | 2 |
Task acceptance:
- [ ] Three Enterprise accounts; row-access-policy capability proved in each.
- [ ] All central machine identities authenticate via WIF; no password, key pair or PAT exists on any service user.
- [ ] Second apply is a no-op; out-of-band WIF re-bind and extra grants are detected.
- [ ] PROD serving warehouse cannot be auto-suspended by a monitor; non-prod spend is capped.

## 5. New tasks required

### INF-101 — Snowflake test estate: synthetic customer orgs, accounts and workload generators
Release: R1 · Estimate: 35–54 h (plus calendar lead time for org creation and commercial approval) · Risk: H · Decisions: D-08, D-09, D-13, D-14, D-20 · Closes: G-INF-01
Why: Every Snowflake live gate needs customer-side accounts with realistic, already-matured ACCOUNT_USAGE data. Plugs in: deps INF-001, INF-002 (EIPs), INF-008 (IaC pattern); INF-103 for step S10. Blocks CON-002, CON-003, CON-005, ING-101…104, FND-102, OPS-103. M1 (must precede M2). This is the **only** non-production Snowflake estate: OPS-103's canaries, FIN-108's tenant zero (the T-A organization account) and ING-101…104's live source facts run on it; every "OPS-103 account" reference elsewhere means an INF-101 account (RECONCILIATION U-03, C-24).
Credit arithmetic (XSMALL = 1 credit/h, 60 s minimum per resume; TO VERIFY serverless rates):
- A full account (A1, A2) runs ETL 12/day × (2 min + 1 min suspend tail) = 36 min, BI 6/day × 1.5 min = 9 min and one 11-min hour-spanning query, for 56 min/day ≈ 0.93 credits/day ≈ 28/month. Serverless adds ≈ 4/month, so ≈ 32 credits/month.
- B1 at half profile ≈ 16. A3 ≈ 1. The org account ≈ 1.
- Bridge extraction at a 4-hourly test cadence is 6 × 1.75 min ≈ 0.175 credits/day ≈ 5.3/month × 4 connected accounts ≈ 21.
- **Total ≈ 103 credits/month.** Monitor cap 150 ≈ $450–585/month at $3.0–3.9/credit.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| INF-101-S01 | Write test-estate specification: orgs/accounts/editions/clouds/regions, purpose per account, consuming tasks, caps, owner approvals | `docs/testing/snowflake-test-estate.md` | Owner approval of commercial setup recorded | 3 |
| INF-101-S02 | Provision org T-A (human, ORGADMIN): organization account (Enterprise, GLOBALORGADMIN; tenant zero for FIN-108, U-03), A1 (Enterprise, AWS eu-west-1), A2 (Enterprise, Azure westeurope; R1, unconditional since D-20), A3 (Enterprise, idle, never connected) | `infra/environments/test-estate.json` | Identifiers recorded; `ORGANIZATION_USAGE.ACCOUNTS` lists A1–A3 from the org account | 3 |
| INF-101-S03 | Provision org T-B: B1 Standard, standalone | same file | B1 has no visibility of T-A | 2 |
| INF-101-S04 | Human SSO and authentication policies in all test accounts; disable the creation-time admin password/RSA key after SSO works | `infra/snowflake-test-estate/bootstrap/*.sql` | Password login fails; SSO login works | 3 |
| INF-101-S05 | IaC stack `test-estate`: provider alias per account; WIF service user `SVC_TESTESTATE_IAC` per account bound to STAGING AWS role `bridge-staging-testestate-iac` | `infra/terraform/stacks/test-estate/` | Plan via WIF from in-VPC STAGING runner | 4 |
| INF-101-S06 | Generator core: database SIM, warehouses WH_SIM_ETL/WH_SIM_BI (XSMALL, AUTO_SUSPEND 60), stored procedures, serverless task schedules, deterministic `QUERY_TAG = bridge_sim:<scenario>:<utc-hour>`, `SIM.RUN_LOG(scenario, started_at, ended_at, query_tag, warehouse, expected_rows)`; hourly known-answer canary scenario with known-answer tags consumed by OPS-103 (absorbed from OPS-103-S03; RECONCILIATION U-03) | `infra/snowflake-test-estate/generator/*.sql` | 24 h after deploy, RUN_LOG has expected run count incl. 24 canary runs | 5 |
| INF-101-S07 | Scenarios: ETL/BI with idle gaps; 10-min query starting hh:55 (D-14 proration); failed and cancelled queries; SQL literals/comments/tags with fake PII; colliding names across A1/B1 (`ANALYTICS_WH`, `SALES`, `ANALYST`, `JDOE_SYNTH`) | scenario procedures | Each scenario tag appears in QUERY_HISTORY after latency | 3 |
| INF-101-S08 | Feature scenarios in A1: hourly pipe from internal stage, serverless task, weekly clustering, MV refresh, one Cortex AI function call/day (TO VERIFY region availability), SPCS CPU_X64_XS pool 1 h/day (TO VERIFY rate), weekly cross-region unload for DATA_TRANSFER_HISTORY | feature procedures | Corresponding usage views show rows after latency | 4 |
| INF-101-S09 | Resource monitors per account (A1 40, A2 40, B1 20, A3 5, org 5, BRIDGE_FINOPS_WH 10 each × 4 = 40; total 150, including OPS-103 canaries and FIN-108 tenant zero — no separate canary budget, RECONCILIATION C-24) and daily org-level spend check → alert (absorbs OPS-103-S09); kill-switch script suspending all tasks/warehouses | `infra/snowflake-test-estate/budget/`, `tools/test_estate/kill_switch.py` | Kill switch leaves zero running tasks; cap table matches monitors | 3 |
| INF-101-S10 | Customer-side install using provisional script (until CON-003): BRIDGE_FINOPS_READER role/user with WIF bound to STAGING connector roles (INF-103), dedicated `BRIDGE_FINOPS_WH` per D-08; A1 network policy allowing only STAGING and PROD EIPs | install SQL + evidence | WIF login from STAGING succeeds; from DEV EIP → network policy denial | 3 |
| INF-101-S11 | Maturity-aware parity harness: choose windows older than D-13 horizon; oracles = row count and credit sum equality between direct view query and Bridge journal/RAW; every RUN_LOG tag present in QUERY_HISTORY within measured latency | `tests/live/parity/` | First nightly run PASS or explicit FAIL with diff | 4 |
| INF-101-S12 | Lifecycle monitoring: account/payment state, expiry, monitor suspend events and generator stoppage → alert (OPS-003 "synthetic account expired"; absorbs OPS-103-S10) | alert rules | Simulated generator stop raises alert within 3 h | 2 |
| INF-101-S13 | 7-day measurement: credits/day per account vs estimate; tune schedules; record | evidence | Actual within cap; deviations explained | 2 |
Task acceptance:
- [ ] An organization with an organization account and ≥2 Enterprise accounts, plus a standalone Standard account in a separate org, exist with SSO-only humans.
- [ ] Workload scenarios produce matured ACCOUNT_USAGE/ORGANIZATION_USAGE rows continuously.
- [ ] Live oracles are parity/presence checks; no live amount is used as a financial fixture.
- [ ] Spend capped at 150 credits/month by monitors; kill switch proved.

### INF-102 — Terraform delivery pipeline: OIDC plan/apply roles, plan policy and drift detection
Release: R1 · Estimate: 18–26 h · Risk: M · Decisions: D-25 · Closes: G-INF-05
Why: Infrastructure must be applied by reviewed CI plans from the start, not from laptops. Plugs in: deps INF-001; blocks INF-002..INF-008 (M0).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| INF-102-S01 | GitHub OIDC provider in each account; customize repository `sub` template to include `repository_owner_id`, `repository_id`, `context` (TO VERIFY exact claim-key syntax) | `infra/terraform/stacks/10-baseline/github_oidc.tf`, API call record | Token `sub` observed in a test job contains the IDs | 2 |
| INF-102-S02 | Roles `bridge-<env>-tf-plan` (read-only; explicit deny on data-bucket GetObject, `secretsmanager:GetSecretValue`, non-state `kms:Decrypt`) and `bridge-<env>-tf-apply` (no org, SCP, break-glass or boundary-policy edits); trust `aud = sts.amazonaws.com`; plan: `pull_request` only for DEV/STAGING; apply: `environment:<env>` only | `ci_tf_roles.tf` | Policy simulation of the stated denials passes | 3 |
| INF-102-S03 | `terraform.yml`: on PR fmt, validate, tflint, config scan (trivy config or checkov), plan per changed stack for DEV/STAGING; upload binary plan and JSON; summary comment | `.github/workflows/terraform.yml` | PR shows plan summary per stack | 3 |
| INF-102-S04 | Apply: DEV auto after merge; STAGING after DEV; PROD manual dispatch with environment approval; apply exact saved plan by digest; stale plan forces re-plan | workflow | Apply of a plan older than state serial → refused | 3 |
| INF-102-S05 | Plan policy (conftest/OPA): delete/replace of protected types (`aws_rds_cluster`, `aws_s3_bucket`, `aws_kms_key`, `aws_eip`, `aws_route53_zone`, `snowflake_database`) requires label `allow-destroy` and second approver; INF-105 cost rules plug in here | `policy/terraform/*.rego` | Plan replacing the landing bucket fails without label | 3 |
| INF-102-S06 | State/plan secret scan for disallowed sensitive attributes (`random_password.result`, `aws_rds_cluster.master_password`, `aws_elasticache_user.passwords`) | `tools/tf/scan_sensitive.py` | Planted `random_password` fails CI | 2 |
| INF-102-S07 | Nightly drift: `plan -detailed-exitcode` per env/stack; exit 2 → issue and metric `terraform_drift{env,stack}` | `.github/workflows/terraform-drift.yml` | Manual console change in DEV detected next night | 2 |
| INF-102-S08 | Negative OIDC tests: fork PR (no token), other repo in org, feature branch targeting `prod` apply role | evidence | Three AccessDenied or no-token outcomes | 2 |
| INF-102-S09 | Runbook and evidence | `docs/runbooks/terraform.md#ci` | Reviewed | 2 |
Task acceptance:
- [ ] All applies after INF-001 come from saved, reviewed CI plans with environment-bound OIDC roles.
- [ ] PR plans cannot read data or secrets and never run against PROD.
- [ ] Destroy/replace of protected resources needs an explicit label and second approver.
- [ ] Drift is detected nightly.

### INF-103 — Runtime identity provisioner for per-connection and per-tenant IAM roles
Release: R1 · Estimate: 30–44 h · Risk: H · Decisions: D-02, D-07, D-22 · Closes: G-INF-02
Why: ADR-004 and D-02 require runtime-created IAM identities. Terraform cannot safely do this per request. Plugs in: deps INF-003, INF-005; CTL-004 for outbox consumption (step-level). Blocks CON-001 (replacing its `connector_identity` Terraform module and its S04/S05/S10 provisioner worker, provisioner IAM and quota monitor), SEC-105 (serving roles requested through this provisioner; SEC-005 proves the policy model with scripted fixtures), API-002, INF-101-S10. This is the single runtime IAM provisioner for both role kinds (RECONCILIATION U-02, C-11).
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| INF-103-S01 | Contract: role kinds and names (`bridge-<env>-conn-<uuid32>`, `bridge-<env>-srv-<uuid32>`, 32 lowercase hex, never reused, no IAM path; RECONCILIATION C-11), tags (tenant_id, connection_id, env, managed_by), trust/inline templates, lifecycle REQUESTED → CREATING → ACTIVE → REVOKING → DELETED (+FAILED), idempotency key (env, kind, subject_uuid, revision) | `docs/security/runtime-iam-provisioning.md` | Security review sign-off | 3 |
| INF-103-S02 | Permission boundaries: conn boundary allows only landing S3 PutObject/AbortMultipartUpload on landing prefix, KMS GenerateDataKey via S3, `sts:GetCallerIdentity`; srv boundary allows only `sts:GetCallerIdentity` | `infra/iam/boundaries/*.json` | Simulation: conn role `s3:GetObject` on reports → denied by boundary | 3 |
| INF-103-S03 | Provisioner task-role policy: create/update/delete/tag and inline-policy actions only on the two name prefixes and only with `iam:PermissionsBoundary` equal to the matching boundary; deny boundary removal/replacement and managed-policy attachment; SCP backstop (INF-001-S04) | `infra/iam/policies/task-identity-provisioner.json` | CreateRole without boundary → AccessDenied | 3 |
| INF-103-S04 | Trust templates: conn → `ecs-tasks.amazonaws.com` with `aws:SourceAccount`/`aws:SourceArn`; srv → only the broker task-role ARN for `sts:AssumeRole` (connector impersonation path uses session name `identity-federation-session`) | `infra/iam/templates/*.json.j2` | Worker role AssumeRole on srv role → denied | 2 |
| INF-103-S05 | Inline policy generator (INF-003-S04 template) with size test and split fallback to customer-managed policies | `services/identity_provisioner/policies.py` | 40 pairs inline; 45 pairs split; JSON validated by `access-analyzer validate-policy` | 3 |
| INF-103-S06 | Service: consume `identity.requested` events (queue from INF-003-S07); idempotent GetRole → compare tag/trust/policy hash → create/update; retry IAM propagation (`MalformedPolicyDocument` for not-yet-visible principals) with capped backoff up to 60 s (TO VERIFY); record ARN and state in PG | `services/identity_provisioner/` | Replaying same event yields no second role; state ACTIVE | 4 |
| INF-103-S07 | Quota guard: count roles (paginated ListRoles by prefix) and read quota via Service Quotas (quota code TO VERIFY); refuse new tenant/connection admission at ≥80%, alarm at 70%; metric `iam_roles_used_ratio` (single owner of these thresholds; RECONCILIATION C-11) | module in service | With simulated quota 100 and 81 roles, request → `IDENTITY_QUOTA_EXHAUSTED` | 3 |
| INF-103-S08 | Revocation order: Snowflake WIF user disabled first (CON/SEC hook), then inline policies removed, then role deleted; tombstone kept | service logic + tests | Deleting while Snowflake user active → refused with explicit error | 3 |
| INF-103-S09 | Daily reconcile: prefix roles vs PG registry; orphan → quarantine (deny-all inline policy) and alarm, never auto-delete; missing → recreate through idempotent path | reconcile job | Planted orphan quarantined; deleted role recreated | 3 |
| INF-103-S10 | Negative tests (STAGING): provisioner creates `bridge-staging-api-x` → denied; attaches AdministratorAccess → denied; conn role `sts:AssumeRole` on another conn role → denied; srv role any S3 call → denied | `tests/aws/iam/test_provisioner.py` | Four denials recorded | 3 |
| INF-103-S11 | Observability and audit: metrics `identity_provision_duration_seconds`, `identity_provision_failures_total{error_class}`; audit events with tenant/connection IDs; CloudTrail correlation | telemetry wiring | Dashboard panel shows synthetic runs | 2 |
| INF-103-S12 | Runbook (RB-01 addendum: orphan, quota, propagation) and evidence | `docs/runbooks/identity-provisioner.md` | Reviewed | 2 |
Task acceptance:
- [ ] Runtime roles can only be created with the matching boundary, only under the two prefixes and only by the provisioner.
- [ ] Serving roles carry no AWS permissions; only the broker can assume them.
- [ ] Admission is refused before the IAM quota is exhausted.
- [ ] Replay is idempotent; orphans are quarantined, not silently deleted.

### INF-104 — Snowflake schema-migration runner and grant-drift audit
Release: R1 · Estimate: 16–26 h · Risk: M · Decisions: D-04, D-21 · Closes: G-INF-03
Why: Pipes, tables and policy bodies must not live in Preview Terraform resources or ad-hoc SQL, and out-of-band grants must be visible. Plugs in: deps INF-008; blocks ING-006, SEC-005, CTL-005.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| INF-104-S01 | Tool decision: schemachange 4.3.3 (connector `<5,>=3`) vs in-house runner; verify WIF through `connections.toml` (`authenticator = "WORKLOAD_IDENTITY"`, `workload_identity_provider = "AWS"`) — TO VERIFY LIVE | `docs/development/snowflake-migrations.md` | Decision recorded with live WIF proof | 2 |
| INF-104-S02 | Layout `infra/snowflake/migrations/<schema>/{V,R}__*.sql`, change-history table in `BRIDGE.OPS_META`, naming rules, allowlisted Jinja variables only (env, database) | directory + README | Lint rejects unknown Jinja variable | 2 |
| INF-104-S03 | Runner container and pipeline step (in-VPC runner as SVC_MIGRATOR); PR job renders `--dry-run` SQL artifact for review | `tools/sf_migrate/`, INF-007 stage | Rendered SQL attached to PR | 3 |
| INF-104-S04 | Concurrency and integrity: GitHub concurrency group per env plus lock row with TTL; checksum change on an applied versioned script fails | runner config | Second concurrent run waits; edited V-script fails | 2 |
| INF-104-S05 | Baseline migration: `OPS_META.CHANGE_HISTORY`, `OPS_META.MIGRATION_LOCK`, SECURITY scaffold tables owned by BRIDGE_SECURITY_ADMIN (bodies filled by SEC-005), CONFIG version tables INSERT-only for BRIDGE_CONFIG_PUBLISHER (D-04) | `infra/snowflake/migrations/ops_meta/V1__baseline.sql` etc. | Applied in DEV/STAGING; rerun is no-op | 2 |
| INF-104-S06 | Nightly grant audit: `SHOW GRANTS TO ROLE`/`OF ROLE`/`TO USER` for manifest roles plus runtime registry principals (SEC-005/INF-103) vs manifest; alarms on any PUBLIC grant, ACCOUNTADMIN grant change, users outside naming convention | `tools/snowflake/grant_audit.py` | Report artifact per env | 4 |
| INF-104-S07 | Tests: manual extra grant in DEV detected; revoked grant detected; failing migration leaves history consistent and rerun succeeds after fix | `tests/live/sf_migrate/` | Three outcomes recorded | 3 |
| INF-104-S08 | Runbook and evidence | `docs/runbooks/snowflake-migrations.md` | Reviewed | 2 |
Task acceptance:
- [ ] Every non-Terraform Snowflake object change is a versioned, reviewed, WIF-applied migration.
- [ ] Out-of-band grants, PUBLIC grants and off-convention users are reported within 24 h.

### INF-105 — Cost guardrails, budgets and baseline cost model
Release: R1 · Estimate: 14–22 h · Risk: L · Decisions: D-08, D-17 · Closes: G-INF-06
Why: No task bounds Bridge's own infrastructure spend, and OPS-009 needs a CUR export. Plugs in: deps INF-001; its conftest rules run in INF-102; M0.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| INF-105-S01 | Commit baseline cost model (G-INF-06 table) and a Pricing Calculator export; owner-approved ceilings per account | `docs/runbooks/cost-baseline.md` | Owner approval recorded | 3 |
| INF-105-S02 | Tags: provider `default_tags` (environment, component, cost_owner, managed_by), org tag policy, activate cost-allocation tags | module + org policy | Cost Explorer groups by `component` after 24 h | 2 |
| INF-105-S03 | AWS Budgets per account (actual 80/100%, forecast 100%) → SNS → email and chat | `budgets.tf` | Budget objects exist per account | 2 |
| INF-105-S04 | Cost Anomaly Detection monitors (per linked account and per service; DEV/STAGING $50 and 20%, PROD $100 and 15%) | `anomaly.tf` | Monitors listed | 1 |
| INF-105-S05 | CUR 2.0 Data Export (Parquet, resource IDs) to finance bucket with Athena table for OPS-009 | `cur.tf`, Athena DDL | First export partition queryable | 2 |
| INF-105-S06 | Conftest cost-trap rules: interface endpoints only in STAGING/PROD and count ≤ 9 × AZ; NAT count per env; no CloudWatch Flow Logs; every log group has retention; Config excludes ENI; SSE-KMS buckets have Bucket Key; instance classes within env allowlist; no Container Insights enhanced unless flagged | `policy/terraform/cost.rego` | Plan adding an endpoint to DEV fails | 3 |
| INF-105-S07 | DEV off-hours: scheduled ECS scale-to-zero (20:00–07:00 UTC and weekends), Aurora Serverless auto-pause | scheduler module | Services at 0 outside hours | 2 |
| INF-105-S08 | Link Snowflake non-prod monitors (INF-008, INF-101) to the same channel; monthly non-prod credit budget 500 | notification config | Test notification received | 1 |
| INF-105-S09 | Tests: $1 DEV budget alert fires; conftest rejection; Config ENI exclusion verified | evidence | All three recorded | 2 |
| INF-105-S10 | Record evidence | index entry | Complete | 1 |
Task acceptance:
- [ ] Every account has a budget and anomaly monitor routed to a named owner.
- [ ] Known cost traps are blocked at plan time.
- [ ] CUR 2.0 data is queryable for OPS-009.

### INF-106 — Egress inspection and customer PrivateLink path (R2)
Release: R2 · Estimate: 16–26 h · Risk: M · Decisions: D-09 · Closes: residual of G-INF-09
Why: R1 relies on application-level host validation plus DNS Firewall. Enterprise customers may require SNI-level egress control and PrivateLink (D-09 defers PrivateLink-only accounts to R2). Plugs in after INF-002 and CON-006.
| Step | Micro-task (imperative, precise) | Deliverable (path / artifact / interface) | Done when (verifiable oracle) | h |
|---|---|---|---|---|
| INF-106-S01 | Cost/benefit record: AWS Network Firewall per AZ (TO VERIFY ≈ $0.395/h/AZ + per GB) vs current controls | decision record | Owner decision | 2 |
| INF-106-S02 | Deploy Network Firewall in inspection subnets with stateful SNI allowlist for extractor subnets | module | Non-Snowflake SNI from extractor dropped | 4 |
| INF-106-S03 | Customer PrivateLink: interface endpoint to the customer account's Snowflake endpoint service with private DNS, per customer account | module + runbook | Test Business Critical account reachable only via PrivateLink | 4 |
| INF-106-S04 | Onboarding wizard hooks and blocker messaging (with CON) | CON interface doc | R1 blocker message replaced by guided flow | 3 |
| INF-106-S05 | Tests and runbook | evidence | Recorded | 3 |
Task acceptance:
- [ ] Extractor egress restricted by SNI; PrivateLink customers onboard without public endpoints.

## 6. Estimate summary

| Task | Release | Low h | High h |
|---|---|---:|---:|
| INF-001 | R1 | 34 | 48 |
| INF-002 | R1 | 32 | 44 |
| INF-003 | R1 | 28 | 38 |
| INF-004 | R1 | 28 | 40 |
| INF-005 | R1 | 36 | 50 |
| INF-006 | R1 | 32 | 44 |
| INF-007 | R1 | 36 | 50 |
| INF-008 | R1 | 40 | 56 |
| INF-101 (new) | R1 | 35 | 54 |
| INF-102 (new) | R1 | 18 | 26 |
| INF-103 (new) | R1 | 30 | 44 |
| INF-104 (new) | R1 | 16 | 26 |
| INF-105 (new) | R1 | 14 | 22 |
| INF-106 (new) | R2 | 16 | 26 |
| **Total R1** | | **379** | **542** |
| **Total R2** | | **16** | **26** |

Corrected dependency edges:
- INF-001 ← FND-001 (was FND-006).
- INF-102 ← INF-001.
- INF-002 ← INF-001, INF-102.
- INF-003 ← INF-001, INF-102 (S08 needs INF-002 at step level).
- INF-004 ← INF-002, INF-003.
- INF-005 ← INF-002, INF-003 (was INF-004).
- INF-006 ← INF-002, INF-003 (S13 needs INF-005 at step level).
- INF-007 ← INF-005, INF-102 (was INF-006).
- INF-008 ← INF-001, INF-002, INF-003, INF-102 (was INF-007).
- INF-101 ← INF-001, INF-002, INF-008.
- INF-103 ← INF-003, INF-005.
- INF-104 ← INF-008.
- INF-105 ← INF-001.

Changes in other domains:
- SEC-002 ← SEC-001, UX-001, INF-001 (DEV Cognito). INF-006 is a gate for SEC-002's staging evidence step, not for its start.
- CON-001 ← CTL-001, SEC-004, INF-103 (was INF-008).
- CON-002 gains INF-101 and INF-008.
- ING-006 gains INF-104.
- SEC-005 gains INF-104. SEC-105 (not SEC-005) gains INF-103: the serving IAM role is requested through the single provisioner, while SEC-005 proves the policy model with scripted fixtures (RECONCILIATION U-02).

The INF-internal longest chain drops from 8 to 4 tasks (INF-001 → INF-102 → INF-002 → INF-004/INF-005 → INF-007).

## 7. Owner questions

1. Is there an existing AWS Organization, or is a new one created? Who owns the management account and billing? Is Control Tower required by any customer or auditor? (R1 assumes plain Organizations.)
2. What is the product domain name and registrar, and which team owns DMARC/SES sender reputation?
3. What are the approved monthly ceilings per AWS account and for Snowflake non-production credits? Proposed: DEV $450, STAGING $1,000, PROD $2,500 AWS; 500 Snowflake non-production credits.
4. Snowflake commercial: capacity or on-demand for Bridge's org? Is opening two separate test orgs approved (on-demand, card billing), or will a partner/ISV arrangement provide them? The Azure account (A2) is required since D-20 (2026-09-28); is its cost approved within the D-32 non-production ceiling?
5. Which AWS Support plan applies for PROD (Business or higher recommended for quota and incident escalation)?
6. Who are the named Snowflake PROD break-glass holders (two humans), and who approves break-glass use?
7. Is ECS runtime monitoring in GuardDuty (per-vCPU charge) required for R1 PROD, or deferred until SOC 2 timing (D-25)?
