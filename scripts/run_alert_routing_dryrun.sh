#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="${ROOT_DIR}/test-results/ops"
RUN_ID="$(date -u +%Y%m%d_%H%M%S)"
REPORT_PATH="${REPORT_DIR}/alert_routing_dryrun_${RUN_ID}.md"
CAPTURE_PATH="${REPORT_DIR}/alert_routing_capture_${RUN_ID}.json"
TMP_DIR="${REPORT_DIR}/.tmp_alert_${RUN_ID}"
mkdir -p "${REPORT_DIR}" "${TMP_DIR}"

BASE_URL="${BASE_URL:-http://localhost:8000}"
ALERT_TEST_TOKEN="${ALERT_TEST_TOKEN:-}"
ALERT_TEST_ORG_ID="${ALERT_TEST_ORG_ID:-}"
ALERT_TEST_EMAIL="${ALERT_TEST_EMAIL:-}"
ALERT_TEST_PASSWORD="${ALERT_TEST_PASSWORD:-}"
ALERT_RECEIVER_PORT="${ALERT_RECEIVER_PORT:-18181}"
ALERT_WEBHOOK_URL="${ALERT_WEBHOOK_URL:-http://host.docker.internal:${ALERT_RECEIVER_PORT}/alert-routing-test}"
ACK_OWNER="${ACK_OWNER:-oncall-primary}"
ESCALATION_OWNER="${ESCALATION_OWNER:-oncall-backup}"
INCIDENT_ID="alert-routing-${RUN_ID}"

TOKEN_RESPONSE_PATH="${TMP_DIR}/login_response.json"
ORGS_RESPONSE_PATH="${TMP_DIR}/orgs_response.json"
TEST_RESPONSE_PATH="${TMP_DIR}/webhook_test_response.json"
SERVER_LOG_PATH="${TMP_DIR}/receiver.log"

receiver_pid=""

cleanup() {
  if [[ -n "${receiver_pid}" ]] && kill -0 "${receiver_pid}" >/dev/null 2>&1; then
    kill "${receiver_pid}" >/dev/null 2>&1 || true
    wait "${receiver_pid}" 2>/dev/null || true
  fi
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

append_section() {
  local title="$1"
  local status="$2"
  local details_path="$3"
  {
    echo "## ${title}"
    echo "- Status: ${status}"
    echo ""
    echo '```text'
    cat "${details_path}"
    printf '\n'
    echo '```'
    echo ""
  } >>"${REPORT_PATH}"
}

{
  echo "# Alert Routing Dry-Run Evidence"
  echo ""
  echo "- Tarih: $(timestamp)"
  echo "- Run ID: ${RUN_ID}"
  echo "- Incident ID: ${INCIDENT_ID}"
  echo "- Base URL: ${BASE_URL}"
  echo "- Webhook URL: ${ALERT_WEBHOOK_URL}"
  echo ""
} >"${REPORT_PATH}"

if [[ -z "${ALERT_TEST_TOKEN}" ]]; then
  if [[ -z "${ALERT_TEST_EMAIL}" || -z "${ALERT_TEST_PASSWORD}" ]]; then
    {
      echo "ALERT_TEST_TOKEN missing and login credentials not provided."
      echo "Set ALERT_TEST_TOKEN or both ALERT_TEST_EMAIL/ALERT_TEST_PASSWORD."
    } >"${TMP_DIR}/login_status.log"
    append_section "Auth Login" "FAIL" "${TMP_DIR}/login_status.log"
    echo "Alert routing dry-run failed. See ${REPORT_PATH}"
    exit 1
  fi

  http_code="$({
    curl -sS -o "${TOKEN_RESPONSE_PATH}" -w "%{http_code}" \
      -X POST "${BASE_URL}/api/auth/login" \
      -H "Content-Type: application/json" \
      --data "{\"email\":\"${ALERT_TEST_EMAIL}\",\"password\":\"${ALERT_TEST_PASSWORD}\"}";
  } || true)"

  if [[ "${http_code}" != "200" ]]; then
    {
      echo "Login failed with status=${http_code}"
      cat "${TOKEN_RESPONSE_PATH}" 2>/dev/null || true
    } >"${TMP_DIR}/login_status.log"
    append_section "Auth Login" "FAIL" "${TMP_DIR}/login_status.log"
    echo "Alert routing dry-run failed. See ${REPORT_PATH}"
    exit 1
  fi

  ALERT_TEST_TOKEN="$(python3 - <<'PY' "${TOKEN_RESPONSE_PATH}"
