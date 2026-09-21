#!/usr/bin/env bash
# SessionStart hook — karar kapilarinin kalibrasyonu bayatladi mi.
#
# Kapilar sessizce bozulur: model surumu degisir, esik kayar, bir fixture
# artik ayirt etmez. Bunu hicbir sey haber vermez — o yuzden oturum acilisinda
# kalibrasyonun yasina bakiyoruz. KOSTURMUYORUZ, yalnizca hatirlatiyoruz:
# olcumun ne zaman yapilacagi insanin karari, maliyeti de var.
set -uo pipefail

DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
# Kayit PROJEDE durur (sdlc/), harness'ta degil: olculen sey bu projenin
# kapilaridir — genel fixture'lar + projenin kendi artifact'leri.
STAMP="$DIR/sdlc/.last-calibration.json"
MAX_DAYS="${SDLC_CALIBRATION_MAX_DAYS:-30}"

# Harness baglanmamissa hook'un soyleyecegi bir sey yok. "gates/" diye
# bakiyordu; harness submodule'e cikinca o dizin projede kalmadi ve hook
# SESSIZCE devre disi kaldi (olculdu 22 Eyl 2026).
[ -f "$DIR/sdlc/project.json" ] || exit 0

if [ ! -f "$STAMP" ]; then
  echo "Karar kapilari hic kalibre edilmemis. Olcmek icin: make sdlc-calibrate"
  exit 0
fi

AT="$(node -e 'try{console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).at||"")}catch{console.log("")}' "$STAMP" 2>/dev/null)"
[ -n "$AT" ] || exit 0

AGE_DAYS="$(node -e '
  const at=new Date(process.argv[1]);
  if(isNaN(at)) { console.log(""); process.exit(0) }
  console.log(Math.floor((Date.now()-at.getTime())/86400000))' "$AT" 2>/dev/null)"
[ -n "$AGE_DAYS" ] || exit 0

SUMMARY="$(node -e '
  try{const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
    console.log(`${r.cases-r.wrong}/${r.cases} dogru, ${r.flapping} salinim`)}catch{console.log("")}' "$STAMP" 2>/dev/null)"

if [ "$AGE_DAYS" -ge "$MAX_DAYS" ]; then
  echo "Karar kapilari ${AGE_DAYS} gundur olculmedi (son: ${SUMMARY}). Bozuk bir kapi, kapi olmamasindan tehlikelidir — make sdlc-calibrate"
fi
exit 0
