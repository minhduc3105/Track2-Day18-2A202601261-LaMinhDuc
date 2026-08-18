## Day 18 Lakehouse Lab — student UX
## Two paths: lightweight (default, pure Python) and Spark (Docker, optional).

VENV       := .venv

# Use PowerShell and the Windows virtual-environment layout when invoked by
# GNU Make on Windows. Keep the Unix defaults for macOS/Linux and CI.
ifeq ($(OS),Windows_NT)
SHELL       := powershell.exe
.SHELLFLAGS := -NoProfile -ExecutionPolicy Bypass -Command
# PowerShell may expose a legacy CP1252 console; notebooks and smoke output
# include Unicode symbols, so force Python's UTF-8 mode for every target.
export PYTHONUTF8 := 1
WIN_VENV_BIN := .\$(VENV)\Scripts
# An existing environment made by MSYS/Git Bash can use bin/ even on Windows.
ifneq ($(wildcard $(VENV)/Scripts/python.exe),)
WIN_VENV_BIN := .\$(VENV)\Scripts
else ifneq ($(wildcard $(VENV)/bin/python.exe),)
WIN_VENV_BIN := .\$(VENV)\bin
endif
PY          := $(WIN_VENV_BIN)\python.exe
PIP         := $(WIN_VENV_BIN)\pip.exe
JUPYTER     := $(WIN_VENV_BIN)\jupyter.exe
JUPYTEXT    := $(WIN_VENV_BIN)\jupytext.exe
PYTEST      := $(WIN_VENV_BIN)\pytest.exe
else
PY          := $(VENV)/bin/python
PIP         := $(VENV)/bin/pip
JUPYTER     := $(VENV)/bin/jupyter
JUPYTEXT    := $(VENV)/bin/jupytext
PYTEST      := $(VENV)/bin/pytest
endif
COMPOSE    := docker compose -f docker/docker-compose.yml

.DEFAULT_GOAL := help

help: ## Show this help
ifeq ($(OS),Windows_NT)
	@Write-Host "`nUsage:`n  make <target>`n"; Get-Content "$(firstword $(MAKEFILE_LIST))" | ForEach-Object { if ($$_ -match '^([a-zA-Z_-]+):.*?##\s*(.+)$$') { "  {0,-14} {1}" -f $$matches[1], $$matches[2] } }
else
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make <target>\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  %-14s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
endif

# ─────────────────────────────────────────────────────────────
# Lightweight path (default) — pure Python, no Docker, no JVM
# ─────────────────────────────────────────────────────────────

setup: ## [lite] Create venv + install deps (~180 MB, ~20s with pip / ~4s with uv)
ifeq ($(OS),Windows_NT)
	@$$uv = Get-Command uv -ErrorAction SilentlyContinue; if ($$null -ne $$uv) { & $$uv.Source venv $(VENV) --clear --python '>=3.10,<3.14' } else { python -m venv --clear $(VENV) }; if ($$LASTEXITCODE -ne 0) { exit $$LASTEXITCODE }
	@& $(PY) -c "import sys; raise SystemExit(0 if (3,10)<=sys.version_info[:2]<(3,14) else 1)"; if ($$LASTEXITCODE -ne 0) { Write-Error "ERROR: need Python 3.10-3.13. Install uv or create .venv with a supported Python version."; exit 1 }
	@$$uv = Get-Command uv -ErrorAction SilentlyContinue; if ($$null -ne $$uv) { & $$uv.Source pip install --python $(PY) -r requirements.txt } else { & $(PIP) install -q -r requirements.txt }; if ($$LASTEXITCODE -ne 0) { exit $$LASTEXITCODE }
	@Get-ChildItem -Path notebooks -Filter *.py | ForEach-Object { & $(JUPYTEXT) --to notebook --update $$_.FullName; if ($$LASTEXITCODE -ne 0) { exit $$LASTEXITCODE } }
