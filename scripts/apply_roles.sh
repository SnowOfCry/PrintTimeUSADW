#!/usr/bin/env bash
# =============================================================================
# apply_roles.sh — Create/refresh the least-privilege database roles (RBAC).
#
# Runs sql/security/001_create_roles.sql against the warehouse Postgres, passing
# the three role passwords in as psql variables so no secret is ever written into
# the SQL file. Idempotent — safe to re-run (e.g. after adding new gold models).
#
# Implements ADR-013 §3 / ADR-019; closes external-audit finding HIGH-6.
#
# Reads from .env (or the environment):
#   POSTGRES_USER / POSTGRES_PASSWORD / POSTGRES_DB   (superuser to run the DDL)
#   PT_INGESTION_PASSWORD / PT_DBT_PASSWORD / PT_BI_READER_PASSWORD
#
# Usage:   ./scripts/apply_roles.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

[ -f .env ] && set -a && . ./.env && set +a

DB="${POSTGRES_DB:-printtime_dw}"
ADMIN="${POSTGRES_USER:-warehouse_user}"
ADMIN_PASS="${POSTGRES_PASSWORD:-changeme_warehouse}"

ING_PW="${PT_INGESTION_PASSWORD:?set PT_INGESTION_PASSWORD in .env}"
DBT_PW="${PT_DBT_PASSWORD:?set PT_DBT_PASSWORD in .env}"
BI_PW="${PT_BI_READER_PASSWORD:?set PT_BI_READER_PASSWORD in .env}"

echo "── Applying least-privilege roles to '$DB' (as $ADMIN)"
docker compose exec -T -e PGPASSWORD="$ADMIN_PASS" postgres \
    psql -v ON_ERROR_STOP=1 -U "$ADMIN" -d "$DB" \
        -v ingestion_pw="$ING_PW" \
        -v dbt_pw="$DBT_PW" \
        -v bi_pw="$BI_PW" \
    < sql/security/001_create_roles.sql

echo "✓ Roles applied."
