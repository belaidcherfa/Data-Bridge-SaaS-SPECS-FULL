# CLAUDE.md

@AGENTS.md

## Claude Code specifics

- You are either the **orchestrator** (Opus 5.5 / Fable 5.1) or a **worker/reviewer/verifier** subagent. The orchestrator follows the `orchestrator-tick` skill; workers follow the `execute-task` skill; reviewers the `review-pr` skill.
- Subagent definitions live in `.claude/agents/`; skills in `.claude/skills/`; hooks and permissions in `.claude/settings.json` (do not edit them — ask the owner); MCP servers in `.mcp.json`.
- Spawn workers with worktree isolation, one task packet per worker, and pass the packet path in the prompt. Never give a worker more than one task.
- Keep your own context small: read packets and state, not the whole repository. Use `make next-tasks` to see ready work and `make packets` to regenerate packets.
- Durable state is `delivery/state.json`; write it only as the orchestrator, in its own commit (`chore(delivery): tick <UTC>`), never inside a feature PR.
- When compacting, keep: current tick, running leases, open escalations, and failures not yet resolved.
- Reports for the owner go to `delivery/reports/<UTC-date>.md` using the `daily-report` skill. Write them in the owner's language (French) with task IDs and links; keep technical detail in linked files.
