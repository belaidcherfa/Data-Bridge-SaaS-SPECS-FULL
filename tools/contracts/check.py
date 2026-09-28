#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6", "jsonschema>=4.23", "sqlglot>=30", "pglast>=7"]
# ///
"""Validate executable contracts (CONVENTIONS.md §14, ADR-017).

Usage: uv run tools/contracts/check.py [--strict]

Checks
  1. Every *.json under contracts/, data/contracts/, packages/*/schema*, infra/, config/ parses.
  2. Every *.yaml/*.yml under the same roots parses.
  3. JSON Schemas ($schema draft 2020-12) are valid schemas; their `examples` validate.
  4. contracts/postgres/*.sql and services/*/migrations/**/*.sql parse with the real PostgreSQL parser
     (pglast/libpg_query: errors); infra/snowflake/migrations/**/*.sql parse with sqlglot's Snowflake
     dialect (statements sqlglot cannot parse are warnings, not errors, unless --strict).
  5. OpenAPI path/component files are YAML mappings; local $ref targets exist.
  6. Problem codes are unique across contracts/errors/problems/*.yaml and match the schema.
  7. Event types are unique across contracts/events/catalog/*.yaml.
  8. State machines (contracts/state-machines/*.yaml): states declared, transitions reference declared
     states, no transition leaves a terminal state, every non-initial state is reachable.
  9. Contract headers: files under contracts/ carry `status` (DRAFT|ACCEPTED|DEPRECATED) somewhere in
     their header comment or $comment (warning only).
Exit code 1 on any error.
"""
from __future__ import annotations

import json
import logging
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
ROOTS = ["contracts", "data/contracts", "packages", "infra", "config", "delivery"]
SKIP_DIRS = {"node_modules", ".venv", "dist", "build", "__pycache__", "packets", "reports", "worktrees"}
errors: list[str] = []
warnings: list[str] = []


def files(pattern: str):
    for r in ROOTS:
        base = ROOT / r
        if not base.exists():
            continue
        for p in base.rglob(pattern):
            if not SKIP_DIRS.intersection(p.parts):
                yield p


def rel(p: Path) -> str:
    return str(p.relative_to(ROOT))


def check_json_yaml() -> dict[Path, object]:
    docs: dict[Path, object] = {}
    for p in files("*.json"):
        try:
            docs[p] = json.loads(p.read_text())
        except Exception as e:  # noqa: BLE001
            errors.append(f"JSON parse {rel(p)}: {e}")
    for pat in ("*.yaml", "*.yml"):
        for p in files(pat):
            try:
                docs[p] = yaml.safe_load(p.read_text())
            except Exception as e:  # noqa: BLE001
                errors.append(f"YAML parse {rel(p)}: {e}")
    return docs


def check_schemas(docs: dict[Path, object]) -> None:
    try:
        from jsonschema import Draft202012Validator
        from jsonschema.exceptions import SchemaError
    except ImportError:
        warnings.append("jsonschema not installed: schema checks skipped")
        return
    for p, d in docs.items():
        if not isinstance(d, dict) or "2020-12" not in str(d.get("$schema", "")):
            continue
        try:
            Draft202012Validator.check_schema(d)
        except SchemaError as e:
            errors.append(f"Invalid JSON Schema {rel(p)}: {e.message}")
            continue
        has_ext_ref = "$ref" in json.dumps(d) and re.search(r'"\$ref":\s*"(?!#)', json.dumps(d))
        if has_ext_ref:
            continue  # examples with external refs are validated by the language test suites
        v = Draft202012Validator(d)
        for i, ex in enumerate(d.get("examples", []) or []):
            for err in v.iter_errors(ex):
                errors.append(f"Example {i} fails {rel(p)}: {err.message}")


def split_sql(text: str) -> list[str]:
    text = re.sub(r"--[^\n]*", "", text)
    # keep $$-quoted bodies intact
    parts, buf, in_dollar = [], [], False
    for line in text.splitlines(keepends=True):
        if line.count("$$") % 2 == 1:
            in_dollar = not in_dollar
        buf.append(line)
        if not in_dollar and line.rstrip().endswith(";"):
            parts.append("".join(buf))
            buf = []
    if "".join(buf).strip():
        parts.append("".join(buf))
    return [s for s in parts if s.strip()]


