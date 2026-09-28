---
contract: security-group-matrix-doc
version: 1
status: DRAFT
owner_task: INF-002
producing_steps: [INF-002-S06]
generated_from: infra/network/sg-matrix.yaml
decisions: [D-07, D-22, D-28, D-33]
last_changed: 2026-09-28
---

# Security-group matrix

Generated from [`infra/network/sg-matrix.yaml`](../../infra/network/sg-matrix.yaml) by `tools/network/render_sg_matrix.py`; do not edit by hand (CI regenerates and diffs). CIDRs per environment are in [`infra/network/cidr-plan.yaml`](../../infra/network/cidr-plan.yaml).

## Invariants

- No ingress rule from 0.0.0.0/0 or ::/0 on any security group.
- Data security groups (sg-aurora, sg-valkey, sg-endpoints) have no egress rules.
- Only sg-alb-internal accepts traffic originating outside the VPC, and only from the CloudFront VPC-origin source.
- No task has a public IP (Security Hub ECS.2).

## Ingress (source → port → destination)

| Destination SG | Attached to | Source | Port | Why |
|---|---|---|---|---|
| `sg-alb-internal` | internal ALB | CloudFront VPC-origin source (managed prefix list com.amazonaws.global.cloudfront.origin-facing or the CloudFront VPC-origins service security group — TO VERIFY LIVE, INF-006-S07) | 443/tcp | /api/* from CloudFront only (D-28) |
| `sg-alb-internal` | internal ALB | sg-ops-bastion | 8443/tcp | private listener for the ops console/API (CTL-102) |
| `sg-alb-internal` | internal ALB | sg-runners | 443/tcp | post-deploy smoke tests from in-VPC runners |
| `sg-api` | api | sg-alb-internal | 8000/tcp | ALB target |
| `sg-ops-api` | ops-api | sg-alb-internal | 8000/tcp | ALB private listener target |
| `sg-broker` | query-broker | VPC Lattice managed prefix list (com.amazonaws.eu-west-1.vpc-lattice) | 8443/tcp | Lattice service; IAM auth policy admits only api, analysis-worker, render-worker, monitor-worker, intelligence-worker, run-worker-python roles (D-22, D-33, C-09) |
| `sg-broker` | query-broker | sg-api, sg-workers, sg-run-workers (only when features.broker_transport = SERVICE_CONNECT_SG) | 8443/tcp | fallback transport |
| `sg-sync-api` | sync-api | VPC Lattice managed prefix list (com.amazonaws.eu-west-1.vpc-lattice) | 8080/tcp | extractor tasks sign with their bridge-{env}-conn-* session (IAM auth policy) |
| `sg-sync-api` | sync-api | sg-extractor (only when features.broker_transport = SERVICE_CONNECT_SG) | 8080/tcp | fallback transport |
| `sg-launcher` | extraction-launcher | — (no ingress) | — | — |
| `sg-extractor` | extractor | — (no ingress) | — | — |
| `sg-workers` | receipt-consumer, analysis-worker, render-worker, monitor-worker, notification-worker, intelligence-worker, control-worker, outbox-dispatcher, authz-provisioner, tenant-onboarder, config-publisher, audit-exporter, migrate, platform-cost, canary | — (no ingress) | — | — |
| `sg-identity-provisioner` | identity-provisioner | — (no ingress) | — | — |
| `sg-dagster-web` | dagster-webserver-ro, dagster-webserver-admin | sg-ops-bastion | 3000/tcp | SSM port-forward only (G-INF-11) |
| `sg-dagster-daemon` | dagster-daemon | — (no ingress) | — | — |
| `sg-dagster-code` | dagster-code-extraction, dagster-code-dbt, dagster-code-intelligence, dagster-code-delivery, dagster-code-maintenance | sg-dagster-daemon | 4000/tcp | gRPC |
| `sg-dagster-code` | dagster-code-extraction, dagster-code-dbt, dagster-code-intelligence, dagster-code-delivery, dagster-code-maintenance | sg-dagster-web | 4000/tcp | gRPC |
| `sg-dagster-code` | dagster-code-extraction, dagster-code-dbt, dagster-code-intelligence, dagster-code-delivery, dagster-code-maintenance | sg-run-workers | 4000/tcp | gRPC |
| `sg-run-workers` | run-worker-dbt, run-worker-python | — (no ingress) | — | — |
| `sg-ops-bastion` | ops-bastion | — (no ingress) | — | — |
| `sg-runners` | CodeBuild-hosted GitHub Actions runners (INF-002-S09) | — (no ingress) | — | — |
| `sg-aurora` | Aurora PostgreSQL cluster | sg-api | 5432/tcp | PostgreSQL |
| `sg-aurora` | Aurora PostgreSQL cluster | sg-ops-api | 5432/tcp | PostgreSQL |
| `sg-aurora` | Aurora PostgreSQL cluster | sg-broker | 5432/tcp | PostgreSQL |
| `sg-aurora` | Aurora PostgreSQL cluster | sg-sync-api | 5432/tcp | PostgreSQL |
| `sg-aurora` | Aurora PostgreSQL cluster | sg-launcher | 5432/tcp | PostgreSQL |
| `sg-aurora` | Aurora PostgreSQL cluster | sg-workers | 5432/tcp | PostgreSQL |
| `sg-aurora` | Aurora PostgreSQL cluster | sg-identity-provisioner | 5432/tcp | PostgreSQL |
| `sg-aurora` | Aurora PostgreSQL cluster | sg-dagster-web | 5432/tcp | PostgreSQL |
| `sg-aurora` | Aurora PostgreSQL cluster | sg-dagster-daemon | 5432/tcp | PostgreSQL |
| `sg-aurora` | Aurora PostgreSQL cluster | sg-dagster-code | 5432/tcp | PostgreSQL |
| `sg-aurora` | Aurora PostgreSQL cluster | sg-run-workers | 5432/tcp | PostgreSQL |
| `sg-aurora` | Aurora PostgreSQL cluster | sg-ops-bastion | 5432/tcp | PostgreSQL |
| `sg-aurora` | Aurora PostgreSQL cluster | sg-runners | 5432/tcp | PostgreSQL |
| `sg-valkey` | ElastiCache Valkey | sg-api | 6379/tcp | cache |
| `sg-valkey` | ElastiCache Valkey | sg-broker | 6379/tcp | cache |
| `sg-valkey` | ElastiCache Valkey | sg-workers | 6379/tcp | cache |
| `sg-endpoints` | interface endpoints (STAGING/PROD) | app subnet CIDRs (infra/network/cidr-plan.yaml tier app) | 443/tcp | private DNS endpoints |

## Egress

| Source SG | Destination | Port | Why |
|---|---|---|---|
| `sg-alb-internal` | sg-api | 8000/tcp | API target group |
| `sg-alb-internal` | sg-ops-api | 8000/tcp | ops API target group |
| `sg-api` | 0.0.0.0/0 | 443/tcp | AWS APIs via NAT/endpoints, Snowflake, Cognito, VPC Lattice (443) |
| `sg-api` | sg-aurora | 5432/tcp | PostgreSQL (IAM auth / rotated secret) |
| `sg-api` | sg-valkey | 6379/tcp | cache (TLS) |
| `sg-ops-api` | 0.0.0.0/0 | 443/tcp | AWS APIs via NAT/endpoints, Snowflake, Cognito, VPC Lattice (443) |
| `sg-ops-api` | sg-aurora | 5432/tcp | PostgreSQL (IAM auth / rotated secret) |
| `sg-broker` | 0.0.0.0/0 | 443/tcp | AWS APIs via NAT/endpoints, Snowflake, Cognito, VPC Lattice (443) |
| `sg-broker` | sg-aurora | 5432/tcp | PostgreSQL (IAM auth / rotated secret) |
| `sg-broker` | sg-valkey | 6379/tcp | cache (TLS) |
| `sg-sync-api` | 0.0.0.0/0 | 443/tcp | AWS APIs via NAT/endpoints, Snowflake, Cognito, VPC Lattice (443) |
| `sg-sync-api` | sg-aurora | 5432/tcp | PostgreSQL (IAM auth / rotated secret) |
| `sg-launcher` | 0.0.0.0/0 | 443/tcp | AWS APIs via NAT/endpoints, Snowflake, Cognito, VPC Lattice (443) |
| `sg-launcher` | sg-aurora | 5432/tcp | PostgreSQL (IAM auth / rotated secret) |
| `sg-extractor` | 0.0.0.0/0 | 443/tcp | customer Snowflake hosts (validated in code; private/link-local IPs blocked), S3 landing via gateway endpoint, sync-api via Lattice |
| `sg-workers` | 0.0.0.0/0 | 443/tcp | AWS APIs via NAT/endpoints, Snowflake, Cognito, VPC Lattice (443) |
| `sg-workers` | sg-aurora | 5432/tcp | PostgreSQL (IAM auth / rotated secret) |
| `sg-workers` | sg-valkey | 6379/tcp | cache (TLS) |
| `sg-identity-provisioner` | 0.0.0.0/0 | 443/tcp | AWS APIs via NAT/endpoints, Snowflake, Cognito, VPC Lattice (443) |
| `sg-identity-provisioner` | sg-aurora | 5432/tcp | PostgreSQL (IAM auth / rotated secret) |
| `sg-dagster-web` | 0.0.0.0/0 | 443/tcp | AWS APIs via NAT/endpoints, Snowflake, Cognito, VPC Lattice (443) |
| `sg-dagster-web` | sg-aurora | 5432/tcp | PostgreSQL (IAM auth / rotated secret) |
| `sg-dagster-web` | sg-dagster-code | 4000/tcp | code-location gRPC |
| `sg-dagster-daemon` | 0.0.0.0/0 | 443/tcp | AWS APIs via NAT/endpoints, Snowflake, Cognito, VPC Lattice (443) |
| `sg-dagster-daemon` | sg-aurora | 5432/tcp | PostgreSQL (IAM auth / rotated secret) |
| `sg-dagster-daemon` | sg-dagster-code | 4000/tcp | code-location gRPC |
| `sg-dagster-code` | 0.0.0.0/0 | 443/tcp | AWS APIs via NAT/endpoints, Snowflake, Cognito, VPC Lattice (443) |
| `sg-dagster-code` | sg-aurora | 5432/tcp | PostgreSQL (IAM auth / rotated secret) |
| `sg-run-workers` | 0.0.0.0/0 | 443/tcp | AWS APIs via NAT/endpoints, Snowflake, Cognito, VPC Lattice (443) |
| `sg-run-workers` | sg-aurora | 5432/tcp | PostgreSQL (IAM auth / rotated secret) |
| `sg-run-workers` | sg-dagster-code | 4000/tcp | code-location gRPC |
| `sg-ops-bastion` | sg-dagster-web | 3000/tcp | Dagster UI tunnel |
| `sg-ops-bastion` | sg-aurora | 5432/tcp | database diagnostics tunnel (ops_readonly) |
| `sg-ops-bastion` | sg-alb-internal | 8443/tcp | ops console |
| `sg-ops-bastion` | sg-endpoints | 443/tcp | ssmmessages endpoint |
| `sg-ops-bastion` | 0.0.0.0/0 | 443/tcp | SSM in DEV (no endpoints) |
| `sg-runners` | 0.0.0.0/0 | 443/tcp | GitHub, AWS APIs, Snowflake (published EIPs) |
| `sg-runners` | sg-aurora | 5432/tcp | DB bootstrap and Alembic dry-runs |
| `sg-runners` | sg-alb-internal | 443/tcp | smoke tests |
| `sg-aurora` | — (no egress) | — | — |
| `sg-valkey` | — (no egress) | — | — |
| `sg-endpoints` | — (no egress) | — | — |

## Reachability expectations

| ID | Source | Destination | Port | Expected | Proof |
|---|---|---|---|---|---|
| R-01 | internet gateway | data-a subnet (Aurora) | 5432 | NOT_REACHABLE | VPC Reachability Analyzer (INF-002-S10) |
| R-02 | extractor ENI | Aurora writer | 5432 | NOT_REACHABLE | VPC Reachability Analyzer |
| R-03 | api ENI | Aurora writer | 5432 | REACHABLE | VPC Reachability Analyzer |
| R-04 | data-a subnet | internet gateway | 443 | NOT_REACHABLE | VPC Reachability Analyzer |
| R-05 | internet | internal ALB | 443 | NOT_REACHABLE | external curl from GitHub-hosted runner (INF-006-S14) |
| R-06 | api ENI | dagster-webserver-ro | 3000 | NOT_REACHABLE | VPC Reachability Analyzer |
| R-07 | ops-bastion ENI | dagster-webserver-ro | 3000 | REACHABLE | VPC Reachability Analyzer |
| R-08 | extractor ENI | Valkey | 6379 | NOT_REACHABLE | VPC Reachability Analyzer |
| R-09 | notification-worker (sg-workers) signed request | query-broker via Lattice | 443 | HTTP_403 | tests/aws/network (INF-005-S11: IAM auth policy denies a non-allowlisted worker role) |
| R-10 | api signed request | query-broker via Lattice | 443 | HTTP_200 | tests/aws/network |
| R-11 | unsigned request | query-broker via Lattice | 443 | HTTP_403 | tests/aws/network |
