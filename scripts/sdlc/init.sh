#!/usr/bin/env bash
# SDLC harness'ini BASKA BIR REPOYA baglar.
#
#   scripts/sdlc/init.sh                      # BU repoda project.json iskeleti uret
#   scripts/sdlc/init.sh --target /yol/repo   # harness'i submodule olarak BAGLA + iskelet
#   scripts/sdlc/init.sh --target /yol/repo --force
#
# Once kopyaliyordu. Kopya, harness guncellendiginde sessizce eskiyen ikinci bir
# kaynaktir: hedef repo yesil gorunurken eski kapilari zorlar. Artik submodule
# bir SURUM isaret eder; guncelleme acik bir hareket, surum de commit'te yazili.
#
# Kopyalanan tek sey projeye AIT olanlar: CI dosyasi (GitHub yalnizca
# .github/workflows'tan okur; selftest iki kopyanin ayrismasini yakalar),
# belge sablonlari ve project.json iskeleti.
#
# Tasimadigi tek sey karar: project.json iskeletini insan gozden gecirir.
set -uo pipefail
# Proje koku: harness'in nerede durdugundan bagimsiz (bkz. _root.sh).
_SDLC_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SDLC_CALLER_DIR/_root.sh"
ROOT="$(sdlc_root)" || exit 1
HARNESS="$(sdlc_harness_root)"

TARGET=""; FORCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:?--target <dizin>}"; shift 2 ;;
    --force)  FORCE="--force"; shift ;;
    *) echo "bilinmeyen secenek: $1" >&2; exit 1 ;;
  esac
done

