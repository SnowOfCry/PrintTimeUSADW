#!/usr/bin/env bash
# =============================================================================
# restore_warehouse.sh — Restore the PrintTimeUSA warehouse from a pg_dump archive.
#
# Usage:
#   ./scripts/restore_warehouse.sh                       # restore LATEST into the warehouse (prompts)
#   ./scripts/restore_warehouse.sh backups/xxx.dump      # restore a specific archive (prompts)
#   ./scripts/restore_warehouse.sh <archive> <target_db> # restore into another DB (e.g. a scratch DB)
#   FORCE=1 ./scripts/restore_warehouse.sh ...           # skip the confirmation prompt
#
# DESTRUCTIVE when the target is the live warehouse: pg_restore --clean drops and
# recreates objects. Defaults to a confirmation prompt. Restore into a scratch DB
# to validate a backup without touching production (that's how the DR test works).
# DR context: ADR-018.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

[ -f .env ] && set -a && . ./.env && set +a
DB="${POSTGRES_DB:-printtime_dw}"
USER="${POSTGRES_USER:-warehouse_user}"
PASS="${POSTGRES_PASSWORD:-changeme_warehouse}"
BACKUP_DIR="$PROJECT_ROOT/backups"

ARCHIVE="${1:-}"
TARGET_DB="${2:-$DB}"

# Default to the most recent archive if none given.
if [ -z "$ARCHIVE" ]; then
    ARCHIVE="$(ls -1t "$BACKUP_DIR/${DB}_"*.dump 2>/dev/null | head -1 || true)"
    [ -z "$ARCHIVE" ] && { echo "ERROR: no archive found in $BACKUP_DIR" >&2; exit 1; }
    echo "No archive given — using latest: $ARCHIVE"
fi
[ -f "$ARCHIVE" ] || { echo "ERROR: archive not found: $ARCHIVE" >&2; exit 1; }

echo "── Restore plan:"
echo "     archive:   $ARCHIVE"
echo "     target DB: $TARGET_DB $([ "$TARGET_DB" = "$DB" ] && echo '(LIVE WAREHOUSE)')"

if [ "${FORCE:-0}" != "1" ]; then
    printf "  This will OVERWRITE '%s'. Type 'yes' to continue: " "$TARGET_DB"
    read -r ANS
    [ "$ANS" = "yes" ] || { echo "Aborted."; exit 1; }
fi

# Create the target DB if it doesn't exist (harmless for the live DB).
docker compose exec -T -e PGPASSWORD="$PASS" postgres \
    psql -U "$USER" -d postgres -tc \
    "SELECT 1 FROM pg_database WHERE datname='$TARGET_DB'" | grep -q 1 || \
docker compose exec -T -e PGPASSWORD="$PASS" postgres \
    createdb -U "$USER" "$TARGET_DB"

echo "── Restoring into '$TARGET_DB' ..."
docker compose exec -T -e PGPASSWORD="$PASS" postgres \
    pg_restore --clean --if-exists --no-owner --no-privileges \
    -U "$USER" -d "$TARGET_DB" < "$ARCHIVE"

echo "✓ Restore complete into '$TARGET_DB'."
