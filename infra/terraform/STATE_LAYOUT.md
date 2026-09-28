---
contract: terraform-state-layout-doc
version: 1
status: DRAFT
owner_task: INF-001
producing_steps: [INF-001-S08, INF-001-S09]
decisions: [D-25]
machine_readable: infra/terraform/state-layout.yaml
last_changed: 2026-09-28
---

# Terraform state layout

The machine-readable contract is [`state-layout.yaml`](state-layout.yaml) (schema [`state-layout.schema.json`](state-layout.schema.json)). This page explains the rules an implementer must not break.

## Rules

1. **One state bucket per AWS account**: `bridge-tfstate-<name>-<aws_account_id>-euw1`, SSE-KMS with the account's `alias/bridge-tfstate-<name>` key and bucket keys, versioned, TLS-only, public access blocked, bucket-owner-enforced, noncurrent versions expire after 90 days. The bucket policy denies every principal except `bridge-<name>-tf-apply` (read/write), `bridge-<name>-tf-plan` and `bridge-<name>-tf-drift` (read), BridgeAdmin and break-glass.
2. **One state object per stack**: key `<stack>/terraform.tfstate`; S3-native locking (`use_lockfile = true`, Terraform ≥ 1.11) writes `<key>.tflock`. No DynamoDB lock table.
3. **Stacks** (applied in this order, each depending only on earlier ones): `00-bootstrap` → `10-baseline` → `20-network`, `30-data` → `40-databases` → `50-compute` → `60-edge` → `70-snowflake` → `80-observability`; plus `org` (management account, human-applied), `shared` (shared-services account) and `test-estate` (staging account, INF-101-S05).
4. **Cross-stack wiring only through SSM** parameters `/bridge/<env>/<stack>/<key>` (type `String`, non-secret). `terraform_remote_state` is forbidden because it grants the consumer read access to the producer's whole state, which can contain sensitive attributes.
5. **Guards before any provider call**: `tools/tf/tf.sh` compares the caller identity with `infra/environments/<name>.json` (after merging `config/environments/<env>.yaml`) and exits before `terraform init` on mismatch; providers set `allowed_account_ids`; a `check` block asserts the region; `-target` is refused on prod without `BREAKGLASS=1` and an incident ID.
6. **No secrets in state**: Aurora uses `manage_master_user_password = true`, runtime database/cache users authenticate with IAM, `random_password` is banned, and `tools/tf/scan_sensitive.py` fails the plan on disallowed sensitive attributes (INF-102-S06).
7. **Plans and applies**: pull-request plans only for DEV/STAGING with the read-only plan role; PROD plans run on `main` under the protected `prod` GitHub environment; applies use the exact saved plan by digest; a plan older than the state serial is refused (INF-102-S04).
8. **Protected resources** (`protected_resource_types`) can be destroyed or replaced only with the `allow-destroy` label and a second approver (INF-102-S05).
9. **Recovery**: restore a prior state object version and verify `serial`/`lineage`; `terraform force-unlock` only with an incident ID; never delete state to clear a lock (INF-001-S11).
