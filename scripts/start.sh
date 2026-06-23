#!/usr/bin/env bash
# =============================================================================
# start.sh — Start the PrintTimeUSA ELT Docker Compose stack
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "╔══════════════════════════════════════════════════════╗"
echo "║   PrintTimeUSA ELT Stack — Starting                 ║"
echo "╚══════════════════════════════════════════════════════╝"

# Check for .env file
if [[ ! -f "$PROJECT_ROOT/.env" ]]; then
  echo ""
  echo "⚠  .env file not found."
  echo "   Copy .env.example to .env and fill in your credentials:"
  echo "   cp .env.example .env"
  echo ""
  exit 1
fi

cd "$PROJECT_ROOT"

echo ""
echo "▶  Building images (this may take a few minutes on first run)..."
docker compose build

echo ""
echo "▶  Starting services..."
docker compose up -d

echo ""
echo "✔  Stack started. Services should be ready in ~60 seconds."
echo ""
echo "   pgAdmin   →  http://localhost:5050"
echo "   Airflow   →  http://localhost:8080"
echo "   SonarQube →  http://localhost:9000"
echo "   Postgres  →  localhost:5432"
echo ""
echo "   Run ./scripts/healthcheck.sh to verify service status."
