---
contract: aws-organization-design-record
version: 1
status: DRAFT
owner_task: INF-001
producing_steps: [INF-001-S02, INF-001-S03, INF-001-S04, INF-001-S05]
decisions: [D-23, D-25, D-02, D-07]
machine_readable: [infra/terraform/org/organization.yaml, infra/terraform/org/scp/, infra/terraform/org/scp/test-matrix.yaml]
last_changed: 2026-09-28
approval: "Owner sign-off required (INF-001-S02 oracle)"
---

# AWS organization design record (G-INF-12)

## 1. Decision

Bridge runs in a dedicated **AWS Organization managed by Terraform from the management account** (`infra/terraform/org/`), with seven accounts, six OUs, nine service control policies and IAM Identity Center for all human access. **AWS Control Tower is not used in R1**: it adds console-driven setup (ClickOps) outside reviewed plans, enables AWS Config in every governed region (the ENI-recording cost trap of G-INF-06 multiplied by regions), and brings an Account Factory for Terraform pipeline that duplicates INF-102. Revisit at SOC 2 certification timing (D-25) or if a customer or auditor requires it.

## 2. Accounts and OUs

| Account | OU | Purpose | Terraform stacks | Root e-mail alias |
|---|---|---|---|---|
| bridge-management | root | Billing, Organizations, Identity Center, organization CloudTrail. No workloads (SCPs do not apply here). | `00-bootstrap`, `org` | `aws+management@<account_email_domain>` |
| bridge-security | security | GuardDuty, Security Hub, IAM Access Analyzer delegated administrator; security alarms | `00-bootstrap`, `10-baseline` | `aws+security@…` |
| bridge-log-archive | security | Organization CloudTrail bucket (Object Lock), Config aggregator, flow-log and resolver-log archive | `00-bootstrap`, `10-baseline` | `aws+log-archive@…` |
| bridge-shared-services | infrastructure | ECR, cosign KMS key (`alias/bridge-image-signing`), apex Route 53 zone, `bridge-shared-releases` evidence bucket | `00-bootstrap`, `10-baseline`, `shared` | `aws+shared-services@…` |
| bridge-dev | workloads/nonprod | DEV environment | `00-bootstrap` … `80-observability` | `aws+dev@…` |
| bridge-staging | workloads/nonprod | STAGING; test-estate IaC and connector roles (INF-101) | same | `aws+staging@…` |
| bridge-prod | workloads/prod | PROD | same | `aws+prod@…` |

The `suspended` OU receives accounts pending closure (deny-all SCP). Accounts are created with `prevent_destroy` and `close_on_deletion = false`. Account IDs live only in `config/environments/*.yaml` (never in this public repository). An optional separate recovery account (ADR-011/OPS-007) is declared with `organization.recovery_account_id` when the owner approves it.

**Billing owner:** the management account's billing contact is the owner (BridgeBilling permission set). **Root credentials:** hardware MFA on every root user, no root access keys; the member-account root is additionally denied by SCP (`bridge-scp-deny-root`); root-only tasks go through the documented break-glass procedure (centralized root access from the management account when available, TO VERIFY LIVE).

## 3. Service control policies

Files in [`infra/terraform/org/scp/`](../../infra/terraform/org/scp/); metadata and attachments in [`organization.yaml`](../../infra/terraform/org/organization.yaml); denied/allowed call matrix in [`test-matrix.yaml`](../../infra/terraform/org/scp/test-matrix.yaml).

