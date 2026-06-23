#!/usr/bin/env bash
# =============================================================================
# stop.sh — Stop the PrintTimeUSA ELT Docker Compose stack
# Containers are stopped but NOT removed. Volumes are preserved.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "╔══════════════════════════════════════════════════════╗"
echo "║   PrintTimeUSA ELT Stack — Stopping                 ║"
echo "╚══════════════════════════════════════════════════════╝"

cd "$PROJECT_ROOT"
docker compose stop

echo ""
echo "✔  All containers stopped. Data volumes are preserved."
echo "   Run ./scripts/start.sh to restart."
