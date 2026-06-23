#!/usr/bin/env bash
# =============================================================================
# healthcheck.sh — Check status of all PrintTimeUSA ELT stack services
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "╔══════════════════════════════════════════════════════╗"
echo "║   PrintTimeUSA ELT Stack — Health Check             ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Container status ─────────────────────────────────────────────────────────
echo "── Container Status ───────────────────────────────────"
docker compose ps
echo ""

# ── PostgreSQL ───────────────────────────────────────────────────────────────
echo "── PostgreSQL ─────────────────────────────────────────"
if docker compose exec -T postgres pg_isready -U "${POSTGRES_USER:-warehouse_user}" \
     -d "${POSTGRES_DB:-printtime_dw}" &>/dev/null; then
  echo "  ✔  PostgreSQL is accepting connections on port 5432"
else
  echo "  ✘  PostgreSQL is NOT ready"
fi
echo ""

# ── Airflow Webserver ─────────────────────────────────────────────────────────
echo "── Airflow Webserver ──────────────────────────────────"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
  echo "  ✔  Airflow is healthy at http://localhost:8080"
else
  echo "  ✘  Airflow not responding (HTTP $HTTP_CODE) — may still be starting"
fi
echo ""

# ── pgAdmin ───────────────────────────────────────────────────────────────────
echo "── pgAdmin ────────────────────────────────────────────"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5050 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
  echo "  ✔  pgAdmin is available at http://localhost:5050"
else
  echo "  ✘  pgAdmin not responding (HTTP $HTTP_CODE)"
fi
echo ""

# ── SonarQube ─────────────────────────────────────────────────────────────────
echo "── SonarQube ──────────────────────────────────────────"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9000 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
  echo "  ✔  SonarQube is available at http://localhost:9000"
else
  echo "  ✘  SonarQube not responding (HTTP $HTTP_CODE) — may take 2-3 min to start"
fi
echo ""

# ── Docker volume summary ──────────────────────────────────────────────────────
echo "── Docker Volumes ─────────────────────────────────────"
docker volume ls --filter "name=printtime" 2>/dev/null || docker volume ls
echo ""

echo "── Logs (last 5 lines per service) ───────────────────"
for svc in postgres airflow-webserver airflow-scheduler; do
  echo ""
  echo "  [${svc}]"
  docker compose logs --tail=5 "$svc" 2>/dev/null | sed 's/^/    /' || true
done
echo ""
echo "✔  Health check complete."
