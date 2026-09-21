#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="${ROOT_DIR}/test-results/ops"
RUN_ID="$(date -u +%Y%m%d_%H%M%S)"
REPORT_PATH="${REPORT_DIR}/rollback_backup_dryrun_${RUN_ID}.md"
BACKUP_ROOT="${REPORT_DIR}/rollback_backup_${RUN_ID}"

mkdir -p "${REPORT_DIR}" "${BACKUP_ROOT}"

MONGO_IMAGE="${MONGO_IMAGE:-mongo:7.0}"
BASE_MONGODB_URL="${MONGODB_URL:-mongodb://admin:password@localhost:27017/crawlens?authSource=admin}"
DRILL_DB="${DRILL_DB:-crawlens_drill_${RUN_ID}}"

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

seconds_now() {
  date -u +%s
}

log_section() {
  local title="$1"
  local status="$2"
  local started="$3"
  local ended="$4"
  local cmd="$5"
  local output="$6"
  {
    echo "## ${title}"
    echo "- Status: ${status}"
    echo "- Started: ${started}"
    echo "- Ended: ${ended}"
    echo "- Command: \`${cmd}\`"
    echo ""
    echo '```text'
    cat "${output}"
    echo '```'
    echo ""
  } >>"${REPORT_PATH}"
}

DRILL_URI_DOCKER="$(python3 - <<'PY' "${BASE_MONGODB_URL}" "${DRILL_DB}"
from urllib.parse import urlparse, urlunparse
import sys

raw_uri = sys.argv[1]
drill_db = sys.argv[2]
parsed = urlparse(raw_uri)
host = parsed.hostname or "localhost"
if host in {"localhost", "127.0.0.1", "::1"}:
    host = "host.docker.internal"
port = parsed.port or 27017
netloc = ""
if parsed.username:
    netloc += parsed.username
    if parsed.password:
        netloc += f":{parsed.password}"
    netloc += "@"
netloc += f"{host}:{port}"
path = f"/{drill_db}"
print(urlunparse((parsed.scheme, netloc, path, parsed.params, parsed.query, parsed.fragment)))
PY
)"

MARKER_ID="rollback-drill-${RUN_ID}"
MARKER_TS="$(timestamp)"

{
  echo "# Rollback + Backup/Restore Dry-Run Evidence"
  echo ""
  echo "- Tarih: $(timestamp)"
  echo "- Run ID: ${RUN_ID}"
  echo "- Mongo image: ${MONGO_IMAGE}"
  echo "- Drill DB: ${DRILL_DB}"
  echo "- Docker URI: ${DRILL_URI_DOCKER}"
  echo "- Marker ID: ${MARKER_ID}"
  echo ""
} >"${REPORT_PATH}"

STEP_OUT="/tmp/rollback_dryrun_step.log"

run_step() {
  local title="$1"
  local cmd="$2"
  local start_ts end_ts start_sec end_sec status
  start_ts="$(timestamp)"
  start_sec="$(seconds_now)"
  if bash -lc "${cmd}" >"${STEP_OUT}" 2>&1; then
    status="PASS"
  else
    status="FAIL"
  fi
  end_ts="$(timestamp)"
  end_sec="$(seconds_now)"
  log_section "${title}" "${status}" "${start_ts}" "${end_ts}" "${cmd}" "${STEP_OUT}"
  if [[ "${status}" != "PASS" ]]; then
    echo "Step failed: ${title}. See ${REPORT_PATH}"
    exit 1
  fi
  echo "${start_sec},${end_sec}"
}

seed_times="$(run_step \
  "Seed Marker Record" \
  "docker run --rm ${MONGO_IMAGE} mongosh \"${DRILL_URI_DOCKER}\" --quiet --eval 'db.drill_markers.insertOne({marker_id: \"${MARKER_ID}\", created_at: new Date(\"${MARKER_TS}\")})'")"

dump_times="$(run_step \
  "Backup (mongodump)" \
  "docker run --rm -v \"${BACKUP_ROOT}:/backup\" ${MONGO_IMAGE} mongodump --uri=\"${DRILL_URI_DOCKER}\" --out=/backup")"

drop_times="$(run_step \
  "Simulate Incident (drop database)" \
  "docker run --rm ${MONGO_IMAGE} mongosh \"${DRILL_URI_DOCKER}\" --quiet --eval 'db.dropDatabase()'")"

restore_times="$(run_step \
  "Restore (mongorestore)" \
  "docker run --rm -v \"${BACKUP_ROOT}:/backup\" ${MONGO_IMAGE} mongorestore --uri=\"${DRILL_URI_DOCKER}\" --drop --nsInclude=\"${DRILL_DB}.*\" \"/backup/${DRILL_DB}\"")"

verify_times="$(run_step \
  "Verify Marker After Restore" \
  "docker run --rm ${MONGO_IMAGE} mongosh \"${DRILL_URI_DOCKER}\" --quiet --eval 'db.drill_markers.countDocuments({marker_id: \"${MARKER_ID}\"})'")"

marker_count="$(tail -n 1 "${STEP_OUT}" | tr -d '\r' | xargs)"
if [[ "${marker_count}" != "1" ]]; then
  echo "Marker verification failed (expected 1, got ${marker_count})" >>"${REPORT_PATH}"
  exit 1
fi

cleanup_times="$(run_step \
  "Cleanup Drill Database" \
  "docker run --rm ${MONGO_IMAGE} mongosh \"${DRILL_URI_DOCKER}\" --quiet --eval 'db.dropDatabase()'")"

dump_end="${dump_times#*,}"
seed_start="${seed_times%%,*}"
drop_start="${drop_times%%,*}"
restore_end="${verify_times#*,}"
rpo_seconds="$((dump_end - seed_start))"
rto_seconds="$((restore_end - drop_start))"

{
  echo "## KPI Summary"
  echo ""
  echo "- RPO approximation (seed -> backup complete): ${rpo_seconds} seconds"
  echo "- RTO approximation (incident -> verified restore): ${rto_seconds} seconds"
  echo "- Verification marker count: ${marker_count}"
  echo ""
  echo "## Artifacts"
  echo ""
  echo "- Backup root: ${BACKUP_ROOT}"
  echo "- Report path: ${REPORT_PATH}"
  echo ""
  echo "## Result"
  echo ""
  echo "- Dry-run rollback + restore: PASS"
} >>"${REPORT_PATH}"

echo "Rollback dry-run evidence generated: ${REPORT_PATH}"
