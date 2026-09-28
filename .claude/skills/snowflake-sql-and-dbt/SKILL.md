---
name: snowflake-sql-and-dbt
description: How to write Snowflake migrations, extraction SQL, dbt models/tests/materializations and broker queries for Bridge — revisioned insert-only facts, publication, row access policies, WIF sessions, query tags, cost control, fixture-mode tests. Use for SEC-Snowflake, ING, DBT, ORC, FIN, ALC, INS SQL work.
---

# Snowflake SQL and dbt

Required reading for the task at hand: ADR-001, ADR-005 (+ amendment: tenant WIF user + per-profile role, `CURRENT_ROLE()`-only row access policies, `DEFAULT_SECONDARY_ROLES=()`), ADR-014 (revisions/publication), ADR-015, `data/contracts/datasets.yaml`, `data/contracts/sources/*.yaml`, CONVENTIONS §11.

## Sessions (every connection)
- Auth: `authenticator='WORKLOAD_IDENTITY'` (AWS) for services and dbt (dbt-snowflake ≥ 1.12). No passwords, no key-pair files in code, no tokens in env files.
- Session parameters: `TIMEZONE='UTC'`, `QUERY_TAG` JSON per `data/contracts/query_tag.schema.json` (tenant_id, build_id or request_id, component, task), `STATEMENT_TIMEOUT_IN_SECONDS` per role, `USE_CACHED_RESULT` as the contract says; connector `arrow_number_to_decimal=True`; Parquet with `USE_LOGICAL_TYPE=TRUE`.
- Always bind parameters (`%(name)s` / `?`); never format identifiers or values from input into SQL. Identifiers come from allowlisted registries and are quoted with the shared helper.

## Migrations (`infra/snowflake/migrations/<SCHEMA>/V<NNNN>__<desc>.sql`)
- Version number inside your lane's block (contracts/README.md). Idempotent where Snowflake allows (`CREATE … IF NOT EXISTS`, `CREATE OR ALTER` for tables/views only when the contract says so); never `CREATE OR REPLACE TABLE` on data tables.
- Grants live in the same migration as the object, to roles (never users), least privilege; readers never get RAW/CONTROL/CONFIG/SECURITY.
- Row access policies attach to base tables of serving datasets; masking policies for `PERSONAL`/`SQL_TEXT` columns where the data contract says so.
- Every object has `COMMENT` naming owner task and contract. Serving views are versioned namespaces (`serving_schema_version`), deployed by release migrations, never by dbt.

## Extraction SQL (customer accounts, ING)
- Completion-time windows on `END_TIME` for query sources, half-open `[from, to)`, with overlap/lag per source contract; dedupe by natural key downstream.
- Read only views granted by the customer setup script; missing privilege → capability `DENIED` + unknown reason, never an error that aborts the whole cycle.
- Customer warehouse cost: bounded windows, `LIMIT` by pages, statement timeout, warehouse from connection config only. Trial accounts are demo-only (D-35).

## dbt (`data/dbt`)
- Layers: `staging` (views, read-time dedupe over accepted RAW with `accepted_seq <= snapshot_seq`) → `intermediate` → `ledger/allocation/marts` facts materialized with the custom **`revisioned`** materialization (insert-only; never `merge`, `delete+insert`, `insert_overwrite`, `microbatch`, `--full-refresh`).
- Only variable: `build_id`. Worksets come from `BUILD_WORKSET`; tenant configuration from `BUILD_CONFIG_PIN`. Multi-tenant set-based SQL; no per-tenant loops, no Jinja loops over tenants.
- Model contracts (`contract: enforced: true`) with exact types (`NUMBER(38,12)` money, `TIMESTAMP_NTZ` UTC, `VARCHAR` sized); every model has `unique`/`not_null`/relationship check models where Snowflake does not enforce keys; tenant-scoped invariants write PASS/FAIL rows into `QUALITY.CHECK_RESULT` (absence = FAIL).
- Clustering per `datasets.yaml` (`tenant_id, partition_start`); order inserts by the clustering key.
- sqlfluff (dbt templater) clean; `dbt build --select state:modified+` against fixtures (`make dbt-build-fixtures`).

## Publication and reads
- Never write publication tables except through `PUBLISH_BATCH` / `REPUBLISH_PRIOR` (ORC-005 owns them). Readers pin `pub_seq` and filter `_pub_from <= :pin AND :pin < _pub_to`.
- API/UX reads go through the query broker only (ADR-005 amendment); the broker's statement builder is the only place SQL for serving is assembled.

## Tests
- Fixture mode (no Snowflake): SQL compiled and parsed with sqlglot (Snowflake dialect), golden results computed from `data/fixtures/` with DuckDB only where semantics are identical — otherwise mark the test `live` and hand it to the DEV live gate (skill `live-gate-handoff`).
- Live (DEV sandbox only, cost-capped): migrations apply cleanly twice, grants audit shows no extra privileges, RAP isolation (skill `tenant-isolation-tests`), revision retry idempotency, publish CAS/fencing.
- Record credits consumed by live tests in the evidence manifest; stop and escalate above the packet's credit budget.
