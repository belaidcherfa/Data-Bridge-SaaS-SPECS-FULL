# ADR-017 — Repository strategy and contract layout

Status: Accepted for implementation. Date: 2026-09-28. Decisions: D-19 (coding agents), D-01 (R1 production slice).

## Context

The owner will implement the product with coding agents orchestrated by a strong model (D-19), running several lanes in parallel for days. Parallel agents need (1) one repository whose layout they can rely on, (2) executable contracts that exist before the code consuming them, and (3) namespaces that cannot collide when two agents write at the same time. The specification repository had no executable contracts ([audit X-06](../../22-implementation-readiness/AUDIT_CROSS_CUTTING.md)); 234 contract artifacts were specified by the readiness review with heterogeneous paths.

## Decision

1. **This repository becomes the product monorepo.** Specifications remain under `docs/`; the PRD stays byte-exact. Code follows the PRD §149 layout (`apps/`, `services/`, `data/`, `packages/`, `infra/`, `tests/`) established by FND-001; executable contracts live in `contracts/` (cross-cutting API, errors, events, state machines, authorization, PostgreSQL reference DDL), `infra/snowflake/migrations/` (Snowflake objects), `data/contracts/` (data contracts), `packages/*/` (package-owned schemas) and `config/environments/` (owner-supplied environment configuration).
2. **One convention file** — [contracts/CONVENTIONS.md](../../../contracts/CONVENTIONS.md) — governs naming, identifiers (UUIDv7, UUIDv5 namespaces), time (UTC, half-open intervals), money (decimal strings, NUMBER(38,12)), unknown values, HTTP (OpenAPI 3.1, RFC 9457 problems, `X-Bridge-Tenant` with echo, 412 on stale `If-Match`), events (outbox envelope), state machines (YAML format), DDL and privacy classification.
3. **Collision-free ownership.** [contracts/README.md](../../../contracts/README.md) assigns every shared namespace (OpenAPI domain files, problem-code prefixes, event domains, state-machine names, PostgreSQL schema files, Snowflake migration version blocks) to exactly one contract lane. Consumers change a contract only through a PR reviewed by the owning lane.
4. **Contract lifecycle.** `DRAFT` (authored by an agent) → `ACCEPTED` (reviewed PR, consuming lanes notified) → `DEPRECATED` (replacement exists). Code may only depend on `ACCEPTED` contracts, except inside the owning task.
5. **Repository visibility.** The repository was designated public for the specification phase. Before any product code, credentials references, customer-specific configuration or security-sensitive implementation lands, the owner makes it **private** (or moves code to a private repository). Environment identifiers are supplied through `config/environments/<env>.yaml` (validated by a JSON Schema, committed only while the repository is private) or through GitHub environment variables; secrets never enter git (they live in AWS Secrets Manager / SSM and GitHub OIDC trust).

## Alternatives

- Separate specification and code repositories: forces agents to synchronize two repositories and breaks "contract and code in the same PR".
- Contracts embedded in code packages only: hides cross-cutting contracts and invites duplicate definitions across services.
- Free-form paths chosen per task: guarantees collisions between parallel agents.

## Consequences

FND-001 creates the package skeleton around the existing `contracts/`, `data/contracts/` and `infra/` trees instead of inventing new locations. CI validates every contract (JSON Schema, Spectral, state-machine linter, SQL parse, schema-diff between Alembic migrations and `contracts/postgres`). A public repository must not receive product code.

## Revisit conditions

Team or agent count grows beyond what one repository's CI can serve within 15 minutes per PR; a component needs a separate release cadence (e.g. a Snowflake Native App); legal separation of code and specifications becomes necessary.

## Validation obligation

`make contracts-check` passes on every PR; the ownership map has no namespace owned twice; repository visibility is private before the first product-code PR merges.
