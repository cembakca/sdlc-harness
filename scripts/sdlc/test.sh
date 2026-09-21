#!/usr/bin/env bash
# Test fazi — KOD KOSTURUR, model degil. PROJEDEN BAGIMSIZ.
#
#   scripts/sdlc/test.sh <TICKET> [--client]
#
# Ne kosacagini `sdlc/project.json` soyler: hangi yigin (stack), hangi komut,
# hangi dosya esleme kurali, hangi servis, hangi altyapi hata kalibi. Bu script
# icinde "pytest", "vitest", "server/" ya da "client/" yazmaz — baska bir
# repoya tasindiginda degisen tek sey o yapilandirmadir.
#
# Sonuc dosyaya (docs/sdlc/<TICKET>/TESTS.md) ve kapi defterine yazilir; karar
# CIKIS KODUNDAN okunur, ciktidaki metinden degil.
set -uo pipefail

# Proje koku: harness'in nerede durdugundan bagimsiz (bkz. _root.sh).
_SDLC_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SDLC_CALLER_DIR/_root.sh"
ROOT="$(sdlc_root)" || exit 1
TICKET="${1:?kullanim: test.sh <TICKET> [--client]}"
FORCE_ALL="${2:-}"
DIR="$ROOT/docs/sdlc/$TICKET"
WT="${SDLC_WORKTREE:-$ROOT/.sdlc-worktrees/$TICKET}"
OUT="$DIR/TESTS.md"
KNOWN="$ROOT/docs/sdlc/known-flaky.txt"

[ -d "$WT" ] || { echo "worktree yok: $WT" >&2; exit 20; }
bash "$ROOT/scripts/sdlc/worktree-clean.sh" "$TICKET" >/dev/null || exit 20

cfg() { node "$ROOT/sdlc/project.ts" "$@" 2>/dev/null; }

# --- degisiklik kumesi: taban dala gore commit edilmis fark -----------------
BASE_BRANCH="${SDLC_BASE:-$(cat "$DIR/.base-branch" 2>/dev/null || echo main)}"
MB="$(git -C "$WT" merge-base "$BASE_BRANCH" HEAD 2>/dev/null || true)"
CHANGED="$(
  {
    [ -n "$MB" ] && git -C "$WT" diff --name-only "$MB..HEAD"
  } 2>/dev/null | grep -v '^docs/sdlc/' | sort -u || true
)"

{
  echo "# Tests — $TICKET"
  echo
  echo "\`scripts/sdlc/test.sh\` · $(date -u +%FT%TZ) · yapılandırma: sdlc/project.json"
  echo
} > "$OUT"

STATUS="pass"; SUMMARY=""; RAN_ANY=0
STACK_NAMES="$(cfg stacks | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{JSON.parse(s).forEach(x=>console.log(x.name))}catch{}})')"

