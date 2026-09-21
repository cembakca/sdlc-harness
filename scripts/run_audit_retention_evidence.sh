#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="${ROOT_DIR}/server"
REPORT_DIR="${ROOT_DIR}/test-results/security"
RUN_ID="$(date -u +%Y%m%d_%H%M%S)"
REPORT_PATH="${REPORT_DIR}/audit_retention_enforcement_${RUN_ID}.md"
TMP_DIR="${REPORT_DIR}/.tmp_audit_retention_${RUN_ID}"
PYTHON_BIN="${SERVER_DIR}/.venv/bin/python"

mkdir -p "${REPORT_DIR}" "${TMP_DIR}"

any_fail=0

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

run_cmd() {
  local title="$1"
  local command="$2"
  local output="${TMP_DIR}/${title// /_}.log"
  local status="PASS"

  if bash -lc "${command}" >"${output}" 2>&1; then
    status="PASS"
  else
    status="FAIL"
    any_fail=1
  fi

  {
    echo "## ${title}"
    echo "- Status: ${status}"
    echo "- Command: \`${command}\`"
    echo ""
    echo '```text'
    cat "${output}"
    printf '\n'
    echo '```'
    echo ""
  } >>"${REPORT_PATH}"
}

if [[ ! -x "${PYTHON_BIN}" ]]; then
  echo "Python binary not found: ${PYTHON_BIN}" >&2
  exit 1
fi

{
  echo "# Audit Retention Enforcement Evidence"
  echo ""
  echo "- Date (UTC): $(timestamp)"
  echo "- Scope: Stage-2 S2-004 acceptance evidence"
  echo "- Server dir: ${SERVER_DIR}"
  echo ""
  echo "Bu rapor unit test + dry-run + apply-run + schedule registration kanitini tek dosyada toplar."
  echo ""
} >"${REPORT_PATH}"

run_cmd \
  "Audit Retention Unit Tests" \
  "cd '${SERVER_DIR}' && '${PYTHON_BIN}' -m pytest tests/test_audit_retention_task.py -q"

run_cmd \
  "Audit Retention Dry Run" \
  "cd '${SERVER_DIR}' && '${PYTHON_BIN}' -m scripts.run_enforce_audit_retention --dry-run"

run_cmd \
  "Audit Retention Apply Run" \
  "cd '${SERVER_DIR}' && '${PYTHON_BIN}' -m scripts.run_enforce_audit_retention"

run_cmd \
  "Beat Schedule Registration" \
  "cd '${SERVER_DIR}' && rg -n 'enforce-audit-retention|enforce_audit_retention_task' app/workers/celery_app.py app/workers/tasks/maintenance_tasks.py"

{
  echo "## Result"
  if [[ "${any_fail}" -eq 0 ]]; then
    echo "- Audit retention evidence: PASS"
  else
    echo "- Audit retention evidence: FAIL"
  fi
} >>"${REPORT_PATH}"

echo "Audit retention evidence generated: ${REPORT_PATH}"

if [[ "${any_fail}" -ne 0 ]]; then
  exit 1
fi
