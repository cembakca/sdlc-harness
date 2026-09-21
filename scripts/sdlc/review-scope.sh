#!/usr/bin/env bash
# Denetciye NE OKUYACAGINI soyler: tum diff mi, yalnizca delta mi.
#
#   scripts/sdlc/review-scope.sh <TICKET>
#
# Ilk review tum degisikligi gorur — bir degisikligin DOKUNMADIGI kodla
# etkilesimi ancak butunu gorunce fark edilir. Duzeltme turlarinda ise
# denetci bir onceki review'dan BERI degiseni okur, arti "gecen turun acik
# bulgulari kapandi mi" sorusunu dogrular.
#
# Olculdu (21 Eyl 2026): duzeltme turunda iki denetci 22 dosyalik +1314
# satirlik diff'i bastan okuyordu; bunun ~1000 satiri bir onceki turda zaten
# okunmustu. Insan code review'inda da ikinci turda dosya bastan okunmaz.
set -uo pipefail

# Proje koku: harness'in nerede durdugundan bagimsiz (bkz. _root.sh).
_SDLC_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SDLC_CALLER_DIR/_root.sh"
ROOT="$(sdlc_root)" || exit 1
TICKET="${1:?kullanim: review-scope.sh <TICKET>}"
DIR="$ROOT/docs/sdlc/$TICKET"
WT="${SDLC_WORKTREE:-$ROOT/.sdlc-worktrees/$TICKET}"
BASE="${SDLC_BASE:-$(cat "$DIR/.base-branch" 2>/dev/null || echo main)}"

if [ "${2:-}" = "--patch" ]; then
  [ -d "$WT" ] || { echo "worktree yok: $WT" >&2; exit 20; }
  git -C "$WT" diff "$BASE...HEAD" -- . ':!docs/sdlc'
  exit $?
fi

# TAM DIFF KOMUTU TEK YERDE. "--cached" onerilmez: build fazi her gorev icin
# commit attigi icin staged alan bos olabilir ve denetci HICBIR SEY gormeden
# "bulgu yok" der (dis denetimde bulundu 21 Eyl 2026). Dogrusu taban daldan
# beri olan her sey, arti commit edilmemis kalan.
FULL_DIFF="git -C $WT diff $BASE...HEAD   (ayrica commit edilmemis icin: git -C $WT diff)"

[ -d "$WT" ] || { echo "FULL"; echo "worktree yok — tam diff okunacak"; exit 0; }

HEAD_NOW="$(git -C "$WT" rev-parse HEAD 2>/dev/null | cut -c1-12)"
LAST="$(node --input-type=module -e '
  const { read } = await import("'"$ROOT"'/gates/journal.ts");
  const rows = read(process.argv[1]).filter((r) => r.gate === "review");
  const last = [...rows].reverse().find((r) => r.measures && r.measures.headSha);
  console.log(last ? String(last.measures.headSha) : "");
' "$TICKET" 2>/dev/null)"

if [ -z "$LAST" ] || [ "$LAST" = "$HEAD_NOW" ]; then
  echo "FULL"
  echo "Bu ilk denetim (ya da onceki denetimden beri commit yok)."
  echo "Oku: $FULL_DIFF"
  exit 0
fi

# Delta gercekten kucuk mu? Degilse tam okumak daha dogru.
#
# DELTA BILETIN KENDI DOSYALARIYLA SINIRLI OLMALI. Worktree arada taban dali
# merge ediyor; "$LAST..HEAD" o merge ile gelen HER SEYI de sayiyordu ve kucucuk
# bir duzeltme turu "8550 satir" gorunup denetciyi tum diff'i bastan okumaya
# yolluyordu (olculdu 21 Eyl 2026, ilk gercek duzeltme turu). Denetcinin isi
# biletin degistirdigi kod; tabandan gelen is baska bir incelemenin konusu.
# Surec belgeleri (docs/sdlc/) denetimin KONUSU DEGIL: denetci urun kodunu okur.
# Gecen turda bunlarin diff'e karismasi denetciyi de yaniltmisti.
TICKET_FILES="$(git -C "$WT" diff --name-only "$BASE...HEAD" 2>/dev/null | grep -v '^docs/sdlc/' | tr '\n' ' ')"
if [ -n "${TICKET_FILES// /}" ]; then
  DELTA_LINES="$(git -C "$WT" diff --shortstat "$LAST..HEAD" -- $TICKET_FILES 2>/dev/null | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0)"
else
  DELTA_LINES="$(git -C "$WT" diff --shortstat "$LAST..HEAD" 2>/dev/null | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0)"
fi
TOTAL_LINES="$(git -C "$WT" diff "$BASE...HEAD" --shortstat 2>/dev/null | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0)"

if [ "${DELTA_LINES:-0}" -gt $(( ${TOTAL_LINES:-1} / 2 )) ]; then
  echo "FULL"
  echo "Delta ($DELTA_LINES satir) toplamin yarisindan buyuk — tam okumak daha dogru."
  echo "Oku: $FULL_DIFF"
  exit 0
fi

echo "DELTA"
echo "Onceki denetim: $LAST · simdi: $HEAD_NOW · yeni satir: ${DELTA_LINES:-?}"
echo "Oku: git -C $WT diff $LAST..HEAD -- $TICKET_FILES"
echo ""
echo "AYRICA: gecen turun acik bulgulari kapandi mi, tek tek dogrula."
echo "Kapanmayanlari 'open' olarak KORU; kapananlari 'fixed' isaretle ve nasil"
echo "kapatildigini bir satirda yaz. Bulguyu kapandi saymak icin kodu gormus olman"
echo "sart — commit mesajina guvenme."
echo ""
if [ -f "$DIR/REVIEW.md" ]; then
  echo "--- onceki bulgular (open olanlar) ---"
  grep -E '^\|' "$DIR/REVIEW.md" | grep -iE '\| *open *\|' | head -20
fi
