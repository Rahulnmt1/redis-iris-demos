#!/usr/bin/env bash
# Links this project's confidential files (.env, credentials, keys) from the owner's
# private secrets vault. Nothing secret is stored in this repository.
#   Vault: ${DEMO_SECRETS_DIR:-$HOME/Documents/RWork/secrets}/redis-iris-demos
#   (private repo github.com/Rahulnmt1/secrets)
set -euo pipefail
VAULT="${DEMO_SECRETS_DIR:-$HOME/Documents/RWork/secrets}/redis-iris-demos"
cd "$(dirname "$0")"
FILES=(
  ".env"
  ".env.backup-before-cloud-creds"
  ".env.backup-before-dedicated-cloud"
  ".env.backup-before-radish"
  "frontend/.env.local"
)
for f in "${FILES[@]}"; do
  src="$VAULT/$f"
  if [ ! -e "$src" ]; then echo "missing in vault: $f" >&2; continue; fi
  if [ -e "$f" ] && [ ! -L "$f" ]; then echo "skipped (real file present): $f" >&2; continue; fi
  mkdir -p "$(dirname "$f")"
  ln -sfn "$src" "$f"
  echo "linked $f"
done
