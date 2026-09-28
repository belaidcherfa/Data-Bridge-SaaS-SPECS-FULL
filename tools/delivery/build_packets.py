#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6"]
# ///
"""Generate agent task packets (delivery/packets/<ID>.md) from the revised task graph and backlogs.

Usage:  uv run tools/delivery/build_packets.py [--check]
        --check  exit 1 if any packet on disk differs from what would be generated (CI drift guard).

Inputs (all repository-relative):
  docs/22-implementation-readiness/revised-task-graph.json  tasks, releases, estimates, dependencies
  docs/22-implementation-readiness/backlog/<DOM>.md          micro-step tables, acceptance, meta
  docs/22-implementation-readiness/REVISED_CRITICAL_PATH.md  lane membership
  delivery/packet-overrides.yaml                              tiers, reviewers, human gates, extra writes
  delivery/state.json                                         task status (optional)
  contracts/_manifests/*.yaml                                 contract ownership (optional)
Format: docs/23-agentic-delivery/TASK_PACKET_FORMAT.md
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
READINESS = ROOT / "docs/22-implementation-readiness"
GRAPH = READINESS / "revised-task-graph.json"
BACKLOG = READINESS / "backlog"
CP_DOC = READINESS / "REVISED_CRITICAL_PATH.md"
OVERRIDES = ROOT / "delivery/packet-overrides.yaml"
STATE = ROOT / "delivery/state.json"
OUT = ROOT / "delivery/packets"
MANIFESTS = ROOT / "contracts/_manifests"

DOMAIN_LANE = {
    "AGT": "A0", "FND": "A1", "INF": "A1", "SEC": "A2", "CTL": "A2", "CON": "B", "ING": "B",
    "ORC": "B", "DBT": "C", "FIN": "C", "API": "D", "UX": "D", "WRK": "D", "ALC": "E", "GOV": "E",
    "RPT": "E", "INS": "F", "OPS": "G", "REL": "G", "ONB": "G", "LCH": "G", "SAS": "H", "PRO": "H",
}
CANONICAL = {
    "FND": "docs/01-architecture/engineering.md", "INF": "docs/17-devops/platform.md",
    "SEC": "docs/02-security/security.md", "CTL": "docs/03-control-plane/control-plane.md",
    "CON": "docs/04-snowflake-connectivity/connectivity.md", "ING": "docs/05-ingestion/ingestion.md",
    "ORC": "docs/06-dagster/orchestration.md", "DBT": "docs/07-dbt/transformation.md",
    "FIN": "docs/08-finops-ledger/ledger.md", "API": "docs/09-api/semantic-api.md",
    "UX": "docs/10-frontend/product.md", "WRK": "docs/10-frontend/workloads.md",
    "ALC": "docs/11-allocation/allocation.md", "GOV": "docs/12-budgets-monitoring/governance.md",
    "INS": "docs/13-insights/intelligence.md", "RPT": "docs/14-reporting/reporting.md",
    "OPS": "docs/16-observability/operations.md", "REL": "docs/19-production-readiness/readiness.md",
    "ONB": "docs/18-customer-onboarding/onboarding.md", "LCH": "docs/20-launch/launch.md",
    "AGT": "docs/23-agentic-delivery/ORCHESTRATION.md", "SAS": "docs/22-implementation-readiness/SAAS_COMPLETENESS.md",
    "PRO": "docs/22-implementation-readiness/SAAS_COMPLETENESS.md",
}
DOMAIN_CHECKS = {
    "default": ["make lint", "make typecheck", "make test-unit", "make contracts-check"],
    "DBT": ["make dbt-build-fixtures", "make dbt-test-fixtures"],
    "FIN": ["make dbt-build-fixtures", "make test-financial"],
    "ALC": ["make dbt-build-fixtures", "make test-financial"],
    "UX": ["make test-web", "make test-e2e-affected", "make a11y"],
    "INF": ["make infra-validate", "make tf-plan ENV=dev"],
    "SEC": ["make test-security"],
    "CTL": ["make test-integration-pg"],
}
LOCK_RULES = [
    (re.compile(r"(^|/)(uv\.lock|pnpm-lock\.yaml|package\.json|pyproject\.toml)$"), "lock:lockfiles"),
    (re.compile(r"migrations/versions|alembic"), "lock:pg-migrations"),
    (re.compile(r"infra/snowflake/migrations"), "lock:sf-migrations"),
    (re.compile(r"contracts/openapi/openapi\.yaml"), "lock:openapi-root"),
    (re.compile(r"\.github/workflows"), "lock:ci-workflows"),
    (re.compile(r"infra/terraform|infra/stacks"), "lock:terraform-state"),
]
PATH_RE = re.compile(r"`([A-Za-z0-9_.\-/{}<>*]+(?:/[A-Za-z0-9_.\-{}<>*]*)*)`")
LIVE_RE = re.compile(r"\b(staging|live|test estate|INF-101|real Snowflake|AWS staging|ENV=staging)\b", re.I)


def load_lanes() -> dict[str, str]:
    lanes: dict[str, str] = {}
    if not CP_DOC.exists():
        return lanes
    for m in re.finditer(r"^- \*\*(A1|A2|B|C|D|E|F|G) ·[^*]*\*\*[^:]*: (.+)$", CP_DOC.read_text(), re.M):
        lane, rest = m.group(1), m.group(2)
        body = rest.split(" R1*:")[0]
        for tid in re.findall(r"\b[A-Z]{2,3}-\d{3}\b", body):
            lanes.setdefault(tid, lane)
    return lanes


def split_backlog_sections() -> dict[str, str]:
    sections: dict[str, str] = {}
    for f in sorted(BACKLOG.glob("*.md")):
        text = f.read_text()
        parts = re.split(r"^### ", text, flags=re.M)
        for part in parts[1:]:
            m = re.match(r"([A-Z]{2,3}-\d{3})\b", part)
            if not m:
                continue
            tid = m.group(1)
            chunk = "### " + part
            # keep the first full section that contains a micro-step table
            if tid not in sections or ("-S01" in chunk and "-S01" not in sections[tid]):
                sections[tid] = re.split(r"^## ", chunk, flags=re.M)[0].rstrip()
    return sections


def anchor(title: str) -> str:
    a = title.strip().lower()
    a = re.sub(r"[^\w\- ]", "", a)
    return a.replace(" ", "-")


def extract(section: str) -> dict:
    lines = section.splitlines()
    meta = next((l for l in lines if l.startswith("Release:")), "")
    deps_line = next((l for l in lines if l.startswith("Dependency changes")), "")
    table = [l for l in lines if l.startswith("|")]
    steps = [l for l in table if re.match(r"^\|\s*[A-Z]{2,3}-\d{3}-S\d+", l)]
    acc: list[str] = []
    in_acc = False
    for l in lines:
        if l.lower().startswith("task acceptance"):
            in_acc = True
            continue
        if in_acc:
            if l.startswith("- ["):
                acc.append(l)
            elif l.strip() and not l.startswith("-"):
                in_acc = False
    decisions = sorted(set(re.findall(r"\bD-\d{2}\b", meta)))
    closes = sorted(set(re.findall(r"\bG-[A-Z]{2,3}-\d{2}\b", meta)))
    return {"meta": meta, "deps_line": deps_line, "table": table, "steps": steps, "acceptance": acc,
            "decisions": decisions, "closes": closes}


def derive_writes(tid: str, steps: list[str]) -> list[str]:
    globs: set[str] = set()
    for row in steps:
        cells = [c.strip() for c in row.strip().strip("|").split("|")]
        deliverable = cells[2] if len(cells) > 2 else ""
        for p in PATH_RE.findall(deliverable):
            if "/" not in p or p.startswith(("http", "/v1", "/t/")) or " " in p:
                continue
            p = re.sub(r"<[^>]+>|\{[^}]+\}", "*", p)
            if re.search(r"\.[A-Za-z0-9]{1,6}$", p.split("/")[-1]) and "*" not in p.split("/")[-1]:
                globs.add(p)
            else:
                globs.add(p.rstrip("/") + "/**")
    globs.add(f"tests/spec/{tid}/**")
    globs.add(f"docs/evidence/{tid}/**")
    return sorted(globs)


DOMAIN_ROOTS = {
    "FND": ["docs/development/**", "tools/**", "Makefile"], "INF": ["infra/**"], "SEC": ["services/api/src/bridge_api/security/**", "packages/bridge_authz/**"],
    "CTL": ["services/api/src/bridge_api/control/**", "services/api/migrations/**"], "CON": ["services/connector/**"],
    "ING": ["services/extractor/**", "services/ingestion/**"], "ORC": ["services/orchestrator/**"], "DBT": ["data/dbt/**"],
    "FIN": ["data/dbt/models/ledger/**", "data/dbt/tests/**", "data/dbt/seeds/**"], "API": ["services/api/src/bridge_api/analytics/**", "packages/semantic_metrics/**"],
    "UX": ["apps/web/**"], "WRK": ["packages/workload_meta/**", "data/dbt/models/workloads/**"], "ALC": ["data/dbt/models/allocation/**", "services/api/src/bridge_api/allocation/**"],
    "GOV": ["services/governance/**", "packages/bridge_stats/**"], "INS": ["services/intelligence/**"], "RPT": ["services/reporting/**"],
    "OPS": ["infra/observability/**", "packages/telemetry/**", "docs/operations/**"], "REL": ["docs/releases/**", ".github/workflows/**"],
    "ONB": ["services/api/src/bridge_api/onboarding/**", "apps/web/src/features/onboarding/**"], "LCH": ["services/api/src/bridge_api/commercial/**", "docs/commercial/**", "docs/legal/**"],
    "AGT": ["tools/orchestrator/**", "tools/delivery/**", "delivery/**", ".claude/**"], "SAS": ["apps/**", "services/**"], "PRO": ["services/**", "apps/web/**"],
}


def original_outputs(dom: str, tid: str) -> list[str]:
    f = ROOT / f"docs/tasks/{dom}/{tid}.md"
    if not f.exists():
        return []
    m = re.search(r"^## Outputs and likely files/components\n+(.+?)\n## ", f.read_text(), re.S | re.M)
    if not m:
        return []
    out = []
    for p in PATH_RE.findall(m.group(1)):
        if p.startswith(("tests/spec", "docs/evidence")) or "<" in p:
            continue
        out.append(p if re.search(r"\.[A-Za-z0-9]{1,6}$", p) else p.rstrip("/") + "/**")
    return out


def contract_owners() -> dict[str, list[str]]:
    owners: dict[str, list[str]] = {}
    if not MANIFESTS.exists():
        return owners
    for f in MANIFESTS.glob("*.yaml"):
        try:
            data = yaml.safe_load(f.read_text()) or {}
        except yaml.YAMLError:
            continue
        entries = data if isinstance(data, list) else data.get("artifacts", data.get("entries", []))
        for e in entries or []:
            if isinstance(e, dict) and e.get("path") and e.get("owner_task"):
                for t in re.findall(r"[A-Z]{2,3}-\d{3}", str(e["owner_task"])):
                    owners.setdefault(t, []).append(str(e["path"]))
    return owners


def tier(tid: str, dom: str, ov: dict) -> str:
    if tid in ov.get("tier_c_tasks", []):
        return "C"
    if dom in ov.get("tier_a_domains", []) or tid in ov.get("tier_a_tasks", []):
        return "A"
    return "B"


def reviewers(tid: str, dom: str, ov: dict) -> list[str]:
    out = ["reviewer"]
    for kind, items in (ov.get("specialized_reviewers") or {}).items():
        if tid in items or dom in items:
            out.append(f"{kind}-reviewer")
    return out


def yaml_block(data: dict) -> str:
    return yaml.safe_dump(data, sort_keys=False, allow_unicode=True, width=200).rstrip()


def build() -> dict[str, str]:
    graph = json.loads(GRAPH.read_text())
    tasks = {t["id"]: t for t in graph["tasks"]}
    ov = yaml.safe_load(OVERRIDES.read_text()) if OVERRIDES.exists() else {}
    state = json.loads(STATE.read_text()) if STATE.exists() else {"tasks": {}}
    lanes = load_lanes()
    sections = split_backlog_sections()
    owners = contract_owners()
    blocks: dict[str, list[str]] = {}
    for t in tasks.values():
        for d in t["dependencies"]:
            blocks.setdefault(d, []).append(t["id"])
    packets: dict[str, str] = {}
    for tid, t in sorted(tasks.items()):
        if t.get("merged_into"):
            continue
        dom = t["domain"]
        sec = sections.get(tid, "")
        ex = extract(sec) if sec else {"meta": "", "deps_line": "", "table": [], "steps": [], "acceptance": [],
                                        "decisions": [], "closes": []}
        writes = derive_writes(tid, ex["steps"]) + original_outputs(dom, tid) + list((ov.get("extra_writes") or {}).get(tid, []))
        if len([w for w in writes if not w.startswith(("tests/spec/", "docs/evidence/"))]) < 1:
            writes += DOMAIN_ROOTS.get(dom, [])
        writes = sorted(dict.fromkeys(writes))
        locks = sorted({lock for w in writes for rx, lock in LOCK_RULES if rx.search(w)})
        contracts = ["contracts/CONVENTIONS.md"]
        for d in t["dependencies"]:
            contracts += owners.get(d, [])
        contracts += owners.get(tid, [])
        contracts += [p for p in PATH_RE.findall(sec) if p.startswith(("contracts/", "data/contracts/"))]
        contracts = list(dict.fromkeys(contracts))
        live = sorted({"snowflake-or-aws-test-estate"} if LIVE_RE.search(sec) else set())
        title_line = sec.splitlines()[0][4:] if sec else f"{tid} — {t['title']}"
        backlog_file = f"docs/22-implementation-readiness/backlog/{dom}.md"
        checks = DOMAIN_CHECKS["default"] + DOMAIN_CHECKS.get(dom, []) + [f"make validate-task TASK={tid} ENV=local"]
        fm = {
            "packet_version": 1,
            "id": tid,
            "title": t["title"],
            "domain": dom,
            "lane": (ov.get("lanes") or {}).get(tid) or lanes.get(tid) or DOMAIN_LANE.get(dom, "G"),
            "release": t["release"],
            "status": (state.get("tasks", {}).get(tid) or {}).get("status", t.get("status", "NOT_STARTED")),
            "model_tier": tier(tid, dom, ov),
            "reviewers": reviewers(tid, dom, ov),
            "estimate_hours": [t["estimate_low_h"], t["estimate_high_h"]],
            "depends_on": sorted(t["dependencies"]),
            "blocks": sorted(blocks.get(tid, [])),
            "decisions": ex["decisions"],
            "closes_findings": ex["closes"],
            "backlog_ref": f"{backlog_file}#{anchor(title_line)}" if sec else t.get("backlog_ref"),
            "original_task": f"docs/tasks/{dom}/{tid}.md" if (ROOT / f"docs/tasks/{dom}/{tid}.md").exists() else None,
            "canonical_refs": [CANONICAL[dom]] if dom in CANONICAL else [],
            "contracts_read": contracts,
            "writes": writes,
            "locks": locks,
            "human_gates": (ov.get("human_gates") or {}).get(tid, []),
            "live_gates": live,
            "checks": checks,
            "evidence_path": f"docs/evidence/{tid}/<short-sha>/",
            "micro_steps": [re.match(r"^\|\s*([A-Z]{2,3}-\d{3}-S\d+)", s).group(1) for s in ex["steps"]],
        }
        body = [f"---\n{yaml_block(fm)}\n---", "",
                f"# {tid} — {t['title']}", "",
                "> Generated by `tools/delivery/build_packets.py` — do not edit. Change the backlog, graph or "
                "`delivery/packet-overrides.yaml`, then run `make packets`.", "",
                "## Objective", "",
                f"Deliver {tid} exactly as specified in its backlog section and the contracts below. Release {t['release']}, "
                f"lane {fm['lane']}, tier {fm['model_tier']}.", "",
                f"Backlog meta: {ex['meta'] or 'n/a'}", "",
                f"{ex['deps_line']}" if ex["deps_line"] else "", "",
                "## Read first", "",
                "1. `AGENTS.md` (rules, definition of done, escalation).",
                f"2. The backlog section: `{fm['backlog_ref']}`.",
                *[f"{i}. `{c}`" for i, c in enumerate(fm["contracts_read"] + fm["canonical_refs"], start=3)],
                f"{len(fm['contracts_read']) + len(fm['canonical_refs']) + 3}. `docs/22-implementation-readiness/RECONCILIATION.md` — search for {tid}.",
                f"{len(fm['contracts_read']) + len(fm['canonical_refs']) + 4}. `docs/22-implementation-readiness/DECISIONS_REQUIRED.md` — decisions {', '.join(ex['decisions']) or 'n/a'}.",
                "",
                "## Micro-steps", "",
                *(ex["table"] or ["_No micro-step table found in the backlog — escalate before starting._"]), "",
                "## Task acceptance", "",
                *(ex["acceptance"] or ["- [ ] See backlog section."]), "",
                "## Definition of done (agent)", "",
                "- [ ] Every micro-step's *Done when* oracle passes and is ticked in the PR description.",
                "- [ ] All `checks` above pass locally and in CI; no test skipped, weakened or quarantined.",
                "- [ ] Diff stays inside `writes`; required `locks` were held; contracts unchanged unless owned.",
                "- [ ] Tenant-isolation, money and UX-state rules of AGENTS.md satisfied where applicable.",
                f"- [ ] Evidence manifest written to `{fm['evidence_path']}` and linked in the PR.",
                "- [ ] Human/live gates prepared and handed off (see below).", "",
                "## Gates", "",
                *(["- Human: " + g for g in fm["human_gates"]] or ["- Human: none"]),
                *(["- Live: " + g + " (run in CI with OIDC; first run witnessed by a human reviewer)" for g in fm["live_gates"]] or ["- Live: none"]),
                "",
                "## Out of scope", "",
                "Anything not listed in the micro-steps. Work belonging to downstream tasks: "
                + (", ".join(fm["blocks"]) if fm["blocks"] else "none") + ".", "",
                "## Escalate when", "",
                "- A contract, decision or dependency output is missing, contradictory or would need to change.",
                "- A vendor behavior differs from the spec (a `TO VERIFY LIVE` assumption fails).",
                "- The diff would leave `writes`, need a lock you cannot get, or exceed the budget.",
                "- Two attempts failed, or a security/financial invariant might be violated.", ""]
        packets[tid] = "\n".join(line for line in body if line is not None) + "\n"
    return packets


def main() -> int:
    check = "--check" in sys.argv
    packets = build()
    OUT.mkdir(parents=True, exist_ok=True)
    drift = []
    for tid, text in packets.items():
        path = OUT / f"{tid}.md"
        if check:
            if not path.exists() or path.read_text() != text:
                drift.append(tid)
        else:
            path.write_text(text)
    index = ["# Task packets", "", "Generated; see docs/23-agentic-delivery/TASK_PACKET_FORMAT.md.", "",
             "| Task | Lane | Release | Tier | Hours | Human gates |", "|---|---|---|---|---|---|"]
    for tid, text in sorted(packets.items()):
        fm = yaml.safe_load(text.split("---")[1])
        index.append(f"| [{tid}]({tid}.md) | {fm['lane']} | {fm['release']} | {fm['model_tier']} | "
                     f"{fm['estimate_hours'][0]}–{fm['estimate_hours'][1]} | {len(fm['human_gates'])} |")
    if not check:
        (OUT / "README.md").write_text("\n".join(index) + "\n")
        print(f"wrote {len(packets)} packets to {OUT.relative_to(ROOT)}")
    elif drift:
        print("packet drift:", ", ".join(drift))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
