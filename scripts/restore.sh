#!/usr/bin/env bash
# Restore a database dump (and optionally the instance volume) produced
# by scripts/backup.sh. DESTRUCTIVE: overwrites current data. Requires
# --yes to actually run, otherwise it only prints what it would do.
#
# Usage:
#   scripts/restore.sh --db backups/evolution_db_20260101_000000.sql.gz --yes
#   scripts/restore.sh --volume backups/evolution_instances_20260101_000000.tar.gz --yes
#   scripts/restore.sh --db <file> --volume <file> --yes
set -euo pipefail
ORIG_PWD="$PWD"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
cd "$(dirname "$SELF")"
# shellcheck source=lib.sh
source ./lib.sh

require_docker
require_env_file

DB_FILE=""
VOLUME_FILE=""
CONFIRM=false

while [ $# -gt 0 ]; do
  case "$1" in
    --db) DB_FILE="$2"; shift 2 ;;
    --volume) VOLUME_FILE="$2"; shift 2 ;;
    --yes) CONFIRM=true; shift ;;
    -h|--help) grep '^#' "$SELF" | grep -Ev '^#!|shellcheck' | sed 's/^#//'; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[ -n "$DB_FILE" ] || [ -n "$VOLUME_FILE" ] || die "Nothing to restore -- pass --db <file> and/or --volume <file>."

# --db/--volume are given relative to the caller's cwd, not this
# script's directory (we cd'd into scripts/ above to source lib.sh).
resolve_path() { case "$1" in /*) echo "$1" ;; *) echo "$ORIG_PWD/$1" ;; esac; }
[ -n "$DB_FILE" ] && DB_FILE="$(resolve_path "$DB_FILE")"
[ -n "$VOLUME_FILE" ] && VOLUME_FILE="$(resolve_path "$VOLUME_FILE")"

if [ -n "$DB_FILE" ]; then
  [ -f "$DB_FILE" ] || die "DB backup file not found: $DB_FILE"
fi
if [ -n "$VOLUME_FILE" ]; then
  [ -f "$VOLUME_FILE" ] || die "Volume backup file not found: $VOLUME_FILE"
fi

echo "This will PERMANENTLY OVERWRITE:"
[ -n "$DB_FILE" ]     && echo "  - the evolution_api database, with contents of: $DB_FILE"
[ -n "$VOLUME_FILE" ] && echo "  - the evolution_instances volume, with contents of: $VOLUME_FILE"
echo

if [ "$CONFIRM" != true ]; then
  log "Dry run (no --yes passed). Nothing was changed. Re-run with --yes to actually restore."
  exit 0
fi

POSTGRES_USER="$(env_get POSTGRES_USER)"
POSTGRES_DB="$(env_get POSTGRES_DB)"

if [ -n "$DB_FILE" ]; then
  docker inspect evolution-postgres >/dev/null 2>&1 || die "evolution-postgres container not found -- is the stack running?"
  log "Restoring database from $DB_FILE ..."
  gunzip -c "$DB_FILE" | docker exec -i evolution-postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
  log "Database restore complete."
fi

if [ -n "$VOLUME_FILE" ]; then
  log "Restoring evolution_instances volume from $VOLUME_FILE ..."
  log "Stopping evolution-api first (session files must not be written to during restore)..."
  dc stop evolution-api
  docker run --rm \
    -v evolution_instances:/data \
    -v "$(cd "$(dirname "$VOLUME_FILE")" && pwd)":/backup:ro \
    alpine sh -c "rm -rf /data/* /data/..?* /data/.[!.]* 2>/dev/null; tar xzf /backup/$(basename "$VOLUME_FILE") -C /data"
  log "Starting evolution-api back up..."
  dc up -d evolution-api
  log "Volume restore complete."
fi

log "Restore finished. Run scripts/healthcheck.sh to verify."
