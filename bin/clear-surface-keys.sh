#!/usr/bin/env bash
# clear-surface-keys.sh — Wipe the auto-populated context-surface secrets
# (MCP_AGENT_KEY, CTX_SURFACE_ID) from macOS Keychain AND from .env, so the
# next `make setup` / `make reset` run creates a fresh surface.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS="$ROOT_DIR/bin/secrets.sh"
ENV_FILE="$ROOT_DIR/.env"

if [[ -x "$SECRETS" ]]; then
  "$SECRETS" del MCP_AGENT_KEY >/dev/null 2>&1 || true
  "$SECRETS" del CTX_SURFACE_ID >/dev/null 2>&1 || true
fi

if [[ -f "$ENV_FILE" ]]; then
  # Reset placeholders in .env to blank so pydantic-settings only sees the
  # keychain-injected values from the environment.
  /usr/bin/sed -i '' 's/^CTX_SURFACE_ID=.*/CTX_SURFACE_ID=/' "$ENV_FILE" || true
  /usr/bin/sed -i '' 's/^MCP_AGENT_KEY=.*/MCP_AGENT_KEY=/' "$ENV_FILE" || true
fi

echo "ok: cleared MCP_AGENT_KEY and CTX_SURFACE_ID from keychain + .env" >&2
