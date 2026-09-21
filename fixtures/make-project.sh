#!/usr/bin/env bash
# Harness'in KENDINI sinadigi ornek projeyi uretir ve yolunu basar.
#
#   P="$(fixtures/make-project.sh)"                 # varsayilan: tek yigin
#   P="$(fixtures/make-project.sh coklu)"           # iki yigin, envFiles, typecheck
#   P="$(fixtures/make-project.sh monorepo)"        # ic ice yiginlar, desen onceligi
#   SDLC_PROJECT_ROOT="$P" ./scripts/sdlc/selftest.sh
#
# Neden uretiliyor, repoda durmuyor: ornek proje KENDI git deposu olmali.
# Harness reposunun icinde duran bir proje, ic ice depo olur; git onu gomulu
# repo diye uyarir ve dal/HEAD sorgulari harness'in dalini dondurur — o zaman
# "taban dal ilerledi" gibi senaryolar olcmedikleri seyi olcmus olur
# (olculdu 21 Eyl 2026: 78 kontrolden 3'u tam bu yuzden dusuyordu).
#
# Neden birden fazla BICIM: harness'in "tasinabilir" iddiasinin tek kaniti
# uzerinde kostugu projelerdi ve o da tek bir bicimdi (olculdu 22 Eyl 2026).
# Cok yiginli ve ic ice duzenler farkli kod yollarini calistirir: yigin
# secimi, desen onceligi, yigin basina ortam dosyasi, yigina ozgu triaj.
#
# Uretilen projeler bilerek KUCUK ve UCUZ: test komutlari gercek test kosmaz,
# cunku burada olculen sey hattin kendisi, projenin testleri degil.
set -euo pipefail

SHAPE="${1:-tek}"
case "$SHAPE" in
  tek|coklu|monorepo) ;;
  *) echo "bilinmeyen bicim: $SHAPE (tek|coklu|monorepo)" >&2; exit 1 ;;
esac

P="$(mktemp -d)/ornek-proje-$SHAPE"
mkdir -p "$P"/{docs/sdlc,sdlc}
cd "$P"

py_stack() { # py_stack <ad> <dizin> <desen>
  mkdir -p "$2/tests"
  printf 'def f():\n    return 1\n' > "$2/a.py"
  printf 'def test_f():\n    assert f\n' > "$2/tests/test_a.py"
  cat <<JSON
    {
      "name": "$1",
      "root": "$2",
      "changedPattern": "$3",
      "deps": [],
      "testCommand": "true",
      "soloCommand": "true",
      "failureFilePattern": "[A-Za-z0-9_./-]+\\\\.py"
    }
JSON
}

ts_stack() { # ts_stack <ad> <dizin> <desen>
  mkdir -p "$2/src"
  printf 'export const f = () => 1\n' > "$2/src/a.ts"
  printf 'NODE_ENV=test\n' > "$2/.env.test"
  cat <<JSON
    {
      "name": "$1",
      "root": "$2",
      "changedPattern": "$3",
      "deps": [],
      "envFiles": ["$2/.env.test"],
      "testCommand": "true",
      "soloCommand": "true",
      "typecheckCommand": "true",
      "failureFilePattern": "[A-Za-z0-9_./-]+\\\\.tsx?"
    }
JSON
}

case "$SHAPE" in
  tek)
    mkdir -p src tests
    printf 'def f():\n    return 1\n' > src/a.py
    printf 'def test_f():\n    assert f\n' > tests/test_a.py
    STACKS="$(cat <<JSON
    {
      "name": "app",
      "root": ".",
      "changedPattern": "^src/",
      "deps": [],
      "testCommand": "true",
      "soloCommand": "true",
      "failureFilePattern": "[A-Za-z0-9_./-]+\\\\.py"
    }
JSON
)"
    ;;
  coklu)
    STACKS="$(py_stack backend server '^server/'),
$(ts_stack client client '^client/')"
    ;;
  monorepo)
    # Ic ice: "apps/api/" hem kendi desenine hem de daha genel bir desene
    # uyabilir. Yigin secimi ILK eslesmeyi alir; sira yapilandirmada yazilidir
    # ve bu bicim o sirayi gercekten kosturur.
    STACKS="$(py_stack api apps/api '^apps/api/'),
$(ts_stack web apps/web '^apps/web/'),
$(ts_stack core packages/core '^packages/')"
    ;;
esac

cat > sdlc/project.json <<JSON
{
  "\$comment": "Harness'in kendi testleri icin urettigi ORNEK proje ($SHAPE). Gercek bir urun degil.",
  "schemaVersion": 1,
  "name": "ornek-$SHAPE",
  "memory": {
    "processDataset": "ornek_sdlc",
    "productDataset": "ornek_project",
    "productDocs": ["README.md"]
  },
  "stacks": [
$STACKS
  ],
  "criticalSurfaces": ["authentication, session or authorization logic"],
  "criticalPaths": [{ "label": "auth / session", "pattern": "(auth|session|token)" }],
  "secrets": { "allowPaths": [] }
}
JSON

echo "# Ornek proje ($SHAPE)" > README.md
printf '.sdlc-worktrees/\n' > .gitignore

git init -q -b main
git add -A
git -c user.name="harness" -c user.email="harness@local" commit -qm "ornek proje ($SHAPE)"

printf '%s\n' "$P"
