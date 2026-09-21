#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="${ROOT_DIR}/server"
REPORT_DIR="${ROOT_DIR}/test-results/security"
RUN_ID="$(date -u +%Y%m%d_%H%M%S)"
REPORT_PATH="${REPORT_DIR}/access_review_operations_${RUN_ID}.md"
PYTHON_BIN="${SERVER_DIR}/.venv/bin/python"

mkdir -p "${REPORT_DIR}"

if [[ ! -x "${PYTHON_BIN}" ]]; then
  echo "Python binary not found: ${PYTHON_BIN}" >&2
  exit 1
fi

set +e
(
  cd "${SERVER_DIR}"
  "${PYTHON_BIN}" -m scripts.run_access_review_report --stale-days 30 --output "${REPORT_PATH}"
)
rc=$?
set -e

echo "Access review evidence generated: ${REPORT_PATH}"
exit "${rc}"
