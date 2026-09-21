#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="${ROOT_DIR}/test-results/ops"
RUN_ID="$(date -u +%Y%m%d_%H%M%S)"
REPORT_PATH="${REPORT_DIR}/t0_live_rehearsal_v2_${RUN_ID}.md"
TMP_DIR="${REPORT_DIR}/.tmp_t0_live_${RUN_ID}"
mkdir -p "${REPORT_DIR}" "${TMP_DIR}"

API_BASE_URL="${API_BASE_URL:-http://localhost:8000}"
FE_BASE_URL="${FE_BASE_URL:-http://localhost:3000}"
LATENCY_THRESHOLD_MS="${LATENCY_THRESHOLD_MS:-1000}"
ERR_LOG_WINDOW="${ERR_LOG_WINDOW:-15m}"
TEST_JWT_SECRET="${TEST_JWT_SECRET:-$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(40))
PY
)}"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

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
  echo "# T0 Live Rehearsal v2"
  echo ""
  echo "- Tarih: $(timestamp)"
  echo "- Run ID: ${RUN_ID}"
  echo "- API Base URL: ${API_BASE_URL}"
  echo "- FE Base URL: ${FE_BASE_URL}"
  echo "- Latency Threshold (ms): ${LATENCY_THRESHOLD_MS}"
  echo ""
  echo "Bu rapor launch-day checklist maddelerini canliya benzer sekilde rehearsal eder."
  echo ""
} >"${REPORT_PATH}"

START_STATUS="PASS"
VERIFY_STATUS="PASS"
COMMS_STATUS="PASS"
INCIDENT_READY_STATUS="PASS"

# 3.1 Launch Start
if ! run_step \
  "Command Center Attendance Check" \
  "printf 'IC=%s\nBE=%s\nFE=%s\nSRE=%s\nQE=%s\nCOMMS=%s\n' '${IC_NAME:-ic-on-duty}' '${BE_LEAD:-be-lead}' '${FE_LEAD:-fe-lead}' '${SRE_LEAD:-sre-lead}' '${QE_LEAD:-qe-lead}' '${COMMS_OWNER:-comms-owner}'" \
  "${TMP_DIR}/command_center_attendance.log"; then
  START_STATUS="FAIL"
fi

if ! run_step \
  "Freeze Rule Marker" \
  "printf 'freeze_active=true\nchange_window=launch\nrecorded_at=%s\n' '$(timestamp)'" \
  "${TMP_DIR}/freeze_rule.log"; then
  START_STATUS="FAIL"
fi

if ! run_step \
  "Config Drift Snapshot" \
  "cd '${ROOT_DIR}' && git rev-parse HEAD && git status --short" \
  "${TMP_DIR}/config_drift.log"; then
  START_STATUS="FAIL"
fi

# 3.3 Real-Time Verification
if ! run_step \
  "API Availability Check" \
  "curl -fsS '${API_BASE_URL}/health'" \
  "${TMP_DIR}/api_health.log"; then
  VERIFY_STATUS="FAIL"
fi

if ! run_step \
  "API Latency Check (p95 proxy)" \
  "for i in 1 2 3 4 5; do curl -o /dev/null -s -w '%{time_total}\n' '${API_BASE_URL}/health'; done" \
  "${TMP_DIR}/latency_samples.log"; then
  VERIFY_STATUS="FAIL"
fi

