#!/usr/bin/env python3
"""PreToolUse(Bash) guard — blocks dangerous commands deterministically (AGENTS.md §9, ORCHESTRATION §12).

Reads the hook JSON from stdin; exit code 2 + stderr blocks the call and explains why to the agent.
"""
import json
import re
import subprocess
import sys

data = json.load(sys.stdin)
cmd = (data.get("tool_input") or {}).get("command", "") or ""
c = " ".join(cmd.split())

RULES = [
    (r"\bgit\s+push\b[^|;&]*\b(origin\s+)?(main|master)\b(?!-)", "Pushing to main is forbidden; open a PR from your agt/* branch."),
    (r"\bgit\s+push\b[^|;&]*(\s--force\b|\s-f\b|\s--force-with-lease\b)", "Force push is forbidden (agent branches are rebased by the orchestrator only)."),
    (r"\bgit\s+push\b[^|;&]*:(main|master)\b", "Pushing to main is forbidden."),
    (r"\bgit\s+(commit|push)\b[^|;&]*--no-verify\b", "--no-verify is forbidden; fix the failing hook instead."),
    (r"\bgit\s+reset\s+--hard\s+origin/(main|master)\b", "Resetting to origin/main discards work; ask the orchestrator."),
    (r"\bgit\s+(branch\s+-D|push\s+\S+\s+--delete)\s+(main|master)\b", "Deleting main is forbidden."),
    (r"\bterraform\s+(apply|destroy|import|state\s+(rm|mv|push))\b", None),  # handled below
    (r"\brm\s+-[a-z]*r[a-z]*f?[a-z]*\s+(/|~|\$HOME|\.\.)(\s|$)", "Recursive delete outside your worktree is forbidden."),
    (r"(curl|wget)\s[^|]*\|\s*(sudo\s+)?(ba|z)?sh\b", "Piping downloads into a shell is forbidden; pin and verify installers."),
    (r"\baws\s+secretsmanager\s+get-secret-value\b", "Reading secrets is forbidden for agents."),
    (r"\b(printenv|env)\b\s*$", "Dumping the environment may leak secrets; print only the variable you need (non-secret)."),
    (r"(--profile|AWS_PROFILE=)\s*\S*prod", "Production AWS profiles are forbidden for agents."),
    (r"\bsnow\s+\S*.*--connection\s+\S*prod", "Production Snowflake connections are forbidden for agents."),
    (r"\bgh\s+pr\s+merge\b", "Only the orchestrator merges, through the merge queue (use its skill)."),
    (r"\bchmod\s+-R\s+777\b", "World-writable permissions are forbidden."),
]

for pattern, message in RULES:
    if re.search(pattern, c):
        if message is None:
            env = re.search(r"(BRIDGE_ENV|TF_WORKSPACE)=(\w+)", c)
            if re.search(r"terraform\s+apply", c) and env and env.group(2) == "dev":
                continue
            message = "terraform apply/destroy/state mutation is only allowed with BRIDGE_ENV=dev; staging/prod go through the reviewed pipeline."
        if "gh pr merge" in c and data.get("agent_type") in (None, "", "orchestrator"):
            continue
        print(f"Blocked by guard_bash: {message}\nCommand: {cmd[:300]}", file=sys.stderr)
        sys.exit(2)

# Secret scan before commits: inspect staged diff.
if re.search(r"\bgit\s+commit\b", c):
    try:
        diff = subprocess.run(["git", "diff", "--cached", "-U0"], capture_output=True, text=True, timeout=20).stdout
    except Exception:  # noqa: BLE001
        diff = ""
    SECRET_PATTERNS = [
        r"AKIA[0-9A-Z]{16}", r"ASIA[0-9A-Z]{16}", r"-----BEGIN (RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----",
        r"xox[baprs]-[0-9A-Za-z-]{10,}", r"ghp_[0-9A-Za-z]{36}", r"github_pat_[0-9A-Za-z_]{40,}",
        r"sk-ant-[0-9A-Za-z_-]{20,}", r"sk_live_[0-9A-Za-z]{20,}", r"(?i)aws_secret_access_key\s*[=:]\s*\S{20,}",
        r"(?i)(password|passwd|secret|token)\s*[=:]\s*['\"][^'\"<>{}$]{8,}['\"]",
    ]
    added = "\n".join(l for l in diff.splitlines() if l.startswith("+") and not l.startswith("+++"))
    for sp in SECRET_PATTERNS:
        if re.search(sp, added):
            print(f"Blocked by guard_bash: staged changes look like they contain a secret (pattern {sp}). Remove it and use Secrets Manager / placeholders.", file=sys.stderr)
            sys.exit(2)
sys.exit(0)
