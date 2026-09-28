---
name: migration-safety
description: Write PostgreSQL (Alembic) and Snowflake migrations that are safe for zero-downtime rolling deploys and multi-tenant data — expand/migrate/contract, lock-safe DDL, RLS on every new table, backfills in batches, reversible steps, tests. Use for any schema change.
---

# Migration safety

## PostgreSQL (Alembic in `services/<svc>/migrations/`, DDL source of truth in `contracts/postgres/`)
- The contract DDL and the Alembic revision change together; CI compares the migrated schema with the contract (`make test-contract`).
- **Expand → migrate → contract** (REL-101): add nullable column / new table → deploy code that writes both → backfill → switch reads → later release drops old. Never rename or drop in the same release as code that depends on the old shape.
- Lock-safe DDL: `SET lock_timeout = '3s'` and `statement_timeout` in every migration; `CREATE INDEX CONCURRENTLY` (in its own non-transactional revision); add `NOT NULL` via `CHECK (...) NOT VALID` → `VALIDATE CONSTRAINT` → `SET NOT NULL`; add FKs `NOT VALID` then validate; no volatile defaults that rewrite tables.
- Every new tenant table: CONVENTIONS §10 columns, composite PK/FK with `tenant_id`, `ENABLE` + `FORCE ROW LEVEL SECURITY`, policy from the SEC template, grants to `bridge_app` only; migration fails if RLS is missing (CI catalog check).
- Backfills: batched by `(tenant_id, id)` keyset, ≤ 5 000 rows per transaction, resumable, idempotent, run as a worker job — not inside the Alembic transaction.
- Downgrade: provide `downgrade()` for expand steps; contract steps are irreversible and say so.
- Status columns: `CHECK (status IN (...))` regenerated from the state machine; widening a CHECK is a two-step (add new constraint NOT VALID, validate, drop old).

## Snowflake (`infra/snowflake/migrations/`)
- Forward-only versioned files in your lane's block; re-runnable (`IF NOT EXISTS`, `CREATE OR ALTER` where allowed); DDL auto-commits — never mix DDL into a transaction that must be atomic (ADR-014).
- Data tables are never `CREATE OR REPLACE`d; column additions are nullable; type changes go through a new column + backfill model.
- Serving views change only through a new `serving_schema_version` namespace; old namespace kept until no pin references it.
- Grants and policies in the same file; the grant-audit test must show no extra privilege.

## Tests
- Upgrade from the previous release schema with fixture data (testcontainers), then downgrade where supported, then upgrade again.
- Lock test: run the migration while a fixture workload holds row locks; it must fail fast (lock_timeout) rather than block.
- RLS catalog test and `tenant-isolation-tests` PostgreSQL rows for new tables.
- Snowflake: apply twice in DEV (idempotence), grant audit, rollback plan documented in the PR.
