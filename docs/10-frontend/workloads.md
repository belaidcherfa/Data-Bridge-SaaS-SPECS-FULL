# Workload intelligence and execution hierarchies

Canonical domain contract. Owner: Data engineer / Frontend. Implementation state: NOT_STARTED.


## Classification and identity

Classification outputs tenant/account/query, workload_type, application, project, environment, execution_id, model/resource, parent/root references, evidence_type, confidence and parser_version. Prefer explicit validated structured tags/native execution IDs; enrich with session client application and approved SQL comments; use query type only as a weak fallback. Preserve conflicting evidence rather than forcing certainty. Rules and custom metadata are versioned. Source query hash and hash version remain distinct from any Bridge text fingerprint.

(amended 2026-09-28, D-34, G-WRK-07) The classifier is **set-based dbt SQL** over structured evidence (WRK-001), revisioned under D-05 so a late SESSIONS row re-classifies the query in the next build; a pure Python `classify()` is kept only as the reference oracle for differential tests. This refines PRD §53–§54: `PY_WORKLOAD_CLASSIFICATION` is replaced by `fct_query_workload`. Confidence is an evidence class — VERIFIED (native linkage: task or dynamic-table query ID, parent/root query, Bridge's own identity) > DECLARED_CORROBORATED (structured comment or tag matching the session application) > DECLARED > OBSERVED (session application only) > INFERRED > UNKNOWN; disagreeing candidates at DECLARED or above set `conflict=true`. Comments and tags are declared evidence, never trusted identity, so a spoofed tag cannot move cost silently. "Bridge overhead" (D-08) is identified from warehouse and user identity before pseudonymization.

(amended 2026-09-28, G-WRK-01, G-WRK-15) Workload metadata extraction is **irreversible and ships with the sanitizer at M1** (phase P1): the WRK-101 library (`extract(query_text, query_tag, policy)`) runs as step 1 of the SEC-007 sanitizer and keeps only the versioned allowlist v1 (dbt keys such as `app`, `dbt_version`, `profile_name`, `target_name`, `node_id`, `invocation_id`, `connection_name`, `project_name`, `materialized`; Power BI keys such as `PowerQuery`, `Host`, `HostContext`, `ActivityId`; Bridge's own key), never owner e-mails, `invocation_command` or free-text run reasons. The allowlist is frozen before the first customer backfill; fields not extracted then cannot be recovered beyond Account Usage's 365 days ([WRK backlog](../22-implementation-readiness/backlog/WRK.md) §3).

Do not require customer JSON artifact uploads for baseline dbt detection. Session client application identifies dbt where present; structured comments may expose project/model/environment and optionally invocation/materialization. Missing invocation means execution grouping unknown, not an invented exact run. Optional approximate session/time groups are clearly labelled and excluded from exact run metrics. dbt Core/Cloud/in-Snowflake/Fusion activity are detected by observed evidence, not assumed from version strings alone.

Power BI identifies Import/DirectQuery and ActivityId only from supported explicit metadata. Missing Power BI activity/report/dataset links remain unknown. Snowflake queries cannot reveal full Fabric CU or report rendering cost; label monetary results as Snowflake-side components. Do not introduce a Microsoft API credential requirement into the baseline source-only feature.

Task/procedure/dynamic-table/native-app/SPCS/Cortex/custom/ad-hoc workloads use verified execution IDs and parent/root fields where available. (amended 2026-09-28, C-10, D-20) TASK_HISTORY and DYNAMIC_TABLE_REFRESH_HISTORY are R1 sources (ING-104) and QUERY_ATTRIBUTION_HISTORY carries PARENT_QUERY_ID and ROOT_QUERY_ID (ING-101); Power BI (WRK-003) is R1. Parent and child executions form evidence graphs, but a query cost belongs once in financial attribution. A high-level invocation totals its distinct leaf/query charge links; shared resources/unattributed cost remain explicit. Resource identity includes account and instance where documented.

## Workload metrics

Cost/execution, cost/model, executions, querycount, wall-clock duration, execution sum, P50/P95, failures, queue, compilation, bytes/rows, repeat frequency and regression use declared populations. (amended 2026-09-28, D-11, G-WRK-08) Query-level detail is retained 365 days (`hot_days`, plan-configurable); execution-level facts (dbt invocations and model executions, Power BI activities, task-graph runs, dynamic-table refreshes, each with cost, query count, wall time, execution sum and status) are retained 400 days (WRK-104); the query-family × day aggregate `fct_query_family_daily` keeps t-digest/HLL sketch states, attributed credits, spill and dominant identity for 400 days. The UI labels which tier a view reads. Wall-clock invocation duration is max(end)-min(start) for a complete invocation, not sum of concurrent query durations. Cross-period comparison shows common/new/disappeared entities and separates run volume from per-run unit cost. Missing history cannot prove deletion or inactivity.

## Drilldown and evidence

Workloads → type → project/application → environment → invocation/activity/task graph → model/hash → query. Each level keeps scope, period, status and metric definitions. dbt unassigned-project/unassigned-invocation buckets and PBI unknown mode are first-class filters. Users can pivot by account/warehouse/user/role/custom tags without losing hierarchy.

Deep evidence such as GET_QUERY_OPERATOR_STATS is on-demand, permission- and retention-gated, sanitized and bounded. (amended 2026-09-28, G-WRK-09) It executes in the customer account on `BRIDGE_FINOPS_WH` and costs customer credits (60-second minimum per resume), needs MONITOR on every customer warehouse, is batched per account within 60 s, shows the estimated credits before running, and is stored as a sanitized evidence artifact (30-day TTL), not as analytical data (WRK-103, R2). A failure to fetch a plan does not invalidate observed query cost. Never promise operator evidence for all one-year-old queries. Preserve evidence confidence; correlations are hypotheses, not causal proof.


The current [GET_QUERY_OPERATOR_STATS contract](https://docs.snowflake.com/en/sql-reference/functions/get_query_operator_stats) covers completed queries from the past14 days and requires OPERATE or MONITOR on the warehouse. Verify MONITOR suffices for the selected customer evidence path and do not extend one-year history claims to query plans.


## Implementation sequence

(amended 2026-09-28) The dependency and gate columns below are the original index. Execution follows the revised graph ([revised-task-graph.json](../22-implementation-readiness/revised-task-graph.json), [revised critical path](../22-implementation-readiness/REVISED_CRITICAL_PATH.md)) and phases P0–P6 of the [release plan](../22-implementation-readiness/RELEASE_PLAN.md); new tasks, revised steps, dependencies and task acceptance are in [backlog/WRK.md](../22-implementation-readiness/backlog/WRK.md).

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [WRK-001](../tasks/WRK/WRK-001.md) | Implement versioned workload classifier and evidence model | DBT-003, SEC-007, API-001 | M5 |
| [WRK-002](../tasks/WRK/WRK-002.md) | Build dbt project, invocation and model intelligence | WRK-001, UX-005 | M5 |
| [WRK-003](../tasks/WRK/WRK-003.md) | Build Power BI activity and mode intelligence | WRK-001, UX-005 | M5 |
| [WRK-004](../tasks/WRK/WRK-004.md) | Build tasks, procedures and other workload execution graphs | WRK-001, FIN-013, UX-005 | M5 |
| [WRK-005](../tasks/WRK/WRK-005.md) | Implement workload comparison and on-demand deep evidence | WRK-002, WRK-003, WRK-004, API-004 | M5 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.
