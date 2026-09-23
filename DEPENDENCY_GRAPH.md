# Dependency graph

This graph defines construction dependencies, not navigation order. A milestone exit requires accepted implementation evidence. Documentation can be researched earlier without authorizing premature implementation.

```mermaid
flowchart TD
  M0["M0 Engineering foundation"] --> M1["M1 Secure control plane"]
  M1 --> M2["M2 Snowflake connectivity"]
  M2 --> M3["M3 Durable ingestion"]
  M3 --> M4["M4 Reconciled financial kernel"]
  M4 --> M5["M5 Cost and workload observability"]
  M5 --> M6["M6 Ownership and allocation"]
  M6 --> M7["M7 Governance and reporting"]
  M5 --> M8["M8 Insights and verified savings"]
  M7 --> M9["M9 Operational qualification"]
  M8 --> M9
  M9 --> M10["M10 Production readiness"]
  M10 --> M11["M11 First customer"]
  M11 --> M12["M12 First production release"]
```

## Contract-level ordering

| Before | Required after | Reason |
|---|---|---|
| Tenant model, RBAC, PostgreSQL RLS | Any tenant configuration CRUD | Avoid retrofit of authorization |
| Account-specific WIF and capability scan | Source activation | Discovery is not permission to query everything |
| Source contract and privacy policy | Extraction query | Decide legal columns, timestamps and sanitization before storage |
| Parquet schema + batch manifest + checkpoint rules | Historical synchronization | Durable replay and completeness must already exist |
| RAW load receipts + manifest acceptance | dbt staging publication | Partial files cannot become a complete dataset |
| Additive ledger + billing reconciliation | Authoritative cost APIs | Query attribution is not a second charge |
| Semantic registry + serving isolation | Customer financial screens | UI formulas and authorization cannot diverge |
| Resource identity + tags + group sets | Allocation simulation | Rules need stable, versioned scope |
| Allocation conservation + reconciliation | Chargeback close | Cannot issue a traceable statement from unstable totals |
| Complete source coverage + baselines | Anomaly/savings assertions | Missing data must not look like savings |
| Notification outbox + destinations | Scheduled monitors/reports | No alert can depend on a best-effort HTTP call |
| Recovery, security, performance evidence | Customer production onboarding | Availability and isolation are release gates |
| Customer consent + paid entitlement + value evidence | First paid release | A deployed environment is not a paying customer |

## Task graph rules

The implementation task index will contain stable task IDs, paths, exact prerequisite IDs, milestone and status. Canonical graph validation rejects unknown prerequisites, cycles, duplicate IDs, missing files and unmet milestone ordering. Numeric order is a recommended topological execution order; dependency edges are authoritative. Distinct tasks may proceed independently only after shared contracts are accepted.

Cross-cutting security, telemetry, fixtures and CI start in M0/M1. M9 qualifies these controls; it does not postpone their implementation until launch. Onboarding UX starts with connection capability work and is completed by the first-customer flow.
