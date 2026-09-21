#!/usr/bin/env bash
# Test, review ve teslim yalnizca commite alinmis kodu olcer.
set -euo pipefail
# Proje koku: harness'in nerede durdugundan bagimsiz (bkz. _root.sh).
_SDLC_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SDLC_CALLER_DIR/_root.sh"
ROOT="$(sdlc_root)" || exit 1
TICKET="${1:?kullanim: worktree-clean.sh <TICKET>}"
WT="${SDLC_WORKTREE:-$ROOT/.sdlc-worktrees/$TICKET}"
[ -d "$WT" ] || { echo "worktree yok: $WT" >&2; exit 20; }
BRANCH="$(git -C "$WT" rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" = "sdlc/$TICKET" ] || { echo "yanlis dal: $BRANCH" >&2; exit 20; }
DIRTY="$(git -C "$WT" status --porcelain --untracked-files=all -- . ':!docs/sdlc')"
[ -z "$DIRTY" ] || { echo "worktree kodu commit edilmemis:" >&2; printf '%s\n' "$DIRTY" >&2; exit 20; }
git -C "$WT" rev-parse --short=12 HEAD
