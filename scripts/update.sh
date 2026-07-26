#!/usr/bin/env bash
# Upgrade the Evolution API (and/or Manager) image tag.
#
# This edits the `image:` line(s) in docker-compose.production.yml,
# takes a backup first, then pulls and recreates just the changed
# service(s) -- Postgres/Redis and their data are left alone.
#
# Usage:
#   scripts/update.sh --api v2.4.0
#   scripts/update.sh --manager latest
#   scripts/update.sh --api v2.4.0 --manager latest
#   scripts/update.sh --api v2.4.0 --skip-backup   # not recommended
set -euo pipefail
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
cd "$(dirname "$SELF")"
# shellcheck source=lib.sh
source ./lib.sh

require_docker
require_env_file

NEW_API_TAG=""
NEW_MANAGER_TAG=""
SKIP_BACKUP=false

while [ $# -gt 0 ]; do
  case "$1" in
    --api) NEW_API_TAG="$2"; shift 2 ;;
    --manager) NEW_MANAGER_TAG="$2"; shift 2 ;;
    --skip-backup) SKIP_BACKUP=true; shift ;;
    -h|--help)
      grep '^#' "$SELF" | grep -Ev '^#!|shellcheck' | sed 's/^#//'
      exit 0
      ;;
    *) die "Unknown argument: $1 (see --help)" ;;
  esac
done

[ -n "$NEW_API_TAG" ] || [ -n "$NEW_MANAGER_TAG" ] || die "Nothing to do -- pass --api <tag> and/or --manager <tag>."

CURRENT_API_IMAGE="$(grep -A1 'container_name: evolution-api$' "$COMPOSE_FILE" | grep 'image:' | awk '{print $2}')"
CURRENT_MANAGER_IMAGE="$(grep -A1 'container_name: evolution-manager$' "$COMPOSE_FILE" | grep 'image:' | awk '{print $2}')"
log "Current API image:     $CURRENT_API_IMAGE"
log "Current Manager image: $CURRENT_MANAGER_IMAGE"

if [ "$SKIP_BACKUP" = false ]; then
  log "Taking a backup before upgrading (use --skip-backup to disable, not recommended)..."
  ./backup.sh
else
  log "Skipping pre-upgrade backup (--skip-backup passed)."
fi

RECREATE_SERVICES=""

if [ -n "$NEW_API_TAG" ]; then
  NEW_API_IMAGE="evoapicloud/evolution-api:${NEW_API_TAG}"
  log "Verifying image exists: $NEW_API_IMAGE"
  docker pull "$NEW_API_IMAGE" >/dev/null || die "Could not pull $NEW_API_IMAGE -- aborting before touching the compose file."
  sed -i.bak "s#image: evoapicloud/evolution-api:.*#image: ${NEW_API_IMAGE}#" "$COMPOSE_FILE" && rm -f "$COMPOSE_FILE.bak"
  log "Updated docker-compose.production.yml -> $NEW_API_IMAGE"
  RECREATE_SERVICES="$RECREATE_SERVICES evolution-api"
fi

if [ -n "$NEW_MANAGER_TAG" ]; then
  NEW_MANAGER_IMAGE="evoapicloud/evolution-manager:${NEW_MANAGER_TAG}"
  log "Verifying image exists: $NEW_MANAGER_IMAGE"
  docker pull "$NEW_MANAGER_IMAGE" >/dev/null || die "Could not pull $NEW_MANAGER_IMAGE -- aborting before touching the compose file."
  sed -i.bak "s#image: evoapicloud/evolution-manager:.*#image: ${NEW_MANAGER_IMAGE}#" "$COMPOSE_FILE" && rm -f "$COMPOSE_FILE.bak"
  log "Updated docker-compose.production.yml -> $NEW_MANAGER_IMAGE"
  RECREATE_SERVICES="$RECREATE_SERVICES evolution-manager"
fi

log "Recreating:${RECREATE_SERVICES}"
# shellcheck disable=SC2086
dc up -d $RECREATE_SERVICES

if [ -n "$NEW_API_TAG" ]; then
  log "Tailing evolution-api logs for migration output (Ctrl+C to stop tailing, containers keep running)..."
  timeout 30 docker logs -f evolution-api 2>&1 | grep -m1 -E "successfully applied|HTTP - ON|error" || true
fi

echo
dc ps
echo
log "Update complete. Run scripts/healthcheck.sh to verify."
log "If this upgrade needs to be rolled back: edit docker-compose.production.yml back to the previous tag(s) and re-run 'dc up -d <service>', or restore from the backup taken above (see scripts/restore.sh)."