else
	@command -v uv >/dev/null 2>&1 && uv venv $(VENV) --clear --python '>=3.10,<3.14' || python3 -m venv --clear $(VENV)
	@$(PY) -c 'import sys; raise SystemExit(0 if (3,10)<=sys.version_info[:2]<(3,14) else 1)' || { echo "ERROR: need Python 3.10-3.13. Install 'uv' (auto-fetches one) or run: python3.12 -m venv .venv"; exit 1; }
	@command -v uv >/dev/null 2>&1 && uv pip install --python $(PY) -r requirements.txt || $(PIP) install -q -r requirements.txt
	@$(JUPYTEXT) --to notebook --update notebooks/*.py 2>/dev/null || $(JUPYTEXT) --to notebook notebooks/*.py
endif

ifeq ($(OS),Windows_NT)
	@Write-Host ""
	@Write-Host "Setup complete. Run make smoke, then make lab."
else
	@echo ""
	@echo "  ✓ Setup complete. Run 'make smoke' then 'make lab'."
endif

smoke: ## [lite] ~15-second end-to-end smoke test (Delta + Iceberg + vectors)
	@$(PY) scripts/verify_lite.py

test: ## [lite] Run the pytest suite the instructor grades against
	@$(PYTEST) -q

lab: ## [lite] Open Jupyter Lab on http://localhost:8888
ifeq ($(OS),Windows_NT)
	@Get-ChildItem -Path notebooks -Filter *.py | ForEach-Object { & $(JUPYTEXT) --to notebook --update $$_.FullName; if ($$LASTEXITCODE -ne 0) { Write-Warning "Could not update $$_.Name" } }
	@& $(JUPYTER) lab --notebook-dir=notebooks --ServerApp.token='' --no-browser
else
	@$(JUPYTEXT) --to notebook --update notebooks/*.py 2>/dev/null || true
	@$(JUPYTER) lab --notebook-dir=notebooks --ServerApp.token='' --no-browser
endif

data: ## [lite] Generate 200K-row Bronze sample for NB4
	@$(PY) scripts/generate_data_lite.py

data-ai: ## [lite] Generate multimodal + agent-trajectory sample for NB7/NB8
	@$(PY) scripts/generate_ai_data.py

run-all: ## [lite] Execute every notebook headlessly (what CI does)
	@$(PY) scripts/run_all.py

simulate: ## [lite] Abuse the lab the way students do (12 scenarios; SIM_FAST=1 to skip venv builds)
	@$(PY) tests/simulate_students.py

clean: ## [lite] Wipe venv + lakehouse data
ifeq ($(OS),Windows_NT)
	@Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $(VENV), _lakehouse, notebooks/.ipynb_checkpoints, .pytest_cache
else
	rm -rf $(VENV) _lakehouse notebooks/.ipynb_checkpoints .pytest_cache
endif

# ─────────────────────────────────────────────────────────────
# Spark on Apple `container` (optional) — macOS 15+, Apple silicon
# Same 3-service stack as the compose path, driven by `container run`,
# because Apple's runtime has no compose plugin and no Docker socket.
# ─────────────────────────────────────────────────────────────

AC := scripts/apple_container.sh

apple-up: ## [apple] Start MinIO + buckets + Spark/Jupyter via Apple `container`
	@$(AC) up

apple-smoke: ## [apple] Run scripts/verify.py in the Spark container
	@$(AC) smoke

apple-data: ## [apple] Generate the 1M-row Bronze table via Spark
	@$(AC) data

apple-status: ## [apple] Show containers + MinIO's injected IP
	@$(AC) status

apple-down: ## [apple] Stop and remove containers (MinIO data kept)
	@$(AC) down

apple-clean: ## [apple] Same as apple-down, plus delete _minio-data/
	@$(AC) clean

# ─────────────────────────────────────────────────────────────
# Spark + Docker path (optional, production-fidelity)
# ─────────────────────────────────────────────────────────────

spark-up: ## [spark] Start MinIO + Spark/Jupyter (Docker — first run pulls ~2 GB)
	$(COMPOSE) up -d
	@echo "  Jupyter → http://localhost:8888 (token: lakehouse)"
	@echo "  MinIO   → http://localhost:9001 (minioadmin / minioadmin)"

spark-smoke: ## [spark] Smoke test inside Spark container
	$(COMPOSE) exec -T spark python /workspace/scripts/verify.py

spark-data: ## [spark] Generate 1M-row Bronze (Spark version)
	$(COMPOSE) exec -T spark python /workspace/scripts/generate_data.py

spark-down: ## [spark] Stop Docker stack (data persists)
	$(COMPOSE) down

spark-clean: ## [spark] Stop AND wipe MinIO + ivy cache
	$(COMPOSE) down -v

.PHONY: help setup smoke test lab data data-ai run-all clean \
        simulate apple-up apple-smoke apple-data apple-status apple-down apple-clean \
        spark-up spark-smoke spark-data spark-down spark-clean
