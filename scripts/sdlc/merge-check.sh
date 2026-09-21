#!/usr/bin/env bash
# Birlesme durumu kapisi — "kendi dunyasinda yesil" yetmez.
#
#   scripts/sdlc/merge-check.sh <TICKET>
#
# Worktree eski bir HEAD'den aciliyor; taban dal ilerledikce o dunya artik yok.
# Testler F4-1'in dunyasinda geciyor ama birlesmis halde ne oldugunu hicbir sey
# sormuyordu (21 Eyl 2026'da fark edildi — hattin hic bakmadigi sessiz risk).
#
# Yaptigi: geride mi → temiz birlesiyor mu → BIRLESMIS HALDE testler yesil mi.
# Exit 0 temiz, 10 insan baksin, 20 birlesme kirik ya da test kirmizi.
set -uo pipefail

# Proje koku: harness'in nerede durdugundan bagimsiz (bkz. _root.sh).
_SDLC_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SDLC_CALLER_DIR/_root.sh"
ROOT="$(sdlc_root)" || exit 1
TICKET="${1:?kullanim: merge-check.sh <TICKET>}"
DIR="$ROOT/docs/sdlc/$TICKET"
WT="${SDLC_WORKTREE:-$ROOT/.sdlc-worktrees/$TICKET}"
BRANCH="sdlc/$TICKET"
BASE="${SDLC_BASE:-$(cat "$DIR/.base-branch" 2>/dev/null || git -C "$ROOT" rev-parse --abbrev-ref HEAD)}"

[ -d "$WT" ] || { echo "worktree yok: $WT" >&2; exit 20; }
bash "$ROOT/scripts/sdlc/worktree-clean.sh" "$TICKET" >/dev/null || exit 20

note() { node -e '
  const { record } = await import("'"$ROOT"'/gates/journal.ts");
  const [ticket, decision, reason] = process.argv.slice(1);
  record({ gate: "merge", ticket, artifact: "'"$BRANCH"'", decision, reason,
           measures: { headSha: process.argv[4] || "", baseSha: process.argv[5] || "", base: "'"$BASE"'" } });
' "$TICKET" "$1" "$2" \
  "$(git -C "$WT" rev-parse --short=12 HEAD 2>/dev/null || echo '')" \
  "$(git -C "$ROOT" rev-parse --short=12 "$BASE" 2>/dev/null || echo '')"; }
# TABAN DAL DA KAYDA GIRER: yalnizca is dalinin HEAD'i kaydedilirse, taban dal
# sonradan ilerledigi halde eski birlesme kontrolu guncel gorunuyordu (dis
# denetimde bulundu 21 Eyl 2026). "Birlesmis halde yesil" iki tarafin da
# o anki halini anlatir.

BEHIND="$(git -C "$ROOT" rev-list --count "$BRANCH..$BASE" 2>/dev/null || echo "?")"
echo "taban dal: $BASE · gerideki commit: $BEHIND"

if [ "$BEHIND" = "0" ]; then
  echo "güncel — birleşme riski yok"
  note pass "taban ($BASE) ile guncel"
  exit 0
fi

PRE="$(git -C "$WT" rev-parse HEAD)"

# Artifact'lerin TEK KAYNAGI ana agac. Worktree'deki kopyalari yalnizca gecmisten
# kalma; uzerlerine yazilan her sey birlesmeyi "local changes would be
# overwritten" ile durduruyordu ve script bunu CAKISMA sanip bos bir dosya
# listesiyle rapor ediyordu (olculdu 21 Eyl 2026, ilk gercek turda). Once bu
# kopyalari HEAD'e dondur: kaybedilen bir sey yok, kaynak ana agacta.
git -C "$WT" checkout -- docs/sdlc >/dev/null 2>&1 || true

if ! git -C "$WT" merge --no-edit "$BASE" >/tmp/sdlc-merge.log 2>&1; then
  CONFLICTS="$(git -C "$WT" diff --name-only --diff-filter=U | tr '\n' ' ')"

  # ARTIFACT CAKISMASI GERCEK CAKISMA DEGILDIR. docs/sdlc/ altindaki belgelerin
  # tek kaynagi ANA AGAC: hat onlari orada uretiyor, worktree'deki kopyalar
  # gecmisten kalma. Iki taraf da yazdigi icin her birlesmede cakisiyorlardi
  # (olculdu 21 Eyl 2026). Kural: bu yollarda TABAN kazanir. Kod yollarindaki
  # cakisma ise gercek cakismadir ve durdurur.
  CODE_CONFLICTS="$(printf '%s\n' $CONFLICTS | grep -v '^docs/sdlc/' | tr '\n' ' ')"
  DOC_CONFLICTS="$(printf '%s\n' $CONFLICTS | grep '^docs/sdlc/' | tr '\n' ' ')"
  if [ -n "${CONFLICTS// /}" ] && [ -z "${CODE_CONFLICTS// /}" ]; then
    echo "artifact çakışması ($DOC_CONFLICTS) — tek kaynak ana ağaç, taban sürümü alınıyor"
    for f in $DOC_CONFLICTS; do
      git -C "$WT" checkout --theirs -- "$f" >/dev/null 2>&1 || git -C "$WT" checkout "$BASE" -- "$f" >/dev/null 2>&1 || true
      git -C "$WT" add -- "$f" >/dev/null 2>&1 || true
    done
    if git -C "$WT" -c user.name="sdlc-harness" -c user.email="sdlc@local" \
         commit -q --no-edit >/dev/null 2>&1; then
      CONFLICTS=""   # cozuldu; asagidaki blok atlanir
    fi
  fi
fi
if [ -n "${CONFLICTS// /}" ]; then
  git -C "$WT" merge --abort >/dev/null 2>&1
  if [ -n "${CONFLICTS// /}" ]; then
    echo "ÇAKIŞMA — taban dal ile birleşmiyor: $CONFLICTS"
    note block "cakisma: $CONFLICTS"
  else
    # Cakisma YOK ama merge yine de basarisiz: sebebi UYDURMA, git'in dediğini yaz.
    REASON="$(grep -v '^Merge with strategy' /tmp/sdlc-merge.log | head -4 | tr '\n' ' ')"
    echo "BİRLEŞME BAŞARISIZ (çakışma değil) — git: $REASON"
    note block "birlesme basarisiz (cakisma degil): $REASON"
  fi
  echo "worktree birleşme öncesi hâline döndürüldü ($PRE)"
  exit 20
fi

echo "temiz birleşti ($BEHIND commit alındı) — şimdi BİRLEŞMİŞ hâlde testler"
if "$ROOT/scripts/sdlc/test.sh" "$TICKET" >/tmp/sdlc-merge-tests.log 2>&1; then
  echo "birleşmiş hâlde testler yeşil"
  tail -3 /tmp/sdlc-merge-tests.log
  note pass "$BASE ile temiz birlesti, birlesmis halde testler yesil"
  exit 0
fi

echo "birleşmiş hâlde TESTLER KIRMIZI — kendi dünyasında yeşildi, birleşince değil:"
tail -6 /tmp/sdlc-merge-tests.log
note block "birlesmis halde testler kirmizi"
exit 20
