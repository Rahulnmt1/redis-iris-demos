BACKEND_HOST ?= 127.0.0.1
BACKEND_PORT ?= $(or $(shell grep -s '^BACKEND_PORT=' .env | cut -d= -f2),8141)
FRONTEND_PORT ?= $(or $(shell grep -s '^FRONTEND_PORT=' .env | cut -d= -f2),3141)

# Active domain: reads DEMO_DOMAIN from .env automatically.
# Override with: make <target> DOMAIN=electrohub
DOMAIN ?= $(or $(shell grep -s '^DEMO_DOMAIN=' .env | cut -d= -f2),reddash)

# Wrap every command that needs credentials so secrets are pulled from macOS
# Keychain at runtime and never live in plain text on disk.
WITH_SECRETS := bin/with-secrets.sh

.PHONY: help domains setup reset dev backend frontend install \
	backend-install frontend-install \
	generate-models generate-data setup-surface load-data \
	seed-memories seed-langcache seed-all flush-redis \
	validate-domain smoke-domain create-domain \
	secrets-setup secrets-paste secrets-list secrets-check

help:
	@echo ""
	@echo "  make secrets-paste      Guided clipboard-driven setup (recommended)"
	@echo "  make secrets-setup      Silent prompt-each-value setup"
	@echo "  make secrets-list       Show which secrets are configured (no values shown)"
	@echo "  make secrets-check      Verify required secrets are present"
	@echo ""
	@echo "  make domains            Show available domains"
	@echo "  make setup [DOMAIN=X]   Full setup (first time or switch domain)"
	@echo "  make reset              Reload data for current domain"
	@echo "  make dev                Start backend + frontend"
	@echo ""
	@echo "  make install            Install Python + JS dependencies"
	@echo "  make seed-memories      Re-seed long-term memories"
	@echo "  make seed-langcache     Re-seed LangCache entries"
	@echo "  make flush-redis        Wipe Redis (preserves Agent Memory)"
	@echo ""
	@echo "  Active domain:   $(DOMAIN)"
	@echo "  Backend port:    $(BACKEND_PORT)"
	@echo "  Frontend port:   $(FRONTEND_PORT)"
	@echo ""

secrets-setup:
	@bin/secrets.sh setup

secrets-paste:
	@bin/secrets.sh setup-clipboard

secrets-list:
	@bin/secrets.sh list

secrets-check:
	@bin/secrets.sh check

domains:
	@echo ""
	@echo "Available domains:"
	@echo ""
	@for d in domains/*/domain.py; do \
		name=$$(basename $$(dirname $$d)); \
		if [ "$$name" = "$(DOMAIN)" ]; then \
			printf "  %-25s <- active\n" "$$name"; \
		else \
			printf "  %-25s\n" "$$name"; \
		fi; \
	done
	@echo ""
	@echo "Switch: make setup DOMAIN=<name>"
	@echo ""

setup:
	@if [ ! -f .env ]; then echo "No .env file. Run: cp .env.example .env"; exit 1; fi
	@echo "Setting up $(DOMAIN)..."
	@echo ""
	@sed -i '' 's/^DEMO_DOMAIN=.*/DEMO_DOMAIN=$(DOMAIN)/' .env
	@$(WITH_SECRETS) uv run python scripts/generate_models.py --domain $(DOMAIN)
	@$(WITH_SECRETS) uv run python scripts/generate_data.py --domain $(DOMAIN)
	@$(WITH_SECRETS) uv run python scripts/flush_redis.py
	@$(WITH_SECRETS) bin/clear-surface-keys.sh
	@$(WITH_SECRETS) uv run python scripts/setup_surface.py --domain $(DOMAIN)
	@$(WITH_SECRETS) uv run python scripts/load_data.py --domain $(DOMAIN)
	@$(WITH_SECRETS) env DEMO_DOMAIN=$(DOMAIN) uv run python -m scripts.seed_memories
	@$(WITH_SECRETS) env DEMO_DOMAIN=$(DOMAIN) uv run python -m scripts.seed_langcache
	@echo ""
	@echo "Done. Run 'make dev' to start."

reset:
	@echo "Reloading $(DOMAIN)..."
	@echo ""
	@$(WITH_SECRETS) uv run python scripts/flush_redis.py
	@$(WITH_SECRETS) bin/clear-surface-keys.sh
	@$(WITH_SECRETS) uv run python scripts/setup_surface.py --domain $(DOMAIN)
	@$(WITH_SECRETS) uv run python scripts/load_data.py --domain $(DOMAIN)
	@$(WITH_SECRETS) env DEMO_DOMAIN=$(DOMAIN) uv run python -m scripts.seed_memories
	@$(WITH_SECRETS) env DEMO_DOMAIN=$(DOMAIN) uv run python -m scripts.seed_langcache
	@echo ""
	@echo "Done. Run 'make dev' to start."

# --- Individual steps ---

backend-install:
	@uv sync

frontend-install:
	@cd frontend && npm install

install: backend-install frontend-install

generate-models:
	@$(WITH_SECRETS) uv run python scripts/generate_models.py --domain $(DOMAIN)

generate-data:
	@$(WITH_SECRETS) uv run python scripts/generate_data.py --domain $(DOMAIN)

load-data:
	@$(WITH_SECRETS) uv run python scripts/load_data.py --domain $(DOMAIN)

setup-surface:
	@$(WITH_SECRETS) uv run python scripts/setup_surface.py --domain $(DOMAIN)

validate-domain:
	@$(WITH_SECRETS) uv run python scripts/validate_domain.py --domain $(DOMAIN)

smoke-domain:
	@$(WITH_SECRETS) uv run python scripts/smoke_domain.py --domain $(DOMAIN)

create-domain:
	@uv run python scripts/create_domain.py $(DOMAIN)

backend:
	@$(WITH_SECRETS) uv run uvicorn backend.app.main:app --reload --host $(BACKEND_HOST) --port $(BACKEND_PORT)

frontend:
	@cd frontend && VITE_API_BASE_URL=http://127.0.0.1:$(BACKEND_PORT) npm run dev -- --host 0.0.0.0 --port $(FRONTEND_PORT)

flush-redis:
	@$(WITH_SECRETS) uv run python scripts/flush_redis.py

seed-memories:
	@$(WITH_SECRETS) env DEMO_DOMAIN=$(DOMAIN) uv run python -m scripts.seed_memories

seed-langcache:
	@$(WITH_SECRETS) env DEMO_DOMAIN=$(DOMAIN) uv run python -m scripts.seed_langcache

seed-all: seed-memories seed-langcache

dev:
	@lsof -ti:$(BACKEND_PORT) | xargs kill -9 2>/dev/null || true
	@lsof -ti:$(FRONTEND_PORT) | xargs kill -9 2>/dev/null || true
	@sleep 0.5
	@trap 'kill 0' EXIT; $(MAKE) backend & $(MAKE) frontend & wait