def check_sql(strict: bool) -> None:
    pg_targets = sorted((ROOT / "contracts/postgres").rglob("*.sql")) if (ROOT / "contracts/postgres").exists() else []
    pg_targets += sorted(p for p in (ROOT / "services").glob("*/migrations/**/*.sql")) if (ROOT / "services").exists() else []
    try:
        import pglast
        for p in pg_targets:
            try:
                pglast.parse_sql(p.read_text())
            except Exception as e:  # noqa: BLE001
                errors.append(f"SQL (postgres) {rel(p)}: {str(e).splitlines()[0][:200]}")
    except ImportError:
        warnings.append("pglast not installed: PostgreSQL checks skipped")
    try:
        import sqlglot
        logging.getLogger("sqlglot").setLevel(logging.ERROR)
    except ImportError:
        warnings.append("sqlglot not installed: Snowflake SQL checks skipped")
        return
    sf = ROOT / "infra/snowflake/migrations"
    for p in sorted(sf.rglob("*.sql")) if sf.exists() else []:
        for stmt in split_sql(p.read_text()):
            try:
                sqlglot.parse_one(stmt, read="snowflake")
            except Exception as e:  # noqa: BLE001
                msg = f"SQL (snowflake) {rel(p)}: {str(e).splitlines()[0][:160]}"
                (errors if strict else warnings).append(msg)


def check_openapi_refs(docs: dict[Path, object]) -> None:
    for p in list((ROOT / "contracts/openapi").rglob("*.yaml")) if (ROOT / "contracts/openapi").exists() else []:
        text = p.read_text()
        for ref in re.findall(r"\$ref:\s*['\"]?([^'\"#\s]+)(#[^'\"\s]*)?", text):
            target = (p.parent / ref[0]).resolve()
            if ref[0] and not target.exists():
                errors.append(f"OpenAPI $ref target missing in {rel(p)}: {ref[0]}")


def check_problems() -> None:
    seen: dict[str, str] = {}
    for p in (ROOT / "contracts/errors/problems").glob("*.yaml") if (ROOT / "contracts/errors/problems").exists() else []:
        d = yaml.safe_load(p.read_text()) or {}
        for prob in d.get("problems", []) if isinstance(d, dict) else []:
            code = prob.get("code")
            if code in seen:
                errors.append(f"Duplicate problem code {code} in {rel(p)} and {seen[code]}")
            seen[code] = rel(p)
            for f in ("code", "http_status", "title", "retryable"):
                if f not in prob:
                    errors.append(f"Problem {code} in {rel(p)} missing {f}")


def check_events() -> None:
    seen: dict[str, str] = {}
    base = ROOT / "contracts/events/catalog"
    for p in base.glob("*.yaml") if base.exists() else []:
        d = yaml.safe_load(p.read_text()) or {}
        items = d.get("events", []) if isinstance(d, dict) else d
        for ev in items or []:
            t = ev.get("type") if isinstance(ev, dict) else None
            if not t:
                continue
            if t in seen:
                errors.append(f"Duplicate event type {t} in {rel(p)} and {seen[t]}")
            seen[t] = rel(p)


def check_state_machines() -> None:
    base = ROOT / "contracts/state-machines"
    for p in base.glob("*.yaml") if base.exists() else []:
        d = yaml.safe_load(p.read_text()) or {}
        if not isinstance(d, dict) or "states" not in d:
            errors.append(f"State machine {rel(p)} has no states")
            continue
        states = set(d["states"].keys()) if isinstance(d["states"], dict) else set(d["states"])
        terminal = set(d.get("terminal", []) or [])
        initial = d.get("initial")
        if initial not in states:
            errors.append(f"{rel(p)}: initial state {initial} not declared")
        adj: dict[str, set[str]] = {}
        for tr in d.get("transitions", []) or []:
            frm = tr.get("from")
            frms = frm if isinstance(frm, list) else [frm]
            to = tr.get("to")
            for f in frms:
                if f not in states and f != "*":
                    errors.append(f"{rel(p)}: transition from undeclared state {f}")
                if f in terminal:
                    errors.append(f"{rel(p)}: transition out of terminal state {f}")
                adj.setdefault(f, set()).add(to)
            if to not in states:
                errors.append(f"{rel(p)}: transition to undeclared state {to}")
            if not tr.get("event"):
                errors.append(f"{rel(p)}: transition {frm}->{to} has no event")
        seen, stack = {initial}, [initial]
        while stack:
            s = stack.pop()
            for n in adj.get(s, set()) | adj.get("*", set()):
                if n not in seen:
                    seen.add(n)
                    stack.append(n)
        for s in states - seen:
            warnings.append(f"{rel(p)}: state {s} unreachable from {initial}")


def check_headers() -> None:
    for p in (ROOT / "contracts").rglob("*"):
        if p.is_file() and p.suffix in {".json", ".yaml", ".yml", ".sql"} and "_manifests" not in p.parts and "_handoffs" not in p.parts:
            head = p.read_text()[:600]
            if not re.search(r"status[=:]\s*\"?(DRAFT|ACCEPTED|DEPRECATED)", head):
                warnings.append(f"Header without status: {rel(p)}")


def main() -> int:
    strict = "--strict" in sys.argv
    docs = check_json_yaml()
    check_schemas(docs)
    check_sql(strict)
    check_openapi_refs(docs)
    check_problems()
    check_events()
    check_state_machines()
    check_headers()
    for w in warnings:
        print("WARN ", w)
    for e in errors:
        print("ERROR", e)
    print(f"contracts-check: {len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
