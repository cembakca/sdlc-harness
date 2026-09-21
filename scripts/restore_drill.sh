#!/usr/bin/env bash
# D5 — GERI YUKLEME PROVASI.
#
# Denenmemis yedek, yedek degil; bir his. Urunun adinda "kanit arsivi" geciyor
# ve musteriye 90 gun saklama sozu veriliyor — bu provanin yesil olmasi, o sozun
# tek olculebilir karsiligi.
#
# Ne yapar:
#   1. Son yedegi GECICI bir dizine geri yukler
#   2. GECICI, bos bir MongoDB baslatir (canli veriye DOKUNMAZ)
#   3. Dump'i oraya yukler
#   4. Yedegin YANINDA saklanan manifest ile koleksiyon sayimlarini karsilastirir
#   5. Gecen sureyi olcer ve RTO hedefiyle kiyaslar
#   6. Her seyi temizler
#
# Canli veritabanina hicbir asamada yazmaz. Karsilastirma canli veriyle degil
# manifest ile yapilir: canli veri prova anina kadar zaten degismis olur.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; DIM=$'\033[2m'; NC=$'\033[0m'

RTO_TARGET_SECONDS="${RTO_TARGET_SECONDS:-7200}"   # D5 hedefi: 2 saat
DRILL_MONGO="crawlens-drill-mongo"
RESTORE_DIR="/tmp/crawlens-drill-$$"
RESTIC_IMAGE="restic/restic:0.17.3"
START="$(date +%s)"
FAIL=0

# Lokalde ayarlar .env.development'tan, CI'da gercek ortamdan gelir. Prova
# COMPOSE'A BAGIMLI DEGIL: CI'da calisan bir yigin yok ve olmamali da —
# provanin dogruladigi sey yedegin kendisi, yigin degil.
if [ -z "${RESTIC_REPOSITORY:-}" ] && [ -f .env.development ]; then
  RESTIC_REPOSITORY="$(grep -E '^RESTIC_REPOSITORY=' .env.development | head -1 | cut -d= -f2-)"
  RESTIC_PASSWORD="$(grep -E '^RESTIC_PASSWORD=' .env.development | head -1 | cut -d= -f2-)"
  export RESTIC_REPOSITORY RESTIC_PASSWORD
fi
: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY gerekli}"
: "${RESTIC_PASSWORD:?RESTIC_PASSWORD gerekli}"

# Depo yerel bir yol ise docker hacmini bagla; uzak (b2:...) ise env yeter.
restic_args=(--rm -e RESTIC_REPOSITORY -e RESTIC_PASSWORD
             -e B2_ACCOUNT_ID="${B2_ACCOUNT_ID:-}" -e B2_ACCOUNT_KEY="${B2_ACCOUNT_KEY:-}")
