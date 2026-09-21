#!/usr/bin/env bash
# Teslimden SONRA ne oldugunu kaydeder.
#
#   scripts/sdlc/outcome.sh <TICKET> <sonuc> "<ne oldu>"
#   sonuc: shipped-clean | incident | rollback | reverted | unused
#
# Hat bugune kadar yalnizca TAHMINLERINI kaydediyordu: blast kapisi "logic"
# dedi, review "severity 3.6" dedi, rota "standard" dedi. Gercekte ne oldugu
# hicbir yere yazilmiyordu — yani esikler yalnizca fixture'lara karsi kalibre,
# uretim gercegine karsi degil.
#
# Bir ofis teslim ettigi isin sonucunu ogrenir; ogrenmiyorsa ayni hatayi
# guvenle tekrarlar.
set -uo pipefail

# Proje koku: harness'in nerede durdugundan bagimsiz (bkz. _root.sh).
_SDLC_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SDLC_CALLER_DIR/_root.sh"
ROOT="$(sdlc_root)" || exit 1
TICKET="${1:?kullanim: outcome.sh <TICKET> <sonuc> \"<ne oldu>\"}"
RESULT="${2:?sonuc: shipped-clean | incident | rollback | reverted | unused}"
WHAT="${3:?ne oldugunu bir cumleyle yaz — sayisiz sonuc ogretmez}"
WHO="${SDLC_APPROVER:-$(git config user.name 2>/dev/null || whoami)}"

case "$RESULT" in
  shipped-clean|incident|rollback|reverted|unused) ;;
  *) echo "gecersiz sonuc: $RESULT" >&2; exit 1 ;;
esac

node -e '
  const { record, read } = await import("'"$ROOT"'/gates/journal.ts");
  const [ticket, result, what, who] = process.argv.slice(1);
  const rows = read(ticket);
  if (!rows.length) {
    console.error(`${ticket} icin kapi kaydi yok — once hattan gecmeli`);
    process.exit(2);
  }
  record({
    gate: "outcome",
    ticket,
    artifact: `docs/sdlc/${ticket}`,
    decision: result,
    reason: `${who}: ${what}`,
  });
  console.log(`sonuc kaydedildi — ${ticket}: ${result}`);
' "$TICKET" "$RESULT" "$WHAT" "$WHO" || exit $?

# Hafizaya da yaz: bir sonraki benzer iste "bunu daha once yapmistik, sonu su
# oldu" diyebilelim.
# Hafizaya yazmak DEFTERE yazmak degildir: defter zorunlu, hafiza istege bagli
# (Cognee kapali olabilir ve hat hafizasiz calisir). Ama sessiz de kalmaz —
# "yazildi sandim" ile "yazilamadi" ayri seylerdir.
"$ROOT/scripts/sdlc/memory.sh" remember-decisions "$TICKET" >/dev/null 2>&1 \
  || echo "   (kararlar hafizaya yazilamadi — defter yerinde, hafiza atlandi)" >&2
echo "kapi defteri hafizaya senkronlandi"
