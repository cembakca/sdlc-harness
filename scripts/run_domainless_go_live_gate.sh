#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="${ROOT_DIR}/test-results/ops"
RUN_ID="$(date -u +%Y%m%d_%H%M%S)"
REPORT_PATH="${REPORT_DIR}/domainless_go_live_gate_${RUN_ID}.md"
TMP_DIR="${REPORT_DIR}/.tmp_domainless_gate_${RUN_ID}"
mkdir -p "${REPORT_DIR}" "${TMP_DIR}" "${ROOT_DIR}/test-results/backend"

API_BASE_URL="${API_BASE_URL:-}"
RUN_SERVER="${RUN_SERVER:-1}"
RUN_CLIENT="${RUN_CLIENT:-1}"
RUN_LANDING="${RUN_LANDING:-1}"

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

append_section() {
  local title="$1"
  local status="$2"
  local started="$3"
  local ended="$4"
  local command="$5"
  local log_path="$6"

  {
    echo "## ${title}"
    echo "- Status: ${status}"
    echo "- Started: ${started}"
    echo "- Ended: ${ended}"
    echo "- Command: \`${command}\`"
    echo ""
    echo '```text'
    cat "${log_path}"
    printf '\n'
    echo '```'
    echo ""
  } >>"${REPORT_PATH}"
}

run_step() {
  local title="$1"
  local command="$2"
  local log_path="$3"
  local started ended status

  started="$(timestamp)"
  if bash -lc "${command}" >"${log_path}" 2>&1; then
    status="PASS"
  else
    status="FAIL"
  fi
  ended="$(timestamp)"
  append_section "${title}" "${status}" "${started}" "${ended}" "${command}" "${log_path}"

  [[ "${status}" == "PASS" ]]
}

{
  echo "# Domainless Go-Live Gate Report"
  echo ""
  echo "- Tarih: $(timestamp)"
  echo "- Run ID: ${RUN_ID}"
  echo "- Workspace: ${ROOT_DIR}"
  echo "- API Base URL: ${API_BASE_URL:-not-set}"
  echo ""
  echo "Bu rapor domain olmadan canliya cikis oncesi kalite kapilarini dogrular."
  echo ""
} >"${REPORT_PATH}"

SERVER_STATUS="SKIP"
CLIENT_STATUS="SKIP"
LANDING_STATUS="SKIP"
SMOKE_STATUS="SKIP"

if [[ "${RUN_SERVER}" == "1" ]]; then
  SERVER_STATUS="PASS"
  if ! run_step \
    "Server Critical Pack" \
    "cd '${ROOT_DIR}/server' && JUNIT_PATH='${ROOT_DIR}/test-results/backend/pytest-junit.xml' ./scripts/run_critical_pack.sh" \
    "${TMP_DIR}/server_critical.log"; then
    SERVER_STATUS="FAIL"
  fi

  if ! run_step \
    "Server Billing/Webhook Smoke" \
    "cd '${ROOT_DIR}/server' && PY_BIN=python3; [ -x .venv/bin/python ] && PY_BIN=.venv/bin/python; TESTING=true ENVIRONMENT=test JWT_SECRET_KEY='test-secret-for-domainless-gate-32chars' \"\$PY_BIN\" -m pytest -q tests/api/test_billing_api.py tests/api/test_billing_plans_edge_api.py" \
    "${TMP_DIR}/server_billing_smoke.log"; then
    SERVER_STATUS="FAIL"
  fi
fi

if [[ "${RUN_CLIENT}" == "1" ]]; then
  CLIENT_STATUS="PASS"
  if ! run_step \
    "Client Lint" \
    "cd '${ROOT_DIR}/client' && npm run lint" \
    "${TMP_DIR}/client_lint.log"; then
    CLIENT_STATUS="FAIL"
  fi

  if ! run_step \
    "Client Build" \
    "cd '${ROOT_DIR}/client' && npm run build" \
    "${TMP_DIR}/client_build.log"; then
    CLIENT_STATUS="FAIL"
  fi
fi

if [[ "${RUN_LANDING}" == "1" ]]; then
  LANDING_STATUS="PASS"
  if ! run_step \
    "Landing Quality Checks" \
    "cd '${ROOT_DIR}/landingpage' && npm run check:i18n && npm run check:claims && npm run check:docs && npm run check:links" \
    "${TMP_DIR}/landing_checks.log"; then
    LANDING_STATUS="FAIL"
  fi

  if ! run_step \
    "Landing Build" \
    "cd '${ROOT_DIR}/landingpage' && npm run build" \
    "${TMP_DIR}/landing_build.log"; then
    LANDING_STATUS="FAIL"
  fi
fi

if [[ -n "${API_BASE_URL}" ]]; then
  SMOKE_STATUS="PASS"
  if ! run_step \
    "API Health Smoke" \
    "curl -fsS '${API_BASE_URL}/health'" \
    "${TMP_DIR}/api_health.log"; then
    SMOKE_STATUS="FAIL"
  fi
fi

OVERALL="PASS"
for s in "${SERVER_STATUS}" "${CLIENT_STATUS}" "${LANDING_STATUS}" "${SMOKE_STATUS}"; do
  if [[ "${s}" == "FAIL" ]]; then
    OVERALL="FAIL"
    break
  fi
done

{
  echo "## Summary"
  echo ""
  echo "| Gate | Status |"
  echo "|---|---|"
  echo "| Server | ${SERVER_STATUS} |"
  echo "| Client | ${CLIENT_STATUS} |"
  echo "| Landing | ${LANDING_STATUS} |"
  echo "| API Smoke | ${SMOKE_STATUS} |"
  echo "| Overall | ${OVERALL} |"
  echo ""
} >>"${REPORT_PATH}"

echo "Report: ${REPORT_PATH}"
if [[ "${OVERALL}" != "PASS" ]]; then
  echo "Domainless go-live gate FAILED"
  exit 1
fi

echo "Domainless go-live gate PASSED"
