# Evidence-backed insights, actions and verified savings

Canonical domain contract. Owner: Data science / FinOps / Frontend. Implementation state: NOT_STARTED.


## Intelligence contract and ownership

Python owns robust statistics, classification and optimization heuristics; dbt owns deterministic feature tables and aggregates. Dagster schedules versioned engine runs and materializes outputs through the same journal/acceptance contracts. PostgreSQL stores assignment/status/actions; analytical evidence, predictions and savings observations stay in Snowflake. No recommendation changes a customer Snowflake object. Future automation/Copilot requires a separate approved scope, permission model and ADR.

Every insight has tenant/scope/resource, type and rule version, first/last seen, baseline/current windows, metric/input publication, evidence IDs, sample count, estimated monetary impact with currency/horizon, confidence method, severity, effort, owner and recommended action. Stable detection fingerprint prevents repeat insights on replay; a new observation appends history. Required lifecycle: Detected → Reviewed → Assigned → Planned → Implemented → Verifying → Validated, with Dismissed, Accepted Risk and Not Applicable carrying reason/actor/expiry where relevant. State transitions are version checked and audited. Validation requires evidence, not merely a click.

The deep dive presents what happened, why it is suspected, when, financial impact, evidence, history, contributors, affected resources and a reversible recommended action. Label correlation and estimated impact honestly. Resource overlaps are grouped into mutually exclusive opportunity sets: rightsizing and suspension of the same idle credits cannot both inflate the opportunity total. Suppress a numerical estimate when required utilization or rates are unavailable.

## Eligibility and guardrails

Default recurring-pattern detector: at least 14 complete comparable daily observations; seasonal detector requires 28. These are initial product thresholds, configurable and versioned after backtesting, not statistical guarantees. No-usage claims require complete access evidence for the entire declared window; absence of permission or history is not proof an object is unused. Never recommend dropping a table automatically. Fail-safe retention is governed by Snowflake behavior; do not promise instant reclamation. Adaptive and standard warehouses have different supported metrics.

