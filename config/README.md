---
contract: owner-environment-config-readme
version: 1
status: DRAFT
owner_task: INF-001
decisions: [D-09, D-21, D-23, D-25, D-32]
last_changed: 2026-09-28
---

# Owner-supplied environment configuration

This directory holds the **non-secret identifiers** that only the owner can provide: AWS account and organization IDs, AZ IDs, DNS names and hosted zones, the e-mail sender domain, the GitHub repository identity used by OIDC trust, Snowflake account identifiers (central accounts and the test estate), alert mailboxes, budget ceilings, egress IP allocations and feature toggles. Terraform, the Snowflake migration runner (INF-104), CI workflows and the validation dispatcher (FND-005) read these values; nothing else in the repository hard-codes them. Code and documentation use `<AWS_ACCOUNT_ID>`-style placeholders instead ([ADR-017](../docs/architecture/adr/ADR-017-repository-and-contract-layout.md) §5).

| File | Purpose |
|---|---|
| [`environments/environment.schema.json`](environments/environment.schema.json) | JSON Schema 2020-12 for one environment file. Every field is annotated `x-bridge-secret: false`. |
| [`environments/dev.example.yaml`](environments/dev.example.yaml) | Template for DEV (workload account, BRIDGE_DEV Snowflake account). |
| [`environments/staging.example.yaml`](environments/staging.example.yaml) | Template for STAGING, including the Snowflake **test estate** (INF-101). |
| [`environments/prod.example.yaml`](environments/prod.example.yaml) | Template for PROD. |
| [`environments/.gitignore`](environments/.gitignore) | Keeps real `dev.yaml`/`staging.yaml`/`prod.yaml` out of git while the repository is public. |
| `environments/examples/*.invalid.example.yaml` | Negative fixtures: each must be rejected by `make config-validate`. |

## 1. How to fill a file

1. Copy the template: `cp config/environments/dev.example.yaml config/environments/dev.yaml` (same for `staging`, `prod`).
2. Replace every `<PLACEHOLDER>`. Where to find each value:

   | Field | Source |
   |---|---|
   | `organization.aws_organization_id`, `*_account_id` | AWS Organizations console (management account) → *AWS accounts*; or `aws organizations list-accounts`. The accounts are created by INF-001-S03; until then keep the placeholder. |
   | `organization.identity_center.*` | IAM Identity Center console → *Settings* (instance ARN, identity store ID). |
   | `aws.account_id` | The DEV / STAGING / PROD workload account ID. |
   | `aws.az_ids`, `aws.reserved_az_id` | `aws ec2 describe-availability-zones --region eu-west-1 --query 'AvailabilityZones[].ZoneId'` **in that account**. Use AZ IDs (`euw1-az1`), never AZ names (`eu-west-1a`), which differ per account. |
   | `dns.*` | Registrar and Route 53 console of the shared-services account (apex zone ID starts with `Z`). |
   | `dns.email.*` | Chosen sending subdomain `notify.<domain>` (RECONCILIATION U-07); role mailboxes only. |
   | `github.repository_owner_id`, `github.repository_id` | `gh api repos/<org>/<repo> --jq '.owner.id, .id'`. |
   | `snowflake.central.*` | In the Snowflake account: `SELECT CURRENT_ORGANIZATION_NAME(), CURRENT_ACCOUNT_NAME(), CURRENT_ACCOUNT(), CURRENT_REGION();` and the edition from `SHOW ORGANIZATION ACCOUNTS` (ORGADMIN). |
   | `snowflake.sso.*` | IdP application metadata (issuer, SSO URL). Upload the IdP certificate (public) to the SSM parameter named in `idp_certificate_ssm_parameter`. |
   | `snowflake.test_estate.*` (staging only) | Identifiers of the test organizations T_A/T_B and accounts TA_ORG/A1/A2/A3/B1 after INF-101-S02/S03 ([test-estate specification](../docs/testing/snowflake-test-estate.md)). |
   | `notifications.*` | Role mailboxes (never a personal inbox). Chat/Slack/Teams webhook URLs are secrets: store them in Secrets Manager under the name given in `*_secret_name`. |
   | `budgets.*` | Owner-approved ceilings recorded in [cost-baseline.md](../docs/runbooks/cost-baseline.md). Decimal strings (`"450"`), never YAML numbers. |
   | `egress.*` | **Leave empty.** Filled from `terraform output` after INF-002 applies the NAT Elastic IPs; the pipeline then generates `infra/environments/<env>.egress.json`. |
   | `features.*` | Owner choices; defaults in the templates follow the INF backlog recommendations. |

