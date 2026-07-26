#!/usr/bin/env bash
# Tail logs for the stack, or a single service.
#
# Usage:
#   scripts/logs.sh                     # follow all services, last 200 lines each
#   scripts/logs.sh evolution-api       # follow just one service
#   scripts/logs.sh evolution-api --no-follow --tail 500
set -euo pipefail
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
cd "$(dirname "$SELF")"
# shellcheck source=lib.sh
source ./lib.sh

require_docker
require_env_file

SERVICE=""
FOLLOW=true
TAIL=200

while [ $# -gt 0 ]; do
  case "$1" in
    --no-follow) FOLLOW=false; shift ;;
    --tail) TAIL="$2"; shift 2 ;;
    evolution-api|evolution-manager|evolution-postgres|evolution-redis) SERVICE="$1"; shift ;;
    -h|--help) grep '^#' "$SELF" | grep -Ev '^#!|shellcheck' | sed 's/^#//'; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

ARGS=(--tail "$TAIL")
[ "$FOLLOW" = true ] && ARGS+=(-f)
[ -n "$SERVICE" ] && ARGS+=("$SERVICE")

dc logs "${ARGS[@]}"
