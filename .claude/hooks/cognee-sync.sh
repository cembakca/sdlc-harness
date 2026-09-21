#!/usr/bin/env bash
# Stop hook — oturum sonunda SDLC artifact'lerini kurum hafizasina yazar.
#
# Ham transcript gitmez, yalnizca kabul edilmis dosyalar: spec/plan/REVIEW/UAT.
# Hafiza bir konusma kaydi degil, kararlarin kaydi olmali.
#
# Cognee kapaliysa memory.sh sessizce cikar; hook hicbir seyi bloke etmez.
set -euo pipefail

DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
# Harness projenin icinde de olabilir (eski duzen), submodule olarak da.
MEM="$DIR/scripts/sdlc/memory.sh"
[ -x "$MEM" ] || MEM="$DIR/${SDLC_SUBMODULE_PATH:-sdlc-harness}/scripts/sdlc/memory.sh"
[ -x "$MEM" ] || exit 0
"$MEM" status >/dev/null 2>&1 || exit 0

# Is tarifleri degismisse onlari da senkronla: hafiza isi hatirlayip SURECI
# unutmamali (21 Eyl 2026'da fark edildi — graf ticket'lari biliyordu ama
# calisanlarin ne yapip ne yapmadigini bilmiyordu).
if find "$DIR/.claude/skills" -name SKILL.md -newermt '-1 day' 2>/dev/null | grep -q .; then
  "$MEM" skills >/dev/null 2>&1 || true
fi

# Son 24 saatte degismis artifact'ler
find "$DIR/docs/sdlc" -maxdepth 2 -name '*.md' -newermt '-1 day' 2>/dev/null |
  while read -r f; do
    "$MEM" remember "$f" >/dev/null 2>&1 || true
  done
exit 0
