---
name: tenant-isolation-tests
description: Write the mandatory multi-tenant isolation tests (PostgreSQL RLS, API tenant header/membership, Snowflake row access policies through the query broker, caches, jobs, events, exports, logs) for any tenant-scoped change. Use whenever a change reads or writes tenant-owned data.
---

# Tenant isolation test kit

Tenant leakage is the one defect that ends the company. Every tenant-scoped change ships these tests; reviewers reject PRs without them.

## Fixture tenants (use exactly these)
`data/fixtures/tenants/`: **TENANT_A** (Enterprise org, 2 accounts), **TENANT_B** (Standard, 1 account, *same Snowflake object names as A*), **TENANT_C** (suspended/offboarding), user **U_AB** member of A and B with different roles, user **U_REVOKED** removed from A during the test. Same-named objects in A and B are deliberate: a test that passes only because names differ is worthless.

## Matrix — apply every applicable row
| Layer | Must prove | How |
|---|---|---|
| PostgreSQL | Foreign-tenant rows invisible and unwritable; missing `app.tenant_id` → zero rows or error (never all rows); `SET` not `SET LOCAL` rejected by helper; FK cannot reference a foreign parent | pytest + testcontainers, connect as `bridge_app` (non-owner, no BYPASSRLS); assert `FORCE` RLS on every new table via catalog query |
| API | Wrong `X-Bridge-Tenant` → non-enumerating 404; missing header → 400 `TENANT_HEADER_REQUIRED`; echo header equals request; U_AB switching tenants never sees A data under B; revoked member → 403 on next request (session epoch); machine token bound to A with header B → 403 | httpx AsyncClient against app with seeded PG |
| Object IDs | Guessing another tenant's UUID gives the same 404 as a nonexistent ID (timing and body identical modulo request_id) | parametrized tests |
| Snowflake serving | Broker session for A returns only A rows from every SERVING view; `CURRENT_ROLE()` profile role only, secondary roles off; a query without broker context fails closed | DEV live gate + fixture-mode unit tests of the broker's statement builder (no string interpolation of tenant IDs) |
| Cache (Valkey) | Keys include tenant, profile, epoch, publication_id; after epoch bump or revocation the old entry is unreachable | unit + integration |
| Jobs/workers | Job payload carries tenant_id; worker sets tenant context before any read; a job for C (suspended) is refused | integration |
| Events/outbox | Consumer of A's event cannot load B's aggregate; dedupe key includes consumer | integration |
| Exports/reports/notifications | Rendered artifact contains only A data; S3 key prefix per tenant; presigned URL scoped and short-lived; notification destination belongs to A | integration + content assertions |
| Logs/telemetry | No foreign tenant IDs, no PERSONAL/SQL_TEXT values in log lines produced during the test | capture structlog output, assert with the log schema |

## Rules
- Tests assert on **absence of foreign data with identical names**, not only on counts.
- Always include the negative control: the same query in tenant A returns A's rows (a test that returns nothing for everyone proves nothing).
- Name tests `test_isolation_<layer>_<scenario>`; mark `@pytest.mark.security`; they run in `make test-security` and block merge.
- Property-based variant (Hypothesis) for query builders: random filters never produce SQL without the tenant predicate/role context.
- New table or view without an isolation test = review finding "blocking".
