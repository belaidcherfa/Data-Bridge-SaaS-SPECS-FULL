---
name: observability-and-runbooks
description: Add metrics, traces, structured logs, SLOs, alerts, dashboards and runbooks for a Bridge component using the telemetry registries — no PII, every alert owned and actionable. Use when a packet mentions telemetry, SLO, alert, runbook, on-call or incident, and for every new service or job type.
---

# Observability and runbooks

Read D-31 (control plane 99.9 %, analytics 99.5 %), D-37 (EU business-hours support + best effort), the OPS backlog, `infra/observability/slo/slo-catalog.yaml`, `packages/telemetry` registries.

- **Registries first**: new metric names, log event names and span attributes are added to `packages/telemetry/registry/*.yaml` (name, type, unit, labels with bounded cardinality, owner task, privacy class). Code uses generated constants — no string literals for metric names.
- **Logs**: structlog JSON per `packages/telemetry/schema/log-event.v1.json`; fields: timestamp, level, event, service, version, request_id/job_id, tenant_id, trace_id. Never SQL text, personal data, tokens, raw payloads. Tests assert the log schema.
- **Metrics**: RED for request paths (rate, errors, duration by route template), USE for queues/pools; tenant_id is **not** a metric label (cardinality) except in the per-tenant fairness metrics explicitly registered.
- **Traces**: OpenTelemetry spans across API → broker → Snowflake statement ID (as attribute), API → job → worker; sampling per environment.
- **SLOs**: define SLI query, objective, window and error-budget policy in the SLO catalog; burn-rate alerts (fast 1 h/5 m, slow 6 h/30 m).
- **Alerts**: each alert has `severity`, `owner`, `runbook_url`, tags required by `infra/policy/alarm-tags.rego`; page only on customer-visible SLO burn or data-integrity risk; everything else is a ticket. Out of EU business hours: best effort (D-37), so auto-remediation and safe degradation matter.
- **Runbook** `docs/runbooks/<component>/<alert>.md`: symptom, impact, dashboards, diagnosis steps (commands, queries — read-only first), mitigation, escalation, customer communication template, follow-up. Tested in game days (OPS).
- **Dashboards** as code (`infra/observability/dashboards/`), one per service plus the tenant-health view.
- **Tests**: metric emitted on the path (unit with in-memory exporter), alert rule syntax check, runbook link exists (CI).
