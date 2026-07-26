#!/usr/bin/env bash
# Fresh install (or idempotent re-apply) of the standalone Evolution API
# stack: dedicated Postgres, dedicated Redis, API, Manager. Isolated
# Docker network and volumes -- does not touch any other stack on the
# host.
#
# Usage: scripts/install.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=lib.sh
source ./lib.sh

require_docker

if [ ! -f "$ENV_FILE" ]; then
  [ -f "$REPO_ROOT/.env.production.example" ] || die ".env.production.example not found -- repo checkout looks incomplete."
  log "No .env.production found. Creating one from .env.production.example with generated secrets..."
  cp "$REPO_ROOT/.env.production.example" "$ENV_FILE"

  gen_secret() { openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 32; }
  gen_key()    { openssl rand -hex 24; }

  PG_PASS="$(gen_secret)"
  REDIS_PASS="$(gen_secret)"
  API_KEY="$(gen_key)"

  # Portable in-place sed for both GNU and BSD/macOS sed.
  sedi() { sed -i.bak "$1" "$ENV_FILE" && rm -f "$ENV_FILE.bak"; }
  sedi "s|__POSTGRES_PASSWORD__|${PG_PASS}|g"
  sedi "s|__REDIS_PASSWORD__|${REDIS_PASS}|g"
  sedi "s|__AUTHENTICATION_API_KEY__|${API_KEY}|g"

  chmod 600 "$ENV_FILE"
  log "Generated .env.production with fresh secrets (chmod 600)."
  log "AUTHENTICATION_API_KEY: ${API_KEY}"
  log "Save this key now -- it will not be printed again by this script."
else
  log ".env.production already exists -- leaving it untouched."
fi

require_env_file

mkdir -p "$BACKUP_DIR"

log "Pulling images..."
dc pull

log "Starting stack (project: $COMPOSE_PROJECT)..."
dc up -d

log "Waiting for containers to report healthy (up to 120s)..."
deadline=$((SECONDS + 120))
services="evolution-postgres evolution-redis evolution-api evolution-manager"
while [ $SECONDS -lt $deadline ]; do
  all_healthy=true
  for c in $services; do
    status="$(docker inspect "$c" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' 2>/dev/null || echo missing)"
    if [ "$status" != "healthy" ] && [ "$status" != "no-healthcheck" ]; then
      all_healthy=false
    fi
  done
  if [ "$all_healthy" = true ]; then
    break
  fi
  sleep 3
done

echo
dc ps
echo
log "Install complete. Run scripts/healthcheck.sh to verify functionally."
