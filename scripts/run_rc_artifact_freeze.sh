#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="${ROOT_DIR}/test-results/release"
RUN_ID="$(date -u +%Y%m%d_%H%M%S)"
FREEZE_DIR="${REPORT_DIR}/rc_artifacts_freeze_${RUN_ID}"
REPORT_PATH="${REPORT_DIR}/rc_artifact_freeze_${RUN_ID}.md"
TMP_DIR="${REPORT_DIR}/.tmp_rc_freeze_${RUN_ID}"
mkdir -p "${REPORT_DIR}" "${FREEZE_DIR}" "${TMP_DIR}"

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

require_file() {
  local path="$1"
  local label="$2"
  if [[ ! -f "${path}" ]]; then
    echo "missing required ${label}: ${path}" >&2
    return 1
  fi
}

latest_file() {
  local dir="$1"
  local pattern="$2"
  find "${dir}" -maxdepth 1 -name "${pattern}" -print | sort | tail -n1
}

capture_hashes() {
  local source="$1"
  local out="$2"
  if [[ -d "${source}" ]]; then
    find "${source}" -type f | sort | while IFS= read -r f; do
      shasum -a 256 "${f}"
    done >"${out}"
  else
    shasum -a 256 "${source}" >"${out}"
  fi
}

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

LATEST_QUALITY="$(latest_file "${ROOT_DIR}/test-results/release" "rc_quality_chain_*.md")"
LATEST_SECURITY="$(latest_file "${ROOT_DIR}/test-results/security" "rc_security_chain_*.md")"
LATEST_VITEST_JUNIT="$(latest_file "${ROOT_DIR}/test-results/release" "vitest_junit_*.xml")"
BACKEND_JUNIT="${ROOT_DIR}/test-results/backend/pytest-junit.xml"
PLAYWRIGHT_JUNIT="${ROOT_DIR}/client/test-results/playwright/junit.xml"
PLAYWRIGHT_JSON="${ROOT_DIR}/client/test-results/playwright/results.json"
FE_DIST_DIR="${ROOT_DIR}/client/dist"

require_file "${LATEST_QUALITY}" "RC quality report"
require_file "${LATEST_SECURITY}" "RC security report"
require_file "${LATEST_VITEST_JUNIT}" "Vitest JUnit archive"
require_file "${BACKEND_JUNIT}" "Backend JUnit"
require_file "${PLAYWRIGHT_JUNIT}" "Playwright JUnit"
require_file "${PLAYWRIGHT_JSON}" "Playwright JSON"
if [[ ! -d "${FE_DIST_DIR}" ]]; then
  echo "missing frontend build artifact directory: ${FE_DIST_DIR}" >&2
  exit 1
fi

GIT_COMMIT="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
GIT_BRANCH="$(git -C "${ROOT_DIR}" rev-parse --abbrev-ref HEAD)"

cp "${LATEST_QUALITY}" "${FREEZE_DIR}/"
cp "${LATEST_SECURITY}" "${FREEZE_DIR}/"
cp "${LATEST_VITEST_JUNIT}" "${FREEZE_DIR}/"
cp "${BACKEND_JUNIT}" "${FREEZE_DIR}/backend-pytest-junit.xml"
cp "${PLAYWRIGHT_JUNIT}" "${FREEZE_DIR}/playwright-junit.xml"
cp "${PLAYWRIGHT_JSON}" "${FREEZE_DIR}/playwright-results.json"
cp -R "${FE_DIST_DIR}" "${FREEZE_DIR}/frontend-dist"

capture_hashes "${FREEZE_DIR}/frontend-dist" "${FREEZE_DIR}/frontend-dist.sha256"
capture_hashes "${FREEZE_DIR}/backend-pytest-junit.xml" "${FREEZE_DIR}/backend-junit.sha256"
capture_hashes "${FREEZE_DIR}/playwright-junit.xml" "${FREEZE_DIR}/playwright-junit.sha256"
capture_hashes "${FREEZE_DIR}/playwright-results.json" "${FREEZE_DIR}/playwright-results.sha256"
capture_hashes "${FREEZE_DIR}/$(basename "${LATEST_VITEST_JUNIT}")" "${FREEZE_DIR}/vitest-junit.sha256"
capture_hashes "${ROOT_DIR}/server/requirements-dev.txt" "${FREEZE_DIR}/server-requirements-dev.sha256"
capture_hashes "${ROOT_DIR}/client/package-lock.json" "${FREEZE_DIR}/client-package-lock.sha256"

if command -v docker >/dev/null 2>&1; then
  docker ps --format "{{.Names}} {{.Image}} {{.Status}}" >"${FREEZE_DIR}/docker-containers.txt" || true
fi

{
  echo "# RC Artifact Freeze Report"
  echo ""
  echo "- Date (UTC): $(timestamp)"
  echo "- Run ID: ${RUN_ID}"
  echo "- RC branch: ${GIT_BRANCH}"
  echo "- RC commit: ${GIT_COMMIT}"
  echo "- Freeze dir: ${FREEZE_DIR}"
  echo ""
  echo "## RC Branch Cut Evidence"
  echo "- Branch cut reference: \`${GIT_BRANCH}\` @ \`${GIT_COMMIT}\`"
  echo "- Git status snapshot:"
  echo '```text'
  git -C "${ROOT_DIR}" status --short
  printf '\n'
  echo '```'
  echo ""
  echo "## Frozen Artifacts"
  echo "- RC quality report: ${FREEZE_DIR}/$(basename "${LATEST_QUALITY}")"
  echo "- RC security report: ${FREEZE_DIR}/$(basename "${LATEST_SECURITY}")"
  echo "- Backend JUnit: ${FREEZE_DIR}/backend-pytest-junit.xml"
  echo "- Vitest JUnit: ${FREEZE_DIR}/$(basename "${LATEST_VITEST_JUNIT}")"
  echo "- Playwright JUnit: ${FREEZE_DIR}/playwright-junit.xml"
  echo "- Playwright JSON: ${FREEZE_DIR}/playwright-results.json"
  echo "- Frontend dist: ${FREEZE_DIR}/frontend-dist"
  echo ""
  echo "## Checksums"
  echo "- frontend-dist.sha256"
  echo "- backend-junit.sha256"
  echo "- vitest-junit.sha256"
  echo "- playwright-junit.sha256"
  echo "- playwright-results.sha256"
  echo "- server-requirements-dev.sha256"
  echo "- client-package-lock.sha256"
  echo ""
  if [[ -f "${FREEZE_DIR}/docker-containers.txt" ]]; then
    echo "## Docker Runtime Snapshot"
    echo '```text'
    cat "${FREEZE_DIR}/docker-containers.txt"
    printf '\n'
    echo '```'
    echo ""
  fi
  echo "## Result"
  echo "- RC artifact freeze: PASS"
} >"${REPORT_PATH}"

echo "RC artifact freeze report generated: ${REPORT_PATH}"
echo "Frozen artifacts directory: ${FREEZE_DIR}"
