---
name: terraform-change
description: Make an AWS or Snowflake-account infrastructure change in infra/terraform safely — module/stack layout, EU-only regions, tagging, least-privilege IAM, no secrets, plan-only outside DEV, policy checks, cost notes and plan evidence. Use for INF, SEC-infra, OPS-alarm and any Terraform edit.
---

# Terraform change

Read ADR-010/ADR-012 (+ amendments), ADR-016 (residency/reachability), D-23 (EU only), D-28 (edge), D-31 (SLOs), D-32 (non-prod spend) and the INF backlog section of your task.

## Layout
- `infra/terraform/org/` (Organizations, SCPs, Identity Center, CloudTrail) — owner-applied only.
- `infra/terraform/stacks/<NN-name>/` (`00-bootstrap`, `10-baseline`, `20-network`, `30-data`, `40-compute`, `50-edge`, `60-observability`, `70-snowflake`, `test-estate`) each with `backend.hcl` per environment, `versions.tf` pinning Terraform and providers, `variables.tf`, `outputs.tf`.
- `infra/terraform/modules/<name>/` reusable modules with `README.md`, input validation blocks and examples.
- Environment values come from `config/environments/<env>.yaml` (owner-supplied, not committed for real envs; `*.example.yaml` are templates) → never hardcode account IDs, ARNs, Snowflake locators or domains; use `<AWS_ACCOUNT_ID>`-style placeholders in docs.

## Rules
- Region: `eu-west-1` only in R1 (D-23, ADR-016); SCP denies every other region except the global services the baseline allowlists (IAM, CloudFront, Route 53, WAF for CloudFront in us-east-1). Central Snowflake accounts co-located in the matching AWS EU region. Any cross-region copy (backups, DR) requires an ADR amendment.
- Tags on every resource via provider `default_tags`: `bridge:env`, `bridge:stack`, `bridge:owner-task`, `bridge:data-class`, `bridge:cost-center`.
- IAM: one role per service/task, no `*` actions on data services, conditions on `aws:SourceVpc`/`aws:PrincipalTag`; GitHub OIDC trust restricted to repo + environment; no IAM users, no access keys.
- Encryption: KMS CMK per data class, S3 Block Public Access, bucket policies deny non-TLS, Object Lock GOVERNANCE for audit/evidence buckets, Aurora/ElastiCache encrypted in transit and at rest.
- Network: private subnets for compute and data, VPC endpoints for AWS services and Snowflake PrivateLink (R2), egress through controlled NAT with allowlists for webhook dispatch.
- Secrets: created as empty `aws_secretsmanager_secret` shells; values set out of band by the owner; never `secret_string` in code or state.
- Snowflake provider: account-level objects only (warehouses, roles, users for WIF, network/auth policies); schemas/tables/pipes via migrations.

## Workflow
1. `terraform fmt -recursive`, `terraform validate`, `tflint`, `trivy config` / `checkov`, `conftest test` with `infra/policy/*.rego` — all clean (`make infra-validate`).
2. `terraform plan` against DEV only (`BRIDGE_ENV=dev`); save the plan summary (no sensitive values) to the evidence manifest. Agents never apply to STAGING/PROD; the hook blocks `terraform apply` unless `BRIDGE_ENV=dev`.
3. Cost note in the PR: new monthly cost estimate per environment (Infracost if available, else a table), and whether D-32 budgets are affected.
4. Destructive changes (replace/destroy of stateful resources) → `needs-human` label and a rollback note; never `-target` or `state rm` without an escalation.
5. STAGING/PROD applies are human gates executed through the release workflow (REL) after review.
