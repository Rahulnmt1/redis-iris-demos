#!/usr/bin/env bash
# secrets.sh — macOS Keychain helper for the Radish Bank demo.
#
# Secrets are stored as "generic-password" entries under the service name
# "redis-iris-radish-bank". Nothing is ever written to disk in plain text.
#
# Usage:
#   bin/secrets.sh set   <KEY> [value]   # value read from stdin if omitted
#   bin/secrets.sh paste <KEY>           # reads the value from macOS clipboard
#   bin/secrets.sh get   <KEY>           # prints the secret to stdout
#   bin/secrets.sh len   <KEY>           # prints only the length (for sanity check)
#   bin/secrets.sh del   <KEY>
#   bin/secrets.sh list                  # lists configured keys (no values)
#   bin/secrets.sh export                # prints `export KEY=...` for each key
#   bin/secrets.sh check                 # verifies required keys are set
#   bin/secrets.sh setup                 # interactive: silent prompt for each key
#   bin/secrets.sh setup-clipboard       # guided: copy → ENTER → repeat per key
#   bin/secrets.sh wipe                  # delete ALL entries under our service
#
# Required keys for Radish Bank:
#   OPENAI_API_KEY
#   REDIS_HOST
#   REDIS_PORT
#   REDIS_PASSWORD
#   CTX_ADMIN_KEY
#   MEMORY_API_BASE_URL
#   MEMORY_STORE_ID
#   MEMORY_API_KEY
#   LANGCACHE_HOST
#   LANGCACHE_CACHE_ID
#   LANGCACHE_API_KEY
#
# Auto-populated by `make setup` (also stored in keychain after setup):
#   MCP_AGENT_KEY
#   CTX_SURFACE_ID

set -euo pipefail

# Each secret is stored as a generic-password keychain entry where:
#   account = the secret KEY (e.g. OPENAI_API_KEY)  ← uniqueness comes from here
#   service = a constant namespace                  ← lets us list / wipe together
# This avoids the historical bug where the macOS keychain used
# (account, service) as the uniqueness tuple and only the label varied,
# so all secrets collapsed to a single entry.
SERVICE="redis-iris-radish-bank"
OWNER="$(whoami)"  # for descriptive label only

REQUIRED_KEYS=(
  OPENAI_API_KEY
  REDIS_HOST
  REDIS_PORT
  REDIS_PASSWORD
  CTX_ADMIN_KEY
  MEMORY_API_BASE_URL
  MEMORY_STORE_ID
  MEMORY_API_KEY
  LANGCACHE_HOST
  LANGCACHE_CACHE_ID
  LANGCACHE_API_KEY
)

OPTIONAL_KEYS=(
  MCP_AGENT_KEY
  CTX_SURFACE_ID
)

ALL_KEYS=("${REQUIRED_KEYS[@]}" "${OPTIONAL_KEYS[@]}")

_label() {
  echo "${SERVICE}:${1}"
}

set_secret() {
  local key="$1"
  local value="${2-}"
  if [[ -z "$value" ]]; then
    # Read silently from stdin if interactive; otherwise read piped data.
    if [[ -t 0 ]]; then
      printf "Enter value for %s (input hidden): " "$key" >&2
      IFS= read -rs value
      echo >&2
    else
      IFS= read -r value
    fi
  fi
  if [[ -z "$value" ]]; then
    echo "error: empty value for $key" >&2
    return 1
  fi
  # Delete first so update is clean; ignore "not found" errors.
  security delete-generic-password \
    -a "$key" -s "$SERVICE" >/dev/null 2>&1 || true
  security add-generic-password \
    -a "$key" \
    -s "$SERVICE" \
    -l "$(_label "$key")" \
    -D "redis-iris-secret" \
    -j "Radish Bank demo secret ($OWNER): $key" \
    -w "$value" \
    -U >/dev/null
  echo "ok: stored $key" >&2
}

get_secret() {
  local key="$1"
  security find-generic-password \
    -a "$key" -s "$SERVICE" -w 2>/dev/null
}

len_secret() {
  local key="$1"
  local v
  v="$(get_secret "$key")"
  echo "${#v}"
}

paste_secret() {
  local key="$1"
  if ! command -v pbpaste >/dev/null 2>&1; then
    echo "error: pbpaste not available (macOS only)" >&2
    return 1
  fi
  # Strip a single trailing newline if pbpaste returns one, but otherwise
  # preserve the clipboard contents exactly.
  local value
  value="$(pbpaste)"
  # Reject obviously-empty clipboards.
  if [[ -z "$value" ]]; then
    echo "error: clipboard is empty" >&2
    return 1
  fi
  set_secret "$key" "$value"
  echo "stored $key from clipboard (length=${#value})" >&2
}

has_secret() {
  local key="$1"
  security find-generic-password \
    -a "$key" -s "$SERVICE" >/dev/null 2>&1
}

del_secret() {
  local key="$1"
  security delete-generic-password \
    -a "$key" -s "$SERVICE" >/dev/null 2>&1 \
    && echo "ok: deleted $key" >&2 \
    || echo "warn: $key not found" >&2
}

list_keys() {
  echo "Required:" >&2
  for k in "${REQUIRED_KEYS[@]}"; do
    if has_secret "$k"; then
      echo "  [x] $k" >&2
    else
      echo "  [ ] $k (missing)" >&2
    fi
  done
  echo "Optional / auto-populated:" >&2
  for k in "${OPTIONAL_KEYS[@]}"; do
    if has_secret "$k"; then
      echo "  [x] $k" >&2
    else
      echo "  [ ] $k" >&2
    fi
  done
}

