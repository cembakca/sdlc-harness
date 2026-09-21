#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="${ROOT_DIR}/test-results/security"
RUN_ID="$(date -u +%Y%m%d_%H%M%S)"
ARTIFACT_DIR="${REPORT_DIR}/artifacts_${RUN_ID}"
REPORT_PATH="${REPORT_DIR}/rc_security_chain_${RUN_ID}.md"
TMP_DIR="${REPORT_DIR}/.tmp_security_${RUN_ID}"
mkdir -p "${REPORT_DIR}" "${ARTIFACT_DIR}" "${TMP_DIR}"

any_fail=0

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
  local output_file="$6"
  {
    echo "## ${title}"
    echo "- Status: ${status}"
    echo "- Started: ${started}"
    echo "- Ended: ${ended}"
    echo "- Command: \`${command}\`"
    echo ""
    echo '```text'
    cat "${output_file}"
    printf '\n'
    echo '```'
    echo ""
  } >>"${REPORT_PATH}"
}

run_step() {
  local title="$1"
  local command="$2"
  local output_file="$3"
  local started ended status
  started="$(timestamp)"

  if bash -lc "${command}" >"${output_file}" 2>&1; then
    status="PASS"
  else
    status="FAIL"
    any_fail=1
  fi

  ended="$(timestamp)"
  append_section "${title}" "${status}" "${started}" "${ended}" "${command}" "${output_file}"
}

{
  echo "# RC Security Chain Report"
  echo ""
  echo "- Tarih: $(timestamp)"
  echo "- Run ID: ${RUN_ID}"
  echo "- Workspace: ${ROOT_DIR}"
  echo "- Artifact dir: ${ARTIFACT_DIR}"
  echo ""
  echo "Bu rapor CI security gate ile hizali local rehearsal sonucudur."
  echo ""
} >"${REPORT_PATH}"

run_step \
  "Secret Scan (gitleaks)" \
  "docker run --rm -v '${ROOT_DIR}:/repo' ghcr.io/gitleaks/gitleaks:v8.24.2 detect --source=/repo --no-git --redact --report-format json --report-path /repo/test-results/security/artifacts_${RUN_ID}/gitleaks.json --config /repo/.gitleaks.toml --max-target-megabytes 5" \
  "${TMP_DIR}/gitleaks.log"

run_step \
  "SAST Scan (semgrep auto)" \
  "docker run --rm -v '${ROOT_DIR}:/repo' semgrep/semgrep:1.118.0 semgrep scan --config auto --error --json --output /repo/test-results/security/artifacts_${RUN_ID}/sast-semgrep.json --exclude /repo/server/node_modules --exclude /repo/client/node_modules --exclude /repo/landingpage/node_modules --exclude /repo/client/dist --exclude /repo/landingpage/dist --exclude /repo/test-results --exclude /repo/server/.venv --exclude /repo/server/venv /repo/server /repo/client /repo/landingpage" \
  "${TMP_DIR}/semgrep.log"

run_step \
  "SAST Scan (bandit server)" \
  "docker run --rm -v '${ROOT_DIR}:/repo' -w /repo/server python:3.11-slim sh -c 'pip install --no-cache-dir -q bandit && bandit -r app -ll -f json -o /repo/test-results/security/artifacts_${RUN_ID}/sast-bandit.json'" \
  "${TMP_DIR}/bandit.log"

run_step \
  "Dependency Audit (server pip-audit)" \
  "docker run --rm -v '${ROOT_DIR}:/repo' -w /repo/server python:3.11-slim sh -c 'pip install --no-cache-dir -q pip-audit && pip-audit -r requirements-dev.txt --ignore-vuln CVE-2024-23342 --format json > /repo/test-results/security/artifacts_${RUN_ID}/deps-pip-audit.json'" \
  "${TMP_DIR}/pip_audit.log"

run_step \
  "Dependency Audit (client npm audit high)" \
  "docker run --rm -v '${ROOT_DIR}:/repo' -w /repo/client node:20-alpine sh -c 'npm audit --audit-level=high --json > /repo/test-results/security/artifacts_${RUN_ID}/deps-npm-client.json'" \
  "${TMP_DIR}/npm_audit_client.log"

if [[ -f "${ROOT_DIR}/landingpage/package-lock.json" ]]; then
  run_step \
    "Dependency Audit (landing npm audit high)" \
    "docker run --rm -v '${ROOT_DIR}:/repo' -w /repo/landingpage node:20-alpine sh -c 'npm audit --audit-level=high --json > /repo/test-results/security/artifacts_${RUN_ID}/deps-npm-landing.json'" \
    "${TMP_DIR}/npm_audit_landing.log"
else
  {
    echo "## Dependency Audit (landing npm audit high)"
    echo "- Status: SKIPPED"
    echo "- Reason: landingpage/package-lock.json not found"
    echo ""
  } >>"${REPORT_PATH}"
fi

run_step \
  "SBOM (server CycloneDX)" \
  "docker run --rm -v '${ROOT_DIR}:/repo' anchore/syft:v1.31.0 dir:/repo/server -o cyclonedx-json=/repo/test-results/security/artifacts_${RUN_ID}/sbom-server.cdx.json" \
  "${TMP_DIR}/sbom_server.log"

run_step \
  "SBOM (client CycloneDX)" \
  "docker run --rm -v '${ROOT_DIR}:/repo' anchore/syft:v1.31.0 dir:/repo/client -o cyclonedx-json=/repo/test-results/security/artifacts_${RUN_ID}/sbom-client.cdx.json" \
  "${TMP_DIR}/sbom_client.log"

if [[ -d "${ROOT_DIR}/landingpage" ]]; then
  run_step \
    "SBOM (landing CycloneDX)" \
    "docker run --rm -v '${ROOT_DIR}:/repo' anchore/syft:v1.31.0 dir:/repo/landingpage -o cyclonedx-json=/repo/test-results/security/artifacts_${RUN_ID}/sbom-landing.cdx.json" \
    "${TMP_DIR}/sbom_landing.log"
fi

{
  echo "## Artifact Index"
  echo ""
  find "${ARTIFACT_DIR}" -maxdepth 1 -type f | sort
  echo ""
  echo "## Result"
  echo ""
  if [[ "${any_fail}" -eq 0 ]]; then
    echo "- RC security chain: PASS"
  else
    echo "- RC security chain: FAIL"
    echo "- Not: FAIL olan adimlar yukarida listelenmistir."
  fi
} >>"${REPORT_PATH}"

echo "RC security chain report generated: ${REPORT_PATH}"

if [[ "${any_fail}" -ne 0 ]]; then
  exit 1
fi
