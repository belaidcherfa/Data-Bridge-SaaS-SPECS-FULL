---
name: escalate
description: Raise a blocking question, contract change, vendor-behavior mismatch, access/budget need, repeated failure or security/financial risk to the orchestrator and owner with options and a recommendation. Use instead of guessing.
---

# Escalate

Create `delivery/escalations/<UTC yyyy-mm-ddTHHMMZ>-<TASK-ID>.md` using the template in docs/23-agentic-delivery/STATE_AND_REPORTING.md §2:
- front matter: id, task, raised_by, kind (decision | contract-change | vendor-behavior | access | budget | failure | security | financial), severity (blocking-task | blocking-lane | blocking-all | info), status OPEN;
- Context with links; 2–4 Options with consequences and effort; one Recommendation; empty "Owner answer".
Commit it on your branch (it is inside every packet's allowed paths) and mention it in the PR or in your final message. Then continue with micro-steps that do not depend on the answer, or stop. Never proceed on an assumption that changes a contract, a decision, a security boundary or a financial result.
