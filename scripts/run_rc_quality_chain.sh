#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="${ROOT_DIR}/test-results/release"
RUN_ID="$(date -u +%Y%m%d_%H%M%S)"
REPORT_PATH="${REPORT_DIR}/rc_quality_chain_${RUN_ID}.md"
TMP_DIR="${REPORT_DIR}/.tmp_rc_${RUN_ID}"
mkdir -p "${REPORT_DIR}" "${TMP_DIR}" "${ROOT_DIR}/test-results/backend"

E2E_API_URL="${RC_E2E_API_URL:-http://127.0.0.1:8110}"
E2E_BASE_URL="${RC_E2E_BASE_URL:-http://127.0.0.1:3110}"
E2E_MONGODB_URL="${RC_E2E_MONGODB_URL:-${MONGODB_URL:-mongodb://admin:password@127.0.0.1:27017/?authSource=admin}}"
E2E_MONGODB_DB="${RC_E2E_MONGODB_DB:-crawlens_e2e_rc_${RUN_ID}}"
FLAKE_THRESHOLD="${RC_E2E_FLAKE_THRESHOLD:-0.02}"
VITEST_JUNIT_ARCHIVE="${REPORT_DIR}/vitest_junit_${RUN_ID}.xml"

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

  if [[ "${status}" != "PASS" ]]; then
    echo "RC quality chain failed at '${title}'. Report: ${REPORT_PATH}"
    exit 1
  fi
}

summarize_junit() {
  local junit_path="$1"
  local out_path="$2"
  if [[ ! -f "${junit_path}" ]]; then
    echo "missing junit file: ${junit_path}" >"${out_path}"
    return
  fi
  python3 - <<'PY' "${junit_path}" >"${out_path}"
import xml.etree.ElementTree as ET
import sys
path = sys.argv[1]
root = ET.parse(path).getroot()
if root.tag == "testsuite":
    tests = int(root.attrib.get("tests", 0))
    failures = int(root.attrib.get("failures", 0))
    errors = int(root.attrib.get("errors", 0))
    skipped = int(root.attrib.get("skipped", 0))
else:
    tests = failures = errors = skipped = 0
    for suite in root.findall("testsuite"):
        tests += int(suite.attrib.get("tests", 0))
        failures += int(suite.attrib.get("failures", 0))
        errors += int(suite.attrib.get("errors", 0))
        skipped += int(suite.attrib.get("skipped", 0))
status = "PASS" if failures == 0 and errors == 0 else "FAIL"
print(f"status={status}")
print(f"tests={tests}")
print(f"failures={failures}")
print(f"errors={errors}")
print(f"skipped={skipped}")
PY
}

summarize_playwright_flake() {
  local json_path="$1"
  local out_path="$2"
  local threshold="$3"
  if [[ ! -f "${json_path}" ]]; then
    echo "missing playwright json report: ${json_path}" >"${out_path}"
    return 1
  fi

  python3 - <<'PY' "${json_path}" "${threshold}" >"${out_path}"
import json
import sys

path = sys.argv[1]
threshold = float(sys.argv[2])
with open(path, "r", encoding="utf-8") as handle:
    root = json.load(handle)

total = 0
flaky = 0
failed = 0
passed = 0
skipped = 0

def walk_suite(suite):
    global total, flaky, failed, passed, skipped
    for spec in suite.get("specs", []):
        for test in spec.get("tests", []):
            total += 1
            outcome = test.get("outcome")
            if outcome == "flaky":
                flaky += 1
            elif outcome == "unexpected":
                failed += 1
            elif outcome == "expected":
                passed += 1
            elif outcome == "skipped":
                skipped += 1
            else:
                statuses = [r.get("status") for r in test.get("results", [])]
                if "failed" in statuses and "passed" in statuses:
                    flaky += 1
                elif "failed" in statuses:
                    failed += 1
                elif "skipped" in statuses:
                    skipped += 1
                elif "passed" in statuses:
                    passed += 1
    for child in suite.get("suites", []):
        walk_suite(child)

for top in root.get("suites", []):
    walk_suite(top)

ratio = (flaky / total) if total else 0.0
gate = "PASS" if ratio <= threshold else "FAIL"

print(f"status={gate}")
print(f"threshold={threshold:.4f}")
print(f"tests={total}")
print(f"passed={passed}")
print(f"failed={failed}")
print(f"flaky={flaky}")
print(f"skipped={skipped}")
print(f"flake_ratio={ratio:.4f}")
PY

  local status_line
  status_line="$(grep '^status=' "${out_path}" | cut -d'=' -f2- || true)"
  [[ "${status_line}" == "PASS" ]]
}

