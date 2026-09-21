#!/usr/bin/env bash
# Repo -> GitHub TEK YONLU aynalama.
#
#   scripts/sdlc/sync-github.sh <TICKET> [--pr]
#
# KAYIT GIT'TE KALIR. GitHub yalnizca koordinasyon yuzeyi: durum, atama,
# gorunurluk, bildirim. Bir issue yorumu kapi kararini DEGISTIREMEZ — kapilar
# yalnizca docs/sdlc/<ticket>/ dosyalarini ve decisions.jsonl'i okur.
#
# Sebebi: onaylar belgenin hash'ine bagli ve bir denetci "hangi belge onaylandi"
# diye sordugunda cevap degismez bir commit olmali, duzenlenebilir bir issue
# govdesi degil. Iki dogru kaynak, hicbir dogru kaynak demektir.
set -uo pipefail

# Proje koku: harness'in nerede durdugundan bagimsiz (bkz. _root.sh).
_SDLC_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SDLC_CALLER_DIR/_root.sh"
ROOT="$(sdlc_root)" || exit 1
HARNESS="$(sdlc_harness_root)"
TICKET="${1:?kullanim: sync-github.sh <TICKET> [--pr]}"
WITH_PR="${2:-}"
DIR="$ROOT/docs/sdlc/$TICKET"
BRANCH="sdlc/$TICKET"

command -v gh >/dev/null || { echo "gh CLI yok" >&2; exit 1; }
[ -f "$DIR/spec.md" ] || { echo "spec yok: $DIR/spec.md" >&2; exit 20; }

SHA="$(git -C "$ROOT" rev-parse HEAD)"
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"
TITLE="$(head -1 "$DIR/spec.md" | sed 's/^# *//; s/^Spec — *//')"

# --- govde: OZET + belgelere SABITLENMIS linkler (dallar degil commit'ler) ---
summary() {
  echo "> Bu issue bir **ayna**. Doğru kaynak repo: \`docs/sdlc/$TICKET/\`."
  echo "> Kapı kararları buradaki yorumlardan değil \`decisions.jsonl\`'dan okunur."
  echo ""
  echo "## Belgeler (commit \`${SHA:0:8}\`)"
  for f in intent.md spec.md plan.md REVIEW.md TESTS.md UAT.md; do
    [ -f "$DIR/$f" ] && echo "- [\`$f\`](https://github.com/$REPO/blob/$SHA/docs/sdlc/$TICKET/$f)"
  done
  echo ""
  echo "## Kapılar"
  node --input-type=module -e '
    const { read } = await import("'"$HARNESS"'/gates/journal.ts");
    const rows = read(process.argv[1]);
    const last = {};
    for (const r of rows) if (!r.gate.startsWith("approve:")) last[r.gate] = r;
    const icon = { pass: "✅", human: "🟡", block: "⛔" };
    for (const [g, r] of Object.entries(last)) {
      console.log(`- ${icon[r.decision] ?? "•"} **${g}** — ${r.decision}: ${r.reason}`);
    }
    const approvals = rows.filter((r) => r.gate.startsWith("approve:"));
    if (approvals.length) {
      console.log("\n## İnsan onayları");
      for (const a of approvals) console.log(`- \`${a.gate.replace("approve:", "")}\` · ${a.at.slice(0,16).replace("T"," ")} · ${a.reason}`);
    }
  ' "$TICKET" 2>/dev/null || echo "_(karar defteri okunamadı)_"
}

# --- etiketler olcumlerden turer ---
labels() {
  node --input-type=module -e '
    const { read } = await import("'"$HARNESS"'/gates/journal.ts");
    const rows = read(process.argv[1]);
    const last = (g) => [...rows].reverse().find((r) => r.gate === g);
    const out = ["sdlc"];
    const blast = last("blast");
    if (blast?.measures?.radius) out.push(`blast:${blast.measures.radius}`);
    const assign = last("assign");
    if (assign?.decision) out.push(`tier:${assign.decision}`);
    const ready = last("readiness");
    out.push(ready?.decision === "pass" ? "ready" : "blocked");
    console.log(out.join(","));
  ' "$TICKET" 2>/dev/null || echo "sdlc"
}

LABELS="$(labels)"
for l in $(printf '%s' "$LABELS" | tr ',' ' '); do
  gh label create "$l" --color "ededed" --description "sdlc harness" >/dev/null 2>&1 || true
done

EXISTING="$(gh issue list --search "in:title [$TICKET]" --state all --json number,title -q '.[0].number' 2>/dev/null)"
BODY="$(summary)"

if [ -n "${EXISTING:-}" ] && [ "$EXISTING" != "null" ]; then
  gh issue edit "$EXISTING" --body "$BODY" --add-label "$LABELS" >/dev/null && \
    echo "issue guncellendi: #$EXISTING"
  ISSUE="$EXISTING"
else
  ISSUE="$(gh issue create --title "[$TICKET] $TITLE" --body "$BODY" --label "$LABELS" 2>/dev/null | grep -oE '[0-9]+$')"
  echo "issue acildi: #${ISSUE:-?}"
fi

[ "$WITH_PR" = "--pr" ] || exit 0

# --- PR: dalda commit varsa ---
git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BRANCH" || { echo "dal yok: $BRANCH"; exit 0; }
BASE="$(cat "$DIR/.base-branch" 2>/dev/null || echo main)"
AHEAD="$(git -C "$ROOT" rev-list --count "$BASE..$BRANCH" 2>/dev/null || echo 0)"
[ "$AHEAD" -gt 0 ] || { echo "dalda commit yok, PR acilmadi"; exit 0; }

git -C "$ROOT" push -u origin "$BRANCH" >/dev/null 2>&1 || { echo "push basarisiz" >&2; exit 1; }

READY="$(node "$HARNESS/gates/readiness.ts" "$TICKET" 2>&1 || true)"
PR_BODY="$(printf '%s\n\n## Teslim hazırlığı\n\n```\n%s\n```\n\nKapatır #%s\n' "$BODY" "$READY" "${ISSUE:-}")"

if gh pr view "$BRANCH" >/dev/null 2>&1; then
  gh pr edit "$BRANCH" --body "$PR_BODY" >/dev/null && echo "PR guncellendi"
else
  gh pr create --base "$BASE" --head "$BRANCH" --title "[$TICKET] $TITLE" --body "$PR_BODY" --draft 2>/dev/null \
    && echo "PR acildi (draft — teslim kapisi gecmeden hazir degil)"
fi
