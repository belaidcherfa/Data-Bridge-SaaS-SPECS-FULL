#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["jsonschema>=4.23"]
# ///
"""Validate a delivery state file against delivery/state.schema.json and the revised task graph.

Usage: uv run tools/delivery/validate_state.py [--state PATH] [--sync]

--state PATH  state file to check (default delivery/state.json; the orchestrator passes the ledger copy,
              ADR-018 §5).
--sync        add graph tasks missing from the state as NOT_STARTED and write the file back (run by the
              orchestrator at SYNC after the graph gains tasks). Tasks present in the state but absent from
              the graph are always an error (a task is never deleted, only MERGED_INTO another).
"""
import json
import sys
from pathlib import Path

import jsonschema

ROOT = Path(__file__).resolve().parents[2]
args = sys.argv[1:]
state_path = Path(args[args.index("--state") + 1]) if "--state" in args else ROOT / "delivery/state.json"
state = json.loads(state_path.read_text())
graph = json.loads((ROOT / "docs/22-implementation-readiness/revised-task-graph.json").read_text())
ids = {t["id"] for t in graph["tasks"]}
missing = ids - set(state["tasks"])
if missing and "--sync" in args:
    for tid in sorted(missing):
        merged = next((t.get("merged_into") for t in graph["tasks"] if t["id"] == tid), None)
        state["tasks"][tid] = {"status": f"MERGED_INTO:{merged}" if merged else "NOT_STARTED", "attempts": 0,
                               "pr": None, "model": None, "steps_done": [], "evidence": None, "blocked_by": []}
    state["tasks"] = dict(sorted(state["tasks"].items()))
    state_path.write_text(json.dumps(state, indent=2, ensure_ascii=False) + "\n")
    print(f"synced: added {len(missing)} task(s): {', '.join(sorted(missing))}")
    missing = set()
jsonschema.validate(state, json.loads((ROOT / "delivery/state.schema.json").read_text()))
extra = set(state["tasks"]) - ids
if missing or extra:
    print("state/graph mismatch: missing", sorted(missing), "extra", sorted(extra), "(use --sync to add missing)")
    sys.exit(1)
done = {k for k, v in state["tasks"].items() if v["status"] == "DONE"}
bad = [t["id"] for t in graph["tasks"] if t["id"] in done and not set(t["dependencies"]) <= done]
if bad:
    print("DONE tasks with unfinished dependencies:", bad)
    sys.exit(1)
held = {l["task"] for l in state.get("leases", [])}
stale = [t for t in held if state["tasks"].get(t, {}).get("status") not in ("IN_PROGRESS", "IN_REVIEW")]
if stale:
    print("leases on tasks that are not IN_PROGRESS/IN_REVIEW:", sorted(stale))
    sys.exit(1)
print(f"state ok: {len(ids)} tasks, {len(done)} done, paused={state['control']['paused']} ({state_path})")
