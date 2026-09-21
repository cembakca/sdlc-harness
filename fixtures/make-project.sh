#!/usr/bin/env bash
# Harness'in KENDINI sinadigi ornek projeyi uretir ve yolunu basar.
#
#   P="$(fixtures/make-project.sh)"
#   SDLC_PROJECT_ROOT="$P" ./scripts/sdlc/selftest.sh
#
# Neden uretiliyor, repoda durmuyor: ornek proje KENDI git deposu olmali.
# Harness reposunun icinde duran bir proje, ic ice depo olur; git onu gomulu
# repo diye uyarir ve dal/HEAD sorgulari harness'in dalini dondurur — o zaman
# "taban dal ilerledi" gibi senaryolar olcmedikleri seyi olcmus olur
# (olculdu 21 Eyl 2026: 78 kontrolden 3'u tam bu yuzden dusuyordu).
#
# Uretilen proje bilerek KUCUK ve UCUZ: test komutu gercek bir test kosmaz,
# cunku burada olculen sey hattin kendisi, projenin testleri degil.
set -euo pipefail

P="$(mktemp -d)/ornek-proje"
mkdir -p "$P"/{src,tests,docs/sdlc,sdlc}
cd "$P"

cat > sdlc/project.json <<'JSON'
{
  "$comment": "Harness'in kendi testleri icin urettigi ORNEK proje. Gercek bir urun degil.",
  "name": "ornek",
  "memory": {
    "processDataset": "ornek_sdlc",
    "productDataset": "ornek_project",
    "productDocs": ["README.md"]
  },
  "stacks": [
    {
      "name": "app",
      "root": ".",
      "changedPattern": "^src/",
      "deps": [],
      "testCommand": "true",
      "soloCommand": "true",
      "failureFilePattern": "[A-Za-z0-9_./-]+\\.py"
    }
  ],
  "criticalSurfaces": ["authentication, session or authorization logic"],
  "criticalPaths": [{ "label": "auth / session", "pattern": "(auth|session|token)" }],
  "secrets": { "allowPaths": [] }
}
JSON

echo "# Ornek proje" > README.md
echo "def f():" > src/a.py
echo "    return 1" >> src/a.py
echo "def test_f():" > tests/test_a.py
echo "    assert f" >> tests/test_a.py
printf '.sdlc-worktrees/\n' > .gitignore

git init -q -b main
git add -A
git -c user.name="harness" -c user.email="harness@local" commit -qm "ornek proje"

printf '%s\n' "$P"
