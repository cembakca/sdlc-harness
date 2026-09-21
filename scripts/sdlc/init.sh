#!/usr/bin/env bash
# SDLC orkestratorunu BASKA BIR REPOYA kurar.
#
#   scripts/sdlc/init.sh                      # BU repoda project.json iskeleti uret
#   scripts/sdlc/init.sh --target /yol/repo   # orkestratoru o repoya KUR + iskeleti uret
#   scripts/sdlc/init.sh --target /yol/repo --force
#
# "Tek dosya degisir" iddiasi yalnizca YAPILANDIRMA icin dogruydu: kapilar,
# script'ler, workflow, beceriler ve CI yine elle tasinmak zorundaydi (dis
# denetimde bulundu 21 Eyl 2026). --target bunu yapar; tasidigi her dosyayi
# listeler ve sonunda kurulumu DOGRULAR.
#
# Tasimadigi tek sey karar: project.json iskeletini insan gozden gecirir.
set -uo pipefail
# Proje koku: harness'in nerede durdugundan bagimsiz (bkz. _root.sh).
_SDLC_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SDLC_CALLER_DIR/_root.sh"
ROOT="$(sdlc_root)" || exit 1

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

  echo "== orkestrator kuruluyor → $TARGET"
  COPIED=0
  copy() { # copy <kaynak-yol> — dizin ya da dosya, hedefte ayni yere
    local rel="$1" src="$ROOT/$1" dst="$TARGET/$1"
    [ -e "$src" ] || return 0
    if [ -e "$dst" ] && [ -z "$FORCE" ]; then echo "  atlandi (var): $rel"; return 0; fi
    mkdir -p "$(dirname "$dst")"
    if [ -d "$src" ]; then
      mkdir -p "$dst"
      cp -R "$src/." "$dst/"
    else
      cp "$src" "$dst"
    fi
    echo "  kuruldu: $rel"; COPIED=$((COPIED+1))
  }

  # Kapilar, script'ler, kadro, workflow, beceriler, CI. Kaynak repoya ait
  # son kalibrasyon olcumunu ve test istisnalarini hedefe tasimiyoruz.
  for source in "$ROOT"/gates/*.ts "$ROOT"/gates/*.md; do
    [ -f "$source" ] && copy "gates/$(basename "$source")"
  done
  copy gates/fixtures
  for source in "$ROOT"/scripts/sdlc/*; do
    [ -f "$source" ] || continue
    case "$(basename "$source")" in
      selftest.sh|cognee-bootstrap.sh) continue ;; # kaynak repo ve Cognee kurulumuna ozgu
    esac
    copy "scripts/sdlc/$(basename "$source")"
  done
  copy sdlc/roster.json
  copy sdlc/roster.ts
  copy sdlc/orchestrator.mjs
  copy sdlc/project.ts
  copy .claude/workflows/sdlc.js
  for sk in sdlc brd-analyst architect uat-packager; do copy ".claude/skills/$sk"; done
  copy docs/sdlc/templates
  mkdir -p "$TARGET/docs/sdlc"
  if [ ! -e "$TARGET/docs/sdlc/known-flaky.txt" ]; then
    : > "$TARGET/docs/sdlc/known-flaky.txt"
    echo "  kuruldu: docs/sdlc/known-flaky.txt (bos)"
  fi
  if [ ! -f "$TARGET/.github/workflows/sdlc-office.yml" ] || [ -n "$FORCE" ]; then
    mkdir -p "$TARGET/.github/workflows"
    cp "$ROOT/sdlc/ci.yml" "$TARGET/.github/workflows/sdlc-office.yml"
    echo "  kuruldu: .github/workflows/sdlc-office.yml"
  fi

  # Make hedefleri ayri bir dosyaya: hedefin kendi Makefile'ini EZMEYIZ.
  if [ -z "$FORCE" ] && [ -f "$TARGET/sdlc.mk" ]; then
    echo "  atlandi (var): sdlc.mk"
  else
    awk '
      /^# -+ AI-native SDLC/ { inside=1 }
      /^## --- kurum hafizasi/ { inside=0 }
      inside && /^sdlc-selftest:/ { skip=2 }
      inside && skip>0 { skip--; next }
      inside { print }
    ' "$ROOT/Makefile" > "$TARGET/sdlc.mk"
    echo "  kuruldu: sdlc.mk  (Makefile'ina ekle:  include sdlc.mk)"
  fi

  echo "== $COPIED oge kuruldu"
  echo ""
  echo "== iskelet uretiliyor (hedef repoda)"
  "$TARGET/scripts/sdlc/init.sh" $FORCE || exit $?

  echo ""
  echo "== kurulum dogrulanıyor (hedef repoda, modelsiz)"
  ( cd "$TARGET" && node sdlc/roster.ts --check && node gates/chain.ts >/dev/null && node scripts/sdlc/workflow-dryrun.mjs && node -e 'JSON.parse(require("fs").readFileSync("sdlc/project.json"))' )
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
  echo "  3. Makefile: include sdlc.mk"
  echo "  4. hafiza opsiyonel; MEMORY_AUTOSTART=0 varsayilandir"
  exit "$RC"
fi

OUT="$ROOT/sdlc/project.json"
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
