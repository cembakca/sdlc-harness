#!/usr/bin/env bash
# D4 — geri alinabilecek surumleri listeler.
#
# Geri alma, panik aninda yapilan bir is. O anda "hangi surume donsem" sorusunun
# cevabi aranmamali, ekranda durmali. Bu script main'deki son commit'lere bakip
# hangilerinin DORT imajinin da registry'de oldugunu soyler — cunku eksik imajli
# bir surume donmek, geri almanin kendisini ariza haline getirir.
#
#   scripts/releases.sh            son 10 commit
#   scripts/releases.sh 20         son 20 commit
#
# GHCR'a okuma icin `docker login ghcr.io` gerekir.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

PREFIX="${GHCR_PREFIX:-ghcr.io/cembakca/crawlens}"
LIMIT="${1:-10}"
COMPONENTS=(server crawler client landing)

GREEN=$'\033[0;32m'; DIM=$'\033[2m'; YELLOW=$'\033[1;33m'; NC=$'\033[0m'

printf "\n${DIM}%-12s %-44s %s${NC}\n" "SURUM" "COMMIT" "IMAJLAR"

git log --format='%h %s' -n "$LIMIT" main 2>/dev/null | while read -r sha subject; do
  full="$(git rev-parse "$sha")"
  present=0
  for c in "${COMPONENTS[@]}"; do
    if docker buildx imagetools inspect "${PREFIX}-${c}:sha-${full}" >/dev/null 2>&1; then
      present=$((present + 1))
    fi
  done
  label="sha-${full:0:7}"
  subject="$(echo "$subject" | cut -c1-42)"
  if [ "$present" -eq 4 ]; then
    printf "${GREEN}%-12s${NC} %-44s %s\n" "$label" "$subject" "4/4 ✓"
  elif [ "$present" -gt 0 ]; then
    printf "${YELLOW}%-12s${NC} %-44s %s\n" "$label" "$subject" "$present/4 — EKSIK"
  else
    printf "${DIM}%-12s %-44s %s${NC}\n" "$label" "$subject" "-"
  fi
done

cat <<TXT

Geri almak icin tam commit sha'si gerekir:
  make rollback RELEASE=sha-\$(git rev-parse <kisa-sha>)

TXT
