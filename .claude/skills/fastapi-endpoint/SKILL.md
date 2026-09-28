---
name: fastapi-endpoint
description: Implement a Bridge HTTP endpoint contract-first in services/api (FastAPI + Pydantic + SQLAlchemy async) — OpenAPI conformance, authentication, tenant header, capabilities, problem details, idempotency, If-Match, keyset pagination, outbox events, audit, telemetry and tests. Use for every API, CTL, CON, ALC, GOV, RPT, ONB, SAS endpoint.
---

# FastAPI endpoint (contract-first)

1. **Contract**: the operation exists in `contracts/openapi/paths/<domain>.yaml` with `operationId`, `x-capability`, `x-owner-task`, request/response schemas, problem codes and examples. If not, stop: `author-contract` (own lane) or `escalate` (`contract-change`).
2. **Router** `services/api/src/bridge_api/routers/<domain>.py`: one handler per `operationId`; function name = operationId in snake_case; response model from the generated/hand-written Pydantic models in `packages/api_contracts` (never ad-hoc dicts). Money fields are `Money` (decimal strings).
3. **Dependencies (in this order)**: `authenticated_principal` (cookie session with CSRF, or machine bearer) → `tenant_context` (verifies membership for `X-Bridge-Tenant`, sets transaction-local `app.tenant_id`, echoes the header) → `require_capability("<x-capability>")` → `db_session` (tenant-scoped). Never read `tenant_id` from the body or path for authorization.
4. **Semantics**:
   - Creates with side effects require `Idempotency-Key` (stored hash of body; same key + other body → 409 `IDEMPOTENCY_KEY_REUSED`; replay returns the stored response).
   - Updates: `PATCH` + `If-Match` revision ETag; stale → 412 `PRECONDITION_FAILED`; bump `revision`.
   - Lists: keyset pagination with sealed cursor (`next_cursor`), `limit` ≤ 500, stable sort with id tiebreaker, `meta` block (publication_id, data_status, coverage, currency, warnings, request_id).
   - Analytical reads: call the query broker client with the pinned publication; never open a Snowflake connection from the API.
   - Long work: enqueue a job (D-33 workers) and return 202 + job resource.
   - Foreign/missing objects: non-enumerating 404 `NOT_FOUND`.
5. **State changes**: validate transitions against `contracts/state-machines/<machine>.yaml` through the shared state-machine helper; write the row, the outbox event (envelope schema) and the audit record (`audit` schema: actor, capability, target, before/after revision — no personal payloads) **in the same transaction**.
6. **Errors**: raise `ProblemError(code=...)` only with codes from `contracts/errors/problems/*.yaml`; validation errors map to `VALIDATION_FAILED` with `errors[]`.
7. **Telemetry**: route template (not raw path) as span name, `tenant_id` as attribute, request_id in logs; no bodies, SQL or personal data logged; RED metrics from `packages/telemetry`.
8. **Tests** (`services/api/tests/`):
   - Contract: response validates against OpenAPI schema (openapi-core / Schemathesis stateful for the domain).
   - Happy path, validation errors, each problem code the operation declares, idempotent replay, stale If-Match 412, pagination (boundaries, stable order, tampered cursor → 400).
   - Authorization: every role without the capability → 403; `tenant-isolation-tests` API rows.
   - Transactional: failure after DB write rolls back row + outbox + audit together.
9. `make lint typecheck test-unit test-integration-pg test-security` green; Spectral/contract checks green.
