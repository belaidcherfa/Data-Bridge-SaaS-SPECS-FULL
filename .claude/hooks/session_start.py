#!/usr/bin/env python3
"""SessionStart hook — prints a short delivery status as additional context (stdout)."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
try:
    state = json.loads((root / "delivery/state.json").read_text())
    tasks = state.get("tasks", {})
    counts: dict[str, int] = {}
    for v in tasks.values():
        counts[v["status"].split(":")[0]] = counts.get(v["status"].split(":")[0], 0) + 1
    print(f"[delivery] paused={state['control']['paused']} ({state['control'].get('pause_reason') or '-'}); "
          f"leases={len(state.get('leases', []))}; open escalations={len(state.get('escalations_open', []))}; "
          f"task status counts={counts}. Read AGENTS.md first; workers read their packet in delivery/packets/.")
except Exception as e:  # noqa: BLE001
    print(f"[delivery] state unavailable: {e}")
