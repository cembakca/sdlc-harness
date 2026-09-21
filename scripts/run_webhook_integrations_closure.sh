#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="${ROOT_DIR}/server"
LANDING_DIR="${ROOT_DIR}/landingpage"
PYTEST_BIN="${SERVER_DIR}/.venv/bin/pytest"
if [[ ! -x "${PYTEST_BIN}" ]]; then
  PYTEST_BIN="python3 -m pytest"
fi

echo "[1/3] Running webhook-focused server gate..."
${PYTEST_BIN} -q \
  "${SERVER_DIR}/tests/api/test_webhook_management_api.py" \
  "${SERVER_DIR}/tests/api/test_webhook_e2e_smoke_api.py" \
  "${SERVER_DIR}/tests/test_webhook_service_unit.py" \
  "${SERVER_DIR}/tests/test_webhook_tasks_unit.py" \
  "${SERVER_DIR}/tests/test_db_validators.py"

echo "[2/3] Running landing integration claim gates..."
(
  cd "${LANDING_DIR}"
  npm run -s check:integrations
  npm run -s check:i18n
  npm run -s check:links
  npm run -s typecheck
)

echo "[3/3] Running landing production build..."
(
  cd "${LANDING_DIR}"
  npm run -s build
)

echo "Webhook + integrations closure gate passed."
