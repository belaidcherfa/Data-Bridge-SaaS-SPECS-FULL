#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6"]
# ///
"""List tasks that are ready to dispatch, ranked for the orchestrator (ORCHESTRATION §3 PLAN).

Usage: uv run tools/delivery/next_tasks.py [--json] [--limit N] [--lane A1] [--all-releases]

A task is READY when its status is NOT_STARTED or READY, every dependency is DONE, its release is in
control.release_scope, and it has no open blocker. Ranking: longest remaining dependency chain (hours,
high estimate) first, so critical-path work is dispatched before slack work; ties by lane balance then ID.
Lane caps, write-glob overlaps and locks are applied by the orchestrator at dispatch time; this tool
reports them so the orchestrator can decide.
"""
from __future__ import annotations

import functools
import json
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
GRAPH = ROOT / "docs/22-implementation-readiness/revised-task-graph.json"
STATE = ROOT / "delivery/state.json"
PACKETS = ROOT / "delivery/packets"


def main() -> int:
    args = sys.argv[1:]
    as_json = "--json" in args
    limit = int(args[args.index("--limit") + 1]) if "--limit" in args else 30
    lane_filter = args[args.index("--lane") + 1] if "--lane" in args else None
    graph = json.loads(GRAPH.read_text())
    state = json.loads(STATE.read_text())
    scope = set(state["control"]["release_scope"]) if "--all-releases" not in args else {"R1", "R2"}
    tasks = {t["id"]: t for t in graph["tasks"] if not t.get("merged_into")}
    status = {tid: (state["tasks"].get(tid) or {}).get("status", "NOT_STARTED") for tid in tasks}
    children: dict[str, list[str]] = {}
    for t in tasks.values():
        for d in t["dependencies"]:
            children.setdefault(d, []).append(t["id"])

    @functools.lru_cache(None)
    def remaining(tid: str) -> float:
        own = 0 if status[tid] == "DONE" else tasks[tid]["estimate_high_h"]
        return own + max((remaining(c) for c in children.get(tid, []) if c in tasks), default=0)

    running = [l["task"] for l in state.get("leases", [])]
    lane_load: dict[str, int] = {}
    ready = []
    for tid, t in tasks.items():
        if status[tid] not in ("NOT_STARTED", "READY") or t["release"] not in scope:
            continue
        if any(status.get(d) != "DONE" for d in t["dependencies"]):
            continue
        if (state["tasks"].get(tid) or {}).get("blocked_by"):
            continue
        pk = PACKETS / f"{tid}.md"
        fm = yaml.safe_load(pk.read_text().split("---")[1]) if pk.exists() else {}
        lane = fm.get("lane", "?")
        if lane_filter and lane != lane_filter:
            continue
        ready.append({"id": tid, "title": t["title"], "lane": lane, "tier": fm.get("model_tier"),
                      "hours": [t["estimate_low_h"], t["estimate_high_h"]], "critical_remaining_h": remaining(tid),
                      "human_gates": fm.get("human_gates", []), "locks": fm.get("locks", []),
                      "writes": fm.get("writes", [])})
    for r in running:
        pk = PACKETS / f"{r}.md"
        if pk.exists():
            lane = yaml.safe_load(pk.read_text().split("---")[1]).get("lane")
            lane_load[lane] = lane_load.get(lane, 0) + 1
    ready.sort(key=lambda x: (-x["critical_remaining_h"], lane_load.get(x["lane"], 0), x["id"]))
    ready = ready[:limit]
    if as_json:
        print(json.dumps({"paused": state["control"]["paused"], "running": running, "ready": ready}, indent=2))
        return 0
    print(f"paused={state['control']['paused']}  running={len(running)}  ready={len(ready)} (showing ≤{limit})")
    print(f"{'task':9} {'lane':4} {'tier':4} {'hours':9} {'crit.rem':>8}  title")
    for x in ready:
        gates = " [human]" if x["human_gates"] else ""
        print(f"{x['id']:9} {x['lane']:4} {x['tier'] or '?':4} {x['hours'][0]:>3}–{x['hours'][1]:<4} {x['critical_remaining_h']:>8.0f}  {x['title'][:70]}{gates}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
