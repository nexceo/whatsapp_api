# Changelog

All notable changes to this deployment repository are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
This tracks the *deployment/ops repo* version (see `VERSION`), not the
Evolution API application version (pinned separately in
`docker-compose.production.yml`, currently `v2.3.7`).

## [1.0.0] - 2026-07-26

### Added

- Initial standalone production deployment: dedicated Postgres 15,
  dedicated Redis 7, `evoapicloud/evolution-api:v2.3.7`,
  `evoapicloud/evolution-manager:latest` — isolated Docker network
  (`evolution-network`) and volumes, no shared infrastructure with any
  other stack on the host.
- `docker-compose.production.yml` — API and Manager bound to
  `127.0.0.1` only; Postgres/Redis not published to the host at all.
- `Docker/production/evolution-manager-nginx.conf` — fixes a bug in the
  vendor `evoapicloud/evolution-manager` image (both `latest` and
  `v2.3.5` reproduced this): its bundled `nginx.conf` passes the
  invalid `gzip_proxied` parameter `must-revalidate`, which crash-loops
  the container. Bind-mounted over the broken file.
- Operational scripts: `install.sh`, `update.sh`, `backup.sh`,
  `restore.sh`, `healthcheck.sh`, `restart.sh`, `logs.sh`, plus shared
  `lib.sh`. All pass `shellcheck` and were functionally verified
  against the live stack (see "Verification" below).
- `docs/EVOLUTION_DEPLOYMENT.md` — architecture, environment variable
  reference, backup locations, health check commands, restart/upgrade
  procedures, troubleshooting.
- `.env.production.example` — non-secret template; `install.sh`
  auto-generates `POSTGRES_PASSWORD`, `REDIS_PASSWORD`, and
  `AUTHENTICATION_API_KEY` on first run if `.env.production` doesn't
  exist yet.

### Verification performed before this release

- Functional REST API validation: health, auth (accept/reject), fetch
  instances, create/duplicate-reject/delete/recreate instance, all with
  correct HTTP status codes.
- QR code generation, auto-rotation (confirmed via `qrcodeCount`
  incrementing in logs), and expiration logic (`QRCODE_LIMIT`) reviewed
  against source. No WhatsApp device connected.
- Manager UI reachability, asset serving, and its API dependency
  confirmed server-side (no headless browser available in this
  environment for full JS-console verification).
- Log review across all 4 containers: zero exceptions, zero DB/Redis
  errors, zero reconnect loops, zero restart loops.
- Every script in `scripts/` was syntax-checked (`bash -n`),
  lint-checked (`shellcheck -x`), and exercised for real against the
  live stack where safe to do so:
  - `healthcheck.sh`, `logs.sh` — read-only, run directly.
  - `backup.sh` — run for real; dump verified to contain expected data.
  - `restore.sh` — argument validation and the `--yes` confirmation gate
    verified directly; the underlying restore commands (Postgres
    `psql` restore, volume tar extraction) verified against disposable
    scratch containers/volumes rather than the live database, to avoid
    any risk to real data.
  - `restart.sh`, `install.sh` — run for real (idempotent / safely
    reversible); stack recovered healthy every time, zero data loss.
  - `update.sh` — run for real with `--api v2.3.7` and
    `--manager latest` (i.e. re-applying the already-current tags) to
    exercise the full backup → pull → sed → recreate code path with
    zero version-change risk.
- Two real bugs found and fixed during script verification:
  1. `--help` in `backup.sh`/`restore.sh`/`update.sh`/`logs.sh` read
     `$0` after the script had already `cd`'d into `scripts/`, so a
     relative invocation (`bash scripts/logs.sh --help`) resolved the
     wrong path. Fixed by resolving the script's own absolute path
     before changing directory.
  2. `restore.sh --db <relative path>` had the same class of bug: the
     script `cd`'s into `scripts/` before validating the user-supplied
     file path, so relative paths resolved against the wrong directory.
     Fixed by capturing the caller's original working directory before
     any `cd` and resolving `--db`/`--volume` against it.

### Not included in this release (deliberately)

- No WhatsApp device connected.
- No webhooks configured.
- No CRM integration.
- No public HTTPS / reverse proxy.
