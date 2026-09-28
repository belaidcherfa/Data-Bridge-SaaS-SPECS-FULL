-- contract=snowflake-py-outputs-insights-access version=1 status=DRAFT owner_task=INS-001 decisions=D-02,D-05,D-22 last_changed=2026-09-28
-- Migration V0706 (lane K8) · grants and row access policies for the INS Python-output tables (V0700–V0705).
-- Depends on: K1 roles (INF-008-S08: BRIDGE_ENGINE, BRIDGE_TRANSFORMER) and K2 policies (SEC-005-S03:
-- SECURITY.RAP_ACCOUNT_SCOPED(P_TENANT_ID, P_ORG_ID, P_ACCOUNT_ID)); the migration runner orders it after them.
-- Insert-only (D-05): BRIDGE_ENGINE gets INSERT/SELECT on revision tables and never UPDATE/DELETE; retry cleanup of its
-- own unpublished build rows goes through the K4 owner's-rights procedure (hand-off, contracts/_handoffs/K8.md);
-- physical deletion of superseded/expired revisions is ORC-105 GC only. Landing tables are transient and writable by
-- the engine. BRIDGE_TRANSFORMER reads revision tables for dbt staging over py.* sources (ORC-103-S07). Tenant readers
-- never receive grants on these base tables: serving uses secure views (K6/INS-101-S02) selected through the query
-- broker (D-22); row access policies are attached to the base tables per ADR-014 §1 / SEC-005 (account-grain facts).

grant select, insert, delete, truncate on table py_outputs.insight_observation_landing to role bridge_engine;
grant select, insert, delete, truncate on table py_outputs.insight_evidence_landing to role bridge_engine;
grant select, insert, delete, truncate on table py_outputs.insight_detector_evaluation_landing to role bridge_engine;
grant select, insert, delete, truncate on table py_outputs.insight_opportunity_group_landing to role bridge_engine;
grant select, insert, delete, truncate on table py_outputs.action_baseline_landing to role bridge_engine;
grant select, insert, delete, truncate on table py_outputs.savings_measurement_landing to role bridge_engine;

grant select, insert on table py_outputs.insight_observation_r to role bridge_engine;
grant select, insert on table py_outputs.insight_evidence_r to role bridge_engine;
grant select, insert on table py_outputs.insight_detector_evaluation_r to role bridge_engine;
grant select, insert on table py_outputs.insight_opportunity_group_r to role bridge_engine;
grant select, insert on table py_outputs.action_baseline_r to role bridge_engine;
grant select, insert on table py_outputs.action_baseline_day_r to role bridge_engine;
grant select, insert on table py_outputs.savings_measurement_r to role bridge_engine;
grant select, insert on table py_outputs.savings_measurement_day_r to role bridge_engine;

grant select on table py_outputs.insight_observation_r to role bridge_transformer;
grant select on table py_outputs.insight_evidence_r to role bridge_transformer;
grant select on table py_outputs.insight_detector_evaluation_r to role bridge_transformer;
grant select on table py_outputs.insight_opportunity_group_r to role bridge_transformer;
grant select on table py_outputs.action_baseline_r to role bridge_transformer;
grant select on table py_outputs.action_baseline_day_r to role bridge_transformer;
grant select on table py_outputs.savings_measurement_r to role bridge_transformer;
grant select on table py_outputs.savings_measurement_day_r to role bridge_transformer;

alter table py_outputs.insight_observation_r add row access policy security.rap_account_scoped on (tenant_id, organization_id, account_id);
alter table py_outputs.insight_evidence_r add row access policy security.rap_account_scoped on (tenant_id, organization_id, account_id);
alter table py_outputs.insight_detector_evaluation_r add row access policy security.rap_account_scoped on (tenant_id, organization_id, account_id);
alter table py_outputs.insight_opportunity_group_r add row access policy security.rap_account_scoped on (tenant_id, organization_id, account_id);
alter table py_outputs.action_baseline_r add row access policy security.rap_account_scoped on (tenant_id, organization_id, account_id);
alter table py_outputs.action_baseline_day_r add row access policy security.rap_account_scoped on (tenant_id, organization_id, account_id);
alter table py_outputs.savings_measurement_r add row access policy security.rap_account_scoped on (tenant_id, organization_id, account_id);
alter table py_outputs.savings_measurement_day_r add row access policy security.rap_account_scoped on (tenant_id, organization_id, account_id);