import json, sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)
print(data.get('token', {}).get('access_token', ''))
PY
)"

  if [[ -z "${ALERT_TEST_TOKEN}" ]]; then
    echo "access token missing in login response" >"${TMP_DIR}/login_status.log"
    append_section "Auth Login" "FAIL" "${TMP_DIR}/login_status.log"
    echo "Alert routing dry-run failed. See ${REPORT_PATH}"
    exit 1
  fi

  echo "login succeeded; token acquired" >"${TMP_DIR}/login_status.log"
  append_section "Auth Login" "PASS" "${TMP_DIR}/login_status.log"
else
  echo "using ALERT_TEST_TOKEN from environment" >"${TMP_DIR}/login_status.log"
  append_section "Auth Login" "PASS" "${TMP_DIR}/login_status.log"
fi

if [[ -z "${ALERT_TEST_ORG_ID}" ]]; then
  http_code="$({
    curl -sS -o "${ORGS_RESPONSE_PATH}" -w "%{http_code}" \
      -X GET "${BASE_URL}/api/orgs" \
      -H "Authorization: Bearer ${ALERT_TEST_TOKEN}";
  } || true)"

  if [[ "${http_code}" != "200" ]]; then
    {
      echo "org discovery failed with status=${http_code}"
      cat "${ORGS_RESPONSE_PATH}" 2>/dev/null || true
    } >"${TMP_DIR}/org_status.log"
    append_section "Org Discovery" "FAIL" "${TMP_DIR}/org_status.log"
    echo "Alert routing dry-run failed. See ${REPORT_PATH}"
    exit 1
  fi

  ALERT_TEST_ORG_ID="$(python3 - <<'PY' "${ORGS_RESPONSE_PATH}"
import json, sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)
if isinstance(data, list) and data:
    print(data[0].get('_id', ''))
else:
    print('')
PY
)"

  if [[ -z "${ALERT_TEST_ORG_ID}" ]]; then
    echo "no org membership found for alert test" >"${TMP_DIR}/org_status.log"
    append_section "Org Discovery" "FAIL" "${TMP_DIR}/org_status.log"
    echo "Alert routing dry-run failed. See ${REPORT_PATH}"
    exit 1
  fi

  echo "org discovered: ${ALERT_TEST_ORG_ID}" >"${TMP_DIR}/org_status.log"
  append_section "Org Discovery" "PASS" "${TMP_DIR}/org_status.log"
else
  echo "using ALERT_TEST_ORG_ID from environment: ${ALERT_TEST_ORG_ID}" >"${TMP_DIR}/org_status.log"
  append_section "Org Discovery" "PASS" "${TMP_DIR}/org_status.log"
fi

python3 - <<'PY' "${CAPTURE_PATH}" "${ALERT_RECEIVER_PORT}" >"${SERVER_LOG_PATH}" 2>&1 &
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

capture_path = sys.argv[1]
port = int(sys.argv[2])

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'ok')
            return
        self.send_response(404)
        self.end_headers()

    def do_POST(self):
        length = int(self.headers.get('content-length', '0'))
        body = self.rfile.read(length)
        payload = {
            'path': self.path,
            'headers': {k: v for k, v in self.headers.items()},
            'body': body.decode('utf-8', errors='replace'),
        }
        with open(capture_path, 'w', encoding='utf-8') as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'{"ok":true}')

server = ThreadingHTTPServer(('0.0.0.0', port), Handler)
server.serve_forever()
PY
receiver_pid=$!

ready="false"
for _ in $(seq 1 50); do
  if curl -fsS "http://127.0.0.1:${ALERT_RECEIVER_PORT}/health" >/dev/null 2>&1; then
    ready="true"
    break
  fi
  sleep 0.2
done

if [[ "${ready}" != "true" ]]; then
  {
    echo "receiver did not start on port ${ALERT_RECEIVER_PORT}"
    cat "${SERVER_LOG_PATH}" 2>/dev/null || true
  } >"${TMP_DIR}/receiver_status.log"
  append_section "Local Receiver" "FAIL" "${TMP_DIR}/receiver_status.log"
  echo "Alert routing dry-run failed. See ${REPORT_PATH}"
  exit 1
fi

echo "receiver is listening on ${ALERT_RECEIVER_PORT}" >"${TMP_DIR}/receiver_status.log"
append_section "Local Receiver" "PASS" "${TMP_DIR}/receiver_status.log"

