# Bridge Data FinOps — repository dispatcher.
# Wave-0 targets for the agentic delivery system. FND-005 extends this file with the full validation
# dispatcher (bootstrap/up/test/validate-task); keep target names stable (AGENTS.md §5).
SHELL := /bin/bash
UV ?= uv
PY_RUN := $(shell command -v $(UV) >/dev/null 2>&1 && echo "$(UV) run" || echo "python3")

.PHONY: help packets packets-check next-tasks contracts-check delivery-check state-validate

help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  %-20s %s\n", $$1, $$2}'

packets: ## Regenerate delivery/packets from the revised graph and backlogs
	$(PY_RUN) tools/delivery/build_packets.py

packets-check: ## Fail if generated packets drift from sources
	$(PY_RUN) tools/delivery/build_packets.py --check

next-tasks: ## Show ready tasks ranked by remaining critical path
	$(PY_RUN) tools/delivery/next_tasks.py

contracts-check: ## Validate contracts (JSON/YAML/JSON Schema/SQL/OpenAPI refs/state machines)
	$(PY_RUN) tools/contracts/check.py

state-validate: ## Validate delivery/state.json against its schema
	$(PY_RUN) tools/delivery/validate_state.py

delivery-check: contracts-check packets-check state-validate ## All delivery-system checks (CI)
