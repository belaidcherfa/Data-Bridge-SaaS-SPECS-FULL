# Workload intelligence and execution hierarchies

Canonical domain contract. Owner: Data engineer / Frontend. Implementation state: NOT_STARTED.


## Classification and identity

Classification outputs tenant/account/query, workload_type, application, project, environment, execution_id, model/resource, parent/root references, evidence_type, confidence and parser_version. Prefer explicit validated structured tags/native execution IDs; enrich with session client application and approved SQL comments; use query type only as a weak fallback. Preserve conflicting evidence rather than forcing certainty. Rules and custom metadata are versioned. Source query hash and hash version remain distinct from any Bridge text fingerprint.

Do not require customer JSON artifact uploads for baseline dbt detection. Session client application identifies dbt where present; structured comments may expose project/model/environment and optionally invocation/materialization. Missing invocation means execution grouping unknown, not an invented exact run. Optional approximate session/time groups are clearly labelled and excluded from exact run metrics. dbt Core/Cloud/in-Snowflake/Fusion activity are detected by observed evidence, not assumed from version strings alone.

Power BI identifies Import/DirectQuery and ActivityId only from supported explicit metadata. Missing Power BI activity/report/dataset links remain unknown. Snowflake queries cannot reveal full Fabric CU or report rendering cost; label monetary results as Snowflake-side components. Do not introduce a Microsoft API credential requirement into the baseline source-only feature.

Task/procedure/dynamic-table/native-app/SPCS/Cortex/custom/ad-hoc workloads use verified execution IDs and parent/root fields where available. Parent and child executions form evidence graphs, but a query cost belongs once in financial attribution. A high-level invocation totals its distinct leaf/query charge links; shared resources/unattributed cost remain explicit. Resource identity includes account and instance where documented.

## Workload metrics

Cost/execution, cost/model, executions, querycount, wall-clock duration, execution sum, P50/P95, failures, queue, compilation, bytes/rows, repeat frequency and regression use declared populations. Wall-clock invocation duration is max(end)-min(start) for a complete invocation, not sum of concurrent query durations. Cross-period comparison shows common/new/disappeared entities and separates run volume from per-run unit cost. Missing history cannot prove deletion or inactivity.

## Drilldown and evidence

Workloads → type → project/application → environment → invocation/activity/task graph → model/hash → query. Each level keeps scope, period, status and metric definitions. dbt unassigned-project/unassigned-invocation buckets and PBI unknown mode are first-class filters. Users can pivot by account/warehouse/user/role/custom tags without losing hierarchy.

Deep evidence such as GET_QUERY_OPERATOR_STATS is on-demand, permission- and retention-gated, sanitized and bounded. A failure to fetch a plan does not invalidate observed query cost. Never promise operator evidence for all one-year-old queries. Preserve evidence confidence; correlations are hypotheses, not causal proof.


The current [GET_QUERY_OPERATOR_STATS contract](https://docs.snowflake.com/en/sql-reference/functions/get_query_operator_stats) covers completed queries from the past14 days and requires OPERATE or MONITOR on the warehouse. Verify MONITOR suffices for the selected customer evidence path and do not extend one-year history claims to query plans.


## Implementation sequence

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [WRK-001](../tasks/WRK/WRK-001.md) | Implement versioned workload classifier and evidence model | DBT-003, SEC-007, API-001 | M5 |
| [WRK-002](../tasks/WRK/WRK-002.md) | Build dbt project, invocation and model intelligence | WRK-001, UX-005 | M5 |
| [WRK-003](../tasks/WRK/WRK-003.md) | Build Power BI activity and mode intelligence | WRK-001, UX-005 | M5 |
| [WRK-004](../tasks/WRK/WRK-004.md) | Build tasks, procedures and other workload execution graphs | WRK-001, FIN-013, UX-005 | M5 |
| [WRK-005](../tasks/WRK/WRK-005.md) | Implement workload comparison and on-demand deep evidence | WRK-002, WRK-003, WRK-004, API-004 | M5 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.
