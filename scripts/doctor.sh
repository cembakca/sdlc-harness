#!/usr/bin/env bash
# Crawlens ortam saglik raporu (D0).
#
# Amaci tek bir soruya tahminsiz cevap vermek: "simdi calisir mi?"
# Cikis kodu: 0 saglikli, 1 duzeltilmesi gereken bir sey var.
#
# Hicbir seyi kendiliginden duzeltmez. Neyin eksik oldugunu ADIYLA soyler.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; DIM=$'\033[2m'; NC=$'\033[0m'
FAIL=0
WARN=0

ok()   { printf "  ${GREEN}OK${NC}    %s\n" "$1"; }
bad()  { printf "  ${RED}EKSIK${NC} %s\n" "$1"; FAIL=1; }
warn() { printf "  ${YELLOW}UYARI${NC} %s\n" "$1"; WARN=1; }
note() { printf "        ${DIM}%s${NC}\n" "$1"; }
head_() { printf "\n${DIM}--- %s${NC}\n" "$1"; }

# --- 1. arac zinciri ---------------------------------------------------------
head_ "araclar"
for tool in docker "docker compose" node npm python3 make; do
  if $tool version >/dev/null 2>&1 || command -v "$tool" >/dev/null 2>&1; then
    ok "$tool"
  else
    bad "$tool bulunamadi"
  fi
done

if docker info >/dev/null 2>&1; then
  ok "docker daemon ayakta"
else
  bad "docker daemon kapali"
  note "Docker Desktop'i baslatin: open -a Docker"
  echo; printf "${RED}Docker olmadan digerleri anlamsiz — burada duruyorum.${NC}\n"; exit 1
fi

# --- 2. env dosyalari --------------------------------------------------------
head_ "ortam dosyalari"
for f in .env.development server/.env; do
  [ -f "$f" ] && ok "$f" || { bad "$f yok"; note "make env"; }
done

if [ -f .env.development ]; then
  # Yiginin acilmasi icin gercekten sart olanlar. Eksik biri, konteynerin
  # saniyeler sonra sessizce olmesi demek.
  for key in JWT_SECRET_KEY MONGO_ROOT_USERNAME MONGO_ROOT_PASSWORD MINIO_ROOT_USER MINIO_ROOT_PASSWORD; do
    value="$(grep -E "^${key}=" .env.development | head -1 | cut -d= -f2-)"
    [ -n "$value" ] && ok "$key tanimli" || bad "$key bos ya da yok (.env.development)"
  done
  # SMTP tek bir ayar degil, birbirine bagli bir uclu: host + port + TLS. Ucunu
  # birbirinden bagimsiz varsaymak, host'u mailpit'e cevirip portu 465'te
  # birakmak gibi bir sonuc veriyor — baglanti reddediliyor ve bildirim teslimi
  # sessizce sifira dusuyor. 11 Eylul 2026 pilot raporundaki "kritik bildirim
  # teslimi FAIL" satiri tam olarak bu sinif bir uyumsuzluktu.
  smtp_host="$(grep -E '^SMTP_HOST=' .env.development | head -1 | cut -d= -f2-)"
  smtp_port="$(grep -E '^SMTP_PORT=' .env.development | head -1 | cut -d= -f2-)"
  smtp_secure="$(grep -E '^SMTP_SECURE=' .env.development | head -1 | cut -d= -f2-)"
  case "${smtp_host:-mailpit}" in
    mailpit|localhost|127.0.0.1)
      if [ "${smtp_port:-1025}" = "1025" ] && [ "${smtp_secure:-false}" != "true" ]; then
        ok "SMTP lokal mailpit'e ayarli (${smtp_host:-mailpit}:${smtp_port:-1025})"
      else
        bad "SMTP uclusu tutarsiz: host=${smtp_host:-mailpit} port=${smtp_port} secure=${smtp_secure}"
        note "mailpit duz metin 1025 dinler; beklenen: SMTP_PORT=1025, SMTP_SECURE=false"
      fi ;;
    *) warn "SMTP_HOST=$smtp_host — lokal yigin disari gercek e-posta gondermeyi deneyecek" ;;
  esac
fi

