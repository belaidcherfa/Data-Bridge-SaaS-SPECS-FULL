# ADR-016 — Customer coverage, residency and reachability

Status: Accepted for implementation (owner decision record 2026-09-28: D-20, D-35 owner decisions; D-08, D-09, D-23 owner-accepted recommendations). Date: 2026-09-28.

## Context

The specifications did not state which customers R1 must serve, where customer metadata is processed, how Bridge reaches accounts protected by network policies, or what Bridge's own extraction costs the customer ([audit](../../22-implementation-readiness/AUDIT_CROSS_CUTTING.md) X-13, X-14, X-27, X-43; blocker G-CON-01). Every account-usage query needs a running warehouse **in the customer account**, billed per second with a 60-second minimum per resume (VERIFIED), and Bridge's own queries appear in the customer's cost data. Evidence: [CON backlog](../../22-implementation-readiness/backlog/CON.md) G-CON-01…05, G-CON-11 and §3.1–§3.5; [INF backlog](../../22-implementation-readiness/backlog/INF.md) G-INF-09, G-INF-10; [ONB backlog](../../22-implementation-readiness/backlog/ONB.md) G-ONB-02, G-ONB-07; [decision record](../../22-implementation-readiness/DECISIONS_REQUIRED.md).

## Decision

1. **Coverage (D-20).** R1 supports all Snowflake editions (Standard, Enterprise, Business Critical, VPS where reachable), organization accounts, ORGADMIN-enabled accounts, multi-account organizations and standalone accounts, direct capacity, on-demand and reseller contracts, and every workload and service family. Former R1\* tasks become R1 (Adaptive, Snowpipe Streaming, QAS, Cortex/AI, SPCS, marketplace/native apps, replication, AI/SPCS pages, Power BI, SAML/OIDC SSO). Capability degradation stays mandatory and visible: Standard edition has no ACCESS_HISTORY and no native tags; reseller and no-billing-access tenants use customer-approved rate tables and reseller invoices (FIN-105, FIN-101); standalone accounts have no organization views and show organization coverage as limited. Insight detector breadth stays at the eight R1 detectors (D-01).
2. **Snowflake trial accounts (D-35).** Accepted for demonstrations only. The connection carries a `TRIAL_ACCOUNT` capability flag detected at probe time (exact signals TO VERIFY LIVE); the UI labels all figures as demonstration data; the account is excluded from paid entitlements, financial gates, reconciliation claims, close and chargeback.
3. **Residency (D-23).** R1 is a single EU deployment (AWS `eu-west-1` with the central Snowflake accounts co-located). The processing region is shown during onboarding and stated in contract wording. Later regions are separate stacks built from the same code and Terraform modules; tenant data never moves across regions. Customer accounts on other clouds or regions are extracted over TLS through Bridge's NAT egress, and the cross-cloud transfer is disclosed.
4. **Reachability (D-09).** Fixed NAT Elastic IPs per environment (allocated once, `prevent_destroy`) are published through `GET /v1/platform/egress-ips`, in the connection wizard and in the install script; changes require 90 days of dual publication. The install script optionally creates a user-level network policy for the Bridge service user. Network-policy denials are a distinct probe outcome (`NETWORK_POLICY_BLOCKED`). The S3 gateway endpoint policy allows reads of the customer's Snowflake stage hosts (`SYSTEM$ALLOWLIST`) so large result downloads work. PrivateLink-only accounts are an R2 capability; R1 shows an explicit onboarding blocker (`CON_PRIVATELINK_R2`).
5. **Customer-side footprint (D-08).** The reviewed, marker-guarded install script, run once by a customer administrator able to use ACCOUNTADMIN (Bridge's runtime never uses it), creates:
   - `BRIDGE_FINOPS_WH` (XSMALL, `AUTO_SUSPEND=60`, `AUTO_RESUME`, `INITIALLY_SUSPENDED`, statement and queue timeouts, no multi-cluster clauses so Standard edition works);
   - resource monitor `BRIDGE_FINOPS_RM` with a customer-chosen monthly quota (default 50 credits; notify 80 %, suspend 100 %, suspend immediately 110 %);
   - `USAGE` and `OPERATE` on that warehouse only, so each account-cycle suspends it explicitly at the end;
   - the reader role with the SNOWFLAKE database roles required by the selected modules (USAGE_VIEWER; GOVERNANCE_VIEWER for QUERY_HISTORY, which also exposes query text and is disclosed; OBJECT_VIEWER for database owners; organization roles in the separate organization script);
   - the WIF service user with `DEFAULT_SECONDARY_ROLES = ()`, converged by `ALTER … SET` on re-run.
   Extraction runs as one hourly account-cycle; the estimated monthly credits (≈ 12.6–13.2 credits per account with explicit suspend versus ≈ 20.6–27.2 with auto-suspend only, plus a one-off backfill cost that grows with 365-day query detail under D-11) are shown before consent. Bridge's queries set `QUERY_TAG='bridge_finops:<component>'` as a diagnostic, but the "Bridge overhead" workload is identified from warehouse and user identity before pseudonymization and is never excluded from totals. A suspension by the resource monitor is `CUSTOMER_QUOTA_EXHAUSTED`, non-retryable until the quota or month changes.
6. **Freshness statement.** With hourly cycles and Account Usage latency, product copy says query data is typically 1–2 hours behind the source; the hot INFORMATION_SCHEMA path is R2 (D-24).

## Alternatives considered

A narrower R1 customer profile (rejected by the owner). Free self-service trials as a sales path (rejected by D-17 and D-35). Multi-region from R1 (cost and operations without a customer need). PrivateLink in R1 (per-customer endpoint work before first value). Running extraction on customer production warehouses (pollutes their costs and keeps them awake). A 15-minute QUERY_HISTORY cadence (≈ 36 extra credits per account per month). One shared extractor role chaining into per-connection roles (concentrates cross-customer reach in every extractor process).

## Consequences

R1 scope grows by ≈ 247–366 engineer-hours (D-20). The IAM role quota is shared between per-connection and per-tenant roles and is guarded at admission. Customers see Bridge's own cost as a first-class workload. Onboarding includes customer network change windows and consent to a credit estimate. Organization and account scripts, the module → view → database role map and the egress IPs are versioned artifacts.

## Revisit conditions

A customer requires a non-EU processing region, PrivateLink, a cadence below one hour, or a trial-to-paid path; Snowflake changes database-role coverage or warehouse billing minimums; measured cycle durations (CON-101) differ materially from the estimate.

## Validation obligation

Live evidence on the INF-101 test estate: install/re-run/revoke scripts on Standard and Enterprise accounts, network-policy block and allowlist, resource-monitor exhaustion, measured cycle cost, trial-account detection, and `SELECT CURRENT_IP_ADDRESS()` from a WIF session within the published IPs. Implementation tasks must link redacted live evidence before production. Documentation acceptance is not execution evidence. See [delivery methodology](../../../DELIVERY_METHODOLOGY.md).
