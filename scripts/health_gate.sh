#!/usr/bin/env bash
# D4 — deploy sonrasi UYGULAMA saglik kapisi.
#
# Dokploy'un "deployment succeeded" cevabi, konteynerin ayaga kalktigini soyler;
# surumun is gorup gormedigini soylemez. Ikisi arasindaki bosluk, Eylul 2026
# pilotunda haftalar yuttu: `cleanup` kuyrugunu kimse tuketmiyordu, robots
# izleme ve canary hic islenmedi, ve her gosterge yesildi.
#
# Bu kapi yalnizca DISARIDAN, HTTP uzerinden sorulabilecek seyleri sorar —
# cunku sunucuda kabuk erisimi olmadan calismasi gerekiyor.
#
#   scripts/health_gate.sh https://api.crawlens.com \
#     --app https://app.crawlens.com --landing https://crawlens.com
#
# Cikis kodu 0 ise surum kabul edilir; 1 ise geri alinmalidir.

set -uo pipefail

API=""
APP_URL=""
LANDING_URL=""
TIMEOUT="${HEALTH_GATE_TIMEOUT:-300}"
INTERVAL="${HEALTH_GATE_INTERVAL:-10}"
TOKEN="${OPS_HEALTH_TOKEN:-}"

usage() { echo "kullanim: $0 <api-base-url> [--app URL] [--landing URL] [--timeout SN]"; exit 1; }

[ $# -ge 1 ] || usage
API="${1%/}"; shift
while [ $# -gt 0 ]; do
  case "$1" in
    --app)     APP_URL="$2"; shift 2 ;;
    --landing) LANDING_URL="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) usage ;;
  esac
done

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; DIM=$'\033[2m'; NC=$'\033[0m'
hdr=("-sS")   # bos dizi genislemesi macOS bash 3.2 + `set -u` altinda hata verir
[ -n "$TOKEN" ] && hdr+=(-H "X-Ops-Token: $TOKEN")

printf "\n${DIM}saglik kapisi — %s (en fazla %ss)${NC}\n\n" "$API" "$TIMEOUT"

# Deploy'dan hemen sonra 502/503 normaldir: konteyner isiniyor. Kapi bu yuzden
# "bir kez sor" degil, "verilen sure icinde saglikli olsun" diye sorar. Ama
# suresiz beklemez — suresiz bekleyen bir kapi, kapi degildir.
wait_for() { # ad, url, kabul-edilen-kod-regex, ekstra-basliklar...
  local name="$1" url="$2" want="$3"; shift 3
  local deadline=$(( $(date +%s) + TIMEOUT ))
  local code="" last=""
  printf "  %-34s" "$name"
  while [ "$(date +%s)" -lt "$deadline" ]; do
    code="$(curl -s -o /tmp/health_gate_body -w '%{http_code}' --max-time 20 "$@" "$url" 2>/dev/null || echo 000)"
    if [[ "$code" =~ $want ]]; then
      printf "${GREEN}gecti${NC} (%s)\n" "$code"
      return 0
    fi
    last="$code"
    sleep "$INTERVAL"
  done
  printf "${RED}DUSTU${NC} (son kod: %s)\n" "$last"
  if [ -s /tmp/health_gate_body ]; then
    sed 's/^/      /' /tmp/health_gate_body | head -20
    echo
  fi
  return 1
}

FAIL=0
wait_for "api /health"        "$API/health"     '^200$' || FAIL=1
wait_for "api /health/db"     "$API/health/db"  '^200$' || FAIL=1
# Asil kapi bu: her kuyrugun tuketicisi var mi.
wait_for "api /health/ready"  "$API/health/ready" '^200$' "${hdr[@]}" || FAIL=1
[ -n "$APP_URL" ]     && { wait_for "client"  "$APP_URL"     '^(200|30[0-9])$' || FAIL=1; }
[ -n "$LANDING_URL" ] && { wait_for "landing" "$LANDING_URL" '^(200|30[0-9])$' || FAIL=1; }

echo
if [ "$FAIL" -eq 1 ]; then
  printf "${RED}KAPI DUSTU — bu surum kabul edilmemeli.${NC}\n"
  printf "Geri alma: make rollback RELEASE=sha-<onceki-commit>\n\n"
  exit 1
fi
printf "${GREEN}kapi gecti — surum kabul edildi.${NC}\n\n"