check_secrets() {
  local missing=0
  for k in "${REQUIRED_KEYS[@]}"; do
    if ! has_secret "$k"; then
      echo "missing: $k" >&2
      missing=$((missing + 1))
    fi
  done
  if (( missing > 0 )); then
    echo "error: $missing required secret(s) missing" >&2
    return 1
  fi
  echo "ok: all required secrets present" >&2
}

setup_clipboard() {
  if ! command -v pbpaste >/dev/null 2>&1; then
    echo "error: pbpaste not available (macOS only)" >&2
    return 1
  fi
  echo "Radish Bank demo — secret setup (silent paste)" >&2
  echo "" >&2
  echo "For each key, you can do EITHER:" >&2
  echo "  A) Paste the value directly at the prompt (input is HIDDEN — nothing" >&2
  echo "     will appear in the terminal or scrollback). Press Enter to submit." >&2
  echo "  B) Just press Enter without typing anything to use the current" >&2
  echo "     clipboard contents (pbpaste)." >&2
  echo "" >&2
  echo "  Type literally:" >&2
  echo "    skip     to leave the existing value unchanged" >&2
  echo "    abort    to stop without further changes" >&2
  echo "    clear    to delete this secret entirely" >&2
  echo "" >&2

  local raw clip value src prev_fp clip_fp current
  prev_fp=""

  for k in "${REQUIRED_KEYS[@]}"; do
    if has_secret "$k"; then
      current="(currently set — paste to overwrite, 'skip' to keep)"
    else
      current="(not set — paste the value, or Enter to use clipboard)"
    fi
    while true; do
      printf "  %s\n     %s\n  > " "$k" "$current" >&2
      # Silent read: hide input even if user types/pastes the secret.
      IFS= read -rs raw
      # Print a newline because -rs suppresses it.
      echo "" >&2
      case "$raw" in
        abort)
          echo "  aborted" >&2
          list_keys
          return 0
          ;;
        skip)
          echo "  skipped (kept existing)" >&2
          break
          ;;
        clear)
          del_secret "$k"
          break
          ;;
        "")
          clip="$(pbpaste)"
          if [[ -z "$clip" ]]; then
            echo "  warn: clipboard is empty. Copy the value first, then press Enter." >&2
            continue
          fi
          value="$clip"
          src="clipboard"
          ;;
        *)
          value="$raw"
          src="direct paste"
          ;;
      esac
      [[ -z "${value:-}" ]] && continue
      clip_fp="$(printf '%s' "$value" | shasum -a 256 | cut -c1-12)"
      if [[ -n "$prev_fp" && "$clip_fp" == "$prev_fp" ]]; then
        echo "  warn: this value is IDENTICAL to the last key you stored." >&2
        echo "        That probably means you forgot to copy a new value for $k." >&2
        printf "        Store it anyway? [y/N] " >&2
        local confirm; IFS= read -r confirm
        case "$confirm" in
          y|Y|yes) ;;
          *) value=""; continue ;;
        esac
      fi
      set_secret "$k" "$value"
      echo "  stored $k via $src (length=${#value}, fp=$clip_fp)" >&2
      prev_fp="$clip_fp"
      value=""
      break
    done
  done

  echo "" >&2
  echo "Done. Status:" >&2
  list_keys
}

setup_interactive() {
  echo "Radish Bank demo — interactive secret setup" >&2
  echo "Values are stored in macOS Keychain (encrypted at rest)." >&2
  echo "Press ENTER on any prompt to keep an existing value." >&2
  echo "" >&2
  local current new
  for k in "${REQUIRED_KEYS[@]}"; do
    if has_secret "$k"; then
      current="(currently set — leave blank to keep)"
    else
      current="(not set)"
    fi
    printf "  %s %s\n  > " "$k" "$current" >&2
    IFS= read -rs new
    echo "" >&2
    if [[ -n "$new" ]]; then
      set_secret "$k" "$new"
    elif ! has_secret "$k"; then
      echo "  skipped (still missing)" >&2
    fi
  done
  echo "" >&2
  echo "Done. Status:" >&2
  list_keys
}

export_env() {
  # Emits eval-able `export KEY='value'` lines for each set secret.
  # Single-quoted with embedded single quotes escaped for safe sourcing.
  local v
  for k in "${ALL_KEYS[@]}"; do
    if has_secret "$k"; then
      v="$(get_secret "$k")"
      # Escape single quotes: ' -> '\''
      v="${v//\'/\'\\\'\'}"
      printf "export %s='%s'\n" "$k" "$v"
    fi
  done
}

cmd="${1:-}"; shift || true
case "$cmd" in
  set)    set_secret "$@" ;;
  paste)  paste_secret "$@" ;;
  get)    get_secret "$@" ;;
  len)    len_secret "$@" ;;
  del|delete|rm) del_secret "$@" ;;
  list|ls) list_keys ;;
  check)  check_secrets ;;
  export) export_env ;;
  setup)  setup_interactive ;;
  setup-clipboard|paste-all) setup_clipboard ;;
  wipe)
    # Remove every entry under our service namespace, regardless of how it
    # was stored. Useful to recover from the prior (account=$USER, label-only)
    # storage layout.
    deleted=0
    while security delete-generic-password -s "$SERVICE" >/dev/null 2>&1; do
      deleted=$((deleted + 1))
      if (( deleted > 200 )); then break; fi
    done
    echo "wiped $deleted entries under service '$SERVICE'" >&2
    ;;
  help|-h|--help|"")
    sed -n '2,30p' "$0" >&2
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    sed -n '2,30p' "$0" >&2
    exit 1
    ;;
esac
