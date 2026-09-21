#!/usr/bin/env bash
# Bir asamanin TUM deterministik olcumlerini TEK seferde yapar.
#
#   scripts/sdlc/measure.sh <TICKET> plan-stage   # atama + spec/scope/blast + onaylar
#   scripts/sdlc/measure.sh <TICKET> build-stage  # postbuild + atama
#   scripts/sdlc/measure.sh <TICKET> review-stage # review kapisi + kapsam + rubrik
#
# Neden: her olcum ayri bir ajan cagrisiyla yapiliyordu ve her ajan sistem
# promptunu, CLAUDE.md'yi (1.224 token) ve arac tanimlarini yeniden oduyordu.
# On sorgu × ~10k token = kosu basina ~100k token, hicbiri is yapmadan.
# Olcumler deterministik; bir ajanin "yorumlamasina" ihtiyaclari yok.
set -uo pipefail

# Proje koku: harness'in nerede durdugundan bagimsiz (bkz. _root.sh).
_SDLC_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SDLC_CALLER_DIR/_root.sh"
ROOT="$(sdlc_root)" || exit 1
HARNESS="$(sdlc_harness_root)"
TICKET="${1:?kullanim: measure.sh <TICKET> <asama>}"
STAGE="${2:?asama: plan-stage | build-stage | review-stage}"
DIR="$ROOT/docs/sdlc/$TICKET"

# JSON alan yazicisi: cikti tek bir nesne olsun, ajan ayristirmasin.
# Kapilar normalde 10 (insan) ya da 20 (blok) ile cikar — bu bir HATA DEGIL,
# karardir. "cmd || yedek" kalibi iyi ciktiyi tam da kapi calistiginda eziyordu
# (olculdu 21 Eyl 2026). Cikis kodundan BAGIMSIZ yakala, bos ise yedege dus.
run_json() {
  local out
  out="$("$@" 2>/dev/null)" || true
  if printf '%s' "$out" | head -c 1 | grep -q '{'; then printf '%s' "$out"; else printf '%s' ""; fi
}

case "$STAGE" in
  plan-stage)
    SPEC="$(run_json node "$HARNESS/gates/evaluate.ts" spec "$DIR/spec.md")"
    SCOPE="$(run_json node "$HARNESS/gates/evaluate.ts" scope "$DIR/spec.md")"
    BLAST="$(run_json node "$HARNESS/gates/evaluate.ts" blast "$DIR/plan.md")"
    ASSIGN="$(run_json node "$HARNESS/gates/assign.ts" "$TICKET")"
    [ -n "$SPEC" ]   || SPEC='{"decision":"block","reason":"spec olculemedi"}'
    [ -n "$SCOPE" ]  || SCOPE='{"decision":"block","reason":"scope olculemedi"}'
    [ -n "$BLAST" ]  || BLAST='{"decision":"unknown","reason":"plan yok"}'
    [ -n "$ASSIGN" ] || ASSIGN='{}' 
    OK_SCOPE="$("$HARNESS/scripts/sdlc/approve.sh" --check "$TICKET" scope 2>/dev/null || true)"
    OK_BLAST="$("$HARNESS/scripts/sdlc/approve.sh" --check "$TICKET" blast 2>/dev/null || true)"
    node --input-type=module -e '
      const [spec, scope, blast, assign, okScope, okBlast] = process.argv.slice(1);
      const j = (s) => { try { return JSON.parse(s) } catch { return { decision: "unknown", raw: String(s).slice(0,200) } } };
      console.log(JSON.stringify({
        gates: { spec: j(spec), scope: j(scope), blast: j(blast) },
        approvals: { scope: okScope || null, blast: okBlast || null },
        assignment: j(assign),
      }, null, 2));
    ' "$SPEC" "$SCOPE" "$BLAST" "$ASSIGN" "$OK_SCOPE" "$OK_BLAST"
    ;;

  build-stage)
    PB="$(run_json node "$HARNESS/gates/postbuild.ts" "$TICKET")"
    [ -n "$PB" ] || PB='{"decision":"block","problems":["postbuild kosmadi"]}' 
    LINT="$("$HARNESS/scripts/sdlc/commit-lint.sh" "$TICKET" 2>&1 || true)"
    ASSIGN="$(run_json node "$HARNESS/gates/assign.ts" "$TICKET")"
    [ -n "$ASSIGN" ] || ASSIGN='{}'
    node --input-type=module -e '
      const [pb, lint, assign] = process.argv.slice(1);
      const j = (s) => { try { return JSON.parse(s) } catch { return { decision: "unknown" } } };
      console.log(JSON.stringify({
        postbuild: j(pb),
        commits: String(lint).trim().split("\n").slice(0, 6),
        assignment: j(assign),
      }, null, 2));
    ' "$PB" "$LINT" "$ASSIGN"
    ;;

  review-stage)
    SCOPE_TXT="$("$HARNESS/scripts/sdlc/review-scope.sh" "$TICKET" 2>/dev/null || echo FULL)"
    LADDER="$(node --input-type=module -e '
      const m = await import("'"$HARNESS"'/gates/questions.ts");
      console.log(m.reviewSeverityLadder());
    ' 2>/dev/null || true)"
    ASSIGN="$(run_json node "$HARNESS/gates/assign.ts" "$TICKET")"
    [ -n "$ASSIGN" ] || ASSIGN='{}'
    node --input-type=module -e '
      const [scope, ladder, assign] = process.argv.slice(1);
      const j = (s) => { try { return JSON.parse(s) } catch { return {} } };
      console.log(JSON.stringify({ reviewScope: scope, severityLadder: ladder, assignment: j(assign) }, null, 2));
    ' "$SCOPE_TXT" "$LADDER" "$ASSIGN"
    ;;

  *) echo "bilinmeyen asama: $STAGE" >&2; exit 1 ;;
esac