for STACK in $STACK_NAMES; do
  PATTERN="$(cfg stack "$STACK" changedPattern)"
  STACK_ROOT="$(cfg stack "$STACK" root)"
  TOUCHED="$(printf '%s\n' "$CHANGED" | grep -E "$PATTERN" || true)"
  if [ -z "${TOUCHED// /}" ] && [ "$FORCE_ALL" != "--client" ]; then
    continue
  fi
  [ -d "$WT/$STACK_ROOT" ] || continue
  RAN_ANY=1
  echo "== yigin: $STACK"
  { echo "## $STACK"; echo; } >> "$OUT"

  # --- hangi testler: diff'teki test dosyalari + degisen modullerin adasi ---
  SELECT=""
  SELECTOR="$(cfg stack "$STACK" testSelector)"
  if [ -n "$SELECTOR" ] && [ "$SELECTOR" != "\"\"" ]; then
    TEST_DIR_PAT="$(printf '%s' "$SELECTOR" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).testDirPattern||"")}catch{}})')"
    SRC_PAT="$(printf '%s' "$SELECTOR" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).sourcePattern||"")}catch{}})')"
    GLOB="$(printf '%s' "$SELECTOR" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).testFileGlob||"")}catch{}})')"
    while read -r f; do
      [ -n "$f" ] || continue
      if printf '%s' "$f" | grep -qE "$TEST_DIR_PAT"; then
        SELECT="$SELECT ${f#$STACK_ROOT/}"
      elif printf '%s' "$f" | grep -qE "$SRC_PAT"; then
        base="$(basename "$f")"; base="${base%.*}"
        for cand in $WT/$STACK_ROOT/$(printf '%s' "$GLOB" | sed "s/{module}/$base/"); do
          [ -f "$cand" ] && SELECT="$SELECT ${cand#$WT/$STACK_ROOT/}"
        done
      fi
    done <<< "$TOUCHED"
    SELECT="$(printf '%s\n' $SELECT | sort -u | tr '\n' ' ')"
  fi

  # --- servisleri harness saglar (ajanin Docker'a ihtiyaci olmasin) --------
  SERVICE_ENV=""
  SERVICES="$(cfg stack "$STACK" services)"
  if [ -n "$SERVICES" ] && [ "$SERVICES" != "\"\"" ] && command -v docker >/dev/null 2>&1; then
    : # test fazinda servis acmiyoruz: testcontainers kendi acar, build fazi
      # harici servis saglar. Burada yalnizca clearEnv uygulanir.
  fi
  CLEAR="$(cfg stack "$STACK" clearEnv | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log((JSON.parse(s)||[]).join(" "))}catch{}})')"
  UNSET_ARGS=""
  for v in $CLEAR; do UNSET_ARGS="$UNSET_ARGS -u $v"; done

  # --- typecheck (varsa) ---------------------------------------------------
  TC="$(cfg stack "$STACK" typecheckCommand)"
  if [ -n "$TC" ] && [ "$TC" != "\"\"" ]; then
    TCRES="$(cd "$WT/$STACK_ROOT" && eval "$TC" 2>&1 | tail -12)"; TC_EXIT=${PIPESTATUS[0]:-0}
    { echo '```'; echo "typecheck ($TC):"; printf '%s\n' "${TCRES:-temiz}"; echo '```'; echo; } >> "$OUT"
    [ "$TC_EXIT" = "0" ] || { STATUS="fail"; SUMMARY="$SUMMARY · $STACK typecheck HATA"; }
  fi

  # --- testler -------------------------------------------------------------
  TCMD="$(cfg stack "$STACK" testCommand)"
  [ -n "$TCMD" ] && [ "$TCMD" != "\"\"" ] || { echo "(test komutu tanimli degil)" >> "$OUT"; continue; }
  if printf '%s' "$TCMD" | grep -q '{files}'; then
    if [ -z "${SELECT// /}" ]; then
      { echo "Diff ile eşleşen test yok."; echo; } >> "$OUT"
      SUMMARY="$SUMMARY · $STACK: eşleşen test yok"
      # Bu yiginin kaynagi degismis ama testi yoksa bu bir EKSIKTIR.
      if printf '%s\n' "$TOUCHED" | grep -qE "$(cfg stack "$STACK" testSelector | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).sourcePattern||"$^")}catch{console.log("$^")}})')"; then
        STATUS="fail"
      fi
      continue
    fi
    RUN="${TCMD//\{files\}/$SELECT}"
  else
    RUN="$TCMD"
  fi

  RES="$(cd "$WT/$STACK_ROOT" && env $UNSET_ARGS sh -c "$RUN" 2>&1)"; EXIT=${PIPESTATUS[0]:-1}
  LINE="$(printf '%s' "$RES" | tail -3 | tr '\n' ' ')"
  printf '%s\n' "$RES" | tail -20
  { echo '```'; echo "$RUN"; printf '%s\n' "$RES" | tail -25; echo '```'; echo; } >> "$OUT"

  if [ "$EXIT" = "0" ]; then
    SUMMARY="$SUMMARY · $STACK: yeşil"
    continue
  fi

  # --- UC SINIF TRIAGE: gercek hata / izolasyon kusuru / altyapi ----------
  FILE_PAT="$(cfg stack "$STACK" failureFilePattern)"
  [ -n "$FILE_PAT" ] && [ "$FILE_PAT" != "\"\"" ] || FILE_PAT='[A-Za-z0-9_./-]+\.(py|tsx?|js)'
  BAD="$(printf '%s' "$RES" | grep -E '^ *(FAILED|ERROR|FAIL)' | grep -oE "$FILE_PAT" | sort -u | head -5)"
  SOLO_CMD="$(cfg stack "$STACK" soloCommand)"
  INFRA_PATS="$(cfg stack "$STACK" infraFailurePatterns | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log((JSON.parse(s)||[]).join("|"))}catch{}})')"
  REAL=""; ISO=""; ENVF=""; UNKNOWN=0

  if [ -z "${BAD// /}" ]; then
    UNKNOWN=1
  else
    # Bir dosyayi "on-varolan" saymak icin dosyanin taban agacta da KIRMIZI
    # olmasi YETMEZ: kac kirmizi oldugu da onemlidir.
    #
    # Ilk gercek build turunda olculdu (21 Eyl 2026): worktree'de 2, taban
    # agacta 1 kirmizi vardi; kapi dosya duzeyinde "ikisi de kirmizi" deyip
    # PASS dedi ve bu ticket'a ait YENI kirmizi gorunmez oldu. Teslim kararini
    # veren kapinin kendisi sessizce geciriyordu.
    #
    # Sinif kararlari (sirayla):
    #   tek basina gecti            → izolasyon kusuru (liste + ISO)
    #   altyapi imzasi              → ENVF
    #   taban yesil, burada kirmizi → REAL
    #   ikisi de kirmizi ama burada DAHA COK → REAL (+N yeni)
    #   ikisi de ayni sayida kirmizi → ISO (gercekten on-varolan)
    fail_count() { printf '%s' "$1" | grep -cE '^ *(FAILED|ERROR|FAIL)' || true; }

    for f in $BAD; do
      [ -n "$SOLO_CMD" ] && [ "$SOLO_CMD" != "\"\"" ] || { REAL="$REAL $f"; continue; }
      SOLO="$(cd "$WT/$STACK_ROOT" && env $UNSET_ARGS sh -c "${SOLO_CMD//\{file\}/$f}" 2>&1)"; SOLO_EXIT=$?

      if [ "$SOLO_EXIT" = "0" ]; then
        # Toplu kosuda dustu, tek basina gecti → izolasyon kusuru
        ISO="$ISO $f"; mkdir -p "$(dirname "$KNOWN")"; grep -qxF "$f" "$KNOWN" 2>/dev/null || printf '%s\n' "$f" >> "$KNOWN"
        continue
      fi
      if [ -n "$INFRA_PATS" ] && printf '%s' "$SOLO" | grep -qE "$INFRA_PATS"; then
        ENVF="$ENVF $f"; continue
      fi
      if [ ! -d "$ROOT/$STACK_ROOT" ]; then REAL="$REAL $f"; continue; fi

      BASE_SOLO="$(cd "$ROOT/$STACK_ROOT" && env $UNSET_ARGS sh -c "${SOLO_CMD//\{file\}/$f}" 2>&1)"; BASE_EXIT=$?
      if [ "$BASE_EXIT" = "0" ]; then
        REAL="$REAL $f"   # taban yesil, burada kirmizi → bu ticket
        continue
      fi
      WT_N="$(fail_count "$SOLO")"; BS_N="$(fail_count "$BASE_SOLO")"
      if [ "${WT_N:-0}" -gt "${BS_N:-0}" ]; then
        REAL="$REAL $f(+$((WT_N-BS_N))_yeni)"   # ayni dosya, taban 1 / burada 2
      else
        ISO="$ISO $f"     # ayni sayida kirmizi → gercekten on-varolan
      fi
    done
  fi

  {
    echo "### Triage"; echo
    [ -n "${REAL// /}" ] && echo "- **Gerçek hata** (bu ticket):$REAL"
    [ -n "${ISO// /}" ] && echo "- **Ön-varolan / izolasyon**:$ISO — ayrı iş."
    [ -n "${ENVF// /}" ] && echo "- **Altyapı**:$ENVF — kod değil; tekrar koştur."
    [ "$UNKNOWN" = "1" ] && echo "- **Ayırt edilemedi**: çıkış kodu kırmızı ama düşen dosya çıkarılamadı — elle bak."
    echo
  } >> "$OUT"

  if [ -n "${REAL// /}" ]; then
    STATUS="fail"; SUMMARY="$SUMMARY · $STACK: gerçek hata:$REAL"
  elif [ "$UNKNOWN" = "1" ]; then
    [ "$STATUS" = "fail" ] || STATUS="env"
    SUMMARY="$SUMMARY · $STACK: kırmızı ama ayırt edilemedi"
  elif [ -n "${ENVF// /}" ]; then
    [ "$STATUS" = "fail" ] || STATUS="env"
    SUMMARY="$SUMMARY · $STACK: altyapı hatası"
  else
    SUMMARY="$SUMMARY · $STACK: yalnızca ön-varolan kusurlar"
  fi
done

# HIC TEST KOSMADIYSA BU "GECTI" DEGILDIR.
#
# Eskiden bu durum TESTS.md'ye yaziliyor ama STATUS "pass" kaliyordu — yani
# hicbir sey olculmeden yesil uretiliyordu. En tehlikeli hali yeni kurulmus bir
# projede: stacks listesi henuz bosken her ticket testten "gecer" (dis denetimde
# bulundu 21 Eyl 2026).
#
# Ayrim onemli: yapilandirmada YIGIN YOKSA bu bir kurulum hatasidir (block).
# Yigin var ama degisiklik hicbirine dokunmuyorsa bu bir YARGI sorusudur —
# salt dokuman degisikligi mesru olabilir — ve insana dusurulur, sessizce
# gecilmez.
if [ "$RAN_ANY" != "1" ]; then
  STACK_COUNT="$(cfg stacks | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log((JSON.parse(s)||[]).length)}catch{console.log(0)}})')"
  if [ "${STACK_COUNT:-0}" = "0" ]; then
    echo "Yapılandırmada hiç yığın tanımlı değil (sdlc/project.json → stacks)." >> "$OUT"
    STATUS="fail"
    SUMMARY="yapılandırmada yığın yok — test koşulamaz, bu bir kurulum hatası"
  else
    echo "Hiçbir yığın etkilenmemiş: $STACK_COUNT yığın tanımlı, değişiklik hiçbirine dokunmuyor." >> "$OUT"
    STATUS="env"
    SUMMARY="değişiklik hiçbir yığına dokunmuyor — hiç test koşmadı, insan bakmalı"
  fi
fi

{ echo "## Verdict"; echo; echo "**$STATUS** —${SUMMARY:- ölçüm yok}"; } >> "$OUT"

node --input-type=module -e '
  const { record } = await import("'"$ROOT"'/gates/journal.ts");
  const s = process.argv[2];
  record({ gate: "test", ticket: process.argv[1], artifact: "docs/sdlc/"+process.argv[1]+"/TESTS.md",
           decision: s === "pass" ? "pass" : s === "env" ? "human" : "block",
           reason: process.argv[3], measures: { headSha: process.argv[4] || "" } });
' "$TICKET" "$STATUS" "$SUMMARY" "$(git -C "$WT" rev-parse --short=12 HEAD 2>/dev/null || echo '')" || exit 20

echo "--- sonuc: $STATUS ($SUMMARY) → $OUT"
case "$STATUS" in pass) exit 0 ;; env) exit 10 ;; *) exit 20 ;; esac
