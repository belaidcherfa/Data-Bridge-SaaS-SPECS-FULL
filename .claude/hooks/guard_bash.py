#!/usr/bin/env python3
"""PreToolUse(Bash) guard — blocks dangerous commands deterministically (AGENTS.md §9, ORCHESTRATION §12).

Reads the hook JSON from stdin; exit code 2 + stderr blocks the call and explains why to the agent.
"""
import json
import os
import re
import subprocess
import sys

data = json.load(sys.stdin)
cmd = (data.get("tool_input") or {}).get("command", "") or ""
c = " ".join(cmd.split())

RULES = [
    (r"\bgit\s+push\b[^|;&]*(\s|:|refs/heads/)(main|master)(?=\s|$|[;&|])", "Pushing to main is forbidden; open a PR from your agt/* branch."),
    (r"\bgit\s+push\b[^|;&]*(\s--force\b|\s-f\b|\s--force-with-lease\b)", "Force push is forbidden (agent branches are rebased by the orchestrator only)."),
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
        if "gh pr merge" in c and data.get("agent_type") in (None, "", "orchestrator") \
                and os.environ.get("BRIDGE_ROLE", "orchestrator") == "orchestrator":
            continue
        print(f"Blocked by guard_bash: {message}\nCommand: {cmd[:300]}", file=sys.stderr)
        sys.exit(2)

# Protected files may not be modified through the shell either (guard_write only sees Edit/Write tools).
PROTECTED = r"(docs/00-project/PRD\.md|\.claude/settings(\.local)?\.json|\.claude/hooks/|\.github/CODEOWNERS|delivery/protected-files\.sha256|config/environments/(dev|staging|prod)\.yaml)"
WRITE_OPS = r"((?<![0-9&])>>?(?!\s*&|\s*/dev/null)|\btee\b|\bsed\s+-[a-zA-Z]*i|\bperl\s+-[a-zA-Z]*i|\bcp\b|\bmv\b|\brm\b|\btruncate\b|\bchmod\b|\bln\b|\bdd\b|\bgit\s+(checkout|restore|rm|mv)\b|\bpython3?\s+-c\b|\bnode\s+-e\b)"
if re.search(PROTECTED, c) and re.search(WRITE_OPS, c) and os.environ.get("BRIDGE_ROLE") != "owner":
    print("Blocked by guard_bash: this command would modify a protected file (PRD, agent policy, CODEOWNERS, "
          "checksums, real environment files). Escalate instead.", file=sys.stderr)
    sys.exit(2)

# Any push while HEAD is main/master (e.g. a bare `git push`) is forbidden.
if re.search(r"\bgit\s+push\b", c):
    try:
        head = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True, text=True, timeout=10).stdout.strip()
    except Exception:  # noqa: BLE001
        head = ""
    explicit = re.search(r"\bgit\s+push\b\s+(-u\s+|--set-upstream\s+)?\S+\s+(?!-)(\S+)", c)
    if head in ("main", "master") and not (explicit and explicit.group(2) not in ("main", "master", "HEAD")):
        print("Blocked by guard_bash: you are on main; work on an agt/* branch and push that branch.", file=sys.stderr)
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
