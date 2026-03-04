# Homelab Automation Strategy

## Vision

Fully automated (or near-automated) provisioning of Raspberry Pi servers and deployment of services to them, driven from an administration workstation (macBook), with all secrets and configuration stored in 1Password.

---

## Scope

### Phase 1 — Complete
- Creating the RPi OS image ✓
- Flashing the image to SD/NVMe ✓
- Process is documented ✓

### Phase 2 — Complete
- Host preparation (via SSH): ✓
  - `apt update && apt upgrade`
  - Install 1Password CLI (`op`)
  - Install Docker
  - Place OP service account token on host
- Service deployment: ✓
  - Generate environment files from 1Password (on host, using stored token)
  - Deploy Docker Compose-based services
- Declarative server spec (`servers.yaml`) generated from 1Password ✓
- Single-command provisioning via `provision.sh` ✓

### Future
- Automate image creation and flashing
- Support additional services: AI server, web hosting, etc.

---

## Target Environments

| Environment | Vault    | Server   | Status          |
|-------------|----------|----------|-----------------|
| Development | devLab   | rpicm5b  | Active target   |
| Production  | prodLab  | (tbd)    | Future          |

No concrete differences between dev and prod environments have been identified yet, but the distinction is preserved intentionally — different vaults, potentially different hostnames, resource limits, and backup policies as the system matures.

---

## Repository Structure

```
/
├── provision.sh             # Entry point: generate spec or provision a server
├── gen-spec.sh              # Generate servers.yaml from 1Password server.* items
├── provision-host.sh        # Prepare a bare host for Docker-based services
├── provision-service.sh     # Deploy a specific service to a prepared host
├── servers.example.yaml     # Documented example spec file
├── CLAUDE.md                # Claude Code instructions
├── STRATEGY.md              # This document
├── common/
│   ├── lib.sh               # Shared shell functions (logging, error handling, vault resolution)
│   └── gen-env.sh           # Generate .env from 1Password fields
└── services/
    └── n8n/
        ├── docker-compose.yml
        └── .env.example
```

---

## 1Password Conventions

### Vaults

| Vault | Purpose | Accessible by |
|-------|---------|---------------|
| `Lab` | Shared items: GitHub SSH key, `op-service-account` token, `server.*` host specs | Admin workstation |
| `devLab` | Dev-specific secrets (`service.*` items) | Dev service account token (on host) |
| `prodLab` | Prod-specific secrets (`service.*` items) | Prod service account token (on host) |

### Item Naming

| Item name | Vault | Contains |
|-----------|-------|---------|
| `server.<name>` | Lab | Host spec: env, hostname, app list |
| `op-service-account` | Lab | OP service account credential; placed on host during provisioning |
| `sshkey.github` | Lab | GitHub SSH key for repo clone |
| `service.<name>` | devLab / prodLab | Service config (env vars for `.env`) |

### Field Naming

| Convention | Example | Purpose |
|------------|---------|---------|
| `env` | `dev` | Required on `server.*` items; selects vault |
| `hostname` | `rpicm5b.iot` | Optional on `server.*`; SSH target |
| `app.<name>` (section) | `app.n8n` | One section per service to deploy; `env.*` fields within the section are host-specific env overrides (future) |
| `env.<VAR>` | `env.POSTGRES_PASSWORD` | Becomes `POSTGRES_PASSWORD=<value>` in `.env` |

---

## Provisioning Flow

```
provision.sh rpicm5b
     │
     ├─ reads servers.yaml (generates from OP if missing)
     │
     ├─ provision-host.sh --env dev --host rpicm5b
     │       SSH → apt upgrade, Docker, op CLI, GitHub key, repo clone
     │       SSH → install OP token to /home/ops/.op_env (mode 600)
     │
     └─ provision-service.sh --env dev --host rpicm5b --service n8n
             SSH → git pull
             SSH → source ~/.op_env && gen-env.sh → .env
             SSH → docker compose up -d
```

Secrets never travel from 1Password through the admin workstation to the host. The host fetches them directly using its stored service account token.

---

## Open Questions

1. **Repo rename/repurpose?** Rename this repo (e.g. `homelab`) or create a new one and archive this?
2. **Dev vs prod differentiation**: No concrete differences identified yet. Things that *might* differ: hostnames, resource limits, log verbosity, data retention, backup frequency. Revisit as the system matures.