if [ -n "$TARGET" ]; then
  TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || { echo "dizin yok: $TARGET" >&2; exit 1; }
  [ "$TARGET" = "$ROOT" ] && { echo "hedef kaynakla ayni" >&2; exit 1; }
  git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 || { echo "hedef bir git reposu degil: $TARGET" >&2; exit 1; }

  echo "== harness baglaniyor → $TARGET"

  # KOPYALAMIYORUZ. Kopya, harness guncellendiginde sessizce eskiyen ikinci bir
  # kaynak olur; hedef repo "yesil" gorunurken eski kapilari zorlar. Submodule
  # bunun yerine bir SURUM isaret eder: guncellemek acik bir hareket olur
  # (git submodule update --remote) ve hangi surumde oldugu commit'te yazar.
  SUB="${SDLC_SUBMODULE_PATH:-sdlc-harness}"
  ORIGIN="$(git -C "$HARNESS" remote get-url origin 2>/dev/null)"
  if [ -z "$ORIGIN" ]; then
    echo "harness reposunun 'origin' uzak adresi yok — once yayinlayin" >&2
    exit 1
  fi

  if [ -e "$TARGET/$SUB" ] && [ -z "$FORCE" ]; then
    echo "  atlandi (var): $SUB"
  else
    ( cd "$TARGET" && git submodule add ${FORCE:+--force} "$ORIGIN" "$SUB" ) || exit 1
    echo "  baglandi: $SUB → $ORIGIN"
  fi

  # Beceriler ve workflow proje kokunden GORUNUR olmali (.claude taranir),
  # ama tek kaynak yine submodule: sembolik bag, kopya degil.
  mkdir -p "$TARGET/.claude/skills" "$TARGET/.claude/workflows"
  for sk in sdlc brd-analyst architect uat-packager; do
    [ -e "$TARGET/.claude/skills/$sk" ] && [ -z "$FORCE" ] && continue
    rm -rf "$TARGET/.claude/skills/$sk"
    ln -s "../../$SUB/.claude/skills/$sk" "$TARGET/.claude/skills/$sk"
  done
  if [ ! -e "$TARGET/.claude/workflows/sdlc.js" ] || [ -n "$FORCE" ]; then
    rm -f "$TARGET/.claude/workflows/sdlc.js"
    ln -s "../../$SUB/.claude/workflows/sdlc.js" "$TARGET/.claude/workflows/sdlc.js"
  fi

  mkdir -p "$TARGET/docs/sdlc"
  [ -e "$TARGET/docs/sdlc/templates" ] || cp -R "$HARNESS/docs/sdlc/templates" "$TARGET/docs/sdlc/templates" 2>/dev/null
  [ -e "$TARGET/docs/sdlc/known-flaky.txt" ] || : > "$TARGET/docs/sdlc/known-flaky.txt"

  if [ ! -f "$TARGET/.github/workflows/sdlc-office.yml" ] || [ -n "$FORCE" ]; then
    mkdir -p "$TARGET/.github/workflows"
    cp "$HARNESS/sdlc/ci.yml" "$TARGET/.github/workflows/sdlc-office.yml"
    echo "  kuruldu: .github/workflows/sdlc-office.yml  (tek kopya; selftest ayrismayi yakalar)"
  fi

  echo ""
  echo "== iskelet uretiliyor (hedef repoda)"
  SDLC_PROJECT_ROOT="$TARGET" "$TARGET/$SUB/scripts/sdlc/init.sh" $FORCE || exit $?

  echo ""
  echo "== kurulum dogrulaniyor (hedef repoda, modelsiz)"
  ( cd "$TARGET" && node "$SUB/sdlc/roster.ts" --check \
      && node "$SUB/gates/chain.ts" >/dev/null \
      && node "$SUB/scripts/sdlc/workflow-dryrun.mjs" \
      && node -e 'JSON.parse(require("fs").readFileSync("sdlc/project.json"))' )
  RC=$?
  echo ""
  if [ "$RC" = "0" ]; then
    echo "KURULUM DOGRULANDI — kapilar ve durdurucular hedef repoda calisiyor."
  else
    echo "KURULUM EKSIK (exit $RC) — yukaridaki basarisiz dogrulamalari kapat." >&2
  fi
  echo ""
  echo "SIRA INSANDA:"
  echo "  1. sdlc/project.json: test komutlari, servisler, kritik yuzeyler"
  echo "  2. .claude/CLAUDE.md: bu reponun anayasasi"
  echo "  3. Makefile'a:"
  echo "       SDLC = $SUB/"
  echo "       SDLC_COMPOSE_PROJECT = <proje>-cognee"
  echo "       SDLC_PROJECT_DATASET = <proje>_project"
  echo "       include \$(SDLC)sdlc.mk"
  echo "  4. hafiza opsiyonel; MEMORY_AUTOSTART=0 varsayilandir"
  exit "$RC"
fi

OUT="$ROOT/sdlc/project.json"
# Harness ayri repoda: hedefte sdlc/ dizini hic olmayabilir.
mkdir -p "$ROOT/sdlc"
[ -f "$OUT" ] && [ -z "$FORCE" ] && { echo "zaten var: $OUT (--force ile uzerine yaz)"; exit 0; }

NAME="$(basename "$ROOT")"
STACKS=""
add_stack() { STACKS="$STACKS$1,"; }

# Python + pytest
for d in server backend api service .; do
  if [ -f "$ROOT/$d/pyproject.toml" ] || [ -f "$ROOT/$d/requirements.txt" ] || [ -d "$ROOT/$d/tests" ]; then
    PY_ROOT="$d"
    # Kok dizin ozel durum: "./tests/" gibi desenler HICBIR yolu eslestirmez,
    # cunku degisiklik listesi "tests/x.py" seklinde gelir (pilot repoda olculdu
    # 21 Eyl 2026 — uretilen yapilandirma hem gecersiz JSON hem yanlis desendi).
    PFX=""; [ "$d" = "." ] || PFX="$d/"
    add_stack "$(cat <<JSON
    {
      "name": "backend",
      "root": "$PY_ROOT",
      "changedPattern": "^$PFX",
      "deps": [".venv"],
      "envFile": ".env",
      "testSelector": {
        "testDirPattern": "^${PFX}tests/",
        "sourcePattern": "^${PFX}(app|src)/",
        "testFileGlob": "tests/test_{module}*.py"
      },
      "testCommand": "./.venv/bin/python -m pytest {files} -q",
      "soloCommand": "./.venv/bin/python -m pytest {file} -q",
      "clearEnv": [],
      "services": [],
      "infraFailurePatterns": ["Connection refused", "DockerException"]
    }
