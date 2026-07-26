#!/usr/bin/env bash
# Restart the whole stack, or a single service.
#
# Usage:
#   scripts/restart.sh                  # restart all 4 containers
#   scripts/restart.sh evolution-api    # restart just one service
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=lib.sh
source ./lib.sh

require_docker
require_env_file

SERVICE="${1:-}"

if [ -n "$SERVICE" ]; then
  case "$SERVICE" in
    evolution-api|evolution-manager|evolution-postgres|evolution-redis) ;;
    *) die "Unknown service '$SERVICE'. Expected one of: evolution-api evolution-manager evolution-postgres evolution-redis" ;;
  esac
  log "Restarting $SERVICE..."
  dc restart "$SERVICE"
else
  log "Restarting all services (project: $COMPOSE_PROJECT)..."
  dc restart
fi

dc ps
log "Restart complete. Run scripts/healthcheck.sh to verify."
