#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_BASE="${ROOT_DIR}/test-results/ops"
RUN_ID="$(date -u +%Y%m%d_%H%M%S)"
OUT_DIR="${OUT_BASE}/launch_evidence_${RUN_ID}"
SUMMARY_PATH="${OUT_DIR}/summary.md"
mkdir -p "${OUT_DIR}"

API_URL="${API_URL:-http://localhost:8000}"
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3002}"
LOKI_URL="${LOKI_URL:-http://localhost:3100}"

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

write_cmd_output() {
  local name="$1"
  shift
  local output_file="${OUT_DIR}/${name}.log"
  if "$@" >"${output_file}" 2>&1; then
    echo "PASS" >"${OUT_DIR}/${name}.status"
  else
    echo "FAIL" >"${OUT_DIR}/${name}.status"
  fi
}

write_http_with_retry() {
  local name="$1"
  local url="$2"
  local retries="${3:-6}"
  local interval_sec="${4:-5}"
  local output_file="${OUT_DIR}/${name}.log"
  : >"${output_file}"
  local attempt=1
  while [[ "${attempt}" -le "${retries}" ]]; do
    {
      echo "attempt=${attempt} url=${url}"
      if curl -fsS "${url}"; then
        echo "status=PASS"
        echo "PASS" >"${OUT_DIR}/${name}.status"
        return 0
      fi
      echo "status=FAIL"
    } >>"${output_file}" 2>&1
    if [[ "${attempt}" -lt "${retries}" ]]; then
      sleep "${interval_sec}"
    fi
    attempt=$((attempt + 1))
  done
  echo "FAIL" >"${OUT_DIR}/${name}.status"
  return 1
}

{
  echo "run_id=${RUN_ID}"
  echo "captured_at_utc=$(timestamp)"
  echo "workspace=${ROOT_DIR}"
  echo "api_url=${API_URL}"
  echo "grafana_url=${GRAFANA_URL}"
  echo "loki_url=${LOKI_URL}"
} >"${OUT_DIR}/timestamps.env"

git -C "${ROOT_DIR}" rev-parse HEAD >"${OUT_DIR}/git_commit.txt"
git -C "${ROOT_DIR}" status --short >"${OUT_DIR}/git_status.txt"

write_cmd_output "docker_ps" docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
write_http_with_retry "api_health" "${API_URL}/health" 3 2 || true
write_http_with_retry "grafana_health" "${GRAFANA_URL}/api/health" 4 3 || true
write_http_with_retry "loki_ready" "${LOKI_URL}/ready" 8 5 || true
write_cmd_output "api_metrics_head" bash -lc "curl -fsS '${API_URL}/metrics' | head -n 80"

# Snapshot pages (dashboard/health UI surfaces)
curl -fsS "${GRAFANA_URL}/login" >"${OUT_DIR}/grafana_login_snapshot.html" || true
curl -fsS "${API_URL}/docs" >"${OUT_DIR}/api_docs_snapshot.html" || true

# Container log snapshots (last 15m)
for svc in crawlens-server-dev crawlens-celery-worker-dev crawlens-celery-beat-dev crawlens-redis-dev crawlens-mongodb-dev; do
  docker logs --since 15m "${svc}" >"${OUT_DIR}/${svc}_logs_15m.log" 2>&1 || true
done

# Pull latest evidence pointers
LATEST_QUALITY="$(find "${ROOT_DIR}/test-results/release" -maxdepth 1 -name 'rc_quality_chain_*.md' -print | sort | tail -n1)"
LATEST_SECURITY="$(find "${ROOT_DIR}/test-results/security" -maxdepth 1 -name 'rc_security_chain_*.md' -print | sort | tail -n1)"
LATEST_T0="$(find "${ROOT_DIR}/test-results/ops" -maxdepth 1 -name 't0_ops_readiness_dryrun_*.md' -print | sort | tail -n1)"
LATEST_PRODUCT="$(find "${ROOT_DIR}/test-results/ops" -maxdepth 1 -name 'product_gates_evidence_*.md' -print | sort | tail -n1)"

{
  echo "# Launch Evidence Capture"
  echo ""
  echo "- Run ID: ${RUN_ID}"
  echo "- Captured (UTC): $(timestamp)"
  echo ""
  echo "## Health & Dashboard Snapshots"
  echo "- API health status: $(cat "${OUT_DIR}/api_health.status")"
  echo "- Grafana health status: $(cat "${OUT_DIR}/grafana_health.status")"
  echo "- Loki ready status: $(cat "${OUT_DIR}/loki_ready.status")"
  echo "- API metrics snapshot status: $(cat "${OUT_DIR}/api_metrics_head.status")"
  echo "- Grafana login snapshot: ${OUT_DIR}/grafana_login_snapshot.html"
  echo "- API docs snapshot: ${OUT_DIR}/api_docs_snapshot.html"
  echo ""
  echo "## Deployment Logs / Timestamps"
  echo "- timestamps: ${OUT_DIR}/timestamps.env"
  echo "- git commit: ${OUT_DIR}/git_commit.txt"
  echo "- git status: ${OUT_DIR}/git_status.txt"
  echo "- docker services: ${OUT_DIR}/docker_ps.log"
  echo "- server logs (15m): ${OUT_DIR}/crawlens-server-dev_logs_15m.log"
  echo "- worker logs (15m): ${OUT_DIR}/crawlens-celery-worker-dev_logs_15m.log"
  echo "- beat logs (15m): ${OUT_DIR}/crawlens-celery-beat-dev_logs_15m.log"
  echo ""
  echo "## Latest Gate Evidence"
  echo "- RC quality: ${LATEST_QUALITY:-MISSING}"
  echo "- RC security: ${LATEST_SECURITY:-MISSING}"
  echo "- T0 ops dry-run: ${LATEST_T0:-MISSING}"
  echo "- Product gates: ${LATEST_PRODUCT:-MISSING}"
} >"${SUMMARY_PATH}"

echo "Launch evidence capture generated: ${OUT_DIR}"
echo "Summary: ${SUMMARY_PATH}"
