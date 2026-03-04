#!/usr/bin/env bash
# lib.sh — Shared functions for homelab provisioning scripts

log() { echo "[$(basename "$0")] $*"; }
die() { echo "[$(basename "$0")] ERROR: $*" >&2; exit 1; }

# Vault for environment-agnostic items (GitHub keys, shared secrets)
LAB_VAULT="Lab"

# Resolve env-specific vault name from environment shorthand
vault_for_env() {
  case "$1" in
    dev)  echo "devLab"  ;;
    prod) echo "prodLab" ;;
    *)    die "Unknown environment '$1'. Use dev or prod." ;;
  esac
}
