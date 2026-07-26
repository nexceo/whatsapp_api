#!/usr/bin/env bash
# Functional health check for the standalone Evolution API stack.
# Exits 0 if everything passes, 1 if anything fails (safe for cron/monitoring).
#
# Usage: scripts/healthcheck.sh [--quiet]
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
# shellcheck source=lib.sh
source ./lib.sh

QUIET=false
[ "${1:-}" = "--quiet" ] && QUIET=true

FAILURES=0
check() {
  local desc="$1" ok="$2"
  if [ "$ok" = "0" ]; then
    [ "$QUIET" = true ] || echo "PASS  $desc"
  else
    echo "FAIL  $desc"
    FAILURES=$((FAILURES + 1))
  fi
}

require_docker
require_env_file

SERVER_PORT="$(env_get SERVER_PORT)"
MANAGER_PORT="$(env_get MANAGER_PORT)"
API_KEY="$(env_get AUTHENTICATION_API_KEY)"
POSTGRES_USER="$(env_get POSTGRES_USER)"
POSTGRES_DB="$(env_get POSTGRES_DB)"
REDIS_PASSWORD="$(env_get REDIS_PASSWORD)"

# --- Container health ---
for c in evolution-postgres evolution-redis evolution-api evolution-manager; do
  status="$(docker inspect "$c" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' 2>/dev/null)"
  restarts="$(docker inspect "$c" --format '{{.RestartCount}}' 2>/dev/null || echo '?')"
  if [ "$status" = "healthy" ] || [ "$status" = "running" ]; then
    check "$c container healthy (restarts: $restarts)" 0
  else
    check "$c container healthy (status: ${status:-not found}, restarts: $restarts)" 1
  fi
done

# --- API reachability + version ---
if RESP="$(curl -sS --max-time 5 "http://127.0.0.1:${SERVER_PORT}/" 2>/dev/null)" && echo "$RESP" | grep -q '"status":200'; then
  check "API root reachable on 127.0.0.1:${SERVER_PORT}" 0
else
  check "API root reachable on 127.0.0.1:${SERVER_PORT}" 1
fi

# --- Auth enforcement ---
CODE="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${SERVER_PORT}/instance/fetchInstances" 2>/dev/null)"
check "API rejects requests without apikey (got $CODE, expected 401)" "$([ "$CODE" = "401" ] && echo 0 || echo 1)"

CODE="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${SERVER_PORT}/instance/fetchInstances" -H "apikey: ${API_KEY}" 2>/dev/null)"
check "API accepts requests with correct apikey (got $CODE, expected 200)" "$([ "$CODE" = "200" ] && echo 0 || echo 1)"

# --- Manager reachability ---
CODE="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${MANAGER_PORT}/health" 2>/dev/null)"
check "Manager UI reachable on 127.0.0.1:${MANAGER_PORT} (got $CODE, expected 200)" "$([ "$CODE" = "200" ] && echo 0 || echo 1)"

# --- Database ---
if docker exec evolution-postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; then
  check "Postgres accepting connections" 0
else
  check "Postgres accepting connections" 1
fi

# --- Redis ---
if [ "$(docker exec evolution-redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning ping 2>/dev/null)" = "PONG" ]; then
  check "Redis responding to PING" 0
else
  check "Redis responding to PING" 1
fi

# --- Persistent storage ---
for v in evolution_postgres_data evolution_redis_data evolution_instances; do
  if docker volume inspect "$v" >/dev/null 2>&1; then
    check "Volume $v exists" 0
  else
    check "Volume $v exists" 1
  fi
done

echo
if [ "$FAILURES" -eq 0 ]; then
  log "All checks passed."
  exit 0
else
  err "$FAILURES check(s) failed."
  exit 1
fi