JSON
)"
    break
  fi
done

# Node / TS
for d in client frontend web app .; do
  if [ -f "$ROOT/$d/package.json" ]; then
    add_stack "$(cat <<JSON
    {
      "name": "client",
      "root": "$d",
      "changedPattern": "^$([ "$d" = "." ] && echo "" || echo "$d/")",
      "deps": ["node_modules"],
      "typecheckCommand": "npx tsc --noEmit",
      "testCommand": "$(grep -q '"vitest"' "$ROOT/$d/package.json" && echo 'npx vitest run --reporter=dot' || echo 'npm test --silent')",
      "soloCommand": "$(grep -q '"vitest"' "$ROOT/$d/package.json" && echo 'npx vitest run {file} --reporter=dot' || echo 'npm test --silent -- {file}')",
      "failureFilePattern": "[A-Za-z0-9_./-]+\\\\.tsx?"
    }
JSON
)"
    break
  fi
done

cat > "$OUT" <<JSON
{
  "\$comment": "scripts/sdlc/init.sh tarafindan uretildi — INSAN GOZDEN GECIRMELI. Tespit kesin degil: test komutlari, servisler ve kritik yuzeyler projeye gore duzeltilmeli.",
  "name": "$NAME",
  "memory": {
    "processDataset": "${NAME}_sdlc",
    "productDataset": "${NAME}_project",
    "productDocs": [$(ls "$ROOT"/README.md "$ROOT"/ROADMAP.md 2>/dev/null | sed "s|$ROOT/||" | awk '{printf "\"%s\",", $0}' | sed 's/,$//')]
  },
  "stacks": [
$(printf '%s' "${STACKS%,}")
  ],
  "criticalSurfaces": [
    "database migration / schema change",
    "authentication, session or authorization logic",
    "payment, billing or invoicing",
    "personal data (storage, export, logging, third-party transfer)",
    "secret, key or credential handling"
  ],
  "criticalPaths": [
    { "label": "database migration", "pattern": "(alembic|migrations?|schema)/" },
    { "label": "auth / session", "pattern": "(auth|session|token|jwt|permission|rbac)" },
    { "label": "payments & billing", "pattern": "(billing|payment|invoice|subscription)" },
    { "label": "secrets & credentials", "pattern": "(^|/)(secrets?|\\\\.env|sops)" },
    { "label": "production infra", "pattern": "(compose\\\\.prod|\\\\.github/workflows|k8s/)" }
  ]
}
JSON

# URETTIGINI DOGRULA. Pilot repoda olculdu (21 Eyl 2026): uretilen dosya gecersiz
# JSON'du ve bunu ancak sonraki komutlar patlayinca fark ettik.
if ! node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$OUT" 2>/dev/null; then
  echo "URETILEN DOSYA GECERSIZ JSON: $OUT" >&2
  node -e 'try{JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))}catch(e){console.error("  "+e.message)}' "$OUT" >&2
  exit 1
fi
echo "uretildi: $OUT (gecerli JSON)"
echo ""
echo "SIMDI INSAN GOZDEN GECIRSIN:"
echo "  1. test komutlari gercekten calisiyor mu (node sdlc/project.ts stack backend testCommand)"
echo "  2. testler bir servis istiyor mu (mongo/postgres/redis) → stacks[].services"
echo "  3. criticalSurfaces bu urunun gercek riskleri mi (odeme? saglik verisi? skorlama?)"
echo "  4. .claude/CLAUDE.md icindeki proje anayasasi bu repoya gore yazilmali"
echo "  5. hafizaya hangi belgeler girecek (memory.productDocs) — bunlar buluta gider"