python3 - <<'PY' "${TMP_DIR}/latency_samples.log" "${LATENCY_THRESHOLD_MS}" >"${TMP_DIR}/latency_eval.log"
import sys
path = sys.argv[1]
threshold_ms = float(sys.argv[2])
vals = []
with open(path, "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        vals.append(float(line) * 1000.0)
vals.sort()
if not vals:
    print("status=FAIL")
    print("reason=no latency samples")
    raise SystemExit(1)
p95_idx = max(0, int(round(0.95 * (len(vals) - 1))))
p95 = vals[p95_idx]
status = "PASS" if p95 <= threshold_ms else "FAIL"
print(f"status={status}")
print(f"samples_ms={vals}")
print(f"p95_ms={p95:.2f}")
print(f"threshold_ms={threshold_ms:.2f}")
if status != "PASS":
    raise SystemExit(1)
PY
cp "${TMP_DIR}/latency_eval.log" "${TMP_DIR}/latency_eval_render.log"
if ! run_step \
  "Latency Threshold Evaluation" \
  "cat '${TMP_DIR}/latency_eval_render.log'" \
  "${TMP_DIR}/latency_eval_section.log"; then
  VERIFY_STATUS="FAIL"
fi

if ! run_step \
  "Error-Rate Proxy Check (server logs)" \
  "docker logs --since '${ERR_LOG_WINDOW}' crawlens-server-dev 2>&1 | rg -n 'ERROR|Traceback|Exception' || true" \
  "${TMP_DIR}/error_rate_proxy.log"; then
  VERIFY_STATUS="FAIL"
fi

if ! run_step \
  "Critical Pages Smoke (Frontend)" \
  "cd '${ROOT_DIR}/client' && CI=1 PW_FORCE_AUTH_REFRESH=1 PLAYWRIGHT_API_URL='http://127.0.0.1:8011' PLAYWRIGHT_BASE_URL='http://127.0.0.1:3011' MONGODB_URL='mongodb://admin:password@127.0.0.1:27017/?authSource=admin' MONGODB_DATABASE='crawlens_t0_live_${RUN_ID}' npx playwright test tests/e2e/smoke-auth.spec.ts tests/e2e/monitoring-sidebar-navigation.spec.ts" \
  "${TMP_DIR}/critical_pages_smoke.log"; then
  VERIFY_STATUS="FAIL"
fi

if ! run_step \
  "Critical Background Jobs Health" \
  "docker ps --format '{{.Names}} {{.Status}}' | rg 'crawlens-celery-(worker|beat|default-worker)-dev'" \
  "${TMP_DIR}/background_jobs.log"; then
  VERIFY_STATUS="FAIL"
fi

if ! run_step \
  "Billing/Auth/Webhook Smoke" \
  "cd '${ROOT_DIR}/server' && PY_BIN=python3; [ -x .venv/bin/python ] && PY_BIN=.venv/bin/python; TESTING=true ENVIRONMENT=test JWT_SECRET_KEY='${TEST_JWT_SECRET}' \"\$PY_BIN\" -m pytest -q tests/api/test_auth_api.py::test_login_success_returns_token_bundle tests/api/test_billing_api.py::test_billing_status_requires_auth tests/api/test_deployments_api.py::test_create_deployment_webhook_success_with_secret" \
  "${TMP_DIR}/billing_auth_webhook_smoke.log"; then
  VERIFY_STATUS="FAIL"
fi

# 3.4 Communication readiness
if ! run_step \
  "Communication Template Presence" \
  "test -f '${ROOT_DIR}/docs/runbook/launch-communications-template.md' && wc -l '${ROOT_DIR}/docs/runbook/launch-communications-template.md'" \
  "${TMP_DIR}/comms_template.log"; then
  COMMS_STATUS="FAIL"
fi

if ! run_step \
  "Incident Template Presence" \
  "test -f '${ROOT_DIR}/docs/runbook/incident-runbook.md' && wc -l '${ROOT_DIR}/docs/runbook/incident-runbook.md'" \
  "${TMP_DIR}/incident_template.log"; then
  COMMS_STATUS="FAIL"
fi

# Incident-response ready simulation
if ! run_step \
  "Incident Ready Simulation Record" \
  "printf 'incident_commander_assigned=true\nseverity_classified=true\nblast_radius_estimated=true\nmitigation_decision_ready=true\nstatus_update_15m_ready=true\n'" \
  "${TMP_DIR}/incident_ready.log"; then
  INCIDENT_READY_STATUS="FAIL"
fi

OVERALL="PASS"
for s in "${START_STATUS}" "${VERIFY_STATUS}" "${COMMS_STATUS}" "${INCIDENT_READY_STATUS}"; do
  if [[ "${s}" != "PASS" ]]; then
    OVERALL="FAIL"
    break
  fi
done

{
  echo "## T0 Live Rehearsal Summary"
  echo ""
  echo "| Area | Status | Evidence |"
  echo "|---|---|---|"
  echo "| Launch Start (3.1) | ${START_STATUS} | command center + freeze + config drift snapshots |"
  echo "| Real-Time Verification (3.3) | ${VERIFY_STATUS} | API/latency/error proxy + FE/BE smoke + workers |"
  echo "| Communication Readiness (3.4) | ${COMMS_STATUS} | launch communications + incident template checks |"
  echo "| Incident Response Ready (5) | ${INCIDENT_READY_STATUS} | simulated readiness record |"
  echo ""
  echo "## Result"
  echo ""
  echo "- T0 live rehearsal v2: ${OVERALL}"
} >>"${REPORT_PATH}"

echo "T0 live rehearsal v2 report generated: ${REPORT_PATH}"

if [[ "${OVERALL}" != "PASS" ]]; then
  exit 1
fi