[Operator statistics](https://docs.snowflake.com/en/sql-reference/functions/get_query_operator_stats) are available for completed queries in the documented 14-day window and require OPERATE or MONITOR on the warehouse. Prefer read-oriented MONITOR where sufficient; verify the exact customer grant. Sanitize retrieved attributes and retain bounded evidence only. Operator percentages describe execution-time components, not credit allocation weights.

## Savings measurement

Freeze baseline version, intervention date, population, volume normalizer, rate basis, exclusion policy, horizon and overlap group before verification. Expected cost = baseline cost per normalized unit × observed post-change units, adjusted only by documented approved covariates. Realized savings = expected cost − observed comparable cost, with confidence/coverage and signed negative outcomes retained. Do not sum different currencies or overlapping actions. Financial close and causal confidence are different axes. A reconciled bill does not prove an action caused the change.

Golden fixture: baseline 100 executions costing200 USD gives2/execution. Post-change 120 executions cost180. Counterfactual240; normalized saving60, not20 from an unadjusted period difference. A second overlapping action cannot claim another60. Estimated opportunity80 remains separate from verified60. With only80% post-period coverage, status stays Verifying and the verified total excludes the incomplete result. A cost increase to260 produces−20, not zero.


## Detector registry for initial implementation

The following derived feature names are Bridge contracts, not invented Snowflake columns. Each detector declares the verified source projection that supplies its inputs during activation. All recurring detectors require complete declared coverage, authorized resource scope, compatible currency/rate basis and the shared monetary impact floor from the [governance contract](../12-budgets-monitoring/governance.md); row-specific sample/window rules override the generic14-day minimum. Operator-only checks use available completed-query evidence and are explicitly not recurring-trend claims. Equality at a strict threshold does not qualify. These starting heuristics produce review candidates, not guaranteed savings or automatic customer changes.

Each registry row is independently switchable and versioned under its family implementation task. Implement its positive fixture, boundary/equality fixture, missing-capability fixture and false-positive fixture as separate micro-step checkpoints. The common INS-001 publisher and INS-006 workflow are reused, not reimplemented per detector.

| ID | Candidate | Exact initial eligibility / predicate | Independent fixture / guardrail |
|---|---|---|---|
| WH01 | Idle | Valid classic idle/metered cost >25% for14 complete days | 60/200=30% qualifies; potential saving cannot exceed60 |
| WH02 | Auto-suspend | Measured idle intervals plus known auto-suspend setting above300s or disabled; repeated at least3 times | Three600s idle gaps qualify; absent settings suppress the setting recommendation |
| WH03 | Rightsizing | Low measured load and no queued overload for14 days; candidate experiment only, conditioned on workload latency objective | Low-load warehouse proposes a controlled test; estimated saving null until size/runtime evidence exists |
| WH04 | Under-utilization | Classic idle ratio>50% with at least14 complete days; no invented CPU percentage | 120 idle/200 compute=60% qualifies; Adaptive null attribution suppresses |
| WH05 | Multi-cluster excess | Configured max clusters>1 with measured peak active clusters below configured maximum throughout14 days | Max4/observed peak1 qualifies as capacity-review candidate, not proof of fourfold saving |
| WH06 | Concurrency mismatch | Observed queue-time share>20% for at least3 complete daily cohorts with at least100 queries each | Queue30s/total100s qualifies; no sizing prescription without runtime evidence |
| WH07 | Resume/suspend thrashing | At least6 verified resume events/hour in3 distinct hours with median active interval<5min | Six cycles qualify; missing event history suppresses |
| WH08 | Consolidation | Two compatible workload scopes each have idle>50%, nonoverlapping measured peak windows and compatible security/SLA policy | Incompatible isolation requirement suppresses even if both are idle |
| Q01 | Cost regression | Comparable query family cost/execution rises>20% and meets monetary impact floor over14-day baseline/current cohorts | 2→3 per execution is+50%; separate execution-volume effect |
| Q02 | Frequency regression | Executions/day rises>50% with stable supported workload identity | 10→20/day qualifies; missing invocation never invents run count |
| Q03 | Spill | Verified nonzero remote spill in at least3 executions of a family; cost floor applies | Three1GiB spill observations qualify; do not convert spill bytes directly to saved credits |
| Q04 | Poor pruning | Partition scan fraction>80% plus operator evidence of selective result (<10% rows retained), in3 executions | 90/100 scanned and1% retained qualifies; missing operator counts suppresses |
| Q05 | Exploding join | Verified join output/max(left input,right input)>10 for a completed query with meaningful cost | 2000 output/max100 inputs=20 qualifies; zero/unknown denominator suppresses |
| Q06 | Compilation overhead | Compilation/(compilation+execution)>50% for100+ family executions over14 days | 600ms/(600+400)=60%; this is elapsed-time evidence, not direct credit attribution |
| Q07 | Cloud-services anomaly | Service-level signed cloud usage exceeds robust monitor policy; query-level detail only explains contributors | Daily signal qualifies; never allocate a universal cloud deduction per query |
| Q08 | Retry waste | Verified logical execution has charged failed attempts before success; otherwise label suspected repeated execution | Failed attempt3 plus success5 reports observed retry expense3 once |
| ST01 | No observed reads | Complete declared access evidence for30 days, no observed reads and positive retained storage | No-read claim is scoped to observed accounts/window; denied access evidence suppresses |
| ST02 | Never observed read | Same as ST01 over all retained observation history; wording remains never observed, not never used in lifetime | Table predating enrollment shows limited history explicitly |
| ST03 | Time-travel footprint | Time-travel bytes/(active+time-travel+fail-safe+retained-clone)>30% for14 days | 40/100=40% qualifies for retention-policy review, not automatic reduction |
| ST04 | Fail-safe footprint | Fail-safe fraction>30% for14 days using physical ownership metrics | 40/100 qualifies; no promise of immediate reclamation or direct fail-safe disable switch |
| ST05 | Unexpected growth | Complete daily physical storage rises>25% over7 days and absolute increase exceeds tenant-configured byte floor | 100GiB→150GiB qualifies above floor; clone ownership prevents duplication |
| PL01 | dbt overscheduling | Exact invocation frequency rises>50% while approved change-volume/rows-changed signal rises<10% | 10→20 runs with unchanged100 changed rows qualifies; missing change signal suppresses |
| PL02 | Task overscheduling | Same PL01 predicate using verified task executions and change signal | Exact20 task runs are counted; inferred query groups cannot substitute |
| PL03 | Low-change frequent execution | At least24 exact executions/day with zero approved change signal in>90% of executions for14 days | 23/24 zero-change executions qualify; successful SELECT row count is not automatically a change signal |
| PL04 | Failure/retry waste | Observed charged failed/retried pipeline attempts exceed10% of supported pipeline charge components | Retry10/total50=20% qualifies, using distinct charge links |
| PL05 | Duplicate pipeline | Explicitly verified overlapping target/output lineage and repeated equivalent workload; hash similarity alone is insufficient | Two verified writers of same approved output become review candidate; no auto-disable |
| PI01 | Tiny files | File Snowpipe median input file size<16MiB with at least100 files in complete day | 100 one-MiB files qualify; Streaming is ineligible |
| PI02 | High ingestion frequency | At least60 verified file-ingest operations/hour and median bytes/operation<16MiB | 120 tiny operations qualify; impact uses billed model, not outdated per-file pricing assumption |
| PI03 | Low bytes per file | Total bytes/positive file count<16MiB on complete file-ingest population | 100MiB/100=1MiB; zero/null file count suppresses |
| PI04 | Ingestion regression | Cost per ingested byte rises>25% versus comparable14-day baseline with verified same pricing architecture | 2→3 USD/GiB qualifies; architecture/rate change is disclosed confounder |
| AI01 | Model cost spike | Model/service spend follows the shared anomaly predicate on complete current source | Retired source cannot create a false drop or recovery |
| AI02 | Expensive model | Approved quality-equivalence evaluation exists and observed alternative cost/request is lower | Without quality evidence, show spend concentration only; no guaranteed interchangeable model recommendation |
| AI03 | Tokens per request | Comparable request population tokens/request rises>25% versus14-day baseline | 100→150 tokens/request qualifies; null request count suppresses |
| AI04 | User concentration | Top authorized user exceeds50% of service spend over7 complete days and impact floor | 60/100 qualifies as concentration observation, not abuse allegation |
| AI05 | Agent anomaly | Parent-inclusive agent spend follows anomaly policy; child components remain explanatory | Parent10/child4 remains10 in both baseline/current |
| AI06 | Search anomaly | Search service spend/usage follows anomaly policy with refresh/serving components distinguished | Maintenance change is not mislabeled token growth |
| AI07 | Business unit cost | Explicit approved business transaction denominator exists; cost/transaction rises>25% | 200/100→300/100 rises50%; request count cannot silently substitute for business transactions |
| SP01 | Pool under-utilization | Authorized measured CPU utilization<20% during billed active intervals for14 complete days | Missing telemetry suppresses;8 credits alone proves no utilization percentage |
| SP02 | Idle pool | Measured zero active workload during positive billed pool intervals for at least60min on3 days | One shared pool charge8 stays8 across services; unknown workload telemetry suppresses |
| SP03 | Unexpected scaling | Observed pool capacity/active-node measure increases>50% without an approved planned-change annotation | 2→4 nodes qualifies as review candidate; exact telemetry source is capability gated |
| SP04 | Application regression | Application-attributed cost per approved workload unit rises>25% over comparable14-day periods | Pool/app shared charges deduplicate; no unit denominator → spend-change evidence only |

Ownership: WH→INS-002; Q/PL→INS-003; ST/PI→INS-004; AI/SP→INS-005. Potential savings are null unless a documented counterfactual/rate/population supports a numerical estimate. Combine overlapping WH idle/suspend/consolidation candidates in one opportunity group; similarly deduplicate query/pipeline retry candidates. Threshold tuning creates a new detector version and must pass the same negative fixtures and retrospective false-positive review.


## Implementation sequence

| Task | Deliverable | Dependencies | Gate |
|---|---|---|---|
| [INS-001](../tasks/INS/INS-001.md) | Build insight registry and evidence publication | WRK-005, API-005, ORC-005, GOV-005 | M8 |
| [INS-002](../tasks/INS/INS-002.md) | Implement warehouse optimization detectors | INS-001, FIN-004, UX-005 | M8 |
| [INS-003](../tasks/INS/INS-003.md) | Implement query and pipeline optimization detectors | INS-001, WRK-002, WRK-004 | M8 |
| [INS-004](../tasks/INS/INS-004.md) | Implement storage and ingestion optimization detectors | INS-001, FIN-006, FIN-011, FIN-012 | M8 |
| [INS-005](../tasks/INS/INS-005.md) | Implement Cortex and container optimization detectors | INS-001, FIN-018, FIN-019, UX-007 | M8 |
| [INS-006](../tasks/INS/INS-006.md) | Implement action workflow and immutable baseline capture | INS-002, INS-003, INS-004, INS-005, CTL-004 | M8 |
| [INS-007](../tasks/INS/INS-007.md) | Measure normalized savings and finish optimization acceptance | INS-006, FIN-009 | M8 |

## Domain acceptance

Each task must satisfy its numerical/security/recovery oracle and the [global delivery standard](../../DELIVERY_METHODOLOGY.md). All customer-visible features must carry the documented UX states. No live test has been performed by this specification.
