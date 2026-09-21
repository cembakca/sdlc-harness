#!/usr/bin/env bash
# Review fazı — build worktree'sindeki diff'e read-only, çapraz model review.
#
#   scripts/sdlc/codex-review.sh HKA-123 [security|spec]
#
# DİKKAT: bu script otomatik zincirde DEĞİL. Kadroda (sdlc/roster.json)
# reviewer_second_opinion rolü — kodu Codex yazdığı için Codex'in kendi kodunu
# denetlemesi zincire koyulmaz. İnsan şüphelendiğinde elle çağrılır.
set -euo pipefail

TICKET="${1:?usage: codex-review.sh <TICKET> [security|spec]}"
LENS="${2:-security}"
ROOT="$(git rev-parse --show-toplevel)"
DIR="$ROOT/docs/sdlc/$TICKET"
WT="${SDLC_WORKTREE_ROOT:-$ROOT/.sdlc-worktrees}/$TICKET"

[ -d "$WT" ] || { echo "worktree yok: $WT — önce build fazı" >&2; exit 20; }

case "$LENS" in
  security)
    LENS_TEXT="Adversarial security review. Focus: authz/authn gaps, input validation,
injection, secret leakage, SSRF, unsafe deserialization, and any path where personal
customer data (KVKK/GDPR scope) reaches logs, analytics or a third party. Assume the
author is competent and the bug is subtle."
    ;;
  spec)
    LENS_TEXT="Conformance review against docs/sdlc/$TICKET/spec.md and plan.md in this
worktree. Report: acceptance criteria not met, work implemented that nobody asked for,
duplicated logic, dead code, and migration/rollback safety."
    ;;
  *) echo "bilinmeyen lens: $LENS (security|spec)" >&2; exit 1 ;;
esac

codex exec review \
  -C "$WT" \
  --uncommitted \
  -o "$DIR/.codex-review-$LENS.md" \
  "$LENS_TEXT

Output rules: review only — do not fix anything. One line per finding:
\`SEVERITY | file:line | finding\` where SEVERITY is one of critical, high, medium, low.
If there are no findings, say exactly: NO FINDINGS." >&2

cat "$DIR/.codex-review-$LENS.md"
