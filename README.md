# Bridge Data FinOps — Engineering delivery system

Implementation-ready specification for the journey from an empty repository to the first paying production customer. **Product implementation has not started.** This repository contains the plan, canonical contracts, decisions and validation requirements; no AWS deployment, Snowflake customer connection or payment is claimed.

Start with [PROJECT_MASTER_PLAN](PROJECT_MASTER_PLAN.md), [DELIVERY_METHODOLOGY](DELIVERY_METHODOLOGY.md), [ARCHITECTURE_OVERVIEW](ARCHITECTURE_OVERVIEW.md), [DEPENDENCY_GRAPH](DEPENDENCY_GRAPH.md) and [MILESTONES](MILESTONES.md).

- [151 implementation tasks in construction order](TASK_INDEX.md), with prerequisites, micro-tasks, data/interfaces, security, failures, UX, tests and DoD.
- [Canonical domain navigation](docs/tasks/README.md) and [machine task index](docs/00-project/task-index.json).
- [Progress and resume state](docs/00-project/STATUS.md), [PRD traceability](docs/00-project/TRACEABILITY.md), [research assumptions](docs/00-project/RESEARCH_REGISTER.md) and [open implementation validations](docs/00-project/OPEN_VALIDATIONS.md).
- [Architecture decisions](docs/architecture/adr/README.md), [test strategy and numerical fixtures](docs/15-testing/validation-strategy.md), [operational runbooks](docs/16-observability/RUNBOOKS.md).
- [Production gates](docs/19-production-readiness/CHECKLIST.md), [first customer value](docs/18-customer-onboarding/FIRST_VALUE.md), [documentation audit](docs/00-project/COHERENCE_AUDIT.md).
- [Authoritative supplied PRD](docs/00-project/PRD.md) and [provenance](docs/00-project/PRD_PROVENANCE.md).

The architecture keeps customer Snowflake as source, AWS WIF authentication, Python/Arrow/Parquet extraction, immutable S3 replay journal, Snowpipe ingestion, dbt Core transformations, central Snowflake analytical truth, Dagster OSS orchestration, PostgreSQL transactional control, disposable Redis cache, FastAPI and React. Multi-tenant and multi-account isolation is foundational.

Resume at FND-001 after reading its exact prerequisites. A published specification is not a completed implementation task. Keep future customer records, secrets and payment evidence out of this public repository.