case "$RESTIC_REPOSITORY" in
  /*) restic_args+=(-v "crawlens_restic_repo:$RESTIC_REPOSITORY") ;;
esac

cleanup() {
  docker rm -f "$DRILL_MONGO" >/dev/null 2>&1 || true
  rm -rf "$RESTORE_DIR" 2>/dev/null || true
}
trap cleanup EXIT

step() { printf "  %-44s" "$1"; }
ok()   { printf "${GREEN}%s${NC}\n" "${1:-tamam}"; }
bad()  { printf "${RED}DUSTU${NC} %s\n" "${1:-}"; FAIL=1; }
# Atlanan adim hata degildir ama sessiz de kalmamalidir: ekranda gorunur.
skip() { printf "${YELLOW}atlandi${NC} %s\n" "${1:-}"; }

printf "\n${DIM}geri yukleme provasi — %s${NC}\n\n" "$(date -u +%Y-%m-%dT%H:%MZ)"

# --- 1. son yedegi geri yukle ------------------------------------------------
step "son yedek geri yukleniyor"
mkdir -p "$RESTORE_DIR"
if docker run "${restic_args[@]}" -v "$RESTORE_DIR:/restore" "$RESTIC_IMAGE" \
     restore latest --target /restore >/tmp/drill-restore.log 2>&1; then
  ok
else
  bad "restic restore basarisiz"
  tail -15 /tmp/drill-restore.log | sed 's/^/      /'
  exit 1
fi

DUMP_ROOT="$(find "$RESTORE_DIR" -type d -name "crawlens" -path "*/mongo/*" | head -1)"
MANIFEST="$(find "$RESTORE_DIR" -type f -name "manifest.json" | head -1)"

step "dump ve manifest bulundu"
if [ -n "$DUMP_ROOT" ] && [ -n "$MANIFEST" ]; then
  ok "$(basename "$(dirname "$DUMP_ROOT")")"
else
  bad "geri yuklenen icerikte dump ya da manifest yok"
  exit 1
fi

# --- 2. gecici, bos bir mongo ------------------------------------------------
step "gecici MongoDB baslatiliyor"
docker rm -f "$DRILL_MONGO" >/dev/null 2>&1 || true
if docker run -d --name "$DRILL_MONGO" mongo:7.0 >/dev/null 2>&1; then
  for _ in $(seq 1 30); do
    docker exec "$DRILL_MONGO" mongosh --quiet --eval "db.adminCommand('ping').ok" 2>/dev/null | grep -q 1 && break
    sleep 2
  done
  ok
else
  bad "gecici mongo baslatilamadi"; exit 1
fi

# --- 3. geri yukle -----------------------------------------------------------
step "mongorestore"
docker cp "$DUMP_ROOT" "$DRILL_MONGO:/dump" >/dev/null 2>&1
if docker exec "$DRILL_MONGO" mongorestore --quiet --db crawlens /dump >/tmp/drill-mongorestore.log 2>&1; then
  ok
else
  bad "mongorestore basarisiz"
  tail -10 /tmp/drill-mongorestore.log | sed 's/^/      /'
fi

# --- 4. manifest ile karsilastir ---------------------------------------------
step "koleksiyon sayimlari manifest ile ortusuyor"
docker exec "$DRILL_MONGO" mongosh crawlens --quiet --eval '
  const out = {};
  db.getCollectionNames().sort().forEach(n => { out[n] = db.getCollection(n).countDocuments(); });
  print(JSON.stringify(out));
' > "$RESTORE_DIR/restored-counts.json" 2>/dev/null

# Karsilastirma ayri bir script: kabuk icine gomulu python kacis karakterleri
# yuzunden sessizce cokmus ve prova yine de yesil yanmisti.
if COMPARE_OUT="$(python3 scripts/compare_restore.py "$MANIFEST" "$RESTORE_DIR/restored-counts.json" 2>&1)"; then
  ok "$(echo "$COMPARE_OUT" | head -1)"
else
  bad
  echo "$COMPARE_OUT" | sed 's/^/      /'
fi

# --- 5. ornek belge gercekten okunabiliyor mu --------------------------------
# Sayim dogru olup icerigin bozuk olmasi mumkun; en az bir kanit kaydi
# gercekten acilmali.
#
# KAYNAKTA hic basarili snapshot yoksa bu adim atlanir — yoksa olcum, yedegin
# calisip calismadigini degil veritabaninda veri olup olmadigini olcer. Taze
# kurulan bir veritabaninda prova bu yuzden P1 veriyordu (14 Eylul 2026);
# gercek yedek yolunda hicbir sorun yoktu.
step "ornek snapshot kaydi okunabiliyor"
SOURCE_SNAPSHOTS="$(python3 -c '
import json, sys
m = json.load(open(sys.argv[1]))
c = m.get("collections", m)
v = c.get("snapshots", 0)
print(v if isinstance(v, int) else v.get("count", 0))
' "$MANIFEST" 2>/dev/null || echo 0)"

if [ "${SOURCE_SNAPSHOTS:-0}" -eq 0 ] 2>/dev/null; then
  skip "kaynakta snapshot yok — bu adimin olcecegi sey yok"
else
  SAMPLE="$(docker exec "$DRILL_MONGO" mongosh crawlens --quiet --eval '
    const s = db.snapshots.find({status: "success"}).limit(1).toArray()[0];
    print(s ? JSON.stringify({id: String(s._id), url_id: String(s.url_id || ""), status: s.status}) : "");
  ' 2>/dev/null)"
  [ -n "$SAMPLE" ] && ok "$(echo "$SAMPLE" | head -c 60)" || bad "okunabilir snapshot yok"
fi

# --- 6. RTO ------------------------------------------------------------------
ELAPSED=$(( $(date +%s) - START ))
printf "\n  gecen sure (RTO): ${DIM}%s sn${NC} · hedef: %s sn  " "$ELAPSED" "$RTO_TARGET_SECONDS"
if [ "$ELAPSED" -le "$RTO_TARGET_SECONDS" ]; then
  printf "${GREEN}hedef icinde${NC}\n"
else
  printf "${RED}HEDEFIN USTUNDE${NC}\n"; FAIL=1
fi

echo
if [ "$FAIL" -eq 1 ]; then
  printf "${RED}PROVA DUSTU — bu bir P1'dir.${NC} Yedekten donulemiyorsa yedek yok demektir.\n\n"
  exit 1
fi
printf "${GREEN}prova gecti.${NC} Yedekten %s icinde donulebiliyor.\n\n" "${ELAPSED}sn"
