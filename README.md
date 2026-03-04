# Homelab

Automation toolkit for provisioning Raspberry Pi hosts and deploying Docker-based services to them, driven from a macBook admin workstation. Secrets are stored in 1Password and fetched at deploy time — never committed to the repo.

---

## How it works

```
provision.sh <server>
     │
     ├─ provision-host.sh     OS updates, Docker, 1Password CLI, GitHub SSH key, repo clone
     │
     └─ provision-service.sh  Pull repo, generate .env from 1Password, docker compose up
```

Server configuration lives in 1Password (`server.*` items in the Lab vault) and is materialized into `servers.yaml` by `gen-spec.sh`. `provision.sh` reads that file and drives everything else.

---

## What's in this repo

```
├── provision.sh             # Entry point: generate spec or provision a server
├── gen-spec.sh              # Generate servers.yaml from 1Password server.* items
├── provision-host.sh        # Prepare a bare host for Docker-based services
├── provision-service.sh     # Deploy a specific service to a prepared host
├── servers.example.yaml     # Documented example spec file
├── common/
│   ├── lib.sh               # Shared functions: log(), die(), vault_for_env()
│   └── gen-env.sh           # Generate .env from 1Password fields
└── services/
    └── n8n/
        ├── docker-compose.yml
        └── .env.example
```

The `services/` directory is the service catalog. A service is supported if and only if `services/<name>/` exists in the repo. Adding a new service requires only adding that directory — no changes to provisioning scripts needed.

---

## Prerequisites

**On the macBook:**
- SSH access to target host as `ops` (key-based)
- [1Password CLI (`op`)](https://developer.1password.com/docs/cli/) installed and authenticated
- `yq` installed (`brew install yq`)
- `jq` installed (`brew install jq`)

**On the target host (post-flash):**
- Account `ops` with passwordless sudo
- Internet access

---

## Usage

### Generate the server spec (once, or after vault changes)

```bash
./provision.sh --generate
```

Queries all `server.*` items in the Lab vault and writes `servers.yaml`. Re-run any time you add or change a server in 1Password.

### Provision a server

```bash
./provision.sh <server>
```

Looks up the server in `servers.yaml` (auto-generates it if missing), provisions the host, then deploys its services.

```bash
./provision.sh rpicm5b                        # full: host + all services
./provision.sh rpicm5b --host-only            # host provisioning only
./provision.sh rpicm5b --services-only        # service deployments only
./provision.sh rpicm5b dev                    # override env (default: from servers.yaml)
./provision.sh rpicm5b --spec myservers.yaml  # use a named spec file
```

Both steps are safe to re-run on an already-provisioned host/service.

### Provision directly (bypassing the spec)

```bash
./provision-host.sh --env dev --host rpicm5b
./provision-service.sh --env dev --host rpicm5b --service n8n
```

---

## 1Password conventions

### Vaults

| Vault | Purpose |
|-------|---------|
| `Lab` | Shared items: GitHub SSH key, `server.*` host specs |
| `devLab` | Dev-environment secrets: `op-service-account`, `service.*` items |
| `prodLab` | Prod-environment secrets |

### `server.*` items (Lab vault)

One item per host, named `server.<name>`. Fields:

| Field | Required | Purpose |
|-------|----------|---------|
| `env` | yes | `dev` or `prod` — selects vault for service secrets |
| `hostname` | no | SSH target; defaults to server name |
| `app.<name>` | yes (≥1) | One **section** per service to deploy (e.g. section `app.n8n`). Fields within the section prefixed `env.*` are host-specific env overrides (future). |

### `service.*` items (devLab / prodLab vaults)

One item per service per environment, named `service.<name>`. Fields prefixed with `env.` become environment variables in the generated `.env`:

```
env.POSTGRES_PASSWORD   →  POSTGRES_PASSWORD=<value>
env.N8N_ENCRYPTION_KEY  →  N8N_ENCRYPTION_KEY=<value>
```

Fields without the `env.` prefix are ignored.

---

## Services

### n8n

Workflow automation with Postgres backend and external task runner.

**Stack** (`services/n8n/docker-compose.yml`):
- `n8nio/n8n` — exposed on port 5678
- `postgres:16-alpine` — data at `/opt/n8n/postgres` (UID/GID 70:70, mode 700)
- `n8nio/runners` — external task runner (connects to n8n broker on port 5679)

**Required 1Password fields** (in `service.n8n`):
- `env.N8N_ENCRYPTION_KEY` — must never change once set; changing it breaks all stored credentials
- `env.POSTGRES_DB`
- `env.POSTGRES_USER`
- `env.POSTGRES_PASSWORD`
- `env.N8N_RUNNERS_AUTH_TOKEN` — generate with `openssl rand -base64 24`

**Stack lifecycle** (on the host at `/opt/n8n/services/n8n`):

```bash
docker compose up -d
docker compose down
docker compose ps
docker compose logs -f n8n
docker compose logs -f postgres
```

**Database backup:**
```bash
docker exec -t n8n-postgres pg_dump -U n8n -d n8n | gzip > /opt/n8n/backups/n8n-$(date +%F).sql.gz
```

**Database restore:**
```bash
gunzip -c /opt/n8n/backups/n8n-YYYY-MM-DD.sql.gz | docker exec -i n8n-postgres psql -U n8n -d n8n
```

**HTTPS transition:** Update `N8N_HOST`, `N8N_PROTOCOL`, `WEBHOOK_URL` in `.env` and remove `N8N_SECURE_COOKIE=false`.

---

## Security model

- `.env` files are never committed. Secrets are fetched from 1Password at deploy time and written on the host.
- The OP service account token is placed on each host at `/home/ops/.op_env` (mode 600) during host provisioning. Service deployments source it from there — the token never passes through the admin workstation at deploy time.
- Generated `.env` files are written with `640` permissions.
- Postgres data directory is owned by UID/GID 70:70 with mode 700.
