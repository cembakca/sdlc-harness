#!/usr/bin/env bash
# Teslim: kapidan gecerse ana dala tasir.
#
#   scripts/sdlc/land.sh <TICKET>
#
# Eskiden yalnizca komutlari BASIYORDU. Bir teslim adiminin isi komut onermek
# degil, kapidan gecmis bir isi tasimak ve bunu kayda gecirmektir. Insan
# tetikler (bu komutu sen yazarsin), kapi karar verir, script uygular.
set -uo pipefail

# Proje koku: harness'in nerede durdugundan bagimsiz (bkz. _root.sh).
_SDLC_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SDLC_CALLER_DIR/_root.sh"
ROOT="$(sdlc_root)" || exit 1
HARNESS="$(sdlc_harness_root)"
TICKET="${1:?kullanim: land.sh <TICKET>}"
DIR="$ROOT/docs/sdlc/$TICKET"
WT="$ROOT/.sdlc-worktrees/$TICKET"
BRANCH="sdlc/$TICKET"
BASE="$(cat "$DIR/.base-branch" 2>/dev/null || echo main)"
bash "$HARNESS/scripts/sdlc/worktree-clean.sh" "$TICKET" >/dev/null || exit 20

echo "== teslim kapisi"
if ! node "$HARNESS/gates/readiness.ts" "$TICKET"; then
  echo ""
  echo "Kapi gecilmedi — tasima yapilmadi. Yukaridaki engelleri kapat."
  exit 20
fi

CURRENT="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
[ "$CURRENT" = "$BASE" ] || { echo "taban dalda degilsin ($CURRENT != $BASE)" >&2; exit 1; }
# Calisma agaci temiz olmali — AMA biletin KENDI belgeleri istisnadir. Artifact'ler
# (spec/plan/REVIEW/TESTS/UAT + decisions.jsonl) ana agacta uretilir ve teslim
# anina kadar commit edilmemis olur; bunlari "kirlilik" sayinca land hicbir normal
# akista calismiyordu (dis denetimde bulundu 21 Eyl 2026). Belgeler isin parcasidir:
# burada kendi commit'ine alinir, boylece teslimle birlikte kayda gecer.
DIRTY="$(git -C "$ROOT" status --porcelain)"
OTHER="$(printf '%s\n' "$DIRTY" | grep -v " docs/sdlc/$TICKET/" | grep -v "^?? docs/sdlc/$TICKET/" | sed '/^$/d')"
if [ -n "$OTHER" ]; then
  echo "calisma agaci temiz degil (biletin belgeleri disinda degisiklik var):" >&2
  printf '%s\n' "$OTHER" >&2
  exit 1
fi
# TESLIM YA TUMUYLE OLUR YA HIC.
#
# Belgeler merge'den ONCE commit ediliyor (git temiz agac istiyor). Merge
# basarisiz olursa taban dalda yarim bir "teslim belgeleri" commit'i kalirdi:
# is teslim edilmemis ama gecmis teslim edilmis gibi gorunurdu (dis denetimde
# bulundu 21 Eyl 2026). Artik geri alma noktasi tutuluyor ve merge dusrse
# commit SOFT olarak geri aliniyor — dosyalar yerinde kalir, tarih temiz.
LAND_UNDO=""
if [ -n "$DIRTY" ]; then
  echo "biletin belgeleri commit ediliyor: docs/sdlc/$TICKET"
  git -C "$ROOT" add -- "docs/sdlc/$TICKET" >/dev/null
  if git -C "$ROOT" commit -q -m "$TICKET: teslim belgeleri (spec/plan/REVIEW/TESTS/UAT + karar defteri)"; then
    LAND_UNDO=1
  else
    echo "belgeler commit edilemedi" >&2
    exit 20
  fi
fi

# Merge dusrse belgeleri geri al: --soft, yani dosyalar silinmez.
undo_docs() {
  [ -n "$LAND_UNDO" ] || return 0
  git -C "$ROOT" reset --soft HEAD~1 >/dev/null 2>&1 \
    && echo "belge commit'i geri alindi (dosyalar yerinde) — taban dalda iz birakilmadi" >&2
}

echo ""
echo "== birlestiriliyor: $BRANCH → $BASE"
APPROVALS="$(node --input-type=module -e '
  const { read } = await import("'"$HARNESS"'/gates/journal.ts");
  const rows = read(process.argv[1]).filter((r) => r.gate.startsWith("approve:"));
  for (const a of rows) console.log(`Approved-${a.gate.replace("approve:", "")}: ${a.reason}`);
' "$TICKET" 2>/dev/null || true)"

git -C "$ROOT" merge --no-ff "$BRANCH" -m "$(cat <<MSG
$TICKET: teslim

Belgeler: docs/sdlc/$TICKET/{spec,plan,REVIEW,TESTS,UAT}.md
Karar defteri: docs/sdlc/$TICKET/decisions.jsonl

$APPROVALS

Teslim kapisi (gates/readiness.ts) bu birlestirmeden once yesildi.
MSG
)" || { echo "birlestirme basarisiz" >&2; undo_docs; exit 20; }

node --input-type=module -e '
  const { record } = await import("'"$HARNESS"'/gates/journal.ts");
  record({ gate: "land", ticket: process.argv[1], artifact: process.argv[2],
           decision: "landed", reason: `${process.argv[3]} dalina birlestirildi` });
' "$TICKET" "$BRANCH" "$BASE" || {
  # Teslim GERCEKLESTI ama deftere yazilamadi: bunu yutmak, en onemli kaydi
  # kaybetmek olur. Merge geri alinmaz (kod tabanda), ama insan bilir.
  echo "TESLIM DEFTERE YAZILAMADI — merge yapildi ama kayit eksik!" >&2
  echo "  elle: node -e ... ya da git log ile dogrula" >&2
  exit 12
}

echo ""
echo "birlestirildi. Worktree duruyor: $WT"
echo "Temizlemek icin: git worktree remove $WT && git branch -d $BRANCH"
echo "Sonucu kaydetmeyi unutma: make sdlc-outcome TICKET=$TICKET R=shipped-clean WHAT=\"...\""
