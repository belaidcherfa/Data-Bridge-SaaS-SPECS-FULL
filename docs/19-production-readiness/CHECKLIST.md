# Production go/no-go checklist

Owner: Delivery manager. Every item starts NOT_RUN. A document existing is not evidence that infrastructure or product works. Attach actual commit, environment, time, result and reviewer to each item.

| Gate | Required proof | Blocking rule / owner |
|---|---|---|
| Build provenance | Pinned runtime matrix, signed image digests, SBOM, dependency and IaC scans | No mutable production artifact; DevOps |
| AWS isolation | Correct account/region, private data services, least-privilege roles, KMS, TLS, WAF, quotas and restore access | Public data endpoint or broad runtime admin blocks; Security |
| Identity | Cognito login/logout/MFA/SSO as contracted, session revocation and machine client scopes | Authentication confusion blocks; Security |
| Tenancy | PG FORCE RLS, identity-bound Snowflake policies, A/B API/cache/jobs/reports attacks | Any disclosure blocks; Security |
| Connectivity | Live WIF with pinned Python/dbt stack, least grants, revocation and multi-account identity proof | RSA/password fallback blocks; Snowflake lead |
| Durable synchronization | Streaming bounds, manifest acceptance, retries/duplicates/late data/schema change/replay/backfill proofs | Accepted data unrecoverable or duplicated blocks; Data lead |
| Financial kernel | Golden fixtures, service authority, signed adjustments/currencies, independent reference comparison and immutable close | Double count/unexplained passed reconciliation blocks; FinOps |
| Complete SaaS | Personas, all navigation/routes, empty/loading/partial/error/denied/success states, accessible UI and Explain This Number | Missing required journey blocks; Product/QA |
| Governance and reports | Allocation conservation, budgets/forecast, monitor suppression, four delivery channels, eight report templates and secure downloads | Cross-scope delivery or false verified saving blocks; QA |
| Monitoring | Working alert routes, synthetic probes, source/platform lag separation and named on-call | Undetected outage or unowned critical alert blocks; SRE |
| Recovery | Timed PG and analytical restore including old retained facts, deletion tombstones and side-effect reconciliation | Unproven recovery blocks; SRE |
| Capacity/economics | Executed benchmark, safe quotas, failure behavior, expected operating budget and margin model | Unbounded resource consumption blocks; SRE/FinOps |
| Customer/legal | Signed scope/retention/residency, terms/privacy review, support contacts and commercial entitlement | Unauthorized collection blocks; Customer success/legal owner |
| Release | Immutable candidate, approvals, rollback rehearsal, production synthetic smoke and no unresolved blocking issue | Failed required gate meansNO-GO; Delivery |

## Approval record template

```yaml
candidate: v1.0.0-rc.N
implementation_commit: REQUIRED
artifact_manifest: REQUIRED_PRIVATE_EVIDENCE_REFERENCE
environment: production
required_checks: {passed: 0, failed: 0, not_run: 14}
known_capability_limits: []
approvals: {engineering: pending, security: pending, finops: pending, operations: pending}
rollback_owner: UNASSIGNED
customer_authorization_reference: REQUIRED
decision: NO_GO
```

A risk acceptance records exact scope, reason, compensating control, owner and expiry. It cannot waive a core architecture boundary, undisclosed tenant exposure or a fabricated financial result. Recheck evidence after material source/library/infrastructure changes.
