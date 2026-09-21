#!/usr/bin/env bash
set -euo pipefail

required_files=(
  "docs/runbook/rollback-backup-drill.md"
  "docs/backup-restore.md"
  "docs/PRODUCTION-DEPLOYMENT-GUIDE.md"
  "docs/GO_LIVE_COMMAND_CENTER_CHECKLIST.md"
)

missing=0
for f in "${required_files[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing required file: $f"
    missing=1
  fi
done

if [[ "$missing" -ne 0 ]]; then
  echo "Rollback readiness check FAILED"
  exit 1
fi

echo "Rollback readiness check PASSED"
