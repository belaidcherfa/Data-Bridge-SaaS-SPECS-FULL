# Implementation validations still open

Documentation completeness does not close these gates. All start NOT_RUN. The task index records implementation NOT_STARTED.

| ID | Owner | Gate | Required evidence / safe default |
|---|---|---|---|
| V01 Runtime matrix | Platform/Snowflake | Before CON-002/M2 | Pinned Python, connector, PyArrow, Dagster, dbt Core and adapter WIF compatibility; no persistent credential fallback |
| V02 AWS region/quotas | DevOps | M1 and M10 | Actual account IDs, region services, IAM role quotas, ECS capacity, KMS trust, DNS and deployment OIDC |
| V03 Source capabilities | Snowflake/Data | Every adapter activation/M3 | Exact current schemas/grants/retention/latencies and account/organization/reseller limitations |
| V04 Central authorization scale | Security | M5/M9 | Principal per tenant/normalized permission-profile quota, role/policy enforcement, pool budget and immediate epoch revocation |
| V05 Financial authority | FinOps | M4/M11 | Native service/invoice inclusion mapping, approved rate/currency scope and independent reference; no invented balancing entries |
| V06 Performance/cost | SRE/FinOps | M9 | Actual measured footprint, safe quotas, query/memory/file limits and approved benchmark spend |
| V07 Recovery | SRE | M9/M10 | Timed PG and canonical Snowflake restoration, historical facts outside raw retention and deletion tombstones |
| V08 Communications | Backend | M7/M10 | SES sending approval, Slack/Teams supported sandbox receipts, webhook SSRF tests and provider timeout behavior |
| V09 Security/privacy | Security/legal owner | M9/M10 | Full isolation suite, vulnerability remediation, approved retention/residency/subprocessors and customer terms |
| V10 Customer authorization | Customer success | M11 | Approved real organization/accounts, admin identity, collection scope and capability acceptance |
| V11 First value/payment | Customer/Finance | M11/M12 | Real customer acceptance and verified payment; synthetic fixtures cannot satisfy these gates |
| V12 Post-launch reviews | Delivery/SRE | First week/day30 | Actual production observations, first complete-period billing reconciliation and assigned improvements |

An external limitation has an explicit feature/coverage consequence. A required failed gate blocks the affected milestone. Optional unavailable capabilities may degrade gracefully only when the product, exports and customer acceptance disclose the missing evidence. Do not repeatedly reopen settled ADRs without new evidence from one of these validations.
