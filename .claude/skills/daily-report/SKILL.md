---
name: daily-report
description: Produce the owner's daily (and weekly) delivery report in French from delivery/state.json, merged PRs, CI, escalations and metrics. Use once per UTC day, or when the owner asks for a status.
---

# Daily report (owner-facing, French)

Gather: `delivery/state.json`; `gh pr list --state merged --search "merged:>=<yesterday>" --label agent`; open `needs-human` PRs; open escalations; `delivery/metrics/<date>.jsonl`; main CI status; `make next-tasks`.
Write `delivery/reports/<UTC-date>.md` with the template in docs/23-agentic-delivery/STATE_AND_REPORTING.md §3: **En bref**, **Décisions / actions attendues de toi** (first!), Avancement par couloir, Livré depuis hier, Qualité, Coûts, Risques, Prochaines 24 h. Every item links to a PR, evidence file or escalation. Never claim a gate passed without evidence. Mirror the file as a comment on the pinned GitHub issue "Rapports de livraison" (and to Slack/Linear/Notion if configured).