3. Keep the `organization` block identical in the three files and `github.visibility` accurate.
4. Validate: `make config-validate` (or `make config-validate ENV=staging`).

## 2. Validation command — `make config-validate`

Implemented by `tools/config/validate_config.py` (INF-001-S01, together with `tools/tf/validate_env.py`). Contract of the command:

| Check | Failure exit code |
|---|---|
| Every `config/environments/*.yaml` parses and validates against `environment.schema.json` (draft 2020-12, format assertions on). | 2 |
| File name stem equals `environment`. | 2 |
| No string in a **real** file (not `*.example.yaml`) matches the placeholder pattern `^<[A-Z][A-Z0-9_]*>$`. Templates may keep placeholders. | 3 |
| `organization`, `budgets.organization_accounts_monthly_usd`, `budgets.snowflake_nonprod_ceiling_credits` are identical across the environment files present. | 4 |
| `snowflake.test_estate` appears only in `staging`; its `monthly_credit_cap` values plus 40 credits of customer-side `BRIDGE_FINOPS_WH` monitors are ≤ 150 (D-32). | 4 |
| Secret-shape scan: no value matches an AWS access key (`AKIA`/`ASIA` + 16), a PEM header, a JWT (`eyJ…`), a Slack/Teams webhook URL, `password=`, or a 40-character base64 secret. | 5 |
| A real file exists while `github.visibility` is `PUBLIC` in it and `git ls-files` reports it as tracked. | 6 |
| Each `examples/*.invalid.example.yaml` is **rejected** (negative fixtures). | 7 |

Terraform and the migration runner call the same validator before `init`; a missing or placeholder value for the target environment stops the run before any provider call (INF-001-S01, S09).

## 3. What is not secret vs. what goes elsewhere

| Kind of value | Where it lives | Examples |
|---|---|---|
| Non-secret identifiers and choices | **This directory** | account IDs, AZ IDs, hosted zone IDs, Snowflake locators, GitHub repository IDs, budgets, feature toggles, secret *names* |
| Credentials and tokens | **AWS Secrets Manager** (per environment account, KMS-encrypted) | chat/Slack/Teams webhook URLs, Stripe restricted key (R2), Dagster metadata DB password (rotated, INF-004-S05) |
| Non-secret runtime parameters shared between stacks | **SSM Parameter Store** `/bridge/<env>/<stack>/<key>` | cross-stack outputs, published egress IPs `/bridge/<env>/egress/ips`, IdP certificate |
| CI identities | **GitHub OIDC** trust (no stored cloud keys) + **GitHub environments** (`dev`, `staging`, `prod`) for protection rules and non-secret variables | role ARNs are derived from account IDs; no `AWS_SECRET_ACCESS_KEY` anywhere |
| Snowflake machine access | **WIF only** (D-21) — bound to AWS role ARNs; nothing to store | — |
| Snowflake bootstrap credential | Used once interactively by a named administrator at account creation, never stored (ADR-010 amendment) | — |

Aurora master credentials are managed by RDS (`manage_master_user_password = true`) and never appear in Terraform state or here (INF-102-S06). There is no Snowflake password, key pair or PAT for any machine identity.

## 4. Repository visibility

The repository was public during the specification phase. **Before any real value is committed, the owner makes the repository private** (ADR-017 §5, ORCHESTRATION human-only gate). Until then:

- real files stay local or in a private store, protected by [`environments/.gitignore`](environments/.gitignore);
- CI reads the values from the private copy through GitHub environment variables or from an encrypted artifact supplied by the owner — never from the public repository.

After the repository is private: set `github.visibility: PRIVATE` in each file, remove the two ignore rules from `.gitignore` in a reviewed PR, and commit the files. Even then they must contain no secrets; the secret-shape scan and gitleaks still run on every PR.

## 5. Rotation and change

- **Identifiers rarely rotate.** Changing an AWS account, Snowflake account or repository ID is a migration: update the file, run `make config-validate`, then plan every affected stack (INF-102 shows the diff; protected resources need the `allow-destroy` label).
- **Egress IPs** never change silently: a new EIP is published at least **90 days** before the old one is retired (RECONCILIATION C-13, CON-102-S02); both sets stay in `infra/environments/<env>.egress.json` during the overlap.
- **Secrets referenced by name** rotate in Secrets Manager without touching this file (webhooks: on suspicion or yearly; Dagster DB password: rotation Lambda, INF-004-S05).
- **Budgets** change only with a recorded owner approval in `docs/runbooks/cost-baseline.md`.
- **Snowflake SSO certificate** rotation: upload the new certificate to the SSM parameter, then apply the `70-snowflake` stack; the parameter name stays the same.
