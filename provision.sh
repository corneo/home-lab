#!/usr/bin/env bash
# provision.sh — Generate server spec or provision a host and its services
#
# Runs on the admin workstation (macBook). Uses servers.yaml as the config,
# generating it from 1Password if needed. Delegates to provision-host.sh
# and provision-service.sh for the actual work.
#
# Prerequisites on the admin workstation:
#   - op   (1Password CLI, authenticated)
#   - yq   (brew install yq)
#   - SSH access to the target host as ops (key-based)
#
# Usage:
#   ./provision.sh --generate [--spec <file>]
#   ./provision.sh <server> [<env>] [--spec <file>] [--host-only | --services-only]
#
# Modes:
#   --generate            Generate (or regenerate) the spec file from 1Password
#                         and stop. Run this to refresh servers.yaml after
#                         making changes to server.* items in 1Password.
#
#   <server>              Provision the named server. Looks up the server in
#                         servers.yaml, auto-generating it first if it doesn't
#                         exist. Server name must match a server.* item in the
#                         Lab vault / an entry in servers.yaml.
#
# Options:
#   --spec <file>         Spec file to use (default: servers.yaml)
#   --host-only           Run provision-host.sh only; skip service deployments
#   --services-only       Run service deployments only; skip provision-host.sh
#
# Examples:
#   ./provision.sh --generate
#   ./provision.sh --generate --spec myservers.yaml
#   ./provision.sh rpicm5b
#   ./provision.sh rpicm5b dev
#   ./provision.sh rpicm5b --host-only
#   ./provision.sh rpicm5b --services-only
#   ./provision.sh rpicm5b --spec myservers.yaml

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common/lib.sh"

# ── Argument Parsing ──────────────────────────────────────────────────────────

usage() {
  cat <<EOF
Usage:
  $0 --generate [--spec <file>]
  $0 <server> [<env>] [--spec <file>] [--host-only | --services-only]
EOF
  exit 1
}

GENERATE=false
SERVER=""
ENV_OVERRIDE=""
SPEC_FILE=""
HOST_ONLY=false
SERVICES_ONLY=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --generate)      GENERATE=true;       shift ;;
    --spec)          SPEC_FILE="$2";      shift 2 ;;
    --host-only)     HOST_ONLY=true;      shift ;;
    --services-only) SERVICES_ONLY=true;  shift ;;
    --help|-h)       usage ;;
    -*)              usage ;;
    *)
      if [[ -z "$SERVER" ]]; then
        SERVER="$1"; shift
      elif [[ -z "$ENV_OVERRIDE" ]]; then
        ENV_OVERRIDE="$1"; shift
      else
        usage
      fi
      ;;
  esac
done

[[ -z "$SPEC_FILE" ]] && SPEC_FILE="servers.yaml"

# Validate
[[ "$GENERATE" == false && -z "$SERVER" ]] && usage
[[ "$HOST_ONLY" == true && "$SERVICES_ONLY" == true ]] \
  && die "--host-only and --services-only are mutually exclusive."

# ── Preflight ─────────────────────────────────────────────────────────────────

command -v yq &>/dev/null || die "yq not found. Install with: brew install yq"

# ── Mode: Generate ────────────────────────────────────────────────────────────

if [[ "$GENERATE" == true ]]; then
  "$SCRIPT_DIR/gen-spec.sh" --output "$SPEC_FILE"
  exit 0
fi

# ── Mode: Provision ───────────────────────────────────────────────────────────

# Auto-generate spec if it doesn't exist
if [[ ! -f "$SPEC_FILE" ]]; then
  log "Spec file '$SPEC_FILE' not found — generating from 1Password..."
  "$SCRIPT_DIR/gen-spec.sh" --output "$SPEC_FILE"
else
  log "Using existing spec: $SPEC_FILE (run --generate to refresh from 1Password)"
fi

# Look up server entry
host_count=$(yq '.hosts | length' "$SPEC_FILE")
IDX=-1
for (( i=0; i<host_count; i++ )); do
  if [[ "$(yq ".hosts[$i].server" "$SPEC_FILE")" == "$SERVER" ]]; then
    IDX=$i
    break
  fi
done
[[ "$IDX" -eq -1 ]] && die "Server '$SERVER' not found in $SPEC_FILE."

# Resolve values
ENV=$(yq ".hosts[$IDX].env" "$SPEC_FILE")
HOSTNAME=$(yq ".hosts[$IDX].hostname // \"$SERVER\"" "$SPEC_FILE")
SERVICES_COUNT=$(yq ".hosts[$IDX].services | length" "$SPEC_FILE")

# Apply env override if given
if [[ -n "$ENV_OVERRIDE" ]]; then
  log "Overriding env '$ENV' → '$ENV_OVERRIDE'"
  ENV="$ENV_OVERRIDE"
fi

log "──────────────────────────────────────────"
log "Server:   $SERVER"
log "Hostname: $HOSTNAME"
log "Env:      $ENV"
log "──────────────────────────────────────────"

# Provision host
if [[ "$SERVICES_ONLY" == false ]]; then
  "$SCRIPT_DIR/provision-host.sh" --env "$ENV" --host "$HOSTNAME"
else
  log "--services-only: skipping host provisioning."
fi

# Deploy services
if [[ "$HOST_ONLY" == false ]]; then
  for (( svc_idx=0; svc_idx<SERVICES_COUNT; svc_idx++ )); do
    SERVICE=$(yq ".hosts[$IDX].services[$svc_idx]" "$SPEC_FILE")
    log "Deploying service '$SERVICE' on $HOSTNAME..."
    "$SCRIPT_DIR/provision-service.sh" --env "$ENV" --host "$HOSTNAME" --service "$SERVICE"
  done
else
  log "--host-only: skipping service deployments."
fi

log "──────────────────────────────────────────"
log "Done: $SERVER"
