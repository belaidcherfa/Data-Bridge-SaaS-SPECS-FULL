---
contract: storage-messaging-catalog-doc
version: 1
status: DRAFT
owner_task: INF-003
producing_steps: [INF-003-S01]
generated_from: infra/storage/catalog.yaml
decisions: [D-03, D-04, D-10, D-11, D-26]
last_changed: 2026-09-28
---

# Storage and messaging catalog

Generated from [`infra/storage/catalog.yaml`](../../infra/storage/catalog.yaml) (do not edit by hand). Every bucket, key, topic and queue in Terraform maps to exactly one row. The landing **key grammar** belongs to ING-005-S01 (RECONCILIATION §5.2); INF consumes it for the connector write-scope template (`infra/iam/templates/connector_s3.json.j2`) and the bucket policy.

## KMS keys

| Alias | Purpose | Key users | Via service | Owner |
|---|---|---|---|---|
| `alias/bridge-{env}-landing` | S3 landing journal (extraction Parquet, manifests, replay, probes) | bridge-{env}-conn-* (GenerateDataKey/Decrypt via s3.eu-west-1 only); bridge-{env}-receipt-consumer; Snowflake storage-integration role bridge-{env}-snowflake-landing (Decrypt via S3) | s3.eu-west-1.amazonaws.com | INF-003-S02 |
| `alias/bridge-{env}-reports` | Report artifacts and exports | bridge-{env}-render-worker; bridge-{env}-analysis-worker; bridge-{env}-api (Decrypt for presigned GET) | s3.eu-west-1.amazonaws.com | INF-003-S02 |
| `alias/bridge-{env}-audit` | Audit export bucket | bridge-{env}-audit-exporter | s3.eu-west-1.amazonaws.com | INF-003-S02 |
| `alias/bridge-recovery` | Snowflake recovery exports (ADR-011, OPS-007), key owned by the recovery/log-archive account | Snowflake RECOVERY_EXPORT_INT storage-integration role | s3.eu-west-1.amazonaws.com | INF-003-S02, OPS-007-S03 |
| `alias/bridge-evidence` | Evidence bucket (shared-services) | CI roles bridge-*-deploy, bridge-*-tf-apply, bridge-shared-services-build, validation runners | s3.eu-west-1.amazonaws.com | INF-003-S02 |
| `alias/bridge-{env}-config-archive` | D-04 archival copy of configuration versions | bridge-{env}-config-publisher | s3.eu-west-1.amazonaws.com | INF-003-S02, CTL-005 |
| `alias/bridge-{env}-aurora` | Aurora storage and snapshots | rds.amazonaws.com via service | rds.eu-west-1.amazonaws.com | INF-004-S02 |
| `alias/bridge-{env}-valkey` | ElastiCache at-rest encryption | elasticache via service | elasticache.eu-west-1.amazonaws.com | INF-004-S06 |
| `alias/bridge-{env}-logs` | CloudWatch Logs groups (task logs) | logs.eu-west-1.amazonaws.com service principal with encryption context arn:aws:logs:eu-west-1:<acct>:log-group:/bridge/{env}/* | — | INF-005-S09 |
| `alias/bridge-{env}-sns` | SNS topics (landing-events, domain-events, alarms) | s3.amazonaws.com (landing-events publish); sns.amazonaws.com; SQS subscribers via service | sns.eu-west-1.amazonaws.com | INF-003-S06 |
| `alias/bridge-{env}-secrets` | Secrets Manager secrets (Dagster DB password, destination and webhook secrets, Cognito BFF client secret) | execution roles listed per secret in infra/services.yaml; bridge-{env}-notification-worker (bridge/{env}/destinations/* at runtime) | secretsmanager.eu-west-1.amazonaws.com | INF-004-S05 |
| `alias/bridge-{env}-pseudonym` | D-10 per-tenant pseudonymization key wrapping (envelope encryption, encryption context {tenant_id}; SEC-103-S02) | bridge-{env}-conn-<uuid32> (kms:Decrypt of its own tenant's wrapped HMAC key only: encryption context tenant_id = aws:PrincipalTag/bridge:tenant_id; allowed by the conn boundary); SEC-103 tenant-key lifecycle component (kms:Encrypt at tenant creation; name TO CONFIRM by SEC-103) | — | SEC-103-S02 (policy content), INF-003-S02 (key) |
| `alias/bridge-tfstate-{name}` | Terraform state (per account) | bridge-{name}-tf-apply; bridge-{name}-tf-plan (Decrypt) | s3.eu-west-1.amazonaws.com | INF-001-S08 |
| `alias/bridge-image-signing` | cosign ECC_NIST_P256 image signing (shared-services); Sign only for the build role, GetPublicKey/Verify for deploy roles | bridge-shared-services-build (Sign); bridge-*-deploy (Verify, GetPublicKey) | — | INF-007-S04 |

## Buckets

| Bucket | Account | Purpose | Encryption | Versioning | Object Lock | Lifecycle | Writers | Readers | Notifications | Policy highlights | Owner |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `bridge-{env}-landing-{aws_account_id}-euw1` | {env} | Immutable extraction journal: landing/, manifests/, replay/, probes/ (key grammar owned by ING-005-S01) | alias/bridge-{env}-landing + bucket key | yes | — | `landing/source=<S>/` generated per landing/source=<S>/ prefix from the source registry retention_class (ING-005-S04, D-26): FINANCIAL → Glacier Instant Retrieval at 30 d, expire at 400 d; QUERY_GRAIN → expire at 90 d; no transition may emit ObjectCreated; `manifests/source=<S>/` same class as the source; `replay/` same class as the source; `probes/` expire 30 d; `*` abort incomplete multipart 1 d; noncurrent versions expire 7 d | bridge-{env}-conn-<uuid32> (PutObject/GetObjectAttributes/AbortMultipartUpload on its literal source × schema_major prefixes only, INF-003-S04); bridge-{env}-receipt-consumer (replay/ only) | Snowflake storage-integration role bridge-{env}-snowflake-landing (landing/, replay/); bridge-{env}-receipt-consumer (manifests/, landing/ HEAD) | landing/*.parquet → sns:bridge-{env}-landing-events; manifests/*.json → sns:bridge-{env}-landing-events; replay/*.parquet → sns:bridge-{env}-landing-events | deny aws:SecureTransport=false; deny PutObject without x-amz-server-side-encryption=aws:kms and the landing key; deny PutObject on landing/, manifests/, replay/, probes/ without s3:if-none-match (ING-005-S03; condition key TO VERIFY LIVE, documented fallback: checksum compare on 412); deny DeleteObject/DeleteObjectVersion to arn:aws:iam::<acct>:role/bridge-{env}-conn-*; deny Bridge principals outside aws:SourceVpce of the env gateway endpoint except the Snowflake storage-integration role and S3 service principals (INF-003-S08); deny keys not matching the anchored landing grammar at intake (quarantine prefix quarantine/, alarm landing_key_violation) | INF-003-S03, S08 |
| `bridge-{env}-reports-{aws_account_id}-euw1` | {env} | Report snapshots/renders (reports/) and ad-hoc exports (exports/) | alias/bridge-{env}-reports + bucket key | yes | — | `exports/` expire 7 d (download links are short-lived, RECONCILIATION C-12); `reports/` expire 400 d unless the report policy sets less (RPT); `*` noncurrent 7 d; abort multipart 1 d | bridge-{env}-render-worker; bridge-{env}-analysis-worker | bridge-{env}-api (presigned GET only after re-authorization) | — | deny non-TLS; deny unencrypted Put; deny principals outside VPCE; no public access | INF-003-S05 |
| `bridge-{env}-audit-{aws_account_id}-euw1` | {env} | Append-only audit export (SEC-008) | alias/bridge-{env}-audit + bucket key | yes | GOVERNANCE 400 d | `*` expire after retention (400 d default; owner policy may extend) | bridge-{env}-audit-exporter | BridgeReadOnly (security review); bridge-{env}-ops-api (read index only) | — | deny non-TLS; deny s3:BypassGovernanceRetention except break-glass; deny DeleteObject* | INF-003-S05 |
| `bridge-{env}-config-archive-{aws_account_id}-euw1` | {env} | D-04 archival copy of every published configuration version (recovery source for CONFIG) | alias/bridge-{env}-config-archive + bucket key | yes | GOVERNANCE 400 d | `*` retain 400 d then expire | bridge-{env}-config-publisher | recovery procedure (OPS-007) | — | deny non-TLS; deny DeleteObject* | INF-003-S05, CTL-005 |
| `bridge-{env}-spa-{aws_account_id}-euw1` | {env} | React SPA assets served by CloudFront OAC (D-28) | SSE-S3 | yes | — | `*` noncurrent 30 d | bridge-{env}-deploy | cloudfront.amazonaws.com with aws:SourceArn = the environment distribution (OAC) | — | deny non-TLS; deny every principal except OAC and deploy role | INF-006-S04 |
| `bridge-{env}-access-logs-{aws_account_id}-euw1` | {env} | ALB access logs and S3 server access logs | SSE-S3 (ALB access logs support SSE-S3 only) | no | — | `*` expire 90 d | elasticloadbalancing log-delivery principal; logging.s3.amazonaws.com | BridgeOperator | — | deny non-TLS | INF-003-S05, INF-006-S03 |
| `aws-waf-logs-bridge-{env}-{aws_account_id}` | {env} | WAF logs for the CLOUDFRONT web ACL with authorization, cookie and x-csrf-token redacted (INF-006-S06); bucket region TO VERIFY LIVE | SSE-S3 | no | — | `*` expire 90 d | delivery.logs.amazonaws.com | BridgeOperator | — | deny non-TLS | INF-006-S06 |
| `bridge-log-archive-network-logs-{aws_account_id}-euw1` | log-archive | VPC Flow Logs (Parquet, 10-min aggregation) and Route 53 Resolver query logs of all environments | SSE-S3 | yes | — | `*` expire 30 d (INF-002-S08) | delivery.logs.amazonaws.com (source accounts in the organization); route53resolver query-log delivery | BridgeReadOnly | — | deny non-TLS; aws:SourceOrgID condition on delivery | INF-002-S07/S08 |
| `bridge-log-archive-cloudtrail-{aws_account_id}-euw1` | log-archive | Organization CloudTrail (all regions, log file validation) | alias/bridge-cloudtrail (log-archive account) + bucket key | yes | GOVERNANCE 400 d | `*` Glacier IR at 90 d; expire 400 d | cloudtrail.amazonaws.com (organization trail) | BridgeReadOnly; security tooling | — | deny non-TLS; deny DeleteObject* | INF-001-S06 |
| `bridge-log-archive-tombstones-{aws_account_id}-euw1` | log-archive | OPS-104 append-only deletion tombstone log mirror (outside restore scope) | alias/bridge-tombstones (log-archive account) + bucket key | yes | GOVERNANCE 400 d | `*` retain (no expiry while any backup could resurrect data) | bridge-{env}-outbox-dispatcher (cross-account PutObject tombstones/seq=<20-digit>.json) | restore procedure (OPS-006/OPS-007) | — | deny non-TLS; deny DeleteObject*; PutObject only with if-none-match | OPS-104 (content), INF-003-S05 (bucket) |
| `bridge-recovery-{aws_account_id}-euw1` | recovery (organization.recovery_account_id or log-archive) | ADR-011 analytical recovery exports (OPS-007-S03) | alias/bridge-recovery + bucket key | yes | GOVERNANCE 35 d | `*` expire 35 d (delete denied except lifecycle) | Snowflake RECOVERY_EXPORT_INT storage-integration role (PutObject only) | restore procedure (break-glass) | — | deny non-TLS; deny DeleteObject* except lifecycle; production app roles cannot read | INF-003-S05, OPS-007-S03 |
| `bridge-shared-evidence-{aws_account_id}-euw1` | shared-services | FND-005 evidence artifacts referenced by docs/evidence/index/*.jsonl (artifact_uri + sha256) | alias/bridge-evidence + bucket key | yes | GOVERNANCE 400 d | `*` expire after 400 d retention | CI validation and deploy roles (PutObject with if-none-match) | reviewers (BridgeReadOnly); tools/validation/verify.py in CI | — | deny non-TLS; deny DeleteObject* | INF-003-S05, FND-005-S06 |
| `bridge-shared-releases-{aws_account_id}-euw1` | shared-services | Release manifests, deploy logs, SBOMs (INF-007-S12) | alias/bridge-evidence + bucket key | yes | GOVERNANCE 400 d | `*` expire after 400 d retention | bridge-shared-services-build; bridge-*-deploy | bridge-*-deploy (verification); reviewers | — | deny non-TLS; deny DeleteObject* | INF-007-S12 |
| `bridge-shared-fixtures-{aws_account_id}-euw1` | shared-services | FND-102 recorded Snowflake fixtures (sanitized, ≤ 5 MB each) pulled by `make fixtures-pull` against a committed sha256 manifest | alias/bridge-evidence + bucket key | yes | — | `drift/` expire 30 d | recorder job role on the bridge-staging-vpc runner | CI (all envs) | — | deny non-TLS | FND-102-S03 |
| `bridge-org-cur-{aws_account_id}-euw1` | management | CUR 2.0 Data Export (Parquet, resource IDs) queried by Athena for OPS-009 (INF-105-S05) | SSE-S3 (Data Exports delivery) | yes | — | `*` retain 400 d then expire | bcm-data-exports.amazonaws.com | bridge-prod-platform-cost (cross-account read) | — | deny non-TLS | INF-105-S05 |
| `bridge-tfstate-{name}-{aws_account_id}-euw1` | every account | Terraform state (infra/terraform/state-layout.yaml) | alias/bridge-tfstate-{name} + bucket key | yes | — | `*` noncurrent 90 d; abort multipart 1 d | bridge-{name}-tf-apply | bridge-{name}-tf-plan; bridge-{name}-tf-drift | — | deny non-TLS; principal allowlist | INF-001-S08 |

## SNS topics

| Topic | Type | Encryption | Publishers | Subscribers | Owner |
|---|---|---|---|---|---|
| `bridge-{env}-landing-events` | STANDARD | alias/bridge-{env}-sns (TO VERIFY LIVE Snowpipe SQS subscription with CMK topic; fallback: unencrypted topic, payload = keys only) | s3.amazonaws.com (aws:SourceArn = landing bucket) | Snowflake Snowpipe SQS (auto-ingest, D-03; filter .parquet under landing/ and replay/); sqs:landing-receipts | INF-003-S06 |
| `bridge-{env}-domain-events` | STANDARD | alias/bridge-{env}-sns | bridge-{env}-outbox-dispatcher | sqs:notify-delivery; sqs:monitor-events; sqs:intelligence-events (filter policies on message attribute `type`) | INF-003-S06, CTL-004 |
| `bridge-{env}-domain-events-ordered.fifo` | FIFO | alias/bridge-{env}-sns | bridge-{env}-outbox-dispatcher (MessageGroupId = aggregate, MessageDeduplicationId = event_id) | sqs:identity-requests.fifo; sqs:authz-provisioning.fifo; sqs:config-publication.fifo | INF-003-S06, CTL-004 |
| `bridge-{env}-ses-events` | STANDARD | alias/bridge-{env}-sns | ses.amazonaws.com (configuration set) | sqs:notify-feedback | INF-006-S11 |
| `bridge-{env}-alarms` | STANDARD | alias/bridge-{env}-sns | cloudwatch.amazonaws.com; events.amazonaws.com; budgets.amazonaws.com; costalerts.amazonaws.com | email: notifications.ops_alert_email / cost_alert_email; chat webhook forwarder | INF-005-S14, INF-105-S03 |
| `bridge-{env}-alarms-use1` | STANDARD | aws/sns (us-east-1) | cloudwatch.amazonaws.com (CloudFront, ACM, WAF alarms in us-east-1); events.amazonaws.com (root-login rule) | email: notifications.ops_alert_email / security_alert_email | INF-006-S15, INF-001-S06 |
| `bridge-{env}-security-alerts` | STANDARD | alias/bridge-{env}-sns | events.amazonaws.com (break-glass assume, SCP/trail changes, GuardDuty HIGH findings) | email: notifications.security_alert_email | INF-001-S06, S13 |

## SQS queues (`bridge-{env}-<name>`)

| Queue | Producer | Consumer | Visibility | maxReceiveCount | Retention | DLQ (retention) | Notes |
|---|---|---|---|---|---|---|---|
| `landing-receipts` | sns:bridge-{env}-landing-events | receipt-consumer | 300 s | 5 | 4 d | `landing-receipts-dlq` (14 d) | S3 events for landing/, manifests/, replay/; duplicate and out-of-order safe (receipt idempotency, ING-007). Poison → DLQ after 5 receives; bounded redrive via StartMessageMoveTask. |
| `identity-requests.fifo` | sns:bridge-{env}-domain-events-ordered.fifo | identity-provisioner | 120 s | 10 | 4 d | `identity-requests-dlq.fifo` (14 d) | MessageGroupId = subject UUID (connection or tenant); IAM propagation retries inside the handler with capped backoff ≤ 60 s (INF-103-S06). |
| `authz-provisioning.fifo` | sns:bridge-{env}-domain-events-ordered.fifo | authz-provisioner | 300 s | 5 | 4 d | `authz-provisioning-dlq.fifo` (14 d) | MessageGroupId = tenant_id (SEC-105 FIFO per tenant). |
| `config-publication.fifo` | sns:bridge-{env}-domain-events-ordered.fifo | config-publisher | 120 s | 5 | 4 d | `config-publication-dlq.fifo` (14 d) | MessageGroupId = tenant_id; duplicates are no-ops keyed by config_version (D-04). |
| `notify-delivery` | sns:bridge-{env}-domain-events | notification-worker | 120 s | 8 | 4 d | `notify-delivery-dlq` (14 d) | Consumer deduplicates on (consumer, event_id) in platform.consumed_event; delivery retry schedule is GOV-007's. |
| `notify-feedback` | sns:bridge-{env}-ses-events | notification-worker | 60 s | 5 | 4 d | `notify-feedback-dlq` (14 d) | SES bounces and complaints → suppression list. |
| `monitor-events` | sns:bridge-{env}-domain-events | monitor-worker | 300 s | 5 | 4 d | `monitor-events-dlq` (14 d) | publication.advanced and budget/monitor configuration changes. |
| `intelligence-events` | sns:bridge-{env}-domain-events | intelligence-worker | 300 s | 5 | 4 d | `intelligence-events-dlq` (14 d) | publication.advanced (intelligence) and action lifecycle events. |

All queues use SSE-SQS; queue policies admit only the named topic (`aws:SourceArn`) or producer role, and only the consumer role may receive/delete. The `report-jobs` queue listed in INF-003-S07 is **removed**: D-33 / RECONCILIATION C-05 moved report and export jobs to PostgreSQL job claims.

## Alarms (INF-003-S11)

- DLQ ApproximateNumberOfMessagesVisible > 0 for 5 min (every DLQ)
- landing-receipts ApproximateAgeOfOldestMessage > 900 s
- CloudTrail metric filter KMS AccessDenied on landing/reports keys
- landing bucket 4xx spike
- landing_key_violation custom metric > 0
