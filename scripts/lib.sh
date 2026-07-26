#!/usr/bin/env bash
# Shared helpers sourced by every script in this directory.
# Not meant to be run directly.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_PROJECT="evolution"
COMPOSE_FILE="$REPO_ROOT/docker-compose.production.yml"
ENV_FILE="$REPO_ROOT/.env.production"
# shellcheck disable=SC2034  # used by backup.sh, restore.sh, install.sh
BACKUP_DIR="$REPO_ROOT/backups"

log()  { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
err()  { printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
die()  { err "$*"; exit 1; }

require_env_file() {
  [ -f "$ENV_FILE" ] || die ".env.production not found at $ENV_FILE. Run scripts/install.sh first, or copy .env.production.example and fill it in."
}

require_docker() {
  command -v docker >/dev/null 2>&1 || die "docker is not installed or not on PATH."
  docker compose version >/dev/null 2>&1 || die "docker compose (v2 plugin) is required."
}

# Reads a single KEY=value out of .env.production without sourcing the
# file (avoids shell interpretation of values like CORS_ORIGIN=*).
env_get() {
  local key="$1"
  [ -f "$ENV_FILE" ] || return 1
  grep -m1 "^${key}=" "$ENV_FILE" | cut -d'=' -f2- | sed -e "s/^['\"]//" -e "s/['\"]$//"
}

dc() {
  docker compose -p "$COMPOSE_PROJECT" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"
}
