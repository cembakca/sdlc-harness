#!/usr/bin/env bash
# fixtures/consumer-smoke.sh — GERCEK bir tuketen repo kurup uctan uca kostur.
#
#   fixtures/consumer-smoke.sh <harness-koku>
#
# Neden gerekli. make selftest'in tamami PROJE kokunde kosar ve harness ayni
# repodaymis gibi davranan senaryolar kurar. Bu yuzden "harness dosyasini proje
# kokunde aramak" sinifindaki hatalar YESIL testlerden kaciyordu: iki kok ayni
# dizin oldugunda gorunmezler (dis denetim, 22 Eyl 2026 — ornek projede
# approve.sh olmayan <proje>/gates/journal.ts icin ERR_MODULE_NOT_FOUND verdi).
#
# Burada harness GERCEKTEN submodule olarak baglanir: yerel bir klondan, ag
# olmadan. Sonra bilet acilir ve komutlar sirayla kosturulur. Model cagrisi
# YOKTUR — JEV_API_KEY bilerek silinir, kapilar offline'da insana duser; bu
# testin olctugu sey kararlar degil, KOMUTLARIN AYAKTA OLUP OLMADIGI.
set -uo pipefail

HARNESS="${1:?kullanim: consumer-smoke.sh <harness-koku>}"
HARNESS="$(cd "$HARNESS" && pwd)"
T="SMOKE-1"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILS=0
step() { # step <ad> <beklenen-cikis-kodlari-virgullu> <komut...>
  local name="$1" codes="$2"; shift 2
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  case ",$codes," in
    *",$rc,"*) printf '    ✓ %s (exit %s)\n' "$name" "$rc" ;;
    *) printf '    ✗ %s — exit %s, beklenen %s\n' "$name" "$rc" "$codes"
       printf '%s\n' "$out" | tail -8 | sed 's/^/        /'
       FAILS=$((FAILS+1)) ;;
  esac
  # Kok karismasinin imzasi: hangi cikis kodu olursa olsun bu gorulmemeli.
  if printf '%s' "$out" | grep -q 'ERR_MODULE_NOT_FOUND\|No such file or directory'; then
    printf '    ✗ %s — KOK KARISMASI: %s\n' "$name" \
      "$(printf '%s' "$out" | grep -m1 -o "ERR_MODULE_NOT_FOUND\|No such file or directory")"
    printf '%s\n' "$out" | grep -m3 -E "Cannot find|No such file" | sed 's/^/        /'
    FAILS=$((FAILS+1))
  fi
}

# Cikis kodu anlamli olmayan komutlar icin: rapor uretildi mi.
report() { # report <ad> <beklenen-metin> <komut...>
  local name="$1" needle="$2"; shift 2
  local out
  out="$("$@" 2>&1)"
  if printf '%s' "$out" | grep -q "$needle"; then
    printf '    ✓ %s\n' "$name"
  else
    printf '    ✗ %s — raporda "%s" yok\n' "$name" "$needle"
    printf '%s\n' "$out" | tail -6 | sed 's/^/        /'
    FAILS=$((FAILS+1))
  fi
  if printf '%s' "$out" | grep -q 'ERR_MODULE_NOT_FOUND'; then
    printf '    ✗ %s — KOK KARISMASI\n' "$name"
    printf '%s\n' "$out" | grep -m2 "Cannot find" | sed 's/^/        /'
    FAILS=$((FAILS+1))
  fi
}

# Harness'in YEREL klonu: ag yok, calisma agacindaki hali sinanir.
BARE="$WORK/harness.git"
git clone -q --local "$HARNESS" "$BARE" 2>/dev/null || {
  echo "  harness klonlanamadi (git deposu degil mi?)"; exit 2; }
( cd "$HARNESS" && git status --porcelain >/dev/null 2>&1 ) && \
  ( cd "$BARE" && git checkout -q -B main )
# Calisma agacindaki (henuz commit edilmemis) hali de sinansin: klonun uzerine
# kopyalanir. Aksi halde test bir onceki commit'i olcer.
for d in gates scripts sdlc fixtures .claude; do
  [ -d "$HARNESS/$d" ] && cp -R "$HARNESS/$d" "$BARE/" 2>/dev/null
done
rm -rf "$BARE/.sdlc-cache"
( cd "$BARE" && git add -A >/dev/null 2>&1 && \
  git -c user.name=s -c user.email=s@l commit -qm "calisma agaci" >/dev/null 2>&1 ) || true

# Tuketen proje.
P="$WORK/tuketen"
mkdir -p "$P/server/tests"
printf 'def f():\n    return 1\n' > "$P/server/a.py"
printf 'def test_f():\n    assert 1\n' > "$P/server/tests/test_a.py"
touch "$P/server/requirements.txt"
echo "# tuketen" > "$P/README.md"
# file:// submodule'u git varsayilan olarak reddeder (CVE-2022-39253). Burada
# kaynak KENDI urettigimiz gecici klon, o yuzden yalnizca bu repo icin aciyoruz.
( cd "$P" && git init -q -b main && git config protocol.file.allow always && git add -A && \
  git -c user.name=s -c user.email=s@l commit -qm init ) >/dev/null

