#!/usr/bin/env bash
# Bir fazin GERCEKTEN hangi modelde kostugunu deftere yazar.
#
#   scripts/sdlc/ran.sh <TICKET> <rol> <model> [efor]
#
# 21 Eylul 2026'da olculdu: gates/assign.ts her role kademe atiyordu ama yalnizca
# GELISTIRICI icin zorlaniyordu (codex-build modeli oradan okuyor). Denetci ve
# test yazari icin atama sadece bir kayitti; F4-1'in review'i atanan modelde
# degil, elle yapildi ve bunu hicbir sey sormadi.
#
# "Kademe olculur" demek, olculen kademenin KOSTUGUNU da bilmek demektir.
set -uo pipefail
# Proje koku: harness'in nerede durdugundan bagimsiz (bkz. _root.sh).
_SDLC_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SDLC_CALLER_DIR/_root.sh"
ROOT="$(sdlc_root)" || exit 1
TICKET="${1:?kullanim: ran.sh <TICKET> <rol> <model> [efor]}"
ROLE="${2:?rol}"; MODEL="${3:?model}"; EFFORT="${4:-}"

node --input-type=module -e '
  const { record } = await import("'"$ROOT"'/gates/journal.ts");
  const [ticket, role, model, effort] = process.argv.slice(1);
  record({
    gate: `ran:${role}`, ticket, artifact: role, decision: "ran",
    reason: `${model}${effort ? " · " + effort : ""}`,
    measures: { model, effort },
  });
' "$TICKET" "$ROLE" "$MODEL" "$EFFORT"