# --- 3. portlar --------------------------------------------------------------
head_ "portlar"
# Bir portu bizim tutmamiz ile yabanci bir surecin tutmasi ayri seyler; ikisini
# ayirmayan bir kontrol her calistirmada uyari uretir ve okunmaz hale gelir.
ours_on_host() { # dinleyen pid, .run/*.pid'lerden birinin soyundan mi?
  # Ata zincirini yukari yuruyoruz: `npm run dev` -> `next` -> `next-server`
  # gibi iki kademeli agaclarda yalnizca dogrudan cocuklara bakmak yetmiyor.
  local pid="$1" recorded hops=0
  while [ -n "$pid" ] && [ "$pid" != "1" ] && [ "$hops" -lt 10 ]; do
    for f in .run/*.pid; do
      [ -f "$f" ] || continue
      recorded="$(cat "$f")"
      [ "$pid" = "$recorded" ] && return 0
    done
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    hops=$((hops + 1))
  done
  return 1
}

check_port() { # port, kim
  local pid
  pid="$(lsof -nP -iTCP:"$1" -sTCP:LISTEN -t 2>/dev/null | head -1)"
  if [ -z "$pid" ]; then
    ok "$1 bos ($2)"
    return
  fi
  local cmd; cmd="$(ps -p "$pid" -o comm= 2>/dev/null | xargs basename 2>/dev/null)"
  if [ "$cmd" = "com.docker.backend" ] || [ "$cmd" = "docker-proxy" ]; then
    ok "$1 bizim konteynerimizde ($2)"
  elif ours_on_host "$pid"; then
    ok "$1 bizim host surecimizde ($2, pid $pid)"
  else
    warn "$1 baska bir surec tarafindan tutuluyor: $cmd (pid $pid) — $2"
  fi
}
check_port 8000 api
check_port 27017 mongodb
check_port 6379 redis
check_port 9000 minio
check_port 8025 mailpit
check_port 5173 client
check_port 3001 landing
check_port 80 traefik

# --- 4. konteynerler ---------------------------------------------------------
head_ "konteynerler"
expected=(traefik mongodb redis minio mailpit api celery-crawl celery-verify celery-default celery-beat celery-exporter canary)
running="$(docker ps --format '{{.Names}}\t{{.Status}}' | grep '^crawlens-' || true)"
if [ -z "$running" ]; then
  warn "hic crawlens konteyneri calismiyor"
  note "make up"
else
  for svc in "${expected[@]}"; do
    line="$(echo "$running" | grep -E "^crawlens-${svc}[[:space:]]" || true)"
    if [ -z "$line" ]; then
      bad "crawlens-$svc calismiyor"
    else
      status="$(echo "$line" | cut -f2)"
      case "$status" in
        *unhealthy*)  bad "crawlens-$svc SAGLIKSIZ — $status" ;;
        *health:\ starting*) warn "crawlens-$svc henuz isiniyor — $status" ;;
        Up*)          ok "crawlens-$svc — $status" ;;
        *)            warn "crawlens-$svc — $status" ;;
      esac
    fi
  done
fi

# --- 5. kuyruk tuketicileri --------------------------------------------------
# 11 Eylul 2026'nin dersi: konteynerin ayakta olmasi kuyrugun tuketildigi
# anlamina gelmiyor. cleanup/default tuketicisiz kaldigi icin canary ve robots
# izleme haftalarca hic islenmedi ve bunu kimse gormedi.
head_ "celery kuyruklari"
if docker ps --format '{{.Names}}' | grep -q '^crawlens-celery-crawl$'; then
  active="$(docker exec crawlens-celery-crawl celery -A app.workers.celery_app inspect active_queues --timeout 15 2>/dev/null || true)"
  for q in crawl scheduled verify default cleanup; do
    if echo "$active" | grep -q "'name': '$q'"; then
      ok "$q kuyrugunun tuketicisi var"
    else
      bad "$q kuyrugunu HIC KIMSE tuketmiyor"
    fi
  done
else
  warn "worker calismadigi icin kuyruk tuketicileri kontrol edilemedi"
fi

# --- 6. python ortamlari -----------------------------------------------------
head_ "python venv (host uzerinde test/calistirma icin)"
for venv in server/venv server/.venv-test; do
  if [ -x "$venv/bin/python" ]; then
    if (cd server && "../$venv/bin/python" -c "import app.main" >/dev/null 2>&1); then
      ok "$venv app.main import edebiliyor"
    else
      bad "$venv guncel degil — 'import app.main' basarisiz"
      note "cd server && ./${venv#server/}/bin/pip install -q -r requirements.txt"
    fi
  else
    warn "$venv yok"
  fi
done

# --- 7. node bagimliliklari --------------------------------------------------
head_ "node_modules"
for dir in client landingpage; do
  [ -d "$dir/node_modules" ] && ok "$dir/node_modules" || { bad "$dir/node_modules yok"; note "cd $dir && npm ci"; }
done

# --- sonuc -------------------------------------------------------------------
echo
if [ "$FAIL" -eq 1 ]; then
  printf "${RED}SONUC: duzeltilmesi gereken seyler var (yukarida EKSIK olarak isaretli).${NC}\n"
  exit 1
elif [ "$WARN" -eq 1 ]; then
  printf "${YELLOW}SONUC: calisir durumda, bakilmasi gereken uyarilar var.${NC}\n"
  exit 0
else
  printf "${GREEN}SONUC: her sey yerinde.${NC}\n"
  exit 0
fi
