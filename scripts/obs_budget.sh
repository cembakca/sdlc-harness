#!/usr/bin/env bash
# D7 — gozlem katmaninin GERCEK bellek kullanimi.
#
# Butce iddiasi degil olcum olsun diye var. "500 MB'i gecmez" cumlesi, olculmedigi
# surece bir dilek; gecen gun de ayni sekilde soylenir.
#
# ROADMAP_DEVOPS D7: 8 GB'lik kutuda gozlem katmani 500 MB'i gecemez. Gecerse,
# izlemek icin var oldugu seyin kaynagini yemeye baslar.

set -uo pipefail

BUDGET_MB="${OBS_BUDGET_MB:-500}"
SERVICES="crawlens-loki crawlens-alloy crawlens-prometheus crawlens-alertmanager crawlens-node-exporter"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; DIM=$'\033[2m'; NC=$'\033[0m'

running=""
for name in $SERVICES; do
  docker ps --format '{{.Names}}' | grep -qx "$name" && running="$running $name"
done

if [ -z "$running" ]; then
  echo "gozlem katmani calismiyor — once: make obs-up"
  exit 1
fi

printf "\n${DIM}gozlem katmani bellek kullanimi (butce: %s MB)${NC}\n\n" "$BUDGET_MB"

# shellcheck disable=SC2086
docker stats --no-stream --format '{{.Name}} {{.MemUsage}}' $running > /tmp/obs_stats.txt

# Tablo dogrudan ekrana; toplam bir dosyaya. (Once python'un ciktisi komut
# ikamesi tarafindan yutulmustu ve tablo hic gorunmuyordu.)
python3 - <<'PYEOF'
import re

def to_mb(value: str) -> float:
    number = float(re.sub(r"[^0-9.]", "", value) or 0)
    unit = re.sub(r"[0-9.]", "", value).strip().lower()
    return {"gib": number * 1024, "mib": number, "kib": number / 1024, "b": number / 1048576}.get(unit, number)

total = 0.0
for line in open("/tmp/obs_stats.txt"):
    parts = line.split()
    if len(parts) < 2:
        continue
    mb = to_mb(parts[1])
    total += mb
    print(f"  {parts[0].replace('crawlens-', ''):<18} {mb:8.1f} MB")
with open("/tmp/obs_total.txt", "w") as fh:
    fh.write(f"{total:.0f}")
PYEOF

total_mb="$(cat /tmp/obs_total.txt)"

printf "\n  toplam: %s MB / %s MB  " "$total_mb" "$BUDGET_MB"
if [ "$total_mb" -le "$BUDGET_MB" ]; then
  printf "${GREEN}butce icinde${NC}\n\n"
  exit 0
fi
printf "${RED}BUTCE ASILDI${NC}\n"
printf "  Saklama suresini ya da hedef sayisini dusurun — ya da butceyi bilerek yukseltin.\n\n"
exit 1
