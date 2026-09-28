---
name: evidence-capture
description: Write the evidence manifest for a task (docs/evidence/<ID>/<short-sha>/index.json) with environment, versions, commands, exit codes, expected vs observed and artifact checksums. Use at the end of every task and after live gates.
---

# Capture evidence

Path: `docs/evidence/<TASK-ID>/<short-sha>/index.json` (schema `docs/evidence/schema/evidence.schema.json` once FND-005 lands). Fields:
`task_id, commit, branch, environment (local|ci|test-estate|staging), started_at, ended_at (UTC), tool_versions {python, node, uv, pnpm, dbt, dagster, snowflake-connector, terraform…}, model, fixture_ids[], commands[{cmd, exit_code, duration_ms, summary}], oracles[{step, expected, observed, pass}], artifacts[{path_or_uri, sha256}], remaining_gates[], reviewer (filled at merge)`.
Rules: no secrets, no customer data, no personal data; large logs go to CI artifacts and are referenced by URI + checksum; expected values are the fixture values, not re-computed by the code under test.
