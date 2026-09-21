#!/usr/bin/env bash
# Ayakta olan yigina uctan uca duman testi.
# "Konteyner ayakta" ile "yigin calisiyor" ayni cumle degil; bu script ikincisini
# olcer. Cikis kodu 0 ise yigin is gorur durumdadir.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; DIM=$'\033[2m'; NC=$'\033[0m'
FAIL=0

step() { printf "  %-46s" "$1"; }
pass() { printf "${GREEN}gecti${NC}\n"; }
fail() { printf "${RED}DUSTU${NC}  %s\n" "${1:-}"; FAIL=1; }

# Iki topoloji var ve ikisi de gecerli: gelistirmede portlar host'a acilir,
# uretim provasinda TEK KAPI Traefik'tir ve TLS aciktir (uretimde de oyle
# olacak). Duman testi ikisinde de calismali, yoksa "prod-local'da smoke
# dusuyor" diye bir folklor olusur ve gercek bir ariza bunun arkasina saklanir.
#
# Adaylar 200 SARTIYLA secilir. Once yalnizca "istek hata vermedi" diye
# bakiliyordu; prova yigininda http adresi 301 donuyor ve bu kontrolden
# geciyordu — yani duman testi uygulamaya hic ulasmadan yesil yaniyordu.
CURL_CA=()
_caroot="$(mkcert -CAROOT 2>/dev/null)"
[ -n "$_caroot" ] && [ -f "$_caroot/rootCA.pem" ] && CURL_CA=(--cacert "$_caroot/rootCA.pem")

http_code() { curl -sS -o /dev/null -w '%{http_code}' --max-time 8 "${CURL_CA[@]}" "$@" 2>/dev/null || echo 000; }

resolve() { # aday url'ler; ilk 200 donen kazanir
  local url
  for url in "$@"; do
    [ "$(http_code "$url")" = "200" ] && { echo "$url"; return 0; }
  done
  echo ""
}

# https once: prova yigininda http zaten https'e yonlendiriyor.
API="${API_BASE:-$(resolve https://api.crawlens.localhost/health http://localhost:8000/health http://api.crawlens.localhost/health)}"
API="${API%/health}"
MAILPIT="${MAILPIT_BASE:-$(resolve https://mail.crawlens.localhost/api/v1/messages http://localhost:8025/api/v1/messages http://mail.crawlens.localhost/api/v1/messages)}"
MAILPIT="${MAILPIT%%/api/*}"

if [ -z "$API" ]; then
  printf "\n${RED}api'ye hicbir kapidan ulasilamiyor${NC} (ne :8000 ne api.crawlens.localhost)\n\n"
  exit 1
fi

printf "\n${DIM}duman testi — api: %s · mail: %s${NC}\n\n" "$API" "${MAILPIT:-yok}"

step "api /health"
curl -fsS --max-time 10 "${CURL_CA[@]}" "$API/health" >/dev/null 2>&1 && pass || fail

step "api /health/db (mongo baglantisi)"
curl -fsS --max-time 15 "${CURL_CA[@]}" "$API/health/db" >/dev/null 2>&1 && pass || fail

step "api openapi semasi"
curl -fsS --max-time 10 "${CURL_CA[@]}" "$API/openapi.json" >/dev/null 2>&1 && pass || fail

step "canary hedefi ayakta"
docker exec crawlens-canary curl -fsS --max-time 10 http://localhost:8081/healthz >/dev/null 2>&1 && pass || fail

step "mailpit ariza kutusu erisilebilir"
docker exec crawlens-mailpit /mailpit readyz >/dev/null 2>&1 && pass || fail

step "minio kovasi mevcut"
docker run --rm --network crawlens -e MC_HOST_local="http://${MINIO_ROOT_USER:-crawlens}:${MINIO_ROOT_PASSWORD:-crawlens123}@minio:9000" \
  minio/mc:latest ls "local/${S3_BUCKET:-crawlens}" >/dev/null 2>&1 && pass || fail

step "redis PONG"
docker exec crawlens-redis redis-cli ping 2>/dev/null | grep -q PONG && pass || fail

step "her kuyrugun tuketicisi var"
queues="$(docker exec crawlens-celery-crawl celery -A app.workers.celery_app inspect active_queues --timeout 20 2>/dev/null || true)"
missing=""
for q in crawl scheduled verify default cleanup; do
  echo "$queues" | grep -q "'name': '$q'" || missing="$missing $q"
done
[ -z "$missing" ] && pass || fail "tuketicisiz:$missing"

step "beat tik atiyor"
docker exec crawlens-celery-beat python -c \
  "import os,time,sys; sys.exit(0 if time.time()-os.path.getmtime('/tmp/celerybeat-schedule')<300 else 1)" 2>/dev/null && pass || fail "zamanlayici dosyasi 5 dakikadir guncellenmedi"


# E-posta yolu ucunda mailpit var; "SMTP ayakta" ile "mesaj kutuya dustu" ayri
# seyler ve arada uyumsuz bir port/TLS uclusu olabiliyor (11 Eylul 2026).
step "e-posta uctan uca mailpit'e dusuyor"
before="$(curl -fsS --max-time 10 "${CURL_CA[@]}" "$MAILPIT/api/v1/messages?limit=1" 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("messages_count",0))' 2>/dev/null || echo 0)"
docker exec crawlens-api python -c "
from app.services.email import send_welcome_email
send_welcome_email('smoke@crawlens.local', 'Smoke', 'Smoke Org')
" >/dev/null 2>&1
delivered=0
for _ in $(seq 1 15); do
  after="$(curl -fsS --max-time 10 "${CURL_CA[@]}" "$MAILPIT/api/v1/messages?limit=1" 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("messages_count",0))' 2>/dev/null || echo 0)"
  if [ "$after" -gt "$before" ]; then delivered=1; break; fi
  sleep 2
done
[ "$delivered" -eq 1 ] && pass || fail "kuyruga girdi ama kutuya dusmedi — SMTP host/port/TLS uclusune bakin"

echo
if [ "$FAIL" -eq 1 ]; then
  printf "${RED}DUMAN TESTI DUSTU.${NC} Ayrinti icin: make logs S=<servis>\n\n"
  exit 1
fi
printf "${GREEN}duman testi gecti.${NC}\n\n"
