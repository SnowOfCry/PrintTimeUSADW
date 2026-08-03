#!/usr/bin/env bash
# =============================================================================
# backup_warehouse.sh — Logical backup of the PrintTimeUSA warehouse database.
#
# Takes a compressed pg_dump (custom format) of the warehouse Postgres, writes a
# timestamped archive under ./backups, and prunes old archives past the retention
# count. Custom format (-Fc) is compressed and supports selective / parallel
# restore via pg_restore.
#
# Usage:   ./scripts/backup_warehouse.sh
# Retain:  BACKUP_RETAIN=14 ./scripts/backup_warehouse.sh   (default 7)
# Restore: ./scripts/restore_warehouse.sh <archive>
#
# DR context: ADR-018. The warehouse is also reproducible from bronze via dbt, so
# this backup is the fast-recovery path; a full rebuild is the fallback.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Load .env (POSTGRES_USER / POSTGRES_DB / POSTGRES_PASSWORD) if present.
[ -f .env ] && set -a && . ./.env && set +a

DB="${POSTGRES_DB:-printtime_dw}"
USER="${POSTGRES_USER:-warehouse_user}"
PASS="${POSTGRES_PASSWORD:-changeme_warehouse}"
RETAIN="${BACKUP_RETAIN:-7}"

BACKUP_DIR="$PROJECT_ROOT/backups"
mkdir -p "$BACKUP_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
ARCHIVE="$BACKUP_DIR/${DB}_${TS}.dump"

echo "── Backing up '$DB' → $ARCHIVE"
# -T: no TTY (so we can redirect stdout). -Fc: compressed custom format.
docker compose exec -T -e PGPASSWORD="$PASS" postgres \
    pg_dump -U "$USER" -d "$DB" -Fc --no-owner --no-privileges > "$ARCHIVE"

# Fail loudly if the archive is empty/tiny (a broken dump is worse than none).
BYTES="$(wc -c < "$ARCHIVE" | tr -d ' ')"
if [ "$BYTES" -lt 1000 ]; then
    echo "ERROR: backup looks empty (${BYTES} bytes) — removing and failing." >&2
    rm -f "$ARCHIVE"
    exit 1
fi
echo "✓ Backup complete: $(du -h "$ARCHIVE" | cut -f1) ($BYTES bytes)"

# Retention: keep the newest $RETAIN archives, delete the rest.
mapfile -t OLD < <(ls -1t "$BACKUP_DIR/${DB}_"*.dump 2>/dev/null | tail -n +"$((RETAIN + 1))")
if [ "${#OLD[@]}" -gt 0 ]; then
    printf '%s\n' "${OLD[@]}" | xargs -r rm -f
    echo "✓ Pruned ${#OLD[@]} archive(s) beyond retention=$RETAIN"
fi

echo "── Backups on disk:"
ls -1t "$BACKUP_DIR/${DB}_"*.dump 2>/dev/null | head -"$RETAIN" | sed 's|.*/|  |'
