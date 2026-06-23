#!/usr/bin/env bash
# =============================================================================
# reset.sh — DESTRUCTIVE: Stop and remove all containers AND volumes.
# Use this to completely wipe the stack and start fresh.
# All PostgreSQL data, Airflow metadata, pgAdmin config, and SonarQube
# data will be permanently deleted.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "╔══════════════════════════════════════════════════════╗"
echo "║   PrintTimeUSA ELT Stack — FULL RESET               ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "⚠  WARNING: This will DELETE all Docker volumes including:"
echo "   - PostgreSQL data warehouse data"
echo "   - Airflow metadata database"
echo "   - pgAdmin configuration"
echo "   - SonarQube data and analysis results"
echo ""
read -r -p "   Are you sure you want to continue? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
  echo "Reset cancelled."
  exit 0
fi

cd "$PROJECT_ROOT"

echo ""
echo "▶  Stopping and removing containers and volumes..."
docker compose down --volumes --remove-orphans

echo ""
echo "✔  Stack fully reset. Run ./scripts/start.sh to rebuild from scratch."