{
  echo "# RC Quality Chain Report"
  echo ""
  echo "- Tarih: $(timestamp)"
  echo "- Run ID: ${RUN_ID}"
  echo "- Workspace: ${ROOT_DIR}"
  echo "- E2E API URL: ${E2E_API_URL}"
  echo "- E2E FE URL: ${E2E_BASE_URL}"
  echo "- E2E Mongo DB: ${E2E_MONGODB_DB}"
  echo ""
} >"${REPORT_PATH}"

run_step \
  "Backend Critical Pack" \
  "cd '${ROOT_DIR}/server' && JUNIT_PATH='${ROOT_DIR}/test-results/backend/pytest-junit.xml' ./scripts/run_critical_pack.sh" \
  "${TMP_DIR}/backend_critical.log"

run_step \
  "Frontend Unit Critical" \
  "cd '${ROOT_DIR}/client' && npx vitest run tests/unit/layout/section-config.test.ts tests/unit/layout/global-context-bar.test.tsx tests/unit/layout/navigation-copy-consistency.test.ts tests/unit/components/page-states.test.tsx tests/unit/hooks/monitoring-contracts.test.tsx --reporter=default --reporter=junit --outputFile.junit=./test-results/vitest/junit.xml" \
  "${TMP_DIR}/frontend_unit_critical.log"

if [[ ! -f "${ROOT_DIR}/client/test-results/vitest/junit.xml" ]]; then
  {
    echo "Vitest junit file missing after unit critical step."
    echo "Expected: ${ROOT_DIR}/client/test-results/vitest/junit.xml"
  } >>"${TMP_DIR}/frontend_unit_critical.log"
  echo "RC quality chain failed: missing vitest junit artifact"
  exit 1
fi
cp "${ROOT_DIR}/client/test-results/vitest/junit.xml" "${VITEST_JUNIT_ARCHIVE}"

run_step \
  "Frontend Build Sanity" \
  "cd '${ROOT_DIR}/client' && npm run build" \
  "${TMP_DIR}/frontend_build.log"

run_step \
  "Frontend E2E Critical" \
  "cd '${ROOT_DIR}/client' && CI=1 PW_FORCE_AUTH_REFRESH=1 PLAYWRIGHT_API_URL='${E2E_API_URL}' PLAYWRIGHT_BASE_URL='${E2E_BASE_URL}' MONGODB_URL='${E2E_MONGODB_URL}' MONGODB_DATABASE='${E2E_MONGODB_DB}' npm run test:e2e:critical" \
  "${TMP_DIR}/frontend_e2e_critical.log"

summarize_junit "${ROOT_DIR}/test-results/backend/pytest-junit.xml" "${TMP_DIR}/backend_junit_summary.log"
summarize_junit "${VITEST_JUNIT_ARCHIVE}" "${TMP_DIR}/vitest_junit_summary.log"
summarize_junit "${ROOT_DIR}/client/test-results/playwright/junit.xml" "${TMP_DIR}/playwright_junit_summary.log"
if ! summarize_playwright_flake "${ROOT_DIR}/client/test-results/playwright/results.json" "${TMP_DIR}/playwright_flake_summary.log" "${FLAKE_THRESHOLD}"; then
  {
    echo "RC quality chain failed: Playwright flake ratio threshold exceeded or report missing."
    cat "${TMP_DIR}/playwright_flake_summary.log"
  } >>"${REPORT_PATH}"
  echo "RC quality chain failed: flake ratio gate"
  exit 1
fi

{
  echo "## Artifact Summary"
  echo ""
  echo "- Backend JUnit: ${ROOT_DIR}/test-results/backend/pytest-junit.xml"
  echo "- Vitest JUnit (archived): ${VITEST_JUNIT_ARCHIVE}"
  echo "- Playwright JUnit: ${ROOT_DIR}/client/test-results/playwright/junit.xml"
  echo "- Playwright JSON: ${ROOT_DIR}/client/test-results/playwright/results.json"
  echo "- Playwright HTML: ${ROOT_DIR}/client/playwright-report"
  echo "- Flake Threshold: ${FLAKE_THRESHOLD}"
  echo ""
  echo "### Backend JUnit"
  echo '```text'
  cat "${TMP_DIR}/backend_junit_summary.log"
  printf '\n'
  echo '```'
  echo ""
  echo "### Vitest JUnit"
  echo '```text'
  cat "${TMP_DIR}/vitest_junit_summary.log"
  printf '\n'
  echo '```'
  echo ""
  echo "### Playwright JUnit"
  echo '```text'
  cat "${TMP_DIR}/playwright_junit_summary.log"
  printf '\n'
  echo '```'
  echo ""
  echo "### Playwright Flake Gate"
  echo '```text'
  cat "${TMP_DIR}/playwright_flake_summary.log"
  printf '\n'
  echo '```'
  echo ""
  echo "## Result"
  echo ""
  echo "- RC quality chain: PASS"
} >>"${REPORT_PATH}"

echo "RC quality chain report generated: ${REPORT_PATH}"
