---
name: author-contract
description: Create or change an executable contract (JSON Schema, OpenAPI path, problem codes, event types, state machine, PostgreSQL DDL, Snowflake migration, data contract) following contracts/CONVENTIONS.md, with examples, manifest and hand-offs. Use for contract-first micro-steps, contract-change escalations and the K-lane contract tasks.
---

# Author or change a contract

Read `contracts/CONVENTIONS.md` and `contracts/README.md` (ownership map, Snowflake version blocks) first. A contract is a promise other agents code against in parallel: be precise, closed and testable.

## 1. Decide where it lives (CONVENTIONS §1)
| Kind | Location | Validation |
|---|---|---|
| Shared value types | `contracts/common/*.schema.json` | JSON Schema 2020-12, `$id urn:bridge:schema:<area>:<name>:v<major>` |
| HTTP API | `contracts/openapi/paths/<domain>.yaml`, `components/schemas/<domain>.yaml` referenced from `openapi.yaml` | Spectral (`contracts/.spectral.yaml`), Redocly bundle, Schemathesis later |
| Errors | `contracts/errors/problems/<domain>.yaml` (`code`, `http_status`, `title`, `retryable`, `detail_template`, `owner_task`) | unique codes (check.py) |
| Events | `contracts/events/catalog/<domain>.yaml` + payload schema `contracts/events/schemas/<type>.v<N>.schema.json` | unique types, envelope conformance |
| Lifecycles | `contracts/state-machines/<machine>.yaml` (CONVENTIONS §9 format) | reachability, terminal, undeclared events |
| Authorization | `contracts/authz/capabilities.yaml` (+ role bundles) | every endpoint cites a capability |
| PostgreSQL | `contracts/postgres/<schema>[.<part>].sql` | real PG parser (pglast) + apply in CI |
| Snowflake | `infra/snowflake/migrations/<SCHEMA>/V<NNNN>__<desc>.sql` in your lane's version block | sqlglot Snowflake + live apply in DEV |
| Data | `data/contracts/**` (sources, datasets, metric/detector registries) | JSON Schema + dbt contracts |

Owner: exactly one task/lane per file (README map). Editing another lane's file = handoff note in `contracts/_handoffs/<from>-to-<to>.md` + `contract-change` escalation, never a silent edit.

## 2. Write it
- Header on every file: `status: DRAFT|ACCEPTED|DEPRECATED`, `owner_task`, `version`, `sources` (spec sections / ADR / decision IDs it implements). For JSON use `$comment`; for YAML/SQL a leading comment.
- Close shapes: `additionalProperties: false`, explicit `required`, enums closed, formats (`uuid`, `date-time`), string patterns, `maxLength`/`maxItems` on everything user-controlled.
- Money/quantities/unknowns/maturity: `$ref` the common schemas — never re-declare. IDs UUIDv7; deterministic IDs use UUIDv5 namespaces from `contracts/common/namespaces.yaml`.
- Every field in data/event/log schemas carries `x-privacy` (CONVENTIONS §12).
- Tenant-owned PG tables: CONVENTIONS §10 columns, composite PK/FK with `tenant_id`, `ENABLE`+`FORCE` RLS, policy from the SEC template, status `CHECK` generated from the state machine, indexes for every documented access path.
- Snowflake: ADR-014 revisioned insert-only facts; grants in the same migration; row access policy for serving base tables; `COMMENT` on every object.
- Examples: at least one valid and one invalid example per schema (`examples` or `contracts/<area>/examples/`), plus a foreign-tenant example for tenant-scoped payloads.

## 3. Prove it
`make contracts-check` (0 errors), Spectral for OpenAPI, and — when the consuming package exists — a round-trip test. For DDL, apply to the local Compose database (`make up`) and run the RLS smoke test from `tenant-isolation-tests`.

## 4. Record it
- Manifest `contracts/_manifests/<lane>.yaml`: every file you own, with `status`, `owner_task`, `consumers` (task IDs), `version`. Packet generation reads it (`contracts_read`).
- Open questions → `contracts/_handoffs/<lane>-open-questions.md` (never TODOs inside a contract).
- Move to `ACCEPTED` only when the owning task's reviewer approves; after that, changes are additive within the major version or go through a `contract-change` escalation with a consumer impact list.
