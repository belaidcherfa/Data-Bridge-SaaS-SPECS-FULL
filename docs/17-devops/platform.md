# AWS platform, networking and deployment foundation

Canonical domain contract. Owner: DevOps. Implementation state: NOT_STARTED.


## Environment and network decision

Create DEV, STAGING, PROD AWS accounts under a managed organization, plus a security/log archive account when organizational ownership allows. EU-west-1 is the initial regional default; central Snowflake should be co-located where feasible. Region/residency and service availability are provisioning gates. Use two AZs minimum, public ALB/NAT subnets, private application subnets and isolated data subnets. ECS tasks have no public IP; Aurora/Redis have no public endpoint. Security groups allow only ALB→API/web, approved services→data, and required egress.

CloudFront distributes the frontend and API origin paths; disable caching on authenticated API responses. WAF attaches to the supported edge/regional resource; it is not an independent network hop. Restrict ALB origin access using AWS-supported origin controls, secret header plus network controls and rotation; do not assume an obscure origin hostname is private. Route53/ACM validate hostnames. Keep Dagster internal behind authenticated operations access.

Use S3 gateway endpoints and appropriate private endpoints for ECR, logs, Secrets Manager, SQS and STS where supported. Controlled NAT egress reaches customer Snowflake endpoints, including non-AWS customer accounts; record cross-cloud transfer/privacy implications. PrivateLink is an optional validated capability, never an assumption for Standard/trial customers.

## Terraform and runtime

Separate state per environment and foundational/application stack. Encrypted versioned S3 backend, provider-supported state locking, least-privilege apply roles, reviewed plans and drift detection. Bootstrap state resources with a small auditable root stack, then import them; never delete state to fix a lock. State can contain secrets and is access-controlled. Account/region guards refuse an unexpected destination.

Fargate services: frontend, API, connector tasks, Dagster web/daemon/code locations/run workers, intelligence, monitor and report workers. Different task roles and resource limits; ECR digest images; non-root/read-only filesystems where compatible; bounded ephemeral storage. Daemon is single-active with recovery; API spans AZs. Task execution role pulls images/logs/secrets; task role authorizes application AWS calls. [ECS IAM distinction](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html).

Aurora PostgreSQL uses multi-AZ failover, encrypted storage, backups and deletion protection. Initially use bounded application pools directly; evaluate RDS Proxy only after transaction-context/pinning tests, since RLS correctness takes precedence over multiplexing. [RDS Proxy pinning](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy-pinning.html).

ElastiCache Redis uses TLS, at-rest encryption, auth/ACL controls and private access; eviction/loss must be safe. S3 landing, reports, audit and Terraform state use separate policies, KMS keys and retention purposes. SQS queues have DLQs, bounded redrive and visibility extension. SNS provides Snowpipe fanout where required; application consumers do not poll Snowflake-managed queues.

## Capacity and observability defaults

Start with explicit small nonzero service minima in staging/prod and a documented budget. Do not invent CPU/RAM counts as proven sizing: choose initial values in task definitions, then benchmark the SLO matrix. Set statement, request and job timeouts; enforce per-tenant concurrency and account admission. Tag AWS resources by environment/component/cost_owner; per-job tenant usage is recorded separately to avoid cardinality explosion in infrastructure tags.


## Implementation sequence

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [INF-001](../tasks/INF/INF-001.md) | Bootstrap AWS accounts, state and environment guards | FND-006 | M1 |
| [INF-002](../tasks/INF/INF-002.md) | Create VPC, endpoints and controlled egress | INF-001 | M1 |
| [INF-003](../tasks/INF/INF-003.md) | Provision KMS, buckets, queues and retention boundaries | INF-002 | M1 |
| [INF-004](../tasks/INF/INF-004.md) | Provision Aurora and Redis with safe resource budgets | INF-002, INF-003 | M1 |
| [INF-005](../tasks/INF/INF-005.md) | Build ECS base services and role separation | INF-003, INF-004 | M1 |
| [INF-006](../tasks/INF/INF-006.md) | Configure edge, DNS, TLS and private operations access | INF-005 | M1 |
| [INF-007](../tasks/INF/INF-007.md) | Create OIDC deployment pipeline and staged rollback | INF-005, INF-006 | M1 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.
