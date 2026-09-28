#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["jsonschema>=4.23"]
# ///
"""Validate delivery/state.json against delivery/state.schema.json and graph consistency."""
import json
import sys
from pathlib import Path

import jsonschema

ROOT = Path(__file__).resolve().parents[2]
state = json.loads((ROOT / "delivery/state.json").read_text())
jsonschema.validate(state, json.loads((ROOT / "delivery/state.schema.json").read_text()))
graph = json.loads((ROOT / "docs/22-implementation-readiness/revised-task-graph.json").read_text())
ids = {t["id"] for t in graph["tasks"]}
missing = ids - set(state["tasks"])
extra = set(state["tasks"]) - ids
if missing or extra:
    print("state/graph mismatch: missing", sorted(missing), "extra", sorted(extra))
    sys.exit(1)
done = {k for k, v in state["tasks"].items() if v["status"] == "DONE"}
bad = [t["id"] for t in graph["tasks"] if t["id"] in done and not set(t["dependencies"]) <= done]
if bad:
    print("DONE tasks with unfinished dependencies:", bad)
    sys.exit(1)
print(f"state ok: {len(ids)} tasks, {len(done)} done, paused={state['control']['paused']}")
