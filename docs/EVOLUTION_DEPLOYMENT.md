# Evolution API — Standalone Production Deployment

This document describes the standalone, isolated Evolution API deployment
running on this host. It shares **no infrastructure** (network, database,
Redis, volumes) with the `nexceo-crm` stack that also runs on this
machine and serves `crm.nexceo.in`.

Compose project name: **`evolution`**
Compose files: `docker-compose.production.yml` (+ `.env.production`, not committed to git)

This deployment is managed from the [`whatsapp_api`](https://github.com/nexceo/whatsapp_api)
repository. Prefer the wrapper scripts in `scripts/` (documented in the
repo `README.md`) over the raw `docker compose` commands below where
one exists -- they add safety checks, backups-before-upgrade, and exit
codes suitable for cron/monitoring. The raw commands are kept here as
reference / for anything the scripts don't cover.

Status as of this writing: infrastructure deployed and functionally
validated (Manager UI, REST API, QR generation, DB, Redis). **No
WhatsApp device is connected, no webhooks are configured, and it is not
integrated with the CRM.**

## 1. Architecture

```
                 ┌─────────────────────────────────────────────┐
                 │        Docker network: evolution-network      │
                 │        (bridge, isolated, not shared)          │
                 │                                                │
 127.0.0.1:8080 ─┼──▶ evolution-api ───┬──▶ evolution-postgres    │
   (Evolution     │   (Baileys/Meta/    │    (postgres:15,        │
    REST API)     │    Evolution        │     internal only)      │
                 │    providers)       │                          │
 127.0.0.1:8081 ─┼──▶ evolution-manager│──▶ evolution-redis       │
   (Manager UI,   │   (static SPA,      │    (redis:7-alpine,     │
    nginx)        │    nginx)           │     internal only)      │
                 │                                                │
                 └─────────────────────────────────────────────┘
```

- The API and Manager are the only services published to the host, and
  only on `127.0.0.1` (not reachable from outside this server).
- Postgres and Redis are **not** published to the host at all — they are
  only reachable from other containers on `evolution-network`. This was
  a deliberate choice: the CRM already owns host ports `5432` and `6379`,
  and internal-only DB/cache access is the more secure default anyway.
- Session/media data for WhatsApp instances lives in the
  `evolution_instances` volume, mounted into `evolution-api` at
  `/evolution/instances`.

## 2. Docker services

| Service | Container name | Image | Purpose |
|---|---|---|---|
| API | `evolution-api` | `evoapicloud/evolution-api:v2.3.7` (pinned) | Core Evolution API — REST endpoints, WhatsApp connection management |
| Manager | `evolution-manager` | `evoapicloud/evolution-manager:latest` | Web UI for managing instances (nginx-served SPA) |
| Database | `evolution-postgres` | `postgres:15` | Persistent storage (instances, messages, contacts, settings, …) |
| Cache | `evolution-redis` | `redis:7-alpine` | Cache + optional instance-state store (`CACHE_REDIS_*`) |

Start order is enforced via `depends_on: condition: service_healthy` —
API and Manager only start once Postgres and Redis pass their health
checks.

## 3. Ports

| Port (host) | Bound to | Container | Notes |
|---|---|---|---|
| `8080` | `127.0.0.1` only | `evolution-api:8080` | REST API + built-in manager at `/manager` |
| `8081` | `127.0.0.1` only | `evolution-manager:80` | Standalone Manager UI |
| — | not published | `evolution-postgres:5432` | Internal network only |
| — | not published | `evolution-redis:6379` | Internal network only |

Nothing is exposed on `0.0.0.0` — there is no public access until an
nginx reverse-proxy + TLS vhost is deliberately added (out of scope for
this phase, and `/etc/nginx` was not touched).

## 4. Volumes

| Volume | Mounted at | Contains |
|---|---|---|
| `evolution_postgres_data` | `evolution-postgres:/var/lib/postgresql/data` | All Postgres data files |
| `evolution_redis_data` | `evolution-redis:/data` | Redis AOF persistence files |
| `evolution_instances` | `evolution-api:/evolution/instances` | Baileys session/auth files per WhatsApp instance |

All three are Docker-managed named volumes (not bind mounts), created
fresh for this deployment — none are shared with `nexceo-crm_*` volumes.
Host paths: `/var/lib/docker/volumes/<name>/_data`.

## 5. Networks

- **`evolution-network`** — dedicated bridge network, created by this
  compose file. Contains exactly the 4 Evolution containers.
- The CRM's network (`nexceo-crm_default`) is untouched and has no
  overlap with this one.

## 6. Environment variables (secrets excluded)

Full reference lives in `.env.production` (gitignored — see
`.gitignore`). Key non-secret settings:

| Variable | Value | Notes |
|---|---|---|
| `SERVER_PORT` | `8080` | |
| `MANAGER_PORT` | `8081` | Compose-only var, not read by the API itself |
| `SERVER_URL` | `http://localhost:8080` | Update when a real domain is fronted |
| `DATABASE_PROVIDER` | `postgresql` | |
| `DATABASE_CONNECTION_CLIENT_NAME` | `evolution_nexceo_prod` | Distinguishes this install if a DB is ever shared |
| `CACHE_REDIS_ENABLED` | `true` | |
| `CACHE_REDIS_PREFIX_KEY` | `evolution` | |
| `CORS_ORIGIN` | `*` | Safe while bound to localhost-only; tighten once public |
| `AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES` | `true` | |
| `WEBHOOK_GLOBAL_ENABLED` | `false` | Intentionally disabled — no CRM integration yet |
| `RABBITMQ_ENABLED` / `SQS_ENABLED` / `WEBSOCKET_ENABLED` / `PUSHER_ENABLED` / `KAFKA_ENABLED` | `false` | All external event transports disabled |
| `TYPEBOT_ENABLED` / `CHATWOOT_ENABLED` / `OPENAI_ENABLED` / `DIFY_ENABLED` / `N8N_ENABLED` / `EVOAI_ENABLED` | `false` | All chatbot integrations disabled |
| `S3_ENABLED` | `false` | Media stored locally in `evolution_instances` volume |
| `TELEMETRY_ENABLED` | `true` | Evolution API's own (non-sensitive) usage telemetry |

Secrets present in `.env.production` but **not** reproduced here:
`POSTGRES_PASSWORD`, `REDIS_PASSWORD`, `AUTHENTICATION_API_KEY`,
`DATABASE_CONNECTION_URI`, `CACHE_REDIS_URI`.

## 7. Backup locations

`backups/` in the repo root holds local backup output (gitignored --
only `.gitkeep` is tracked). Nothing is scheduled automatically yet;
run manually or wire up a cron entry. Treat this as local/on-host
storage only; copy dumps off this host for real disaster recovery.

**Preferred: use the wrapper script**
```bash
scripts/backup.sh                 # DB dump + instance volume archive
scripts/backup.sh --db-only
scripts/backup.sh --volume-only
RETENTION_DAYS=30 scripts/backup.sh   # default retention is 14 days
```

**Restore (destructive -- see scripts/restore.sh --help):**
```bash
scripts/restore.sh --db backups/evolution_db_<timestamp>.sql.gz --yes
scripts/restore.sh --volume backups/evolution_instances_<timestamp>.tar.gz --yes
```
Without `--yes` it only prints what it would do.

**Raw equivalent (what the scripts do under the hood):**
```bash
docker exec evolution-postgres pg_dump -U evolution -d evolution_api \
  | gzip > backups/evolution_db_$(date +%Y%m%d_%H%M%S).sql.gz

gunzip -c backups/evolution_db_<timestamp>.sql.gz | \
  docker exec -i evolution-postgres psql -U evolution -d evolution_api

docker run --rm -v evolution_instances:/data -v "$PWD/backups":/backup \
  alpine tar czf /backup/evolution_instances_$(date +%Y%m%d_%H%M%S).tar.gz -C /data .
```

**Redis** is a cache/ephemeral store (`CACHE_REDIS_SAVE_INSTANCES=false`)
— it is not treated as a primary data store and is not part of the
backup procedure. AOF persistence (`--appendonly yes`) protects against
container restarts only, not against needing a real backup.

## 8. Health check commands

**Preferred: `scripts/healthcheck.sh`** -- runs every check below plus
container-health/restart-count checks, exits 0/1 (cron/monitoring
friendly).

**Raw equivalent:**
```bash
# Container status / health
docker compose -p evolution -f docker-compose.production.yml --env-file .env.production ps

# API root (no auth required) — should return status 200 + version info
curl -sS http://127.0.0.1:8080/

# Authenticated call — should return 200 (or 401 without the apikey header)
curl -sS http://127.0.0.1:8080/instance/fetchInstances -H "apikey: <AUTHENTICATION_API_KEY>"

# Manager UI health
curl -sS http://127.0.0.1:8081/health

# Postgres
docker exec evolution-postgres pg_isready -U evolution -d evolution_api

# Redis
docker exec evolution-redis redis-cli -a '<REDIS_PASSWORD>' --no-auth-warning ping

# Restart-loop / crash check
docker inspect evolution-api evolution-manager evolution-postgres evolution-redis \
  --format '{{.Name}}: RestartCount={{.RestartCount}} Health={{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}'
```

## 9. Restart procedure

**Preferred:**
```bash
scripts/restart.sh                  # everything
scripts/restart.sh evolution-api    # just one service
```

**Raw equivalent / full stop-start (containers only — volumes and data persist):**
```bash
docker compose -p evolution -f docker-compose.production.yml --env-file .env.production restart
docker compose -p evolution -f docker-compose.production.yml --env-file .env.production down
docker compose -p evolution -f docker-compose.production.yml --env-file .env.production up -d
```

**Never run `down -v`** — it deletes the named volumes (Postgres data,
Redis data, and all WhatsApp session files) permanently. There is no
volume overlap with the CRM stack, but this still means real, unrecoverable
data loss for Evolution itself.

## 10. Upgrade procedure

**Preferred: `scripts/update.sh`** -- takes a backup automatically
(unless `--skip-backup`), verifies the target image actually pulls
before touching the compose file, edits the `image:` tag, recreates
only the changed service(s), and tails logs for migration output.

```bash
scripts/update.sh --api v2.4.0
scripts/update.sh --manager latest
scripts/update.sh --api v2.4.0 --manager latest
```

Before running it: review the upstream `CHANGELOG.md` (in the Evolution
API project, not this repo's) for breaking changes / new required env
vars between the current and target version, and add any new variables
to `.env.production` (and `.env.production.example`) first.

Re-run `scripts/healthcheck.sh` afterward.

Rollback: `scripts/update.sh --api <previous-tag>` again, or restore
from the pre-upgrade backup with `scripts/restore.sh` (see §7).
Postgres migrations are additive/forward-only in the upstream project
(no down-migrations shipped), so a DB restore from backup is the only
path back if a migration itself caused the problem.

## 11. Troubleshooting

**`evolution-manager` restart-looping with `nginx: [emerg] invalid value "must-revalidate" in /etc/nginx/conf.d/nginx.conf:11`**
This is a bug in the vendor image itself (`evoapicloud/evolution-manager`,
reproduced on both `latest` and `v2.3.5`) — `must-revalidate` is not a
valid `gzip_proxied` parameter. Already fixed in this deployment by
bind-mounting `Docker/production/evolution-manager-nginx.conf` (a
corrected copy of the same config) over `/etc/nginx/conf.d/nginx.conf`.
If a future image version fixes this upstream, the volume mount can be
removed from `docker-compose.production.yml`.

**API returns `{"response":{"message":"Not allowed by CORS"}}`**
`CORS_ORIGIN` is set to a fixed allowlist that doesn't include the
caller's `Origin` (or the caller sent no `Origin` header at all, which
this middleware also rejects under a strict allowlist). Since this
instance is `127.0.0.1`-only, `CORS_ORIGIN=*` is the current, correct
setting — don't narrow it without confirming health checks and curl
still work.

**`evolution-api` container `unhealthy` right after `up -d`**
Expected during the first ~30s (`start_period: 30s` in the healthcheck)
while Prisma migrations run and the server boots — check
`docker logs evolution-api` for "HTTP - ON: 8080" before assuming a real
failure.

**Redis logs `WARNING Memory overcommit must be enabled!`**
Benign, host-level kernel advisory (`vm.overcommit_memory`), not
specific to this deployment or an error condition. Fixing it requires a
host sysctl change (`sysctl vm.overcommit_memory=1`) — out of scope
here since it's host-wide and would also affect the CRM's containers;
raise it separately with whoever owns host-level tuning if it needs
addressing.

**Need to inspect a WhatsApp instance's raw session files**
```bash
docker run --rm -v evolution_instances:/data alpine ls -la /data
```

**Port already in use when starting**
`8080`/`8081` are only used by this stack; if either is taken, check
`ss -tlnp | grep -E ':(8080|8081)'` — do not touch ports `3000`, `5432`,
or `6379`, which belong to `nexceo-crm`.

**Confirming isolation from the CRM stack**
```bash
docker network inspect evolution-network --format '{{range $k,$v := .Containers}}{{$v.Name}} {{end}}'
docker network inspect nexceo-crm_default --format '{{range $k,$v := .Containers}}{{$v.Name}} {{end}}'
```
Should show two disjoint container lists with zero overlap.