| SCP | Attached to | Guard |
|---|---|---|
| `bridge-scp-deny-leave-org` | root | No account leaves the organization |
| `bridge-scp-protect-security-services` | root | CloudTrail, GuardDuty, Security Hub, Config, Access Analyzer cannot be stopped/deleted (break-glass only); flow/resolver logs removable only by tf-apply |
| `bridge-scp-region-guard` | root | eu-west-1 only; us-east-1 only for `acm`, `wafv2`, `cloudwatch`, `sns`, `logs`, `kms`, `events` (CloudFront/Cognito certificates, CLOUDFRONT WAF, CloudFront alarms, root-login rule — G-INF-10); global services exempt |
| `bridge-scp-deny-root` | root | Member-account root can do nothing |
| `bridge-scp-deny-iam-users` | security, infrastructure, workloads | No IAM users, access keys, console passwords, service-specific credentials (break-glass only) |
| `bridge-scp-deny-kms-deletion` | security, infrastructure, workloads | No key deletion/disable; key policies changed only by tf-apply |
| `bridge-scp-runtime-role-guard` | workloads | Runtime roles `bridge-<env>-conn-<uuid32>` / `bridge-<env>-srv-<uuid32>` are created or changed only by the identity provisioner and always with the matching boundary; no boundary removal; only own split S3 policies attach; boundary policies changed only by a BridgeAdmin human session or break-glass; nobody assumes conn roles; only the query broker assumes srv roles; only the extraction launcher passes conn roles (INF-103, D-02, D-07, RECONCILIATION C-11) |
| `bridge-scp-prod-ecs-exec` | workloads/prod | ECS Exec only into the `ops-bastion` container; exec cannot be enabled on other task definitions (condition keys TO VERIFY LIVE, SCP-20…22) |
| `bridge-scp-deny-all-suspended` | suspended | Deny all except break-glass |

AWS allows at most five SCPs per target including `FullAWSAccess`; the attachment plan uses at most five (root) and relies on inheritance. SCPs are backstops: identity policies and permission boundaries remain the primary control.

## 4. Human access (IAM Identity Center, INF-001-S05)

| Permission set | Max session | Accounts | Scope |
|---|---|---|---|
| BridgeAdmin | 1 h | all | Administrator; the only human path to boundary-policy changes and production Terraform applies of the `org` stack (human-only gate) |
| BridgeOperator | 4 h | staging, prod | Read-only plus the audited `ops-bastion` SSM port-forward (INF-006-S13) |
| BridgeDeveloper | 8 h | dev | Power user in DEV, no IAM writes except PassRole on `bridge-dev-*` |
| BridgeDeveloperReadOnly | 8 h | staging | Read-only, explicit deny on data buckets and secret values |
| BridgeReadOnly | 4 h | all except management | View-only for audit |
| BridgeBilling | 4 h | management | Billing and Cost Explorer |

MFA is required at the IdP (or Identity Center's built-in MFA when `external_idp = NONE`). There are no IAM users anywhere.

## 5. Break-glass

- Role `bridge-break-glass` exists in every member account, assumable only from a management-account principal with hardware MFA; every assumption fires an EventBridge rule → SNS security topic → `security_alert_email` (INF-001-S13).
- **Holders:** two named humans (owner decision; names recorded in the private owner register, not in this public repository).
- Use requires an incident ID; the session is reviewed within one business day (D-25 evidence).

## 6. Bootstrap sequence (human, audited)

1. Owner creates or designates the management account and enables Organizations (all features) and Identity Center; records IDs in `config/environments/*.yaml`.
2. BridgeAdmin runs stack `00-bootstrap` in the management account with local state, then migrates the state into its own bucket (`terraform init -migrate-state`, INF-001-S08).
3. BridgeAdmin applies the `org` stack: OUs, accounts, SCPs **in deny-only test mode first on the `workloads/nonprod` OU**, delegated administrators, Identity Center permission sets.
4. For each member account: `00-bootstrap` (state bucket + key) then `10-baseline` (GitHub OIDC provider, CI roles, security baseline) — from this point every apply goes through INF-102's reviewed saved plans.
5. Execute the SCP test matrix; record each denied call's exact error text as INF-001 evidence.

## 7. Open owner questions (INF backlog §7)

1. Existing organization or a new one; who owns the management account and billing.
2. Product domain and registrar (root e-mail alias domain).
3. Whether a separate recovery account is approved.
4. Names of the two break-glass holders and the approver of break-glass use.
