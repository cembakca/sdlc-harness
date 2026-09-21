#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="${ROOT_DIR}/test-results/ops"
RUN_ID="$(date -u +%Y%m%d_%H%M%S)"
REPORT_PATH="${REPORT_DIR}/t0_ops_readiness_dryrun_${RUN_ID}.md"
TMP_DIR="${REPORT_DIR}/.tmp_t0_ops_${RUN_ID}"
mkdir -p "${REPORT_DIR}" "${TMP_DIR}"

API_BASE_URL="${API_BASE_URL:-http://localhost:8000}"
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3002}"
CANARY_CHECKS="${CANARY_CHECKS:-3}"
CANARY_INTERVAL_SEC="${CANARY_INTERVAL_SEC:-5}"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

append_cmd_section() {
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
  append_cmd_section "${title}" "${status}" "${started}" "${ended}" "${command}" "${log_path}"
  if [[ "${status}" != "PASS" ]]; then
    return 1
  fi
  return 0
}

{
  echo "# T0 Ops Readiness Dry-Run"
  echo ""
  echo "- Tarih: $(timestamp)"
  echo "- Run ID: ${RUN_ID}"
  echo "- API Base URL: ${API_BASE_URL}"
  echo "- Grafana URL: ${GRAFANA_URL}"
  echo "- Canary Checks: ${CANARY_CHECKS}"
  echo "- Canary Interval (sec): ${CANARY_INTERVAL_SEC}"
  echo ""
  echo "Bu rapor production deploy yapmaz; T0 operasyon akisini dry-run olarak dogrular."
  echo ""
} >"${REPORT_PATH}"

SLO_STATUS="PASS"
PIN_STATUS="PASS"
DEPLOY_SEQUENCE_STATUS="PASS"

if ! run_step \
  "SLO Dashboard Live Check" \
  "curl -fsS '${GRAFANA_URL}/api/health'" \
  "${TMP_DIR}/slo_dashboard.log"; then
  SLO_STATUS="FAIL"
fi

PIN_PACK="${ROOT_DIR}/docs/runbook/war-room-pin-pack.md"
if [[ -f "${PIN_PACK}" ]]; then
  sha256sum "${PIN_PACK}" >"${TMP_DIR}/pin_pack_sha.log"
  {
    echo "## War-Room Pin Pack Check"
    echo "- Status: PASS"
    echo "- File: ${PIN_PACK}"
    echo ""
    echo '```text'
    cat "${TMP_DIR}/pin_pack_sha.log"
    printf '\n'
    echo '```'
    echo ""
  } >>"${REPORT_PATH}"
else
  PIN_STATUS="FAIL"
  {
    echo "## War-Room Pin Pack Check"
    echo "- Status: FAIL"
    echo "- Reason: ${PIN_PACK} not found"
    echo ""
  } >>"${REPORT_PATH}"
fi

if ! run_step \
  "Pre-Deploy Service Snapshot" \
  "docker ps --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}'" \
  "${TMP_DIR}/predeploy_services.log"; then
  DEPLOY_SEQUENCE_STATUS="FAIL"
fi

CANARY_LOG="${TMP_DIR}/canary_health.log"
{
  echo "canary_checks=${CANARY_CHECKS}"
  echo "interval_sec=${CANARY_INTERVAL_SEC}"
} >"${CANARY_LOG}"

for i in $(seq 1 "${CANARY_CHECKS}"); do
  if ! curl -fsS "${API_BASE_URL}/health" >>"${CANARY_LOG}" 2>&1; then
    DEPLOY_SEQUENCE_STATUS="FAIL"
  fi
  if [[ "${i}" -lt "${CANARY_CHECKS}" ]]; then
    sleep "${CANARY_INTERVAL_SEC}"
  fi
done

append_cmd_section \
  "Canary Health Window Check" \
  "${DEPLOY_SEQUENCE_STATUS}" \
  "$(timestamp)" \
  "$(timestamp)" \
  "curl -fsS ${API_BASE_URL}/health (x${CANARY_CHECKS}, interval=${CANARY_INTERVAL_SEC}s)" \
  "${CANARY_LOG}"

if ! run_step \
  "Post-Canary Service Snapshot" \
  "docker ps --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}'" \
  "${TMP_DIR}/postcanary_services.log"; then
  DEPLOY_SEQUENCE_STATUS="FAIL"
fi

OVERALL="PASS"
for status in "${SLO_STATUS}" "${PIN_STATUS}" "${DEPLOY_SEQUENCE_STATUS}"; do
  if [[ "${status}" != "PASS" ]]; then
    OVERALL="FAIL"
    break
  fi
done

{
  echo "## T0 Gate Summary"
  echo ""
  echo "| Gate | Status | Evidence |"
  echo "|---|---|---|"
  echo "| SLO dashboard live | ${SLO_STATUS} | ${GRAFANA_URL}/api/health |"
  echo "| War-room runbook pin pack hazir | ${PIN_STATUS} | docs/runbook/war-room-pin-pack.md |"
  echo "| Deploy order + canary + rollout dry-run | ${DEPLOY_SEQUENCE_STATUS} | pre/post service snapshot + canary health window |"
  echo ""
  echo "## Result"
  echo ""
  echo "- T0 ops readiness dry-run: ${OVERALL}"
} >>"${REPORT_PATH}"

echo "T0 ops readiness dry-run report generated: ${REPORT_PATH}"

if [[ "${OVERALL}" != "PASS" ]]; then
  exit 1
fi
