# whatsapp_api

Standalone production deployment for [Evolution API](https://doc.evolution-api.com)
(WhatsApp integration platform) — dedicated Postgres, dedicated Redis,
dedicated Docker network, dedicated volumes. Fully isolated from any
other stack running on the same host.

This is a **deployment/ops repository**, not an application source
repository: it runs the published `evoapicloud/evolution-api` and
`evoapicloud/evolution-manager` Docker images. No Evolution API
application source code is vendored here — upgrades are done by
bumping an image tag (`scripts/update.sh`), not by building from
source.

Current pinned version: see [`VERSION`](./VERSION) and
[`CHANGELOG.md`](./CHANGELOG.md).

## Status

Infrastructure-validated. As of this repository's initial release: all
4 containers healthy, REST API/auth/QR/CRUD functionally verified, no
WhatsApp device connected, no webhooks configured, no CRM integration.
See `docs/EVOLUTION_DEPLOYMENT.md` for the full validation record.

## Architecture

```
 127.0.0.1:8080 ──▶ evolution-api ────┬──▶ evolution-postgres  (internal only)
                                       │
 127.0.0.1:8081 ──▶ evolution-manager └──▶ evolution-redis     (internal only)

              all on the dedicated "evolution-network" bridge
```

- API and Manager are the only services published to the host, and only
  on `127.0.0.1` — nothing is reachable from outside this server.
- Postgres and Redis are not published to the host at all; they're only
  reachable from other containers on `evolution-network`.
- WhatsApp session/auth data lives in the `evolution_instances` volume.

Full detail: [`docs/EVOLUTION_DEPLOYMENT.md`](./docs/EVOLUTION_DEPLOYMENT.md).

## Repository layout

```
whatsapp_api/
├── README.md
├── CHANGELOG.md
├── VERSION
├── docker-compose.production.yml   # the whole stack
├── .env.production.example         # copy to .env.production and fill in (or let install.sh generate secrets)
├── .gitignore
├── Docker/
│   └── production/
│       └── evolution-manager-nginx.conf   # fixes a broken nginx.conf shipped in the vendor manager image
├── scripts/
│   ├── lib.sh          # shared helpers, not run directly
│   ├── install.sh       # fresh install / idempotent re-apply
│   ├── update.sh        # bump API/Manager image tag, with pre-upgrade backup
│   ├── backup.sh         # dump Postgres + archive the instance volume
│   ├── restore.sh        # restore a backup (destructive, requires --yes)
│   ├── healthcheck.sh    # full functional health check, exit-code driven
│   ├── restart.sh        # restart all services, or one
│   └── logs.sh           # tail logs, all services or one
├── backups/              # local backup output (gitignored, .gitkeep only)
└── docs/
    └── EVOLUTION_DEPLOYMENT.md   # full architecture/ops reference
```

## Prerequisites

- Docker Engine with the Compose v2 plugin (`docker compose version`)
- `openssl` (used by `install.sh` to generate secrets)
- Ports `8080` and `8081` free on `127.0.0.1` (configurable via
  `SERVER_PORT` / `MANAGER_PORT` in `.env.production`)

## Quick start

```bash
git clone git@github.com:nexceo/whatsapp_api.git
cd whatsapp_api
scripts/install.sh
scripts/healthcheck.sh
```

`install.sh` is idempotent: if `.env.production` already exists it's
left untouched and the script just pulls images and reconciles the
running stack (safe to re-run any time, including against an
already-running deployment).

If you'd rather set secrets yourself instead of letting `install.sh`
generate them:

```bash
cp .env.production.example .env.production
chmod 600 .env.production
# edit POSTGRES_PASSWORD, REDIS_PASSWORD, AUTHENTICATION_API_KEY,
# DATABASE_CONNECTION_URI, CACHE_REDIS_URI (the __PLACEHOLDER__ values)
scripts/install.sh
```

## Scripts

All scripts live in `scripts/`, are safe to run from any working
directory, and print usage with `-h`/`--help` where applicable.

| Script | Purpose |
|---|---|
| `install.sh` | Fresh install or idempotent re-apply of the whole stack |
| `update.sh --api <tag>` / `--manager <tag>` | Upgrade an image tag; backs up first by default |
| `backup.sh [--db-only\|--volume-only]` | Dump Postgres + archive WhatsApp session volume to `backups/` |
| `restore.sh --db <file> [--volume <file>] --yes` | Restore a backup. **Destructive.** Dry-runs (prints what it would do) without `--yes` |
| `healthcheck.sh` | Full functional check (containers, API, auth, DB, Redis, volumes); exit 0/1 for cron/monitoring |
| `restart.sh [service]` | Restart everything, or one container |
| `logs.sh [service] [--no-follow] [--tail N]` | Tail logs |

Every script targets the fixed Compose project name `evolution`, so it
manages the same containers/volumes/network regardless of where this
repo is checked out on disk.

## Security notes

- `.env.production` contains real secrets and is gitignored — never
  commit it. Only `.env.production.example` (placeholders) is tracked.
- The API and Manager are bound to `127.0.0.1` only. There is no public
  HTTPS endpoint until an nginx vhost + TLS is deliberately added
  (out of scope for this repo today).
- Postgres and Redis have no host-published ports at all.

## Upgrading, backups, restore, troubleshooting

See [`docs/EVOLUTION_DEPLOYMENT.md`](./docs/EVOLUTION_DEPLOYMENT.md) for
the full reference: environment variable table, backup/restore
procedures, health check commands, restart/upgrade procedures, and a
troubleshooting section (including a known vendor bug in the Manager
image and how this repo works around it).

## Out of scope (by design, for now)

- No WhatsApp device connected
- No webhooks configured
- No integration with any CRM
- No public-facing HTTPS / reverse proxy

These are deliberate boundaries for the current phase, not omissions.
