# Agentic delivery — index

Status: ACCEPTED 2026-09-28 · Decision: D-19 · Architecture: [ADR-018](../architecture/adr/ADR-018-agentic-delivery.md).

Bridge Data FinOps is built by coding agents under an orchestrator, with 1–2 human reviewers and an owner who reads summaries. This folder is the operating manual of that system.

| Document | For | Content |
|---|---|---|
| [HUMAN_CHECKPOINTS.md](HUMAN_CHECKPOINTS.md) | Owner (French) | What only a human can do: before start (H0–H5), as soon as possible (H6–H10), daily/weekly routine, emergency stop |
| [ORCHESTRATION.md](ORCHESTRATION.md) | Orchestrator, reviewers | Roles, tick loop, model tiers, dispatch prompt, parallelism rules, review rubric, gates, runtime modes, server, safety invariants |
| [TASK_PACKET_FORMAT.md](TASK_PACKET_FORMAT.md) | Workers, tooling | Packet front matter and body; how packets are generated |
| [STATE_AND_REPORTING.md](STATE_AND_REPORTING.md) | Orchestrator, owner | Ledger state, task status machine, escalation file, daily/weekly reports, metrics |
| [PARALLELISM.md](PARALLELISM.md) | Orchestrator, owner | Dependency kinds (runtime / contract / decision), waves, critical path, integration slices |
| [STACK.md](STACK.md) | Everyone | Runtimes, libraries and versions, infra/CI tools, agent tooling, MCP servers, methodology, commands |

## Where things are

| Path | What |
|---|---|
| [`AGENTS.md`](../../AGENTS.md), [`CLAUDE.md`](../../CLAUDE.md) | Mandatory rules for every agent (loaded automatically by Claude Code) |
| [`delivery/packets/`](../../delivery/packets/README.md) | One generated packet per task (`make packets`, drift-checked in CI) |
| `delivery/state.json` | Initial state and schema on `main`; live state on branch `delivery-ledger` |
| [`delivery/packet-overrides.yaml`](../../delivery/packet-overrides.yaml) | Tiers, specialized reviewers, human gates, extra writes |
| `delivery/dependency-kinds.yaml` | Runtime / contract / decision classification of every graph edge |
| [`delivery/mcp/`](../../delivery/mcp/optional-servers.example.json) | Optional MCP servers for the delivery host |
| `.claude/agents/` | worker, worker-critical, reviewer, security/finops/data/frontend reviewers, verifier, rescuer, contract-author, reporter |
| `.claude/skills/` | orchestrator-tick, execute-task, review-pr, verify-task, escalate, evidence-capture, daily-report, author-contract, tenant-isolation-tests, money-and-ledger, snowflake-sql-and-dbt, fastapi-endpoint, react-screen, background-job, terraform-change, migration-safety, observability-and-runbooks, live-gate-handoff |
| `.claude/hooks/`, `.claude/settings.json` | Deterministic guardrails (bash and write guards, session status) |
| `.mcp.json` | Default MCP servers (playwright, context7, aws-docs, terraform) |
| `.github/workflows/delivery.yml` | delivery-check, scope-guard, secrets, protected-files |
| `.github/workflows/agent-task.yml`, `orchestrator-tick.yml` | Mode C (GitHub-hosted), disabled unless `DELIVERY_MODE=C` |
| [`contracts/`](../../contracts/README.md) | Executable contracts per lane (K1–K10), conventions, manifests, hand-offs |
| [`tools/delivery/`](../../tools/delivery/) | build_packets, next_tasks, validate_state, scope_guard, parallelism |
| [`docs/22-implementation-readiness/backlog/AGT.md`](../22-implementation-readiness/backlog/AGT.md) | Delivery tooling tasks AGT-001…AGT-007 (lane A0) |

## Start sequence

1. Owner: checkpoints H0–H5 ([HUMAN_CHECKPOINTS](HUMAN_CHECKPOINTS.md)).
2. **Wave 0** (mode A, interactive orchestrator on the server): AGT-001, AGT-002, AGT-004 and FND-001 in parallel; then AGT-003, AGT-007 (contract ratification), AGT-005, AGT-006 while FND-002…FND-005 proceed.
3. **Wave 1**: contracts ACCEPTED → contract-gated tasks across lanes become startable ([PARALLELISM](PARALLELISM.md)).
4. After the 48-hour pilot and quality baseline: owner authorizes **mode B** (autonomous loop, reports in French every day).

## Commands

```bash
make help            # list targets
make packets         # regenerate task packets
make next-tasks      # ready tasks ranked by remaining critical path
make contracts-check # validate contracts
make delivery-check  # contracts + packets drift + state (what CI runs)
```
