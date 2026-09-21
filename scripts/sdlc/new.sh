#!/usr/bin/env bash
# Yeni ticket: klasor + intent iskeleti + DAL + taban kaydi.
#
#   scripts/sdlc/new.sh <TICKET> ["baslik"]
#
# Dal ticket'in acilisinda dogar, build fazinda degil. Sebebi: ticket
# intent.md ile var olur; isin nereye yazilacagi o andan itibaren bellidir.
# Dali build'e birakmak, ticket ile kod arasindaki bagi build'e kadar
# gorunmez yapiyordu (olculdu 21 Eyl 2026: F4-1'in dali ticket'tan saatler
# sonra, ilk Codex kosusunda olustu).
set -uo pipefail

# Proje koku: harness'in nerede durdugundan bagimsiz (bkz. _root.sh).
_SDLC_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SDLC_CALLER_DIR/_root.sh"
ROOT="$(sdlc_root)" || exit 1
TICKET="${1:?kullanim: new.sh <TICKET> [\"baslik\"]}"
TITLE="${2:-}"
DIR="$ROOT/docs/sdlc/$TICKET"
BRANCH="sdlc/$TICKET"

case "$TICKET" in
  */*|*" "*) echo "ticket adi bosluk ya da / icermemeli: $TICKET" >&2; exit 1 ;;
esac

BASE="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
case "$BASE" in
  "sdlc/"*) echo "zaten bir ticket dalindasin ($BASE). Once taban dala don." >&2; exit 1 ;;
esac

mkdir -p "$DIR"
if [ ! -f "$DIR/intent.md" ]; then
  sed "s/<TICKET>/$TICKET/g" "$ROOT/docs/sdlc/templates/intent.md" > "$DIR/intent.md"
  [ -n "$TITLE" ] && sed -i '' "1s|.*|# Intent — $TICKET: $TITLE|" "$DIR/intent.md" 2>/dev/null || true
  echo "olusturuldu: docs/sdlc/$TICKET/intent.md"
else
  echo "zaten var: docs/sdlc/$TICKET/intent.md"
fi

printf '%s\n' "$BASE" > "$DIR/.base-branch"
echo "taban dal kaydedildi: $BASE"

if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "dal zaten var: $BRANCH"
else
  git -C "$ROOT" branch "$BRANCH" >/dev/null
  echo "dal acildi: $BRANCH (tabani $BASE)"
fi

cat <<INFO

Sirada:
  1. docs/sdlc/$TICKET/intent.md dosyasini SEN doldur (hattin tek insan-yazimi belgesi)
  2. Claude Code icinde: /sdlc $TICKET
  3. Gorunurluk istersen: make sdlc-github TICKET=$TICKET
INFO
