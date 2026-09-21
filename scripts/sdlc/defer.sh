#!/usr/bin/env bash
# Ertelenen isi BIR YERE koyar.
#
#   scripts/sdlc/defer.sh <KAYNAK-TICKET> <YENI-TICKET> "<baslik>" "<neden ertelendi>"
#
# 21 Eylul 2026'da olculdu: F4-1'in plani iki bulguyu gerekcesiyle erteledi
# (#7 bildirim hacmi, #13 HTTP-200 interstitial) — ve o is hicbir yere
# yazilmadi. Gerekcesiyle ertelemek durustur; ertelenen isin kaydini tutmamak
# degildir. Ertelenen is bir ticket olur, iki yonlu baglanir.
set -uo pipefail

# Proje koku: harness'in nerede durdugundan bagimsiz (bkz. _root.sh).
_SDLC_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SDLC_CALLER_DIR/_root.sh"
ROOT="$(sdlc_root)" || exit 1
FROM="${1:?kullanim: defer.sh <KAYNAK> <YENI> \"baslik\" \"neden\"}"
NEW="${2:?yeni ticket kimligi}"
TITLE="${3:?baslik}"
WHY="${4:?neden ertelendi}"
SRC="$ROOT/docs/sdlc/$FROM"
DST="$ROOT/docs/sdlc/$NEW"

[ -d "$SRC" ] || { echo "kaynak ticket yok: $FROM" >&2; exit 1; }

"$ROOT/scripts/sdlc/new.sh" "$NEW" "$TITLE" >/dev/null || exit 1

cat > "$DST/intent.md" <<INTENT
# Intent — $NEW: $TITLE

> **$FROM ticket'ından ertelendi.** Bu dosya otomatik açıldı; problemi ve
> kısıtları insan doldurur, ama ertelenme gerekçesi kaybolmasın diye kaynağıyla
> birlikte kaydedildi.

## Problem
$WHY

## Neden şimdi değil, neden hiç değil de ertelendi
<$FROM kapsamında yapılamamasının sebebi yukarıda. Bu işin kendi başına
yapılabilir bir çıktısı var mı, yoksa başka bir işe mi bağlı — yaz.>

## Kaynak
- Ticket: [$FROM](../$FROM/spec.md)
- Bulgular: [$FROM/REVIEW.md](../$FROM/REVIEW.md)
- Plan kararı: [$FROM/plan.md](../$FROM/plan.md)

## Başarı nasıl görünür
<Ölçülebilir sonuç.>

## Kısıtlar
<Bütçe, uyum, mimari.>

## Kapsam dışı
<Kesinlikle yapılmayacaklar.>
INTENT

# Kaynak tarafa geri bag: ertelenen is nereye gitti
BACKLINK="$SRC/deferred.md"
if [ ! -f "$BACKLINK" ]; then
  { echo "# Ertelenen işler — $FROM"; echo ""; echo "Bu ticket kapsamında bilerek yapılmayan, kendi ticket'ına taşınan işler."; echo ""; } > "$BACKLINK"
fi
printf -- '- [%s](../%s/intent.md) — %s\n  - gerekçe: %s\n' "$NEW" "$NEW" "$TITLE" "$WHY" >> "$BACKLINK"

# Karar defterine de dus: ertelenme bir karardir
node --input-type=module -e '
  const { record } = await import("'"$ROOT"'/gates/journal.ts");
  const [from, to, title, why] = process.argv.slice(1);
  record({ gate: "defer", ticket: from, artifact: `docs/sdlc/${to}/intent.md`,
           decision: "deferred", reason: `${title} → ${to}: ${why}` });
' "$FROM" "$NEW" "$TITLE" "$WHY" || {
  # KANIT YAZIMI SESSIZCE DUSMEZ. Erteleme bir karardir: hangi is, neden,
  # hangi ticket'a devredildi. Deftere gecmezse gecmis eksik kalir ve
  # "bu neden yapilmadi" sorusunun cevabi kaybolur (dis denetim, 21 Eyl 2026).
  echo "erteleme deftere YAZILAMADI: $FROM → $NEW" >&2
  exit 12
}

echo "ertelendi: $FROM → $NEW"
echo "  $DST/intent.md (insan dolduracak)"
echo "  $BACKLINK (geri bağ)"
