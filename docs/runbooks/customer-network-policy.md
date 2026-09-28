---
contract: customer-network-policy-snippet
version: 1
status: DRAFT
owner_task: INF-002
producing_steps: [INF-002-S03, INF-002-S13]
consumers: [CON-003, CON-006, CON-102]
decisions: [D-09]
rulings: [RECONCILIATION U-24, RECONCILIATION C-13]
last_changed: 2026-09-28
---

# Customer network-policy snippet (D-09)

Bridge reaches customer Snowflake accounts over TLS from fixed NAT Elastic IPs per environment. The IPs are published in `infra/environments/<env>.egress.json` (schema [`infra/environments/egress.schema.json`](../../infra/environments/egress.schema.json)), in SSM `/bridge/<env>/egress/ips` and through `GET /v1/platform/egress-ips` (CON-102-S01). This page is the INF-owned source of the SQL block that CON-003's install script and CON-006's wizard (step 4, network) render. It is parameterized **only** by the egress file; never type IPs by hand.

## 1. Inputs

| Parameter | Source | Example (documentation range) |
|---|---|---|
| `allowlist` | `<env>.egress.json#/allowlist` (= `ips ∪ previous_ips ∪ announced_ips`) | `203.0.113.10`, `203.0.113.11` |
| `rule_fqn` | Install-script database/schema chosen by CON-003 for Bridge objects | `BRIDGE_FINOPS_ADMIN.NETWORK.BRIDGE_FINOPS_EGRESS` |
| `policy_name` | Fixed | `BRIDGE_FINOPS_NP` |
| `service_user` | Install-script WIF service user (CON-003) | `BRIDGE_FINOPS_READER_USER` |

Only production IPs are rendered for customer accounts. Test-estate accounts (INF-101-S10) allow STAGING **and** PROD IPs so that the DEV-EIP denial can be tested.

## 2. Snippet (rendered by the install script, user-level policy)

```sql
-- Bridge egress allowlist, generated from <env>.egress.json published_at=<published_at>.
-- Applies to the Bridge service user only; the account-level policy is not changed.
CREATE NETWORK RULE IF NOT EXISTS <rule_fqn>
  MODE = INGRESS
  TYPE = IPV4
  VALUE_LIST = ('<allowlist[0]>', '<allowlist[1]>')
  COMMENT = 'Bridge FinOps egress IPs (D-09); source <env>.egress.json';

-- Re-runs converge the list (IP rotation within the 90-day overlap):
ALTER NETWORK RULE <rule_fqn> SET VALUE_LIST = ('<allowlist[0]>', '<allowlist[1]>');

CREATE NETWORK POLICY IF NOT EXISTS BRIDGE_FINOPS_NP
  ALLOWED_NETWORK_RULE_LIST = ('<rule_fqn>')
  COMMENT = 'Bridge FinOps service user network policy (D-09)';

ALTER USER <service_user> SET NETWORK_POLICY = BRIDGE_FINOPS_NP;
```

Rules:

- The block is **optional** (wizard toggle, CON-006-S05). When absent, the customer's account-level network policy (if any) must include the same `allowlist`; the probe reports `NETWORK_POLICY_BLOCKED` otherwise (ADR-016 §4).
- User-level policy is preferred over account-level: it never locks out the customer's own users.
- The rule lists **all** entries of `allowlist`, including announced and previous sets, so an IP change never interrupts extraction.
- No `BLOCKED_NETWORK_RULE_LIST`, no private/PrivateLink rules in R1 (PrivateLink-only accounts are R2, INF-106/CON-103).
- Removal (revoke script, CON-003): `ALTER USER <service_user> UNSET NETWORK_POLICY; DROP NETWORK POLICY IF EXISTS BRIDGE_FINOPS_NP; DROP NETWORK RULE IF EXISTS <rule_fqn>;`.

## 3. Change procedure (adopted from CON-102-S02; RECONCILIATION C-13)

| Day | Action | Egress file change |
|---|---|---|
| D−90 or earlier | Allocate the new EIP(s) (`prevent_destroy`), announce to customers (e-mail + wizard banner), re-render scripts | `announced_ips` = new set; `announced_effective_from` = D |
| D−90 … D | Customers re-run the install script or `ALTER NETWORK RULE … SET VALUE_LIST` | `allowlist` contains old and new |
| D | Route NAT through the new EIP(s); oracle `SELECT CURRENT_IP_ADDRESS()` from a WIF session ∈ new set | `ips` = new set, `previous_ips` = old set, `retire_after` = D + 90 days, `announced_*` cleared |
| ≥ D + 90 | Release the old EIP(s) only after the label `allow-destroy` and a second approver (INF-102-S05) | `previous_ips` = [], `retire_after` = null |

A replaced EIP is never released while it is in `allowlist`. The PROD egress file changes only through the `prod` GitHub environment with a reviewer other than the author.

## 4. Verification

1. `tools/network/validate_egress.py` checks the invariants in the schema `$comment`.
2. INF-002-S11 probe: from an ECS task in each AZ of the environment, `SELECT CURRENT_IP_ADDRESS()` over a WIF session returns a member of `ips`.
3. INF-101-S10: a WIF login to test-estate A1 from the DEV EIP fails with a network-policy denial; from STAGING it succeeds.