echo "  kurulum"
step "init.sh --target (submodule bagla + iskelet)" "0" \
  env -u SDLC_PROJECT_ROOT SDLC_SUBMODULE_PATH=sdlc-harness SDLC_HARNESS_ORIGIN="$BARE" \
      GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always \
      "$HARNESS/scripts/sdlc/init.sh" --target "$P"
# init submodule'u uzaktan cekmeye calisir; yerel klona yonlendir.
if [ ! -d "$P/sdlc-harness/gates" ]; then
  ( cd "$P" && rm -rf sdlc-harness .gitmodules && \
    git submodule add -q --force "$BARE" sdlc-harness >/dev/null 2>&1 ) || true
fi
[ -d "$P/sdlc-harness/gates" ] || { echo "    ✗ submodule baglanmadi"; exit 1; }
printf 'SDLC = sdlc-harness/\ninclude $(SDLC)sdlc.mk\n' > "$P/Makefile"

# README'nin KISA YOLU: yapilandirma yokken submodule icinden init.sh cagirmak.
# Burasi kok kesfinin en kaygan yeri — submodule'un kendi git deposu vardir ve
# "git ust dizini" submodule'u dondurur; iskelet o zaman harness'in icine
# yazilirdi (dis denetim, 22 Eyl 2026).
rm -f "$P/sdlc/project.json"
( cd "$P" && env -u SDLC_PROJECT_ROOT bash sdlc-harness/scripts/sdlc/init.sh >/dev/null 2>&1 ) || true
if [ -f "$P/sdlc/project.json" ] && [ ! -f "$P/sdlc-harness/sdlc/project.json" ]; then
  printf '    ✓ %s\n' "kisa yol iskeleti PROJEYE yazdi"
else
  printf '    ✗ %s\n' "kisa yol iskeleti yanlis koke yazdi (harness icine)"
  FAILS=$((FAILS+1))
fi

cd "$P"
# Anahtar YOK: kapilar olcmesin, insana dussun. Olculen sey komutlarin ayakta
# olmasi; kararlar kalibrasyonun isi.
export SDLC_PROJECT_ROOT="$P"
unset JEV_API_KEY
S="sdlc-harness/scripts/sdlc"

echo "  modelsiz denetimler"
step "sdlc/project.json gecerli"        "0"     node sdlc-harness/sdlc/validate.ts
step "kadro kurallari"                  "0"     node sdlc-harness/sdlc/roster.ts --check
step "durum makinesi"                   "0"     node sdlc-harness/gates/chain.ts
step "kuru kosum"                       "0"     node sdlc-harness/scripts/sdlc/workflow-dryrun.mjs
step "sir taramasi"                     "0"     "$S/secret-scan.sh"
step "kalibrasyon plani"                "0"     node sdlc-harness/gates/calibrate.ts --plan

echo "  bilet yasam dongusu"
step "sdlc-new"                         "0"     "$S/new.sh" "$T" "duman testi"
step "durum"                            "0"     node sdlc-harness/gates/status.ts
for f in spec plan REVIEW TESTS UAT; do echo "# $f" > "docs/sdlc/$T/$f.md"; done
step "kapi: spec (offline -> insan)"    "10,20" node sdlc-harness/gates/evaluate.ts spec "docs/sdlc/$T/spec.md"
step "onay durumu (--check)"            "0,1"   "$S/approve.sh" --check "$T" blast
# Onay INTERAKTIF terminal ister (exit 2): bu dogru davranis, kayit bir
# insan hareketidir. Burada olculen sey komutun ayakta olmasi.
step "onay komutu ayakta (interaktif ister)" "0,1,2,20" "$S/approve.sh" "$T" blast "duman testi"
step "defter gecmisi"                   "0"     node sdlc-harness/gates/history.ts "$T"
step "kademe atamasi"                   "0"     node sdlc-harness/gates/assign.ts "$T"
step "commit disiplini"                 "0,1,20" "$S/commit-lint.sh" "$T"
step "test fazi"                        "0,1,20" "$S/test.sh" "$T"
step "postbuild"                        "0,10,20" node sdlc-harness/gates/postbuild.ts "$T"
step "teslim hazirligi"                 "0,20"  node sdlc-harness/gates/readiness.ts "$T"
# doctor'in cikis kodu KRITIK SAYISIDIR: ciplak bir CI runner'inda .venv ve
# codex gercekten eksiktir ve bunu soylemesi DOGRUDUR. Burada olculen sey ortam
# butunlugu degil, komutun ayakta olup raporunu uretebilmesi.
report "doctor (rapor uretiyor mu)" "doctor:" "$S/doctor.sh" "$T"
step "olcum ozeti"                      "0,1,20" "$S/measure.sh" "$T" plan-stage
step "worktree temizligi"               "0,20"  bash "$S/worktree-clean.sh" "$T"
step "teslim kapisi (durmali)"          "20"    "$S/land.sh" "$T"

if [ "$FAILS" -gt 0 ]; then
  echo "  tuketen repo duman testi: $FAILS adim kirik"
  exit 1
fi
echo "  tuketen repo duman testi: kurulumdan teslime butun komutlar ayakta"
