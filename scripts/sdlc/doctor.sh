#!/usr/bin/env bash
# Hat saglik kontrolu — test fazinin tiyatro olmadigini dogrular.
#
#   scripts/sdlc/doctor.sh [TICKET]
#
# 21 Eylul 2026'daki ilk uctan uca kosuda Codex "testleri kosturamadim" dedi ve
# bu bir dipnot olarak gecti. Test kosturamayan bir worktree'de test fazi
# calistirmak, yesil gormedigin halde yesil sanmaktir. Bu script once sorar.
set -uo pipefail

# Proje koku: harness'in nerede durdugundan bagimsiz (bkz. _root.sh).
_SDLC_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SDLC_CALLER_DIR/_root.sh"
ROOT="$(sdlc_root)" || exit 1
HARNESS="$(sdlc_harness_root)"
TICKET="${1:-}"
fail=0
ok()   { printf "  ✓ %s\n" "$1"; }
warn() { printf "  ~ %s\n" "$1"; }
bad()  { printf "  ✗ %s\n" "$1"; fail=$((fail+1)); }

echo "== araclar"
command -v node >/dev/null && ok "node $(node -v)" || bad "node yok"
command -v codex >/dev/null && ok "codex $(codex --version 2>/dev/null | head -1)" || bad "codex CLI yok"
command -v docker >/dev/null && ok "docker" || warn "docker yok — testcontainers calismaz"

echo "== kadro ve kapilar"
node "$HARNESS/sdlc/roster.ts" --check >/dev/null 2>&1 && ok "roster kurallari temiz" || bad "roster --check basarisiz"
if grep -q "^JEV_API_KEY=." "$ROOT/.env" 2>/dev/null; then ok "JEV anahtari var (kapilar olcuyor)"
else warn "JEV anahtari yok — her kapi insana duser"; fi

echo "== hafiza"
if "$HARNESS/scripts/sdlc/memory.sh" status >/dev/null 2>&1; then
  ok "cognee ayakta"
  # SAGLIK YESILI OKUMA GARANTISI DEGILDIR. /health 200 donerken embedding
  # saglayicisi kotasi bitmis olabilir; o zaman recall sonsuz yeniden dener ve
  # hat "emsal yok" sanir (olculdu 21 Eyl 2026: Gemini 402 RESOURCE_EXHAUSTED).
  # Bu yuzden doctor GERCEK bir okuma denemesi yapar.
  # DOCTOR_FULL=1 ise tam tur (yaz -> graf -> geri oku); yoksa hizli okuma denemesi.
  if [ "${DOCTOR_FULL:-0}" = "1" ]; then
    if MEMORY_TIMEOUT="${DOCTOR_MEMORY_TIMEOUT:-90}" "$HARNESS/scripts/sdlc/memory.sh" verify >/dev/null 2>&1; then
      ok "hafiza tam tur dogrulandi (yazildi, grafa girdi, geri okundu)"
    else
      warn "cognee ayakta ama HAFIZA CALISMIYOR — tam tur basarisiz.
       calistir: make sdlc-memory-verify   (ayrinti icin)"
    fi
  elif MEMORY_TIMEOUT="${DOCTOR_MEMORY_TIMEOUT:-45}" "$HARNESS/scripts/sdlc/memory.sh" recall "saglik denemesi" >/dev/null 2>&1; then
    ok "hafiza okunabiliyor (gercek recall denendi)"
    # OKUNABILIYOR OLMASI, DOGRU SEYI BULDUGU ANLAMINA GELMEZ. Olculdu
    # 21 Eyl 2026: verify yesilken hafiza belgelerin yarisini bulamiyordu.
    if [ -f "$ROOT/sdlc/quality-probe.json" ]; then
      PRODUCT_DATASET="$(node -e 'const p=require(process.argv[1]);console.log(p.memory?.productDataset||"product")' "$ROOT/sdlc/project.json")"
      if COGNEE_DATASET="$PRODUCT_DATASET" QUALITY_MIN="${QUALITY_MIN:-60}" \
         "$HARNESS/scripts/sdlc/memory.sh" quality >/dev/null 2>&1; then
        ok "hafiza DOGRU belgeyi buluyor (kaynagi bilinen sorular)"
      else
        warn "hafiza cevap veriyor ama DOGRU belgeyi bulamiyor — make sdlc-memory-quality"
      fi
    fi
  else
    warn "cognee ayakta ama OKUMA CALISMIYOR — recall yanit vermedi; hat emsal goremez.
       kanit icin: make sdlc-memory-verify · sebep icin: docker compose -p ${SDLC_COMPOSE_PROJECT:-sdlc-cognee} logs --tail 30 cognee-backend"
  fi
else
  warn "cognee kapali — hat hafizasiz calisir"
fi

cfg() { node "$HARNESS/sdlc/project.ts" "$@" 2>/dev/null; }
echo "== test ortami (yapilandirmadaki yiginlar)"
for st in $(cfg stacks | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{JSON.parse(s).forEach(x=>console.log(x.name))}catch{}})'); do
  SROOT="$(cfg stack "$st" root)"
  if [ ! -d "$ROOT/$SROOT" ]; then bad "$st: kok dizin yok ($SROOT)"; continue; fi
  MISSING=""
  for dep in $(cfg stack "$st" deps | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log((JSON.parse(s)||[]).join(" "))}catch{}})'); do
    [ -e "$ROOT/$SROOT/$dep" ] || MISSING="$MISSING $dep"
  done
  if [ -n "${MISSING// /}" ]; then bad "$st: eksik bagimlilik:$MISSING"; else ok "$st: bagimliliklar kurulu"; fi
  SVC="$(cfg stack "$st" services)"
  if [ -n "$SVC" ] && [ "$SVC" != '""' ]; then
    if command -v docker >/dev/null 2>&1; then
      ok "$st: servisler build fazinda harness tarafindan aciliyor (Docker var)"
    else
      bad "$st: servis gerekiyor ama Docker yok"
    fi
  fi
done

if [ -n "$TICKET" ]; then
  echo "== ticket: $TICKET"
  WT="$ROOT/.sdlc-worktrees/$TICKET"
  [ -f "$ROOT/docs/sdlc/$TICKET/plan.md" ] && ok "plan.md var" || bad "plan.md yok"
  if [ -d "$WT" ]; then
    ok "worktree var: $WT"
    for st in $(cfg stacks | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{JSON.parse(s).forEach(x=>console.log(x.name))}catch{}})'); do
      SROOT="$(cfg stack "$st" root)"
      for dep in $(cfg stack "$st" deps | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log((JSON.parse(s)||[]).join(" "))}catch{}})'); do
        [ -e "$WT/$SROOT/$dep" ] || warn "worktree'de $SROOT/$dep YOK — build fazi baglayacak"
      done
    done
  else
    warn "worktree henuz yok (build fazi acacak)"
  fi
fi

echo
[ "$fail" -eq 0 ] && echo "doctor: kritik eksik yok ($fail)" || echo "doctor: $fail kritik eksik"
exit "$fail"
