#!/usr/bin/env bash
# gen-env.sh — Generate a .env file from 1Password fields prefixed with "env."
#
# Fetches a named item from the appropriate vault, finds all fields whose label
# starts with "env.", strips that prefix, and emits NAME=value lines.
#
# Output goes to stdout by default. Use --output to write directly to a file
# (requires the script to run as a user with write access to the destination).
#
# Usage:
#   gen-env.sh --env <dev|prod> --item <item-name>
#   gen-env.sh --env <dev|prod> --item <item-name> --output /path/to/.env
#
# Examples:
#   gen-env.sh --env dev --item service.n8n > /opt/n8n/.env
#   gen-env.sh --env dev --item service.n8n --output /opt/n8n/.env

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

usage() {
  echo "Usage: $0 --env <dev|prod> --item <item-name> [--output <file>]"
  exit 1
}

ENV=""
ITEM=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --env)    ENV="$2";    shift 2 ;;
    --item)   ITEM="$2";   shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -z "$ENV" || -z "$ITEM" ]] && usage

VAULT=$(vault_for_env "$ENV")

log "Fetching item '$ITEM' from vault '$VAULT'..."

ENV_CONTENT=$(op item get "$ITEM" --vault "$VAULT" --format json \
  | jq -r '.fields[]
      | select(.label | startswith("env."))
      | (.label | ltrimstr("env.")) + "=" + .value')

if [[ -z "$ENV_CONTENT" ]]; then
  die "No fields with 'env.' prefix found in item '$ITEM' (vault: $VAULT)"
fi

if [[ -n "$OUTPUT" ]]; then
  # Write file with 640 permissions (owner rw, group r, others none)
  # Owner will be whoever runs this script; group set to docker for service access
  install -m 640 /dev/null "$OUTPUT"
  echo "$ENV_CONTENT" > "$OUTPUT"
  log "Written to $OUTPUT (640)"
else
  echo "$ENV_CONTENT"
fi
