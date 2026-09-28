#!/usr/bin/env python3
"""PreToolUse(Edit|Write|MultiEdit|NotebookEdit) guard — protects the PRD, policy files and secrets."""
import json
import re
import sys

data = json.load(sys.stdin)
ti = data.get("tool_input") or {}
path = ti.get("file_path") or ti.get("notebook_path") or ti.get("path") or ""
p = path.replace("\\", "/")
content = " ".join(str(ti.get(k, "")) for k in ("content", "new_string", "new_source"))
content += " ".join(str(e.get("new_string", "")) for e in ti.get("edits", []) or [] if isinstance(e, dict))

RULES = [
    (r"(^|/)docs/00-project/PRD\.md$", "The PRD is byte-exact and read-only."),
    (r"(^|/)\.claude/(settings(\.local)?\.json|hooks/)", "Agent policy files are owner-controlled; escalate instead."),
    (r"(^|/)\.env(\.(?!example$)[^/]*)?$", "Never write .env files; use config/environments (non-secret) or Secrets Manager."),
    (r"\.(pem|key|p12|pfx|jks)$", "Never write key material."),
    (r"(^|/)id_(rsa|ed25519|ecdsa)(\.pub)?$", "Never write SSH keys."),
    (r"(^|/)config/environments/(dev|staging|prod)\.yaml$", "Real environment files are owner-supplied; edit the *.example.yaml template instead."),
    (r"(^|/)\.github/CODEOWNERS$", "CODEOWNERS is owner-controlled."),
]
for pattern, message in RULES:
    if re.search(pattern, p):
        print(f"Blocked by guard_write: {message}\nPath: {path}", file=sys.stderr)
        sys.exit(2)
if re.search(r"-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}|sk-ant-[0-9A-Za-z_-]{20,}", content):
    print("Blocked by guard_write: content looks like a secret.", file=sys.stderr)
    sys.exit(2)
sys.exit(0)