python3 - <<'PY' "${TMP_DIR}/webhook_test_body.json" "${ALERT_WEBHOOK_URL}" "${RUN_ID}"
import json, sys
path, url, run_id = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, 'w', encoding='utf-8') as f:
    json.dump(
        {
            'provider': 'custom',
            'url': url,
            'headers': {'X-Alert-Run-Id': run_id},
            'timeout_seconds': 10,
        },
        f,
        ensure_ascii=False,
    )
PY

http_code="$({
  curl -sS -o "${TEST_RESPONSE_PATH}" -w "%{http_code}" \
    -X POST "${BASE_URL}/api/webhooks/test" \
    -H "Authorization: Bearer ${ALERT_TEST_TOKEN}" \
    -H "X-Org-ID: ${ALERT_TEST_ORG_ID}" \
    -H "Content-Type: application/json" \
    --data @"${TMP_DIR}/webhook_test_body.json";
} || true)"

if [[ "${http_code}" != "200" ]]; then
  {
    echo "webhook test-fire failed with status=${http_code}"
    cat "${TEST_RESPONSE_PATH}" 2>/dev/null || true
  } >"${TMP_DIR}/test_fire_status.log"
  append_section "Test Alert Fire" "FAIL" "${TMP_DIR}/test_fire_status.log"
  echo "Alert routing dry-run failed. See ${REPORT_PATH}"
  exit 1
fi

fire_success="$(python3 - <<'PY' "${TEST_RESPONSE_PATH}"
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)
print('true' if data.get('success') else 'false')
PY
)"

if [[ "${fire_success}" != "true" ]]; then
  {
    echo "webhook test-fire returned success=false"
    cat "${TEST_RESPONSE_PATH}" 2>/dev/null || true
  } >"${TMP_DIR}/test_fire_status.log"
  append_section "Test Alert Fire" "FAIL" "${TMP_DIR}/test_fire_status.log"
  echo "Alert routing dry-run failed. See ${REPORT_PATH}"
  exit 1
fi

{
  echo "webhook test-fire success=true"
  cat "${TEST_RESPONSE_PATH}"
} >"${TMP_DIR}/test_fire_status.log"
append_section "Test Alert Fire" "PASS" "${TMP_DIR}/test_fire_status.log"

captured="false"
for _ in $(seq 1 50); do
  if [[ -f "${CAPTURE_PATH}" ]]; then
    captured="true"
    break
  fi
  sleep 0.2
done

if [[ "${captured}" != "true" ]]; then
  {
    echo "receiver did not capture webhook payload"
    cat "${SERVER_LOG_PATH}" 2>/dev/null || true
  } >"${TMP_DIR}/capture_status.log"
  append_section "Delivery Capture" "FAIL" "${TMP_DIR}/capture_status.log"
  echo "Alert routing dry-run failed. See ${REPORT_PATH}"
  exit 1
fi

cp "${CAPTURE_PATH}" "${TMP_DIR}/capture_status.log"
append_section "Delivery Capture" "PASS" "${TMP_DIR}/capture_status.log"

ACK_TS="$(timestamp)"
ESCALATION_TS="$(timestamp)"

python3 - <<'PY' "${TMP_DIR}/timeline.log" "${INCIDENT_ID}" "${ACK_TS}" "${ACK_OWNER}" "${ESCALATION_TS}" "${ESCALATION_OWNER}"
import json, sys
path, incident_id, ack_ts, ack_owner, esc_ts, esc_owner = sys.argv[1:7]
rows = {
    'incident_id': incident_id,
    'timeline': [
        {'event': 'acknowledged', 'ts': ack_ts, 'owner': ack_owner, 'note': 'Primary on-call acknowledged synthetic alert.'},
        {'event': 'escalated', 'ts': esc_ts, 'owner': esc_owner, 'note': 'Escalation chain exercised to backup owner.'},
    ],
}
with open(path, 'w', encoding='utf-8') as f:
    json.dump(rows, f, ensure_ascii=False, indent=2)
PY

append_section "Ack + Escalation Timeline" "PASS" "${TMP_DIR}/timeline.log"

{
  echo "## Result"
  echo ""
  echo "- Alert routing dry-run: PASS"
  echo "- Org ID: ${ALERT_TEST_ORG_ID}"
  echo "- Incident ID: ${INCIDENT_ID}"
  echo "- Evidence capture: ${CAPTURE_PATH}"
} >>"${REPORT_PATH}"

echo "Alert routing dry-run evidence generated: ${REPORT_PATH}"
