#!/usr/bin/env bash
# Back up the Postgres database and the WhatsApp instance/session volume.
# Redis is a cache (CACHE_REDIS_SAVE_INSTANCES=false) and is intentionally
# not backed up.
#
# Usage:
#   scripts/backup.sh                 # backup DB + instance volume
#   scripts/backup.sh --db-only
#   scripts/backup.sh --volume-only
#   RETENTION_DAYS=30 scripts/backup.sh   # override default 14-day retention
set -euo pipefail
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
cd "$(dirname "$SELF")"
# shellcheck source=lib.sh
source ./lib.sh

require_docker
require_env_file
mkdir -p "$BACKUP_DIR"

DO_DB=true
DO_VOLUME=true
case "${1:-}" in
  --db-only) DO_VOLUME=false ;;
  --volume-only) DO_DB=false ;;
  "") : ;;
  -h|--help) grep '^#' "$SELF" | grep -Ev '^#!|shellcheck' | sed 's/^#//'; exit 0 ;;
  *) die "Unknown argument: $1" ;;
esac

RETENTION_DAYS="${RETENTION_DAYS:-14}"
TS="$(date +%Y%m%d_%H%M%S)"
POSTGRES_USER="$(env_get POSTGRES_USER)"
POSTGRES_DB="$(env_get POSTGRES_DB)"

if [ "$DO_DB" = true ]; then
  docker inspect evolution-postgres >/dev/null 2>&1 || die "evolution-postgres container not found -- is the stack running?"
  OUT="$BACKUP_DIR/evolution_db_${TS}.sql.gz"
  log "Dumping database ${POSTGRES_DB} -> $OUT"
  docker exec evolution-postgres pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" | gzip > "$OUT"
  SIZE="$(du -h "$OUT" | cut -f1)"
  log "Database backup written: $OUT ($SIZE)"
fi

if [ "$DO_VOLUME" = true ]; then
  OUT="$BACKUP_DIR/evolution_instances_${TS}.tar.gz"
  log "Archiving evolution_instances volume -> $OUT"
  docker run --rm \
    -v evolution_instances:/data:ro \
    -v "$BACKUP_DIR":/backup \
    alpine tar czf "/backup/$(basename "$OUT")" -C /data .
  SIZE="$(du -h "$OUT" | cut -f1)"
  log "Instance volume backup written: $OUT ($SIZE)"
fi

if [ "$RETENTION_DAYS" -gt 0 ] 2>/dev/null; then
  log "Pruning backups older than ${RETENTION_DAYS} days in $BACKUP_DIR..."
  find "$BACKUP_DIR" -maxdepth 1 -type f \( -name 'evolution_db_*.sql.gz' -o -name 'evolution_instances_*.tar.gz' \) -mtime "+${RETENTION_DAYS}" -print -delete
fi

log "Backup complete."
