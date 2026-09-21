#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="${ROOT_DIR}/server"
REPORT_DIR="${ROOT_DIR}/test-results/security"
RUN_ID="$(date -u +%Y%m%d_%H%M%S)"
REPORT_PATH="${REPORT_DIR}/sso_callback_contract_${RUN_ID}.md"
TMP_DIR="${REPORT_DIR}/.tmp_sso_contract_${RUN_ID}"
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
  echo "# SSO Callback Contract Evidence"
  echo ""
  echo "- Date (UTC): $(timestamp)"
  echo "- Scope: Stage-2 S2-001 acceptance evidence"
  echo "- Server dir: ${SERVER_DIR}"
  echo ""
  echo "Bu rapor feature-gate, bearer-guard, audit trail ve test coverage kanitini toplar."
  echo ""
} >"${REPORT_PATH}"

run_cmd \
  "Identity Bridge Unit Tests" \
  "cd '${SERVER_DIR}' && '${PYTHON_BIN}' -m pytest tests/test_identity_bridge_service_unit.py -q"

run_cmd \
  "SSO Callback API Contract Tests" \
  "cd '${SERVER_DIR}' && '${PYTHON_BIN}' -m pytest tests/api/test_auth_sso_callback_api.py -q"

run_cmd \
  "SSO Route and Gate Verification" \
  "cd '${ROOT_DIR}' && rg -n 'sso/callback|SSO_IDENTITY_BRIDGE_ENABLED|_verify_sso_callback_bearer|SSO_CALLBACK_LOGIN' server/app/api/auth.py server/app/services/identity_audit.py"

{
  echo "## Result"
  if [[ "${any_fail}" -eq 0 ]]; then
    echo "- SSO callback contract evidence: PASS"
  else
    echo "- SSO callback contract evidence: FAIL"
  fi
} >>"${REPORT_PATH}"

echo "SSO callback contract evidence generated: ${REPORT_PATH}"

if [[ "${any_fail}" -ne 0 ]]; then
  exit 1
fi
