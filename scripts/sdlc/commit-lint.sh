#!/usr/bin/env bash
# Ticket dalindaki commit'ler bir ise benziyor mu.
#
#   scripts/sdlc/commit-lint.sh <TICKET>
#
# Kural (CLAUDE.md #9): bir plan gorevi = bir commit. 21 Eyl 2026'da olculdu:
# ticket dali "work in progress (merge-check)" adli tek bir sekilsiz commit
# tasiyordu — yani kendi kuralimizi kendi harness'imiz cigniyordu. Git gecmisi
# isin kaydidir; sekilsiz bir gecmis, kaydi olmayan bir is demektir.
#
# Beklenen bicim:  <TICKET>(task N): ozet
# Harness commit'leri (checkpoint, merge) muaftir — onlar is degil, altyapidir.
set -uo pipefail

# Proje koku: harness'in nerede durdugundan bagimsiz (bkz. _root.sh).
_SDLC_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SDLC_CALLER_DIR/_root.sh"
ROOT="$(sdlc_root)" || exit 1
TICKET="${1:?kullanim: commit-lint.sh <TICKET>}"
WT="${SDLC_WORKTREE:-$ROOT/.sdlc-worktrees/$TICKET}"
DIR="$ROOT/docs/sdlc/$TICKET"
BASE="$(cat "$DIR/.base-branch" 2>/dev/null || echo main)"

[ -d "$WT" ] || { echo "worktree yok: $WT" >&2; exit 20; }

MB="$(git -C "$WT" merge-base "$BASE" HEAD 2>/dev/null || true)"
[ -n "$MB" ] || { echo "taban bulunamadi ($BASE)" >&2; exit 20; }

# NOT: mapfile bash 3.2'de (macOS varsayilani) yok — satir satir okuyoruz.
SUBJECTS_RAW="$(git -C "$WT" log --no-merges --format='%s' "$MB..HEAD" 2>/dev/null || true)"
TASKS="$(grep -cE '^### [0-9]+\.' "$DIR/plan.md" 2>/dev/null || echo 0)"

work=0; harness=0; shapeless=""
while IFS= read -r s; do
  [ -n "$s" ] || continue
  case "$s" in
    "$TICKET(task "*) work=$((work+1)) ;;
    *checkpoint*|*"work in progress"*|*"merge-check"*) harness=$((harness+1)) ;;
    *) shapeless="$shapeless
  ✗ $s" ;;
  esac
done <<EOF_SUBJECTS
$SUBJECTS_RAW
EOF_SUBJECTS

echo "ticket dali: $(git -C "$WT" rev-parse --abbrev-ref HEAD) · taban: $BASE"
echo "plan gorevi: $TASKS · gorev commit'i: $work · harness commit'i: $harness"

if [ -n "$shapeless" ]; then
  echo "bicime uymayan commit'ler:$shapeless"
fi

if [ "$work" -eq 0 ]; then
  echo ""
  echo "HIC GOREV COMMIT'I YOK — is tek blok halinde duruyor. Her plan gorevi kendi"
  echo "commit'ini birakmali; aksi halde review deltasi, geri alma ve kaydin kendisi"
  echo "calismaz."
  exit 10
fi

if [ "$work" -lt "$TASKS" ]; then
  echo ""
  echo "UYARI: $TASKS gorev var, $work gorev commit'i var — bazi gorevler ayni"
  echo "commit'e sikismis ya da henuz yapilmamis olabilir."
  exit 10
fi

echo "commit disiplini: tamam"
exit 0
