#!/usr/bin/env bash
# with-secrets.sh — Run a command with secrets loaded from macOS Keychain.
#
# Secrets are exported into the child process's environment only.
# They are NOT written to disk at any point.
#
# Usage:
#   bin/with-secrets.sh <command> [args...]
#
# Example:
#   bin/with-secrets.sh make backend
#   bin/with-secrets.sh uv run python scripts/setup_surface.py --domain radish-bank

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS="$ROOT_DIR/bin/secrets.sh"

if [[ ! -x "$SECRETS" ]]; then
  chmod +x "$SECRETS"
fi

if [[ $# -eq 0 ]]; then
  echo "usage: $0 <command> [args...]" >&2
  exit 2
fi

# Verify required secrets exist before running.
if ! "$SECRETS" check >/dev/null 2>&1; then
  echo "==> Some required secrets are missing. Status:" >&2
  "$SECRETS" list
  echo >&2
  echo "Set them with: bin/secrets.sh set <KEY>" >&2
  exit 1
fi

# Eval the export lines into THIS shell, then exec the child so the
# secrets live only in the child process (not on disk).
secret_exports="$("$SECRETS" export)"
# shellcheck disable=SC1090
eval "$secret_exports"

exec "$@"
