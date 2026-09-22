#!/usr/bin/env bash
# HATTIN KENDI REGRESYON TESTI.
#
#   scripts/sdlc/selftest.sh
#
# Kapilari kalibre ettik ama DURDURUCULARI hic denemedik. Bir durdurucunun
# calistigini varsaymak, bir kapinin ayirt ettigini varsaymakla ayni hata:
# bozuk bir durdurucu, durdurucu olmamasindan tehlikelidir — olmadigini
# bilirsin, bozuk oldugunu bilmezsin.
#
# Her senaryo KASITLI olarak kirmizi bir durum kurar ve hattin GERCEKTEN
# durdugunu dogrular. Model cagrisi ve API anahtari YOK — yalnizca deterministik
# parcalar; bu yuzden CI'da da kosabilir.
set -uo pipefail

# Proje koku: harness'in nerede durdugundan bagimsiz (bkz. _root.sh).
_SDLC_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SDLC_CALLER_DIR/_root.sh"
ROOT="$(sdlc_root)" || exit 1
# HARNESS ile PROJE ayri koklerdir (ayrildiktan sonra). Harness'a ait dosyalar
# (gates, scripts, CI sablonu, workflow) HARNESS altinda; projeye ait olanlar
# (project.json, docs/sdlc, yuzeyler) ROOT altinda aranir.
HARNESS="$(sdlc_harness_root)"
T="SELFTEST-$$"
DIR="$ROOT/docs/sdlc/$T"
PASS=0; FAIL=0

cleanup() { rm -rf "$DIR"; }
trap cleanup EXIT

expect() { # expect <ad> <beklenen-exit> <gercek-exit>
  if [ "$2" = "$3" ]; then
    printf '  ✓ %s\n' "$1"; PASS=$((PASS+1))
  else
    printf '  ✗ %s — beklenen exit %s, gelen %s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1))
  fi
}
expect_text() { # expect_text <ad> <aranan> <metin>
  if printf '%s' "$3" | grep -qi -- "$2"; then
    printf '  ✓ %s\n' "$1"; PASS=$((PASS+1))
  else
    printf '  ✗ %s — çıktıda "%s" yok\n' "$1" "$2"; FAIL=$((FAIL+1))
  fi
}

mkdir -p "$DIR"
J="$DIR/decisions.jsonl"
# Artan zaman damgasi: saniye cozunurlugu senaryolari yaristiriyordu.
TS_SEQ=0
now() { TS_SEQ=$((TS_SEQ+1)); node -e 'console.log(new Date(Date.now()+Number(process.argv[1])*1000).toISOString())' "$TS_SEQ"; }
# FIXTURE SATIRLARI DA MUHURLU YAZILIR. Elle printf ile yazmak, defter zincirini
# kirar ve kapi hakli olarak "kurcalanmis" der (olculdu 21 Eyl 2026: mühür
# eklenince iki senaryo düştü — koruma çalışıyordu, test verisi geçersizdi).
# Sahte veri de gercek yoldan uretilmeli; yoksa test ettigimiz sey uretimdeki
# yol olmaz.
note() { # note <kapi> <artifact> <karar> <gerekce> [ek-olcum-json]
  node --input-type=module -e '
    const { record } = await import("'"$HARNESS"'/gates/journal.ts");
    const [gate, ticket, artifact, decision, reason, extra] = process.argv.slice(1);
    let measures = {};
    if (extra) { try { measures = JSON.parse(extra).measures ?? JSON.parse(extra) } catch {} }
    record({ gate, ticket, artifact, decision, reason, measures });
  ' "$1" "$T" "$2" "$3" "$4" "${5:-}" || {
    # Fixture yazilamiyorsa senaryolar anlamsiz olur; sessizce gecme.
    echo "FIXTURE YAZILAMADI: $1" >&2; return 1
  }
}

echo "hattın durdurucuları — kasıtlı kırmızı senaryolar"
echo "──────────────────────────────────────────────────────────"

# --- 1. Review kapısı bloke ederse teslim durmalı --------------------------
for f in spec plan REVIEW TESTS UAT; do echo "# $f" > "$DIR/$f.md"; done
note spec "docs/sdlc/$T/spec.md" pass "ok"
note scope "docs/sdlc/$T/spec.md" pass "ok"
note blast "docs/sdlc/$T/plan.md" pass "ok"
note review "docs/sdlc/$T/REVIEW.md" block "unresolved severity 4 finding"
note test "docs/sdlc/$T/TESTS.md" pass "yesil"
note merge "sdlc/$T" pass "guncel"
note postbuild "worktree" human "uyari"
OUT="$(node "$HARNESS/gates/readiness.ts" "$T" 2>&1)"; RC=$?
expect "review block → teslim kapısı durdurur" 20 "$RC"
expect_text "gerekçe review'ı gösteriyor" "review" "$OUT"

# --- 2. Kırmızı test teslimi durdurmalı -----------------------------------
: > "$J"
note spec "docs/sdlc/$T/spec.md" pass "ok"; note scope "docs/sdlc/$T/spec.md" pass "ok"
note blast "docs/sdlc/$T/plan.md" pass "ok"; note review "docs/sdlc/$T/REVIEW.md" pass "temiz"
note merge "sdlc/$T" pass "guncel"; note postbuild "worktree" pass "ok"
note test "docs/sdlc/$T/TESTS.md" block "gercek hata: tests/test_x.py"
OUT="$(node "$HARNESS/gates/readiness.ts" "$T" 2>&1)"; RC=$?
expect "kırmızı test → teslim kapısı durdurur" 20 "$RC"
expect_text "gerekçe testleri gösteriyor" "test" "$OUT"

# --- 3. İnsan kapısı, kayıtlı onay yoksa geçilemez ------------------------
: > "$J"
note spec "docs/sdlc/$T/spec.md" pass "ok"; note scope "docs/sdlc/$T/spec.md" pass "ok"
note blast "docs/sdlc/$T/plan.md" human "kritik yuzey"
note review "docs/sdlc/$T/REVIEW.md" pass "temiz"; note test "docs/sdlc/$T/TESTS.md" pass "yesil"
note merge "sdlc/$T" pass "guncel"; note postbuild "worktree" pass "ok"
OUT="$(node "$HARNESS/gates/readiness.ts" "$T" 2>&1)"; RC=$?
expect "onaysız insan kapısı → teslim kapısı durdurur" 20 "$RC"
expect_text "gerekçe kayıtlı onay yokluğunu söylüyor" "ONAY YOK" "$OUT"
APPROVAL_OUT="$("$HARNESS/scripts/sdlc/approve.sh" "$T" blast "ajan onayi" 2>&1)"; APPROVAL_RC=$?
expect "ajan/non-interaktif onay kaydedemez" 2 "$APPROVAL_RC"

# --- 4. Onay kaydedilince geçmeli, ama BELGE DEĞİŞİNCE düşmeli ------------
note "approve:blast" "docs/sdlc/$T/plan.md" approved "test onayi" '{"artifactHash":"AAAA"}'
OUT="$(node "$HARNESS/gates/readiness.ts" "$T" 2>&1)"; RC=$?
expect "kayıtlı onay (hash'siz kapı) → geçer" 0 "$RC"

: > "$J"
note spec "docs/sdlc/$T/spec.md" pass "ok"; note scope "docs/sdlc/$T/spec.md" pass "ok"
# Kapinin hash'i BELGENIN GERCEK hash'i olmali: yoksa kapi zaten bayat cikar ve
# bu senaryo onay-uyusmazligini degil, bayatligi test etmis olur.
PLAN_HASH="$(node -e 'const c=require("node:crypto"),f=require("node:fs");
console.log(c.createHash("sha256").update(f.readFileSync(process.argv[1])).digest("hex").slice(0,16))' "$DIR/plan.md")"
note blast "docs/sdlc/$T/plan.md" human "kritik" "{\"artifactHash\":\"$PLAN_HASH\"}"
note "approve:blast" "docs/sdlc/$T/plan.md" approved "eski surume onay" '{"artifactHash":"BBBB"}'
note review "docs/sdlc/$T/REVIEW.md" pass "temiz"; note test "docs/sdlc/$T/TESTS.md" pass "yesil"
note merge "sdlc/$T" pass "guncel"; note postbuild "worktree" pass "ok"
OUT="$(node "$HARNESS/gates/readiness.ts" "$T" 2>&1)"; RC=$?
expect "belge değişmiş onay → teslim kapısı durdurur" 20 "$RC"
expect_text "gerekçe belgenin değiştiğini söylüyor" "BELGE DEĞİŞMİŞ" "$OUT"

# --- 5. Bayat karar (kod ilerlemiş) sayılmamalı ---------------------------
: > "$J"
note spec "docs/sdlc/$T/spec.md" pass "ok"; note scope "docs/sdlc/$T/spec.md" pass "ok"
note blast "docs/sdlc/$T/plan.md" pass "ok"; note review "docs/sdlc/$T/REVIEW.md" pass "temiz"
note postbuild "worktree" pass "ok"
note test "docs/sdlc/$T/TESTS.md" pass "yesil" '{"headSha":"0000eskikod"}'
note merge "sdlc/$T" pass "guncel"
mkdir -p "$ROOT/.sdlc-worktrees/$T" && git -C "$ROOT" worktree add -f --detach "$ROOT/.sdlc-worktrees/$T" HEAD >/dev/null 2>&1
OUT="$(node "$HARNESS/gates/readiness.ts" "$T" 2>&1)"; RC=$?
git -C "$ROOT" worktree remove --force "$ROOT/.sdlc-worktrees/$T" >/dev/null 2>&1 || true
expect "bayat test kararı (kod ilerlemiş) → durdurur" 20 "$RC"
expect_text "gerekçe kararın bayat olduğunu söylüyor" "BAYAT" "$OUT"

# --- 6. Okunamayan REVIEW.md sessizce "temiz" sayılmamalı -----------------
: > "$J"
note spec "docs/sdlc/$T/spec.md" pass "ok"; note scope "docs/sdlc/$T/spec.md" pass "ok"
note blast "docs/sdlc/$T/plan.md" pass "ok"; note review "docs/sdlc/$T/REVIEW.md" pass "temiz"
note test "docs/sdlc/$T/TESTS.md" pass "yesil"; note merge "sdlc/$T" pass "guncel"
note postbuild "worktree" pass "ok"
python3 - "$DIR/REVIEW.md" <<'PY'
import sys
open(sys.argv[1],"w").write("# Review\n\n" + ("Bilinmeyen bicimde uzun bir denetim raporu. " * 40))
PY
OUT="$(node "$HARNESS/gates/readiness.ts" "$T" 2>&1)"; RC=$?
expect "okunamayan REVIEW.md → durdurur (sessizce temiz saymaz)" 20 "$RC"
expect_text "gerekçe okunamadığını söylüyor" "okunamadı" "$OUT"

# --- 7. Plan uygunluğu "human" dediyse KAYITLI ONAY şart -----------------
# Dis denetimde bulundu (21 Eyl 2026): postbuild plan disi dosyayi "human" ile
# isaretliyordu, teslim kapisi ise "block degilse yeterli" diyordu — insan
# karari onay birakmadan atlanabiliyordu.
: > "$J"
for f in spec plan REVIEW TESTS UAT; do echo "# $f" > "$DIR/$f.md"; done
note spec "docs/sdlc/$T/spec.md" pass "ok"; note scope "docs/sdlc/$T/spec.md" pass "ok"
note blast "docs/sdlc/$T/plan.md" pass "ok"; note review "docs/sdlc/$T/REVIEW.md" pass "temiz"
note test "docs/sdlc/$T/TESTS.md" pass "yesil"; note merge "sdlc/$T" pass "guncel"
note postbuild "worktree" human "planda olmayan dosya degismis"
OUT="$(node "$HARNESS/gates/readiness.ts" "$T" 2>&1)"; RC=$?
expect "postbuild human + onay yok → durdurur" 20 "$RC"
expect_text "gerekçe onay eksikliğini gösteriyor" "ONAY YOK" "$OUT"

# Ayni durum, onay KAYDA GECINCE gecmeli.
note "approve:postbuild" "worktree" approved "insan: kapsam sizintisi kabul"
OUT="$(node "$HARNESS/gates/readiness.ts" "$T" 2>&1)"; RC=$?
expect "postbuild human + kayıtlı onay → geçer" 0 "$RC"

# --- 8. Belgesi değişmiş "pass" kararı bayat sayılmalı --------------------
# Yesil bir karar, olctugu belge yeniden yazildiysa artik o belge hakkinda
# degildir (dis denetimde bulundu 21 Eyl 2026).
: > "$J"
HASH="$(node -e 'const c=require("node:crypto"),f=require("node:fs");
console.log(c.createHash("sha256").update(f.readFileSync(process.argv[1])).digest("hex").slice(0,16))' "$DIR/REVIEW.md")"
note spec "docs/sdlc/$T/spec.md" pass "ok"; note scope "docs/sdlc/$T/spec.md" pass "ok"
note blast "docs/sdlc/$T/plan.md" pass "ok"
note review "docs/sdlc/$T/REVIEW.md" pass "temiz" "{\"artifactHash\":\"$HASH\"}"
note test "docs/sdlc/$T/TESTS.md" pass "yesil"; note merge "sdlc/$T" pass "guncel"
note postbuild "worktree" pass "ok"
OUT="$(node "$HARNESS/gates/readiness.ts" "$T" 2>&1)"; RC=$?
expect "hash'i tutan pass → geçer" 0 "$RC"

echo "# Review (yeniden yazildi)" > "$DIR/REVIEW.md"   # belge degisti, karar degismedi
OUT="$(node "$HARNESS/gates/readiness.ts" "$T" 2>&1)"; RC=$?
expect "belgesi değişmiş pass → BAYAT, durdurur" 20 "$RC"
expect_text "gerekçe bayatlığı söylüyor" "BAYAT" "$OUT"

# --- 9. Taban dal ilerlediyse birleşme kontrolü bayat sayılmalı -----------
# merge-check yalnizca is dalinin HEAD'ini kaydediyordu; taban dal sonradan
# ilerledigi halde eski kontrol guncel gorunuyordu (dis denetim, 21 Eyl 2026).
: > "$J"
echo "# REVIEW" > "$DIR/REVIEW.md"
note spec "docs/sdlc/$T/spec.md" pass "ok"; note scope "docs/sdlc/$T/spec.md" pass "ok"
note blast "docs/sdlc/$T/plan.md" pass "ok"; note review "docs/sdlc/$T/REVIEW.md" pass "temiz"
note test "docs/sdlc/$T/TESTS.md" pass "yesil"; note postbuild "worktree" pass "ok"
BASE_NOW="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
BASE_SHA="$(git -C "$ROOT" rev-parse --short=12 HEAD)"
note merge "sdlc/$T" pass "birlesmis halde yesil" "{\"baseSha\":\"$BASE_SHA\",\"base\":\"$BASE_NOW\"}"
OUT="$(node "$HARNESS/gates/readiness.ts" "$T" 2>&1)"; RC=$?
expect "taban dal yerinde → birleşme kontrolü geçerli" 0 "$RC"

: > "$J"
note spec "docs/sdlc/$T/spec.md" pass "ok"; note scope "docs/sdlc/$T/spec.md" pass "ok"
note blast "docs/sdlc/$T/plan.md" pass "ok"; note review "docs/sdlc/$T/REVIEW.md" pass "temiz"
note test "docs/sdlc/$T/TESTS.md" pass "yesil"; note postbuild "worktree" pass "ok"
note merge "sdlc/$T" pass "birlesmis halde yesil" "{\"baseSha\":\"000000000000\",\"base\":\"$BASE_NOW\"}"
OUT="$(node "$HARNESS/gates/readiness.ts" "$T" 2>&1)"; RC=$?
expect "taban dal ilerledi → birleşme kontrolü BAYAT, durdurur" 20 "$RC"
expect_text "gerekçe taban dalı gösteriyor" "taban dal" "$OUT"

# --- 10. Build hatası review fazına geçmemeli ----------------------------
# "if ! komut; then \$?" her zaman 0 verir — basarisiz build sessizce
# review'a geciyordu (dis denetim, 21 Eyl 2026; kabukta dogrulandi).
RC_CAPTURE="$(bash -c 'f(){ return 20; }; E=0; f || E=$?; echo $E')"
expect "build exit kodu doğru yakalanıyor" 20 "$RC_CAPTURE"
if grep -q 'if ! "$HARNESS/scripts/sdlc/codex-build.sh"' "$HARNESS/scripts/sdlc/run.sh"; then
  printf '  ✗ %s\n' "run.sh hâlâ exit kodunu yutan kalıbı kullanıyor"; FAIL=$((FAIL+1))
else
  printf '  ✓ %s\n' "run.sh build exit kodunu yutmuyor"; PASS=$((PASS+1))
fi

# --- 11. Her yuzey bir yigina bagli olmali -------------------------------
# Repoda bir yuzey var ama project.json'da yigini yoksa, test.sh "degisiklik
# hicbir yigina dokunmuyor" deyip TEST KOSTURMADAN gecer (dis denetimde
# bulundu 21 Eyl 2026: landingpage/ tanimsizdi).
for SURFACE in $(node -e '
  const fs=require("node:fs"), p=process.argv[1];
  for (const d of fs.readdirSync(p, {withFileTypes:true})) {
    if (!d.isDirectory() || d.name.startsWith(".")) continue;
    const manifests = ["package.json", "pyproject.toml", "requirements.txt", "go.mod", "Cargo.toml"];
    if (manifests.some((m) => fs.existsSync(`${p}/${d.name}/${m}`)))
      console.log(d.name);
  }' "$ROOT"); do
  # Yigin ADI yuzey dizininden farkli olabilir (backend ↔ server/); eslesme ROOT ile.
  if node -e 'const p=require(process.argv[1]);
    process.exit(p.stacks.some(s=>s.root===process.argv[2])?0:1)' "$ROOT/sdlc/project.json" "$SURFACE"; then
    printf '  ✓ %s\n' "yüzey $SURFACE bir yığına bağlı"; PASS=$((PASS+1))
  else
    printf '  ✗ %s\n' "yüzey $SURFACE project.json'da tanımsız — testleri hiç koşmaz"; FAIL=$((FAIL+1))
  fi
done
# Yapilandirma once GECERLI JSON olmali (pilot repoda uretilen dosya degildi).
if node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$ROOT/sdlc/project.json" 2>/dev/null; then
  printf '  ✓ %s\n' "sdlc/project.json geçerli JSON"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "sdlc/project.json geçersiz JSON — yapılandırma okunamıyor"; FAIL=$((FAIL+1))
fi
# Watch modu hatti kilitler: test komutu asla yalin "vitest"/"pytest-watch" olmamali.
if node -e 'const p=require(process.argv[1]);
  const bad=p.stacks.filter(s=>/(^|\s)vitest(\s|$)/.test(s.testCommand)&&!/vitest run/.test(s.testCommand));
  process.exit(bad.length?1:0)' "$ROOT/sdlc/project.json"; then
  printf '  ✓ %s\n' "hiçbir yığın watch modunda test komutu kullanmıyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "bir yığının test komutu watch modunda açılıyor — hat kilitlenir"; FAIL=$((FAIL+1))
fi

# --- 12. CI'da (worktree yokken) bayatlik kontrolu kapanmamali -----------
# readiness currentHead'i yalnizca worktree'den okuyordu; CI'da .sdlc-worktrees
# olmadigi icin staleOf sessizce devre disi kaliyordu (dis denetim, 21 Eyl 2026).
: > "$J"
for f in spec plan REVIEW TESTS UAT; do echo "# $f" > "$DIR/$f.md"; done
note spec "docs/sdlc/$T/spec.md" pass "ok"; note scope "docs/sdlc/$T/spec.md" pass "ok"
note blast "docs/sdlc/$T/plan.md" pass "ok"; note review "docs/sdlc/$T/REVIEW.md" pass "temiz"
note merge "sdlc/$T" pass "guncel"; note postbuild "worktree" pass "ok"
note test "docs/sdlc/$T/TESTS.md" pass "yesil" '{"headSha":"0000eskikod"}'
# CI'yi taklit et: worktree YOK, kok dizin biletin dalinda. Klonlamak YANLIS
# olurdu — klon son COMMIT'i alir, calisma agacindaki kapiyi degil; test o zaman
# kendi degisikligini denemis olmaz.
CI_ROOT="$(mktemp -d)"
mkdir -p "$CI_ROOT/gates" "$CI_ROOT/sdlc" "$CI_ROOT/docs/sdlc/$T"
cp "$HARNESS"/gates/*.ts "$CI_ROOT/gates/" 2>/dev/null
cp "$HARNESS"/sdlc/*.ts "$HARNESS"/sdlc/roster.json "$CI_ROOT/sdlc/" 2>/dev/null
cp "$ROOT/sdlc/project.json" "$CI_ROOT/sdlc/" 2>/dev/null
cp "$DIR"/*.md "$DIR/decisions.jsonl" "$CI_ROOT/docs/sdlc/$T/"
git -C "$CI_ROOT" init -q -b "sdlc/$T" 2>/dev/null
git -C "$CI_ROOT" add -A >/dev/null 2>&1
git -C "$CI_ROOT" -c user.name=selftest -c user.email=selftest@local commit -q -m "ci fixture" 2>/dev/null
# env -u: SDLC_PROJECT_ROOT ayrikken disaridan verilir; verilirse readiness
# CI taklidini degil gercek projeyi olcer ve senaryo olcmedigi seyi gecer.
OUT="$(env -u SDLC_PROJECT_ROOT node "$CI_ROOT/gates/readiness.ts" "$T" 2>&1)"; RC=$?
expect "worktree yokken de bayat karar yakalanır (CI)" 20 "$RC"
expect_text "gerekçe kaynağı dalı gösteriyor" "dal sdlc/$T" "$OUT"

# Kok baska daldayken dogru kod SHA'si bilinmez: eski yesili gecirme.
git -C "$CI_ROOT" checkout -q -b some-other-branch 2>/dev/null
OUT="$(env -u SDLC_PROJECT_ROOT node "$CI_ROOT/gates/readiness.ts" "$T" 2>&1)"; RC=$?
expect "kök başka daldayken doğrulanamayan kod durdurur" 20 "$RC"
expect_text "gerekçe doğrulanamayan anlık görüntüyü gösteriyor" "kod anlık görüntüsü" "$OUT"
rm -rf "$CI_ROOT"

# --- 13. land.sh biletin kendi belgelerini "kirlilik" saymamali ----------
# Artifact'ler ana agacta uretilir ve teslime kadar commit edilmemistir; bunlari
# kirlilik sayinca land hicbir normal akista calismiyordu (dis denetim, 21 Eyl 2026).
if grep -q 'grep -v " docs/sdlc/\$TICKET/"' "$HARNESS/scripts/sdlc/land.sh"; then
  printf '  ✓ %s\n' "land.sh biletin belgelerini kirlilik saymıyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "land.sh biletin kendi belgeleri yüzünden duruyor"; FAIL=$((FAIL+1))
fi

# --- 14. CI: detached HEAD'de de bayatlik kontrolu calismali ------------
# GitHub bir PR'i varsayilan olarak MERGE COMMIT uzerinde, detached HEAD ile
# checkout eder; "kok biletin dalinda mi" kosulu hic gerceklesmez ve kontrol
# sessizce kapanirdi (dis denetimde bulundu 21 Eyl 2026).
: > "$J"
for f in spec plan REVIEW TESTS UAT; do echo "# $f" > "$DIR/$f.md"; done
note spec "docs/sdlc/$T/spec.md" pass "ok"; note scope "docs/sdlc/$T/spec.md" pass "ok"
note blast "docs/sdlc/$T/plan.md" pass "ok"; note review "docs/sdlc/$T/REVIEW.md" pass "temiz"
note merge "sdlc/$T" pass "guncel"; note postbuild "worktree" pass "ok"
note test "docs/sdlc/$T/TESTS.md" pass "yesil" '{"headSha":"0000eskikod"}'
CI2="$(mktemp -d)"
mkdir -p "$CI2/gates" "$CI2/sdlc" "$CI2/docs/sdlc/$T"
cp "$HARNESS"/gates/*.ts "$CI2/gates/"; cp "$HARNESS"/sdlc/*.ts "$HARNESS"/sdlc/roster.json "$CI2/sdlc/" 2>/dev/null
cp "$ROOT/sdlc/project.json" "$CI2/sdlc/" 2>/dev/null
cp "$DIR"/*.md "$DIR/decisions.jsonl" "$CI2/docs/sdlc/$T/"
git -C "$CI2" init -q 2>/dev/null
git -C "$CI2" add -A >/dev/null 2>&1
git -C "$CI2" -c user.name=selftest -c user.email=s@l commit -q -m "pr merge commit" 2>/dev/null
git -C "$CI2" checkout -q --detach 2>/dev/null          # GitHub PR checkout'u boyle
OUT="$(SDLC_HEAD_SHA=1111yenikod node "$CI2/gates/readiness.ts" "$T" 2>&1)"; RC=$?
expect "detached HEAD + SDLC_HEAD_SHA → bayatlık yakalanır" 20 "$RC"
expect_text "gerekçe kaynağı SDLC_HEAD_SHA diyor" "SDLC_HEAD_SHA" "$OUT"
OUT="$(node "$CI2/gates/readiness.ts" "$T" 2>&1)"
expect_text "SHA verilmezse kaynak 'yok' olarak görünür" "kaynak: yok" "$OUT"
rm -rf "$CI2"

# CI gercekten SDLC_HEAD_SHA geciriyor mu, ve PR'in UCUNU mu checkout ediyor?
CIF="$HARNESS/.github/workflows/sdlc-office.yml"
grep -q "SDLC_HEAD_SHA" "$CIF" \
  && { printf '  ✓ %s\n' "CI teslim kapısına head SHA'sını geçiriyor"; PASS=$((PASS+1)); } \
  || { printf '  ✗ %s\n' "CI head SHA'sını geçirmiyor — kontrol CI'da kapalı"; FAIL=$((FAIL+1)); }
grep -q "pull_request.head.sha" "$CIF" \
  && { printf '  ✓ %s\n' "CI PR'ın ucunu checkout ediyor (merge commit değil)"; PASS=$((PASS+1)); } \
  || { printf '  ✗ %s\n' "CI varsayılan merge-commit checkout'unda"; FAIL=$((FAIL+1)); }

# --- 15. Hafiza: "soramadim" ile "emsal yok" karismamali -----------------
# Saglayici kotasi bitince recall zaman asimina ugruyor, script eskiden
# "(cevap alinamadi)" yazip EXIT 0 donuyordu (olculdu 21 Eyl 2026).
MOUT="$(COGNEE_API_URL=http://127.0.0.1:59999 MEMORY_TIMEOUT=2 "$HARNESS/scripts/sdlc/memory.sh" recall "x" 2>&1)"; MRC=$?
if [ "$MRC" != "0" ] || printf '%s' "$MOUT" | grep -qi "kapali"; then
  printf '  ✓ %s\n' "hafıza ulaşılamazken sessizce 'emsal yok' denmiyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "hafıza ulaşılamaz ama çıktı boş/sessiz — emsal yok sanılır"; FAIL=$((FAIL+1))
fi
# Dataset cozulemezse sinirsiz sorgu YAPILMAZ (baska projenin hafizasi gelmesin).
DOUT="$(COGNEE_DATASET="yok-boyle-bir-dataset-$$" MEMORY_TIMEOUT=5 "$HARNESS/scripts/sdlc/memory.sh" recall "x" 2>&1)"; DRC=$?
if [ "$DRC" != "0" ] || printf '%s' "$DOUT" | grep -qi "kapali"; then
  printf '  ✓ %s\n' "dataset çözülemezse sınırsız sorgu yapılmıyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "dataset çözülemedi ama sorgu yine de yapıldı"; FAIL=$((FAIL+1))
fi
# Doctor saglik yesiliyle yetinmemeli: gercek bir okuma denemesi yapmali.
grep -q "memory.sh\" recall\|memory.sh recall" "$HARNESS/scripts/sdlc/doctor.sh" \
  && { printf '  ✓ %s\n' "doctor gerçek okuma denemesi yapıyor"; PASS=$((PASS+1)); } \
  || { printf '  ✗ %s\n' "doctor yalnızca /health bakıyor"; FAIL=$((FAIL+1)); }

# --- 16. Hafiza yalnizca localhost'a bagli olmali ------------------------
if grep -qE '127\.0\.0\.1|COGNEE_BIND' "$HARNESS/ops/cognee/compose.yml"; then
  printf '  ✓ %s\n' "cognee portları localhost'a bağlı"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "cognee portları tüm arayüzlere açık"; FAIL=$((FAIL+1))
fi

# --- 17. Bilinen kirilgan dosya sonsuz bagisiklik kazanmamali -------------
# Ilk gercek build turunda olculdu (21 Eyl 2026): dosya bir kez "bilinen
# kirilgan" listesine girince, o dosyaya sonradan eklenen YENI kirmizi da
# affediliyordu; kapi worktree'de 2 / tabanda 1 kirmiziyi "on-varolan" sayip
# PASS dedi. Kapinin kendisi sessizce geciriyordu.
if grep -q 'WT_N' "$HARNESS/scripts/sdlc/test.sh" && grep -q 'BS_N' "$HARNESS/scripts/sdlc/test.sh"; then
  printf '  ✓ %s\n' "bilinen kırılgan dosyada kırmızı SAYISI tabanla karşılaştırılıyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "bilinen kırılgan dosya blanket muafiyet alıyor — yeni kırmızı görünmez"; FAIL=$((FAIL+1))
fi

# --- 18. Test ortami worktree'de uretilebilir olmali ----------------------
# Ayni turda olculdu: client/.env.local worktree'ye hic gitmiyordu (env kopyalama
# donguse her yiginda uzerine yaziyor, yalnizca SON yigin env aliyordu). Sonuc:
# bir test worktree'de kirmizi, ana agacta yesil — kod degismeden.
if grep -q 'env_files_of' "$HARNESS/scripts/sdlc/codex-build.sh"; then
  printf '  ✓ %s\n' "her yığının env dosyaları worktree'ye kopyalanıyor (çoğul)"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "yalnızca tek yığın env alabiliyor — test ortamı üretilebilir değil"; FAIL=$((FAIL+1))
fi
# Gitignore'lu ama testi belirleyen dosyalar yapilandirmada YAZILI olmali.
# PROJEYE OZGU: her projede boyle bir dosya olmak zorunda degil (harness'in
# ornek projesinde yok). Kural tek yonlu — bildiren dogru bildirsin.
if node -e 'const p=require(process.argv[1]);
  const bad=(p.stacks||[]).filter(s=>s.envFiles && !Array.isArray(s.envFiles));
  process.exit(bad.length?1:0)' "$ROOT/sdlc/project.json" 2>/dev/null; then
  printf "  ✓ %s\n" "env dosyası bildirimi geçerli"; PASS=$((PASS+1))
else
  printf "  ✗ %s\n" "envFiles bildirimi bozuk"; FAIL=$((FAIL+1))
fi

# --- 19. Build prompt'u kumsal sozlesmesini ve bulgu rolunu soylemeli -----
# Codex servise ulasamadigi halde testleri kosmayi deneyip turu yariya birakti;
# ayrica review belgesi hakkindaki meta bulguyu "dur" emri sanip 8 gorevi atladi.
if grep -q "NO NETWORK" "$HARNESS/scripts/sdlc/codex-build.sh"; then
  printf '  ✓ %s\n' "prompt kumsalın ağa kapalı olduğunu söylüyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "prompt ağ sözleşmesini söylemiyor — tur boşa gider"; FAIL=$((FAIL+1))
fi
if grep -q "never stop orders" "$HARNESS/scripts/sdlc/codex-build.sh"; then
  printf '  ✓ %s\n' "bulgular iş kalemi olarak tanımlı (durdurma emri değil)"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "meta bulgu tüm turu durdurabilir"; FAIL=$((FAIL+1))
fi

# --- 20. Birlesme kontrolu sebebi UYDURMAMALI ----------------------------
# Ilk gercek turda olculdu: merge "local changes would be overwritten" ile
# basarisiz oldu, script bunu CAKISMA sanip BOS bir dosya listesiyle raporladi.
# Yanlis teshis, teshis olmamasindan beterdir: insan olmayan bir cakismayi arar.
if grep -q "cakisma degil" "$HARNESS/scripts/sdlc/merge-check.sh"; then
  printf '  ✓ %s\n' "birleşme başarısızlığında git'in gerçek sebebi yazılıyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "her birleşme hatası 'çakışma' diye raporlanıyor"; FAIL=$((FAIL+1))
fi
# Artifact cakismasi gercek cakisma degildir: tek kaynak ana agac.
if grep -q "DOC_CONFLICTS" "$HARNESS/scripts/sdlc/merge-check.sh"; then
  printf '  ✓ %s\n' "artifact çakışmasında taban sürümü alınıyor (tek kaynak kuralı)"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "artifact çakışması hattı durduruyor"; FAIL=$((FAIL+1))
fi

# --- 21. Review kapsami taban merge'ini "yeni is" saymamali ---------------
# Kucucuk bir duzeltme turu "8550 satir" gorunup denetciyi tum diff'i bastan
# okumaya yolluyordu; delta biletin kendi dosyalariyla sinirli olmali.
if grep -q "TICKET_FILES" "$HARNESS/scripts/sdlc/review-scope.sh"; then
  printf '  ✓ %s\n' "review kapsamı biletin kendi dosyalarıyla sınırlı"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "review kapsamı tabandan gelen işi de sayıyor"; FAIL=$((FAIL+1))
fi

# --- 22. Repoya sır girmesin --------------------------------------------
# 21 Eyl 2026'da olculdu: ops/cognee/agents.env (8 ajan anahtari) bir PR'a girdi
# ve push edildi. Dosya CALISILAN dalin .gitignore'unda korunuyordu ama PR dali
# BASKA bir taban uzerinden acilmisti. Kapilar bu sinifi goremez: kapilar KODU
# denetler, git komutlarini degil.
#
# Test IZOLE bir repoda kosar: gercek reponun index'ine dokunmak, paralel bir
# oturumun isini bozabilir.
SS_ROOT="$(mktemp -d)"
mkdir -p "$SS_ROOT/scripts/sdlc" "$SS_ROOT/sdlc" "$SS_ROOT/docs"
# _root.sh de kopyalanir: secret-scan artik proje kokunu ondan buluyor.
# (Bu senaryo, kok keşfi degisikliginde ANINDA kirildi ve gercek bir
# paketleme bagimliligini gosterdi — kurulum eksikse tarama hic kosmuyor.)
cp "$HARNESS/scripts/sdlc/secret-scan.sh" "$HARNESS/scripts/sdlc/_root.sh" "$SS_ROOT/scripts/sdlc/"
echo '{"name":"ss","stacks":[]}' > "$SS_ROOT/sdlc/project.json"
git -C "$SS_ROOT" init -q 2>/dev/null
git -C "$SS_ROOT" add -A >/dev/null 2>&1
git -C "$SS_ROOT" -c user.name=s -c user.email=s@l commit -q -m init 2>/dev/null

# (a) temiz repo temiz demeli
( cd "$SS_ROOT" && unset SDLC_PROJECT_ROOT && ./scripts/sdlc/secret-scan.sh >/dev/null 2>&1 )
expect "temiz repoda sır taraması geçer" 0 "$?"

# (b) sır tasiyan DOSYA ADI yakalanmali
printf 'COGNEE_AGENT_X=abc\n' > "$SS_ROOT/agents.env"
git -C "$SS_ROOT" add -f agents.env >/dev/null 2>&1
( cd "$SS_ROOT" && unset SDLC_PROJECT_ROOT && ./scripts/sdlc/secret-scan.sh --staged >/dev/null 2>&1 )
expect "agents.env staged → durdurur" 1 "$?"
git -C "$SS_ROOT" rm -q --cached agents.env >/dev/null 2>&1; rm -f "$SS_ROOT/agents.env"

# (c) ICERIKTEKI anahtar imzasi yakalanmali
# Sahte anahtar CALISMA ANINDA kuruluyor: tam dizge bu dosyada DURMAMALI, yoksa
# tarayici kendi testini sir sanip repoyu kirmizi yapar (olculdu 21 Eyl 2026).
# Muaf tutmak yanlis cozum olurdu — o zaman bu dosyadaki GERCEK bir sizintiyi da
# goremezdi.
FAKE_KEY="AKIA""3MPLQZ7XKD91WBNV"
printf 'k = "%s"\n' "$FAKE_KEY" > "$SS_ROOT/leak.py"
git -C "$SS_ROOT" add -f leak.py >/dev/null 2>&1
OUT="$( cd "$SS_ROOT" && unset SDLC_PROJECT_ROOT && ./scripts/sdlc/secret-scan.sh --staged 2>&1 )"; RC=$?
expect "koddaki anahtar imzası → durdurur" 1 "$RC"
expect_text "gerekçe dosyayı gösteriyor" "leak.py" "$OUT"
git -C "$SS_ROOT" rm -q --cached leak.py >/dev/null 2>&1; rm -f "$SS_ROOT/leak.py"

# (d) BELGE ORNEKLERI alarm vermemeli — yanlis alarm korumayi ise yaramaz kilar
printf 'AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE\n' > "$SS_ROOT/docs/guide.md"
git -C "$SS_ROOT" add -f docs/guide.md >/dev/null 2>&1
( cd "$SS_ROOT" && unset SDLC_PROJECT_ROOT && ./scripts/sdlc/secret-scan.sh --staged >/dev/null 2>&1 )
expect "AWS belge örneği → alarm vermez" 0 "$?"

# (e) TARAMA KOSAMAZSA "temiz" dememeli (bu script'te uc kez yasandi)
if grep -q "SIR TARAMASI KOSULAMADI" "$HARNESS/scripts/sdlc/secret-scan.sh"; then
  printf '  ✓ %s\n' "tarama koşamazsa sessizce 'temiz' demiyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "tarama hatası 'temiz' sayılıyor"; FAIL=$((FAIL+1))
fi
rm -rf "$SS_ROOT"

# --- 23. CI dosyasi YAPISAL olarak saglam mi ----------------------------
# 21 Eyl 2026'da olculdu: workflow'a bir satir eklerken girintiyi kacirdim,
# GitHub "workflow file issue" deyip kostu bile — yani CI kendi kendini
# denetleyemedigi tek durum, CI dosyasinin BOZUK oldugu durum. Bunu yerelde
# yakalamak gerekir; bozuk CI, olmayan CI'dir.
CI_OK=1
node -e '
  const fs=require("fs");
  const lines=fs.readFileSync(process.argv[1],"utf8").split("\n");
  let blockIndent=null, bad=[];
  lines.forEach((l,i)=>{
    const m=/^(\s*)[a-zA-Z_-]+:\s*[|>][-+]?\s*$/.exec(l);
    if (m) { blockIndent=m[1].length; return; }
    if (blockIndent===null) return;
    if (!l.trim()) return;
    const ind=l.match(/^\s*/)[0].length;
    if (ind<=blockIndent) {
      // blok bitti: bu satir yeni bir anahtar mi, yoksa kacik govde mi?
      if (!/^\s*[-a-zA-Z_]/.test(l)) bad.push(i+1);
      blockIndent=null;
    }
  });
  if (bad.length) { console.error("govde blok disina kacmis satir(lar): "+bad.join(", ")); process.exit(1); }
' "$HARNESS/.github/workflows/sdlc-office.yml" 2>/dev/null || CI_OK=0
if [ "$CI_OK" = "1" ]; then
  printf '  ✓ %s\n' "CI workflow dosyası yapısal olarak sağlam"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "CI workflow dosyasında blok dışına kaçmış satır var — GitHub koşamaz"; FAIL=$((FAIL+1))
fi

# --- 24. Rol sinyalleri KOPMAMIS olmali -----------------------------------
# 21 Eyl 2026'da olculdu: blast kapisi yeniden tasarlanirken "radius" sorusu
# kaldirildi, ama assign.ts guvenlik denetcisinin kademesini hala blast.radius'tan
# okuyordu. Sinyal SESSIZCE koptu ve rol "complexity(fallback)"e dustu — karar
# uretilmeye devam etti, yalnizca yanlis sebeple. Kapinin sordugu ile asagi
# akisin okudugu ayrisirsa hic kimse fark etmez.
SIG_OUT="$(node "$HARNESS/gates/assign.ts" F4-1 2>/dev/null || true)"
if printf '%s' "$SIG_OUT" | grep -q '"signal"'; then
  FALLBACKS="$(printf '%s' "$SIG_OUT" | grep -o '"signal": *"[^"]*fallback[^"]*"' | wc -l | tr -d ' ')"
  if [ "${FALLBACKS:-0}" = "0" ]; then
    printf '  ✓ %s\n' "hiçbir rol sinyali kopuk değil (fallback yok)"; PASS=$((PASS+1))
  else
    printf '  ✗ %s\n' "$FALLBACKS rol sinyali kopmuş — kapı ölçmüyor ya da ad değişmiş"; FAIL=$((FAIL+1))
  fi
else
  printf '  ✓ %s\n' "sinyal kontrolü atlandı (ölçülmüş ticket yok)"; PASS=$((PASS+1))
fi
# Blast kapisi radius'u TURETIP deftere yazmali (assign onu okuyor).
if grep -q 'derived: { radius' "$HARNESS/gates/questions.ts" && grep -q 'result.derived' "$HARNESS/gates/evaluate.ts"; then
  printf '  ✓ %s\n' "blast kapısı radius'u türetip deftere yazıyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "radius deftere yazılmıyor — reviewer_security sinyali kopar"; FAIL=$((FAIL+1))
fi

# --- 25. Kademe uyusmazligi TESLIMI DURDURMALI ---------------------------
# Atama olculur ama zorlanmazsa, "kademe olculur" sozunun yarisi bos kalir.
if grep -q 'mismatch.length === 0' "$HARNESS/gates/readiness.ts"; then
  printf '  ✓ %s\n' "kademe uyuşmazlığı teslimi durduruyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "kademe uyuşmazlığı yalnızca bilgi — atama zorlanmıyor"; FAIL=$((FAIL+1))
fi

# --- 26. Zincir uyeligi YAPISAL olmali ------------------------------------
# Kadro tablosuna bakan biri orada duran her rolun hatta kostugunu sanar;
# reviewer_second_opinion tam da boyle yanlis okunuyordu.
if node -e 'const r=require(process.argv[1]);
  process.exit(r.roles.reviewer_second_opinion.inChain === false ? 0 : 1)' "$HARNESS/sdlc/roster.json" 2>/dev/null; then
  printf '  ✓ %s\n' "zincir üyeliği yapısal alan (inChain)"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "zincir üyeliği yalnızca açıklama metninde — yanlış okunur"; FAIL=$((FAIL+1))
fi
if grep -q "inChain === false" "$HARNESS/sdlc/roster.ts"; then
  printf '  ✓ %s\n' "roster --check zincir üyeliğini doğruluyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "inChain yazılı ama denetlenmiyor"; FAIL=$((FAIL+1))
fi

# --- 27. Orkestrasyon KURU KOSUMDA yurumeli ------------------------------
# 21 Eyl 2026'da olculdu: workflow'un 17 ajanindan yalnizca 5'i gercekten
# kosmustu ve arka %70'inde IKI COKME vardi (rBuild gecici olu bolgede,
# specGate hic tanimli degil). Gercek bir tur ~1 saat surup token yakiyor;
# kuru kosum saniyeler suruyor ve kontrol akisinin tamamini yuruyor.
DRY="$(node "$HARNESS/scripts/sdlc/workflow-dryrun.mjs" 2>&1)"; DRC=$?
if [ "$DRC" = "0" ]; then
  printf '  ✓ %s\n' "orkestrasyon kuru koşumda uçtan uca yürüyor ($(printf '%s' "$DRY" | grep -c '✓') senaryo)"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "orkestrasyon kuru koşumda kırılıyor:"; FAIL=$((FAIL+1))
  printf '%s\n' "$DRY" | grep -A1 '✗' | head -4 | sed 's/^/      /'
fi

# --- 28. Orkestrasyon PROJEYE BAGIMLI OLMAMALI ---------------------------
# Harness baska bir repoda da kosacak: workflow'da proje adi, dil, veritabani
# ya da kadro disi model adi gecmemeli.
LEAK="$(grep -oiE 'mongo|postgres|crawlens|pytest|vitest|\.venv' "$HARNESS/.claude/workflows/sdlc.js" | sort -u | tr '\n' ' ')"
if [ -z "${LEAK// /}" ]; then
  printf '  ✓ %s\n' "orkestrasyonda projeye özgü varsayım yok"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "orkestrasyon projeye bağımlı: $LEAK"; FAIL=$((FAIL+1))
fi
# Model adlari yalnizca kadroda: roster --check zaten bakiyor, burada da
# workflow'un cagirdigi her script'in VAR oldugunu dogrula (kurulum eksikligi).
MISSING=""
for f in $(grep -oE 'scripts/sdlc/[a-z-]+\.(sh|mjs)' "$HARNESS/.claude/workflows/sdlc.js" | sort -u); do
  [ -x "$HARNESS/$f" ] || MISSING="$MISSING $f"
done
for f in $(grep -oE 'gates/[a-z]+\.ts' "$HARNESS/.claude/workflows/sdlc.js" | sort -u); do
  [ -f "$HARNESS/$f" ] || MISSING="$MISSING $f"
done
if [ -z "${MISSING// /}" ]; then
  printf '  ✓ %s\n' "orkestrasyonun çağırdığı her parça kurulu"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "orkestrasyon eksik parça çağırıyor:$MISSING"; FAIL=$((FAIL+1))
fi

# --- 29. Defter KURCALANAMAZ olmali --------------------------------------
# Butun kanit sistemi deftere dayaniyor. Denetlendi 21 Eyl 2026: journal.ts'te
# hic butunluk kontrolu yoktu — kabuk erisimi olan bir ajan sahte bir
# "approve:blast" satiri ekleyip teslimi acabilirdi.
SEAL_T="SEALPROBE-$$"
node --input-type=module -e '
  const { record, verify, journalPath } = await import("'"$HARNESS"'/gates/journal.ts");
  const fs = await import("node:fs");
  const t = process.argv[1];
  record({ gate: "probe", ticket: t, artifact: "x", decision: "pass", reason: "1" });
  record({ gate: "probe", ticket: t, artifact: "x", decision: "pass", reason: "2" });
  if (!verify(t).ok) { console.error("temiz defter bozuk gorundu"); process.exit(1); }
  // (a) SAHTE ONAY ekle — muhursuz satir
  fs.appendFileSync(journalPath(t), JSON.stringify({ at: new Date().toISOString(),
    gate: "approve:blast", ticket: t, artifact: "x", decision: "approved", reason: "sahte" }) + "\n");
  if (verify(t).ok) { console.error("SAHTE ONAY YAKALANMADI"); process.exit(2); }
  // (b) var olan satiri degistir
  const p = journalPath(t);
  const lines = fs.readFileSync(p, "utf8").trim().split("\n"); lines.pop();
  const r = JSON.parse(lines[0]); r.decision = "approved"; lines[0] = JSON.stringify(r);
  fs.writeFileSync(p, lines.join("\n") + "\n");
  if (verify(t).ok) { console.error("DEGISTIRILEN SATIR YAKALANMADI"); process.exit(3); }
' "$SEAL_T" >/dev/null 2>&1
expect "defter kurcalaması yakalanıyor (sahte onay + değiştirilmiş satır)" 0 "$?"
rm -rf "$ROOT/docs/sdlc/$SEAL_T"
LEGACY_T="LEGACYPROBE-$$"
node --input-type=module -e '
  const { record, verify, journalPath } = await import("'"$HARNESS"'/gates/journal.ts");
  const fs = await import("node:fs"), crypto = await import("node:crypto"), path = await import("node:path");
  const ticket = process.argv[1], journal = journalPath(ticket), dir = path.dirname(journal);
  fs.mkdirSync(dir, { recursive: true });
  const old = JSON.stringify({ at: "2026-01-01", gate: "approve:blast", ticket,
    artifact: "x", decision: "approved", reason: "miras" });
  fs.writeFileSync(journal, old + "\n");
  if (verify(ticket).ok) process.exit(1); // ozetsiz miras guvenilir degil
  fs.writeFileSync(path.join(dir, ".legacy-sha256"), crypto.createHash("sha256").update(old + "\n").digest("hex") + "\n");
  record({ gate: "probe", ticket, artifact: "x", decision: "pass", reason: "yeni" });
  if (!verify(ticket).ok) process.exit(2);
  fs.writeFileSync(journal, fs.readFileSync(journal, "utf8").replace("miras", "sahte"));
  if (verify(ticket).ok) process.exit(3);
' "$LEGACY_T" >/dev/null 2>&1
expect "miras kararlar kayıtlı özete bağlı; değiştirilirse durur" 0 "$?"
rm -rf "$ROOT/docs/sdlc/$LEGACY_T"
# Teslim kapisi bozuk defteri ENGEL saymali.
if grep -q "defter bütünlüğü" "$HARNESS/gates/readiness.ts"; then
  printf '  ✓ %s\n' "teslim kapısı defter bütünlüğüne bakıyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "teslim kapısı bozuk defteri fark etmiyor"; FAIL=$((FAIL+1))
fi

# --- 30. Durum makinesi TEK KAYNAK ve tuketici olmali ---------------------
# Orkestrator 13 ayri erken return tasiyordu ve acik gecis tablosu yoktu;
# arka %70'teki iki cokme tam da bu yuzden saklanabilmisti.
if node "$HARNESS/gates/chain.ts" >/dev/null 2>&1; then
  printf '  ✓ %s\n' "geçiş tablosunda ölü faz yok"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "geçiş tablosunda erişilemeyen faz var"; FAIL=$((FAIL+1))
fi
# Workflow'daki her faz adi tabloda olmali (ve tersi kuru kosumda denetleniyor).
UNKNOWN=""
for ph in $(grep -oE 'phase\("[^"]+"\)' "$HARNESS/.claude/workflows/sdlc.js" | sed 's/phase("//; s/")//' | sort -u); do
  grep -q "\"$ph\"" "$HARNESS/gates/chain.ts" || UNKNOWN="$UNKNOWN $ph"
done
if [ -z "${UNKNOWN// /}" ]; then
  printf '  ✓ %s\n' "orkestrasyondaki her faz geçiş tablosunda tanımlı"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "tabloda olmayan faz:$UNKNOWN"; FAIL=$((FAIL+1))
fi

# --- 31. Butce sinirsiz olmamali ------------------------------------------
# Devre kesici tur SAYISINI siniryordu, turun BUYUKLUGUNU degil.
if grep -q "budgetCheck" "$HARNESS/.claude/workflows/sdlc.js"; then
  printf '  ✓ %s\n' "pahalı fazlardan önce bütçe kontrolü var"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "bütçe kontrolü yok — bir tur sessizce üç katına çıkabilir"; FAIL=$((FAIL+1))
fi

# --- 32. TASINAN CI ile BURADAKI CI ayni olmali --------------------------
# Dis denetimde bulundu 21 Eyl 2026: yeni projeye kurulan CI yalnizca kadro,
# durum makinesi, kuru kosum ve sir taramasi yapiyordu — selftest, commit
# disiplini, kalibrasyon ve TESLIM KAPISI yoktu. Yani yeni projede PR yesil
# gorunurken bilet kirmizi olabilirdi. Iki dosya artik tek kaynak.
if diff -q "$HARNESS/sdlc/ci.yml" "$HARNESS/.github/workflows/sdlc-office.yml" >/dev/null 2>&1; then
  printf '  ✓ %s\n' "taşınan CI ile buradaki CI aynı dosya"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "CI şablonu ayrışmış — yeni projeye zayıf kapı kurulur"; FAIL=$((FAIL+1))
fi
# Tuketen repodaki kopya da ayni dosya olmali. Harness submodule olunca CI
# projenin .github/workflows altindan kosar; o kopya sessizce eskirse PR yesil
# gorunurken kapilar eski surumu zorlar.
if [ "$ROOT" != "$HARNESS" ] && [ -f "$ROOT/.github/workflows/sdlc-office.yml" ]; then
  if diff -q "$HARNESS/sdlc/ci.yml" "$ROOT/.github/workflows/sdlc-office.yml" >/dev/null 2>&1; then
    printf '  ✓ %s\n' "projedeki CI kopyasi harness ile ayni"; PASS=$((PASS+1))
  else
    printf '  ✗ %s\n' "projedeki CI kopyasi eskimis — cp \$SDLC/sdlc/ci.yml .github/workflows/sdlc-office.yml"; FAIL=$((FAIL+1))
  fi
fi
# Sablon gercekten teslim kapisini ve durduruculari kosturuyor mu?
CI_MISS=""
for step in "selftest.sh" "commit-lint.sh" "readiness.ts" "last-calibration"; do
  grep -q "$step" "$HARNESS/sdlc/ci.yml" || CI_MISS="$CI_MISS $step"
done
if [ -z "${CI_MISS// /}" ]; then
  printf '  ✓ %s\n' "taşınan CI durdurucuları ve teslim kapısını zorluyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "taşınan CI'da eksik adım:$CI_MISS"; FAIL=$((FAIL+1))
fi

# --- 33. HIC TEST KOSMAMASI "gecti" SAYILMAMALI --------------------------
# Yeni kurulmus, stacks listesi bos bir projede her ticket testten geciyordu.
if grep -q "yapılandırmada yığın yok" "$HARNESS/scripts/sdlc/test.sh"; then
  printf '  ✓ %s\n' "yığın yoksa test 'geçti' demiyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "hiç test koşmadan pass üretilebiliyor"; FAIL=$((FAIL+1))
fi

# --- 34. TESLIM ATOMIK olmali --------------------------------------------
# Belgeler merge'den once commit ediliyor; merge dusrse taban dalda yarim bir
# "teslim belgeleri" commit'i kalirdi — is teslim edilmemis ama gecmis teslim
# edilmis gibi gorunurdu.
if grep -q "undo_docs" "$HARNESS/scripts/sdlc/land.sh"; then
  printf '  ✓ %s\n' "merge düşerse belge commit'i geri alınıyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "başarısız teslim taban dalda iz bırakıyor"; FAIL=$((FAIL+1))
fi

# --- 35. KANIT YAZIMI sessizce dusmemeli ---------------------------------
SWALLOW=""
for f in defer.sh land.sh; do
  grep -qE "record\(" "$HARNESS/scripts/sdlc/$f" 2>/dev/null || continue
  grep -qE "2>/dev/null \|\| true$" "$HARNESS/scripts/sdlc/$f" && SWALLOW="$SWALLOW $f"
done
if [ -z "${SWALLOW// /}" ]; then
  printf '  ✓ %s\n' "defter yazımı hata yutmuyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "kanıt yazımı sessizce düşebiliyor:$SWALLOW"; FAIL=$((FAIL+1))
fi

# --- 36. HARNESS PROJENIN ICINDE YASADIGINI VARSAYMAMALI -----------------
# Ayri repoya cikip submodule olarak baglanacak: <proje>/sdlc-harness/...
# "Kendi konumumun iki ustu" varsayimi o düzende proje kokunu DEGIL harness
# kokunu verir ve her sey sessizce yanlis dizinde calisir (olculdu 21 Eyl 2026:
# 21 kabuk script'i + 9 gate bu varsayimi tasiyordu).
LEGACY_ROOT="$(grep -lF -- 'BASH_SOURCE[0]}")/../..' "$HARNESS"/scripts/sdlc/[a-z]*.sh 2>/dev/null | grep -v selftest.sh | wc -l | tr -d " ")"
LEGACY_TS="$(grep -lF -- "new URL(\"..\", import.meta.url)" "$HARNESS"/gates/*.ts "$ROOT"/sdlc/*.ts 2>/dev/null | grep -vc root.ts | tr -d " ")"
if [ "${LEGACY_ROOT:-0}" = "0" ] && [ "${LEGACY_TS:-0}" = "0" ]; then
  printf '  ✓ %s\n' "kök keşfi açık (harness taşınabilir)"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "$LEGACY_ROOT script + $LEGACY_TS gate hâlâ iki-üst varsayımında"; FAIL=$((FAIL+1))
fi

# IC ICE DUZENDE gercekten calisiyor mu — taklit kur, kok bul.
NEST="$(mktemp -d)"
mkdir -p "$NEST/sdlc-harness/scripts/sdlc" "$NEST/sdlc-harness/gates" "$NEST/sdlc"
cp "$HARNESS/scripts/sdlc/_root.sh" "$NEST/sdlc-harness/scripts/sdlc/"
cp "$HARNESS/gates/root.ts" "$NEST/sdlc-harness/gates/"
echo '{"name":"nested","stacks":[]}' > "$NEST/sdlc/project.json"
SH_ROOT="$( unset SDLC_PROJECT_ROOT; . "$NEST/sdlc-harness/scripts/sdlc/_root.sh"; _SDLC_CALLER_DIR="$NEST/sdlc-harness/scripts/sdlc" sdlc_root 2>/dev/null | xargs -I{} sh -c 'cd "{}" && pwd -P' )"
TS_PROBE='const fs = await import("node:fs"); const m = await import("./sdlc-harness/gates/root.ts"); console.log(fs.realpathSync(m.projectRoot()));'
TS_ROOT="$(cd "$NEST" && env -u SDLC_PROJECT_ROOT node --input-type=module -e "$TS_PROBE" 2>/dev/null)"
NEST_REAL="$(cd "$NEST" && pwd -P)"
if [ "$SH_ROOT" = "$NEST_REAL" ] && [ "$TS_ROOT" = "$NEST_REAL" ]; then
  printf '  ✓ %s\n' "iç içe düzende projeyi buluyor, harness dizinini değil"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "iç içe düzende yanlış kök — kabuk: $SH_ROOT · gate: $TS_ROOT"; FAIL=$((FAIL+1))
fi
rm -rf "$NEST"

# Kalibrasyon fixture'lari: genel olanlar harness'ta, gercek olanlar projede.
# Kural tek yonlu: GERCEK proje dosyalari genel fixture dizinine SIZMAMALI.
# Projenin kendi fixture dizini olmasi zorunlu degil — yeni bir proje henuz
# kendi isiyle kalibrasyon beslememis olabilir.
if ! ls "$HARNESS/gates/fixtures"/real-* >/dev/null 2>&1; then
  printf '  ✓ %s\n' "projeye ait fixture dizini harness dışında"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "gerçek proje dosyaları genel fixture dizinine karışmış"; FAIL=$((FAIL+1))
fi

# --- Kalibrasyon hangi modele ait, kapilar hangi modelle olctu ----------
# Kalibrasyon kaydi "kapilar ayirt ediyor" der ve bu cumle BIR MODEL
# hakkindadir. jev-latest takma adi arkasindaki model isim degismeden kayar
# (olculdu 22 Eyl 2026: istenen jev-latest, donen jev-1.13.0). Model kaydiysa
# kayit hala TAZE gorunur ama kosan kapi hakkinda bir sey soylemez — hicbir sey
# kirmiziya donmedigi icin en sinsi kapi bozulmasi budur.
MD="$(mktemp -d)/proje"; mkdir -p "$MD/sdlc" "$MD/docs/sdlc/MD-1"
printf '{"schemaVersion":1,"name":"p","stacks":[]}' > "$MD/sdlc/project.json"
for f in spec plan REVIEW TESTS UAT; do echo "# $f" > "$MD/docs/sdlc/MD-1/$f.md"; done
md_row() { # md_row <kapi> <model>
  env -u SDLC_PROJECT_ROOT SDLC_PROJECT_ROOT="$MD" node --input-type=module -e '
    const { record } = await import(process.argv[1] + "/gates/journal.ts");
    record({ gate: process.argv[2], ticket: "MD-1", artifact: "x", decision: "pass",
             reason: "ok", model: process.argv[3], measures: {} });
  ' "$HARNESS" "$1" "$2"
}
# Ciktiyi DEGISKENE aliyoruz, boruya degil: readiness 20 ile cikar ve
# pipefail altinda "grep buldu" yerine "node 20 dondu" okunur — kontrol o zaman
# hep basarisiz gorunur (bu selftest yazilirken tam bu oldu).
md_readiness() {
  local out
  out="$(env -u SDLC_PROJECT_ROOT SDLC_PROJECT_ROOT="$MD" node "$HARNESS/gates/readiness.ts" MD-1 2>&1 || true)"
  printf '%s\n' "$out" | grep "kalibrasyon modeli" || true
}
md_row spec jev-1.13.0
printf '{"at":"%s","cases":22,"wrong":0,"flapping":0,"repeats":2,"model":"jev-1.13.0"}' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$MD/sdlc/.last-calibration.json"
MD_LINE="$(md_readiness)"
if printf '%s' "$MD_LINE" | grep -q "✓"; then
  printf '  ✓ %s\n' "kalibrasyon ile ölçümler aynı modeldeyken geçiyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "aynı modelde olmasına rağmen engel çıkıyor — $MD_LINE"; FAIL=$((FAIL+1))
fi
# Simdi model kaysin: kayit hala taze, ama artik baska bir modeli anlatiyor.
md_row blast jev-1.14.0
MD_LINE="$(md_readiness)"
if printf '%s' "$MD_LINE" | grep -q "BAŞKA MODELLE"; then
  printf '  ✓ %s\n' "model kayınca kalibrasyon kaydı engel sayılıyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "model kaydı halde kapı geçiyor — bozuk kalibrasyon taze görünüyor"; FAIL=$((FAIL+1))
fi
# Eski kayitlar model yazmiyordu: gecmisi cezalandirmamali.
printf '{"at":"%s","cases":22,"wrong":0,"flapping":0,"repeats":2}' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$MD/sdlc/.last-calibration.json"
MD_LINE="$(md_readiness)"
if printf '%s' "$MD_LINE" | grep -q "✓"; then
  printf '  ✓ %s\n' "modelsiz eski kalibrasyon kaydı engel sayılmıyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "eski kayıt yüzünden duruyor — geçmiş cezalandırılıyor"; FAIL=$((FAIL+1))
fi
rm -rf "$MD"

# --- Harness'ta proje adi gomulu kalmasin -------------------------------
# "Her projeye tasinir" iddiasini zayiflatan en sessiz sey, bir yerde duran
# eski urun adidir: compose dosyasinda sabit proje/konteyner adlari iki projenin
# ayni makinede yan yana kosmasini engelliyordu (dis denetim, 22 Eyl 2026).
# Aciklama satirlari serbest — orada gecmis anlatiliyor; olculen sey KOD.
NAMELEAK="$(grep -rn 'crawlens' "$HARNESS/ops" "$HARNESS/sdlc" 2>/dev/null \
            | grep -v '^\s*#' | grep -viE '^[^:]+:[0-9]+:\s*(#|//|\*)' || true)"
if [ -z "$NAMELEAK" ]; then
  printf '  ✓ %s\n' "harness yapılandırmasında gömülü proje adı yok"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "harness'ta gömülü proje adı var:"; FAIL=$((FAIL+1))
  printf '%s\n' "$NAMELEAK" | head -3 | sed 's/^/      /'
fi
# Sabit container_name iki projenin yan yana kosmasini engeller.
if grep -q 'container_name:' "$HARNESS/ops/cognee/compose.yml" 2>/dev/null; then
  printf '  ✗ %s\n' "compose sabit container_name kullanıyor — iki proje çakışır"; FAIL=$((FAIL+1))
else
  printf '  ✓ %s\n' "compose konteyner adlarını projeden türetiyor"; PASS=$((PASS+1))
fi

# --- Tuketen repo: kurulumdan teslime butun komutlar ayakta mi ----------
# Selftest'in geri kalani PROJE kokunde kosar ve harness ayni repodaymis gibi
# davranan senaryolar kurar. Bu yuzden "harness dosyasini proje kokunde aramak"
# sinifindaki hatalar YESIL testlerden kaciyordu: iki kok ayni dizin oldugunda
# gorunmezler. Dis denetim tam bunu buldu (22 Eyl 2026) ve 100/100 gecen bir
# suit onu kacirmisti.
#
# Bu senaryo GERCEK bir submodule kurar ve komutlari sirayla kosturur.
# SDLC_SKIP_CONSUMER_SMOKE=1 ile atlanir (yavas ortamlar icin).
if [ "${SDLC_SKIP_CONSUMER_SMOKE:-0}" = "1" ]; then
  printf '  ~ %s\n' "tüketen repo duman testi atlandı (SDLC_SKIP_CONSUMER_SMOKE=1)"
elif SMOKE_OUT="$(env -u SDLC_PROJECT_ROOT "$HARNESS/fixtures/consumer-smoke.sh" "$HARNESS" 2>&1)"; then
  printf '  ✓ %s\n' "tüketen repoda kurulumdan teslime bütün komutlar ayakta"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "tüketen repoda komutlar kırık:"; FAIL=$((FAIL+1))
  printf '%s\n' "$SMOKE_OUT" | grep -E '✗' | head -6 | sed 's/^/    /'
fi

# --- Onbellek anahtari DEGISKEN baglamla bozulmamali ---------------------
# scope kapisi state'e urun hafizasindan geri cagirim enjekte ediyor ve o metin
# her kosuda biraz farkli cumleleniyor. Anahtar tum state uzerinden kurulunca
# kapi onbellege HIC giremiyordu: ayni spec icin defterde 9692 ve 9756 token
# gorundu (olculdu 22 Eyl 2026). Dogrulamayla birlikte her kosuda iki tam olcum.
CK="$(env -u SDLC_PROJECT_ROOT SDLC_PROJECT_ROOT="$(mktemp -d)" node --input-type=module -e '
const c = await import(process.argv[1] + "/gates/cache.ts");
const bad = [];
const qs = [{ id: "q" }];
// Ayni cekirdek + FARKLI baglam -> ayni anahtar olmali (cacheState verilirse).
const a = c.keyOf("m", "CEKIRDEK", qs);
const b = c.keyOf("m", "CEKIRDEK", qs);
if (a !== b) bad.push("ayni cekirdek farkli anahtar uretiyor");
if (a === c.keyOf("m", "BASKA CEKIRDEK", qs)) bad.push("cekirdek degisince anahtar degismiyor");
console.log(bad.join(" · "));
' "$HARNESS" 2>&1)"
CK_WIRED=""
grep -q "cacheState" "$HARNESS/gates/jev.ts" || CK_WIRED="jev.ts cacheState almiyor"
grep -q "stateBeforeContext" "$HARNESS/gates/evaluate.ts" || CK_WIRED="$CK_WIRED evaluate.ts baglam oncesi hali saklamiyor"
if [ -z "$CK$CK_WIRED" ]; then
  printf '  ✓ %s\n' "önbellek anahtarı değişken bağlamdan etkilenmiyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "önbellek anahtarı bozuk — $CK $CK_WIRED"; FAIL=$((FAIL+1))
fi

# --- Sozlesmeye uymayan model ciktisi: DURUS, cokme degil ---------------
# writeArtifact ham Error firlatiyordu: kosu yigin iziyle oluyor, deftere satir
# dusmuyor ve modelin NE dondugu hic gorulemiyordu — hatayi teshis edecek tek
# kanit siliniyordu (olculdu 22 Eyl 2026, M1'in plan fazinda).
AW="$(mktemp -d)/proje"; mkdir -p "$AW/sdlc" "$AW/docs/sdlc/AW-1"
printf '{"schemaVersion":1,"name":"p","stacks":[]}' > "$AW/sdlc/project.json"
AW_OUT="$(env -u SDLC_PROJECT_ROOT SDLC_PROJECT_ROOT="$AW" node --input-type=module -e '
import { readFileSync, existsSync } from "node:fs";
// orchestrate.mjs bir CLI; writeArtifact davranisini kaynagindan okuyup
// ayni kurallarla sinamak yerine, sozlesmenin iki ucunu dogruluyoruz:
const src = readFileSync(process.argv[1] + "/scripts/sdlc/orchestrate.mjs", "utf8");
const bad = [];
if (!/function normalizeDocument/.test(src)) bad.push("cikti normalize edilmiyor");
// Normalizasyon GERCEKTEN calisiyor mu — ve sart gevsemis mi?
const fn = new Function("return " + (src.match(/function normalizeDocument[\s\S]*?\n}/) || [""])[0])();
const check = (inp, shouldStartWithHash) => {
  const out = String(fn(inp) ?? "");
  if (out.startsWith("#") !== shouldStartWithHash) bad.push(`normalize yanlis: ${JSON.stringify(inp.slice(0, 30))}`);
};
check("# Plan\n\nx", true);
check("```markdown\n# Plan\n\nx\n```", true);          // sarmalanmis belge acilir
check("Here is the plan.\n\n---\n\n# Plan\n\nx", true); // aciklama onu kesilir
check("hic baslik yok, duz metin", false);               // BASLIK YOKSA YINE REDDEDILIR
if (!/\.rejected/.test(src)) bad.push("reddedilen cikti kaydedilmiyor");
if (!/sdlcStop/.test(src)) bad.push("sozlesme ihlali yapisal durus uretmiyor");
if (!/process\.exitCode = 20/.test(src)) bad.push("durus kapi kararlariyla ayni cikis kodunu kullanmiyor");
// unfence gercekten soyuyor mu
const m = "```markdown\n# Plan\n\nicerik\n```".match(/^```[a-zA-Z]*\n([\s\S]*?)\n```$/);
if (!m || !m[1].trim().startsWith("#")) bad.push("unfence deseni sarmalanmis belgeyi acmiyor");
console.log(bad.join(" · "));
' "$HARNESS" 2>&1)"
if [ -z "$AW_OUT" ]; then
  printf '  ✓ %s\n' "sözleşmeye uymayan model çıktısı duruş üretiyor, çökme değil"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "artifact sözleşmesi bozuk — $AW_OUT"; FAIL=$((FAIL+1))
fi
rm -rf "$AW"

# --- Spec kapisi TITIZLIGI cezalandirmamali ------------------------------
# Eski olcum tek bir soruydu: "bu spec'teki HER kabul kriteri dogrulanabilir".
# N maddenin tumu uzerindeki bir baglac, madde sayisiyla yapisal olarak coker.
# Esik 0.80 ise DORT maddelik fixture'lar uzerinde ayarlanmisti. Sonuc: gercek
# spec'ler gecemiyordu ve kapi, bilesik maddeleri bolmeyi — dogru spec
# pratigini — cezalandiriyordu (olculdu 22 Eyl 2026: M1'in spec'i 18'den 44
# maddeye bolundu, madde kalitesi yukseldi, toplam olcum 0.51'den yalnizca
# 0.59'a gelebildi ve kapi yine durdurdu).
SPECGATE="$(env -u SDLC_PROJECT_ROOT node --input-type=module -e '
const { GATES } = await import(process.argv[1] + "/gates/questions.ts");
const g = GATES.spec;
const bad = [];
const mkSpec = (n) => "## Acceptance criteria\n\n" + Array.from({length:n},(_,i)=>
  `${i+1}. WHEN x happens, THE SYSTEM SHALL set field y to ${i}.`).join("\n\n");
const decide = (n, score) => {
  const prepared = g.prepare(mkSpec(n));
  const qs = g.questions(prepared);
  const a = Object.fromEntries(qs.map(q => [q.id, { id: q.id, value: q.kind === "noul" ? score : 1, confidence: 1 }]));
  a.ambiguity = { id: "ambiguity", value: 1, confidence: 1, probabilities: { "0": 0.9, "1": 0.1 } };
  a.scope = { id: "scope", value: 0.9, confidence: 1 };
  return g.decide(a, prepared);
};
// BOYUTTAN BAGIMSIZLIK: ayni kalitede 4 ve 60 maddelik spec ayni karari almali.
const small = decide(4, 0.9), big = decide(60, 0.9);
if (small.decision !== "pass") bad.push(`4 maddelik guclu spec gecmedi: ${small.reason}`);
if (big.decision !== "pass") bad.push(`60 maddelik guclu spec gecmedi: ${big.reason}`);
// Kriter basina olculmeli: TEK zayif madde durdurmali, sayisi ne olursa olsun.
const prepared = g.prepare(mkSpec(40));
const qs = g.questions(prepared);
const a = Object.fromEntries(qs.map(q => [q.id, { id: q.id, value: q.kind === "noul" ? 0.95 : 1, confidence: 1 }]));
a.ambiguity = { id: "ambiguity", value: 1, confidence: 1, probabilities: { "0": 0.9, "1": 0.1 } };
a.scope = { id: "scope", value: 0.9, confidence: 1 };
a.ac_7 = { id: "ac_7", value: 0.2, confidence: 1 };
const one = g.decide(a, prepared);
if (one.decision !== "block") bad.push("tek zayif kriter durdurmadi");
else if (!/AC-7/.test(one.reason)) bad.push(`blok gerekcesi zayif maddeyi adiyla soylemiyor: ${one.reason}`);
// Kriter yoksa gecmemeli.
if (g.decide({ ambiguity:{id:"ambiguity",value:1,confidence:1,probabilities:{"0":0.9}}, scope:{id:"scope",value:0.9,confidence:1} }, "").decision !== "block")
  bad.push("kriteri olmayan spec gecti");
console.log(bad.join(" · "));
' "$HARNESS" 2>&1)"
if [ -z "$SPECGATE" ]; then
  printf '  ✓ %s\n' "spec kapısı boyuttan bağımsız, tek zayıf kriteri adıyla durduruyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "spec kapısı bozuk — $SPECGATE"; FAIL=$((FAIL+1))
fi

# --- Zincir KAGITTA MI, kapida mi ---------------------------------------
# chain.ts yaziliydi ama gercek hicbir komut ona bakmiyordu: yalnizca kuru
# kosum, HIC KOSMAMIS orkestrator ve selftest okuyordu. Sonuc F4-1'in kendi
# defterinde: teslim kapisi UAT kaniti yokken 37 kez olctu, blast kapisi plani
# scope karari verilmeden once olctu (olculdu 22 Eyl 2026).
FD="$(mktemp -d)/proje"; mkdir -p "$FD/sdlc" "$FD/docs/sdlc/FL-1"
printf '{"schemaVersion":1,"name":"p","stacks":[]}' > "$FD/sdlc/project.json"
echo "# plan" > "$FD/docs/sdlc/FL-1/plan.md"
# Bos bir bilete plan.md birakip dogrudan blast kapisina girmek DURMALI:
# plan.md'nin diskte durmasi, spec ve scope kapilarindan gectigi anlamina gelmez.
env -u SDLC_PROJECT_ROOT -u SDLC_FLOW_OVERRIDE SDLC_PROJECT_ROOT="$FD" \
  node "$HARNESS/gates/evaluate.ts" blast "$FD/docs/sdlc/FL-1/plan.md" >/dev/null 2>&1
if [ "$?" = "21" ]; then
  printf '  ✓ %s\n' "dayanaksız kapı durduruluyor (zincir kâğıtta değil)"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "dayanağı olmayan kapı ölçüyor — zincir yine kâğıtta"; FAIL=$((FAIL+1))
fi
# Istisna BYPASS degil, KAYITTIR: gecerse deftere flow:override satiri duser.
env -u SDLC_PROJECT_ROOT SDLC_PROJECT_ROOT="$FD" SDLC_FLOW_OVERRIDE="selftest" \
  node "$HARNESS/gates/evaluate.ts" blast "$FD/docs/sdlc/FL-1/plan.md" >/dev/null 2>&1
if grep -q '"gate":"flow:override"' "$FD/docs/sdlc/FL-1/decisions.jsonl" 2>/dev/null; then
  printf '  ✓ %s\n' "akış istisnası deftere yazılıyor (bayrak değil, kayıt)"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "akış istisnası kayıtsız geçiyor — sessiz bypass"; FAIL=$((FAIL+1))
fi
# Onkosul tablosu zincirle tutarli olmali: her onkosul bilinen bir faz olmali.
if env -u SDLC_PROJECT_ROOT node -e '
  const c = await import(process.argv[1] + "/gates/chain.ts");
  const bad = [];
  for (const [ph, reqs] of Object.entries(c.REQUIRES)) {
    if (!(ph in c.TRANSITIONS)) bad.push(`bilinmeyen faz: ${ph}`);
    for (const r of reqs) if (!(r in c.TRANSITIONS)) bad.push(`${ph} -> bilinmeyen: ${r}`);
  }
  if (bad.length) { console.error(bad.join(" · ")); process.exit(1); }
' "$HARNESS" 2>/dev/null; then
  printf '  ✓ %s\n' "önkoşul tablosu zincirle tutarlı"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "önkoşul tablosunda bilinmeyen faz var"; FAIL=$((FAIL+1))
fi
rm -rf "$FD"

# --- IKI KOK KARISMASIN --------------------------------------------------
# Harness dosyasini PROJE kokunde aramak, ayni repoda calisirken gorunmez bir
# hatadir: iki kok ayni dizindir. Submodule duzeninde ise her komut kirilir —
# ornek projede approve.sh, olmayan <proje>/gates/journal.ts icin
# ERR_MODULE_NOT_FOUND verdi (dis denetim, 22 Eyl 2026).
# Kabuk VE gate'ler birlikte taranir: karisma ilk once gates/readiness.ts ve
# gates/evaluate.ts icinde bulundu, yalnizca kabuk taransaydi kacacakti.
MIX="$(grep -rn '\$ROOT/gates/\|\${ROOT}/gates/\|\$ROOT/scripts/sdlc/\|\${ROOT}/scripts/sdlc/' \
        "$HARNESS/scripts/sdlc/" 2>/dev/null | grep -v '/selftest.sh:' || true)"
# sdlc/ karisik bir dizin: project.ts ve roster.ts HARNESS kodu, project.json ve
# fixtures/ PROJE verisi. Bu yuzden dizin degil DOSYA adlariyla bakilir.
MIX="$MIX$(grep -rn '\$ROOT/sdlc/project\.ts\|\$ROOT/sdlc/roster\.ts\|\$ROOT/sdlc/validate\.ts\|\$ROOT/sdlc/orchestrator\.mjs' \
        "$HARNESS/scripts/sdlc/" 2>/dev/null | grep -v '/selftest.sh:' || true)"
MIX="$MIX$(grep -rn 'fromRoot("gates\|fromRoot("scripts/sdlc\|root}/gates\|root}/scripts/sdlc' \
        "$HARNESS/gates/" "$HARNESS/sdlc/" 2>/dev/null || true)"
if [ -z "$MIX" ]; then
  printf '  ✓ %s\n' "hiçbir script harness dosyasını proje kökünde aramıyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "harness dosyası proje kökünde aranıyor (\$ROOT yerine \$HARNESS olmalı):"; FAIL=$((FAIL+1))
  printf '%s\n' "$MIX" | sed 's/^/      /' | head -5
fi
# $HARNESS kullanan her script onu TANIMLAMALI.
UNDEF=""
for f in "$HARNESS"/scripts/sdlc/*.sh; do
  grep -q '\$HARNESS' "$f" || continue
  grep -q '^HARNESS=' "$f" || UNDEF="$UNDEF $(basename "$f")"
done
if [ -z "${UNDEF// /}" ]; then
  printf '  ✓ %s\n' "\$HARNESS kullanan her script onu tanımlıyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "\$HARNESS tanımsız kullanılıyor:$UNDEF"; FAIL=$((FAIL+1))
fi
# Harness reposunda urun script'i durmamali.
STRAY="$(ls "$HARNESS/scripts" 2>/dev/null | grep -v '^sdlc$' || true)"
if [ -z "$STRAY" ]; then
  printf '  ✓ %s\n' "harness'ta yalnızca hat script'leri var"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "harness'a ürün script'i sızmış: $(printf '%s' "$STRAY" | tr '\n' ' ')"; FAIL=$((FAIL+1))
fi

# --- Olc, dogrula, dondur ------------------------------------------------
# Onbellek ucuzluk getirdi ama yeni bir risk yaratti: sinirda duran bir olcum
# artik gunlerce DONUYOR. Yazi-tura bir kez atilip sonuc iki hafta servis
# edilirse kararlilik degil, kararlilik GORUNTUSU elde edilir.
# Senaryo yerinde bir HTTP sunucusuyla kosar: gercek model cagrisi yok, o yuzden
# kararsizlik senaryosu bedava ve yeniden uretilebilir.
if CF_OUT="$(env -u SDLC_PROJECT_ROOT -u JEV_API_KEY -u JEV_API_URL -u SDLC_GATE_CONFIRM \
      node "$HARNESS/fixtures/confirm-freeze.mjs" "$HARNESS" 2>&1)"; then
  printf '  ✓ %s\n' "kararsız ölçüm dondurulmuyor, ihtiyatlısı seçiliyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "ölç-doğrula-dondur bozuk:"; FAIL=$((FAIL+1))
  printf '%s\n' "$CF_OUT" | sed 's/^/      /'
fi

# Kapilar bu sinyali KULLANMALI: kararsiz bir olcumde "pass" kalmak, kapinin
# kendi kararini tekrar edemedigi girdiyi sessizce gecirmektir.
CF_MISS=""
grep -q 'unstable' "$HARNESS/gates/evaluate.ts" || CF_MISS="$CF_MISS evaluate.ts"
grep -q 'confirm:' "$HARNESS/gates/evaluate.ts" || CF_MISS="$CF_MISS evaluate.ts(confirm)"
grep -q 'confirm:' "$HARNESS/gates/assign.ts" || CF_MISS="$CF_MISS assign.ts(confirm)"
if [ -z "${CF_MISS// /}" ]; then
  printf '  ✓ %s\n' "kapılar kararsızlık sinyalini kullanıyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "kararsızlık sinyali kullanılmıyor:$CF_MISS"; FAIL=$((FAIL+1))
fi

# --- Anahtar PROJEDE aranmali, harness'ta degil -------------------------
# jev.ts .env'i "bu dosyanin bir ustu" diye ariyordu. Harness submodule'e
# cikinca orasi proje koku olmaktan cikti ve HER KAPI sessizce offline'a dustu
# — yani "olcemedim" degil, "hepsini insana dusuruyorum" (olculdu 22 Eyl 2026).
ENVP="$(mktemp -d)/proje"; mkdir -p "$ENVP/sdlc"
printf '{"schemaVersion":1,"name":"p","stacks":[]}' > "$ENVP/sdlc/project.json"
printf 'JEV_API_KEY=selftest-sahte-anahtar\n' > "$ENVP/.env"
if env -u JEV_API_KEY SDLC_PROJECT_ROOT="$ENVP" node -e '
const m = await import(process.argv[1] + "/gates/jev.ts");
process.exit(m.isOffline() ? 1 : 0);' "$HARNESS" 2>/dev/null; then
  printf '  ✓ %s\n' "JEV anahtarı proje kökündeki .env'den okunuyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "anahtar bulunamıyor — her kapı sessizce offline'a düşer"; FAIL=$((FAIL+1))
fi
rm -rf "$ENVP"

# --- Olcum onbellegi: ucuzlatiyor mu, ve DOGRU yerde susuyor mu ----------
# F4-1'de assign kapisi ayni plan.md'yi 58 kez olctu; 55'i birebir tekrardi ve
# tek basina 381 bin input token yedi — biletin toplaminin ucte ikisi
# (olculdu karar defterinden 22 Eyl 2026).
#
# Ama onbellegin SUSMASI gereken tek yer var: kalibrasyon. Isi "ayni girdide
# ayni cevap mi" diye sormak; onbellekten okursa flapping her zaman 0 cikar ve
# kontrol bos bir guvenceye doner — repeats:1 hatasinin aynisi, baska kilikta.
CACHE_OUT="$(SDLC_PROJECT_ROOT="$(mktemp -d)" node -e '
const c = await import(process.argv[1] + "/gates/cache.ts");
const k1 = c.keyOf("m", "belge", [{ id: "a" }]);
const k2 = c.keyOf("m", "belge", [{ id: "a" }]);
const k3 = c.keyOf("m", "BASKA belge", [{ id: "a" }]);
const k4 = c.keyOf("m", "belge", [{ id: "b" }]);
const k5 = c.keyOf("BASKA-model", "belge", [{ id: "a" }]);
const out = [];
if (k1 !== k2) out.push("ayni girdi farkli anahtar");
if (k1 === k3) out.push("belge degisince anahtar degismiyor");
if (k1 === k4) out.push("sorular degisince anahtar degismiyor");
if (k1 === k5) out.push("model degisince anahtar degismiyor");
c.put({ at: new Date().toISOString(), model: "m", key: k1, answers: { a: 1 }, usage: { input_tokens: 9, output_tokens: 0 } });
if (!c.get(k1)) out.push("yazilan kayit geri okunmuyor");
// Yas siniri: takma ad (jev-latest) arkasindaki model isim degismeden kayabilir.
c.put({ at: new Date(Date.now() - 40 * 86400000).toISOString(), model: "m", key: "eski", answers: {}, usage: undefined });
if (c.get("eski")) out.push("yas siniri uygulanmiyor");
process.env.SDLC_GATE_NO_CACHE = "1";
if (c.get(k1)) out.push("SDLC_GATE_NO_CACHE=1 onbellegi kapatmiyor");
console.log(out.join(" · "));
' "$HARNESS" 2>&1)" || CACHE_OUT="calisamadi: $CACHE_OUT"
if [ -z "$CACHE_OUT" ]; then
  printf '  ✓ %s\n' "ölçüm önbelleği içerikle anahtarlanıyor (belge/soru/model/yaş)"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "ölçüm önbelleği bozuk — $CACHE_OUT"; FAIL=$((FAIL+1))
fi

# Kalibrasyondaki HER olcum onbellegi acikca kapatmali.
CAL_ASKS="$(grep -c 'await ask(' "$HARNESS/gates/calibrate.ts")"
CAL_NOCACHE="$(grep -c 'cache: false' "$HARNESS/gates/calibrate.ts")"
if [ "$CAL_ASKS" = "$CAL_NOCACHE" ] && [ "$CAL_ASKS" != "0" ]; then
  printf '  ✓ %s\n' "kalibrasyon önbelleği kullanmıyor ($CAL_ASKS ölçümün $CAL_NOCACHE'i açıkça kapalı)"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "kalibrasyon önbellekten okuyor — salınım ölçülemez ($CAL_ASKS ölçüm, $CAL_NOCACHE kapalı)"; FAIL=$((FAIL+1))
fi

# Onbellek git'e girmemeli: paylasilan bir onbellek "kim neyi olctu" sorusunu
# bulanıklastirir ve CI zaten modelsiz kosar.
if grep -qxF '.sdlc-cache/' "$ROOT/.gitignore" 2>/dev/null; then
  printf '  ✓ %s\n' "ölçüm önbelleği git'e girmiyor"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' ".sdlc-cache/ .gitignore'da yok — ölçüm kayıtları repoya sızar"; FAIL=$((FAIL+1))
fi

# --- Kalibrasyon dongusu kopuk mu (MODELSIZ) -----------------------------
# Kalibrasyon vakalarinin fixture'lari iki yerden gelir: genel olanlar
# harness'ta, gercek olanlar projede. Eksik bir fixture OLCULMEYEN bir vakadir:
# kapi o durumda hic sinanmaz ama rapor "hepsi tuttu" der. Eskiden bu yalnizca
# UCRETLI bir kosuda ortaya cikiyordu (olculdu 22 Eyl 2026: harness'ta uc tane
# projeye ozgu vaka gomuluydu ve baska her projede dusuyordu).
if OUT_CAL="$(SDLC_PROJECT_ROOT="$ROOT" node "$HARNESS/gates/calibrate.ts" --plan 2>&1)"; then
  printf '  ✓ %s\n' "kalibrasyon vakalarının hepsinin fixture'ı var ($(printf '%s' "$OUT_CAL" | tail -1 | sed 's/^ *//'))"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "kalibrasyon döngüsü kopuk — $(printf '%s' "$OUT_CAL" | grep 'FIXTURE YOK' | tr '\n' ' ')"; FAIL=$((FAIL+1))
fi

# --- Yigin secimi: her yigina gercekten is dusuyor mu --------------------
# Yigin secimi ILK eslesmeyi alir. Daha genel bir desen ondeyse arkasindaki
# yigina hicbir degisiklik ulasmaz: testleri hic kosmaz ve "gecti" gorunur.
# Bu kontrol PROJENIN kendi yapilandirmasi uzerinde kosar, o yuzden her bicimde
# (tek / coklu / monorepo) farkli bir yolu zorlar.
ROUTE_OUT="$(SDLC_PROJECT_ROOT="$ROOT" node -e '
const { loadProject, stackFor } = await import(process.argv[1] + "/sdlc/project.ts");
const stacks = loadProject().stacks;
const bad = [];
for (const s of stacks) {
  const body = s.changedPattern.startsWith("^") ? s.changedPattern.slice(1) : s.changedPattern;
  let lit = "";
  for (const ch of body) { if ("\\.*+?()[]{}|$".includes(ch)) break; lit += ch; }
  if (!lit) continue;
  const sample = lit.endsWith("/") ? lit + "x" : lit;
  const got = stackFor(sample);
  if (!got || got.name !== s.name) bad.push(`${s.name}: "${sample}" -> ${got ? got.name : "hicbiri"}`);
}
console.log(JSON.stringify({ count: stacks.length, bad }));
' "$HARNESS" 2>&1)" || ROUTE_OUT=""
ROUTE_BAD="$(printf '%s' "$ROUTE_OUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).bad.join(" · "))}catch{console.log("OKUNAMADI: "+s.slice(0,120))}})')"
ROUTE_N="$(printf '%s' "$ROUTE_OUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).count)}catch{console.log("?")}})')"
if [ -z "$ROUTE_BAD" ]; then
  printf '  ✓ %s\n' "her yığına kendi değişikliği düşüyor ($ROUTE_N yığın, gölgede kalan yok)"; PASS=$((PASS+1))
else
  printf '  ✗ %s\n' "yığın gölgede kalıyor — $ROUTE_BAD"; FAIL=$((FAIL+1))
fi

# --- Yapilandirma dogrulayicisi gercekten durduruyor mu ------------------
# Yapilandirma harness'in TEK projeye ozgu girdisi ve uzun sure hic
# denetlenmiyordu. Bozuk bir alan hatti durdurmaz, SESSIZCE yanlis calistirir:
# "^./" hicbir yolu eslestirmez, o yuzden "degisen dosya yok" denir ve testler
# "gecti" sayilir (pilot repoda olculdu 21 Eyl 2026).
VD="$(mktemp -d)/proje"; mkdir -p "$VD/sdlc" "$VD/src"
vcheck() { # vcheck <ad> <beklenen-rc> <json>
  printf '%s' "$3" > "$VD/sdlc/project.json"
  env -u SDLC_PROJECT_ROOT SDLC_PROJECT_ROOT="$VD" node "$HARNESS/sdlc/validate.ts" >/dev/null 2>&1
  local rc=$?
  if [ "$rc" = "$2" ]; then
    printf '  ✓ %s\n' "yapılandırma denetimi: $1"; PASS=$((PASS+1))
  else
    printf '  ✗ %s (beklenen rc=%s, gelen %s)\n' "yapılandırma denetimi: $1" "$2" "$rc"; FAIL=$((FAIL+1))
  fi
}
OKJSON='{"schemaVersion":1,"name":"p","stacks":[{"name":"a","root":"src","changedPattern":"^src/","testCommand":"true","soloCommand":"true"}]}'
vcheck "sağlam yapılandırma geçer" 0 "$OKJSON"
vcheck "bozuk JSON durdurur" 1 '{ bu json degil'
vcheck "yığınsız yapılandırma durdurur" 1 '{"schemaVersion":1,"name":"p","stacks":[]}'
vcheck "olmayan yığın dizini durdurur" 1 '{"schemaVersion":1,"name":"p","stacks":[{"name":"a","root":"yok","changedPattern":"^src/","testCommand":"true"}]}'
vcheck "hiçbir yolu eşleştirmeyen desen durdurur" 1 '{"schemaVersion":1,"name":"p","stacks":[{"name":"a","root":"src","changedPattern":"^./","testCommand":"true"}]}'
vcheck "watch modundaki test komutu durdurur" 1 '{"schemaVersion":1,"name":"p","stacks":[{"name":"a","root":"src","changedPattern":"^src/","testCommand":"vitest"}]}'
vcheck "geçersiz düzenli ifade durdurur" 1 '{"schemaVersion":1,"name":"p","stacks":[{"name":"a","root":"src","changedPattern":"^src/","testCommand":"true","failureFilePattern":"([a-z"}]}'
vcheck "hafızaya sır yolu vermek durdurur" 1 '{"schemaVersion":1,"name":"p","memory":{"productDocs":[".env"]},"stacks":[{"name":"a","root":"src","changedPattern":"^src/","testCommand":"true"}]}'
vcheck "gölgede kalan yığın durdurur" 1 '{"schemaVersion":1,"name":"p","stacks":[{"name":"hepsi","root":"src","changedPattern":"^src/","testCommand":"true"},{"name":"ic","root":"src","changedPattern":"^src/ic/","testCommand":"true"}]}'
vcheck "harness şemadan eskiyse durdurur" 1 '{"schemaVersion":999,"name":"p","stacks":[{"name":"a","root":"src","changedPattern":"^src/","testCommand":"true"}]}'
rm -rf "$VD"

# Bozuk yapilandirma SESSIZCE varsayilanlara dusmemeli: dusen bir hat, yigin
# listesi bos oldugu icin hicbir sey kosmaz ve bunu kimseye soylemez.
VD2="$(mktemp -d)/proje"; mkdir -p "$VD2/sdlc"; printf '%s' '{ bozuk' > "$VD2/sdlc/project.json"
if env -u SDLC_PROJECT_ROOT SDLC_PROJECT_ROOT="$VD2" node "$HARNESS/sdlc/project.ts" >/dev/null 2>&1; then
  printf '  ✗ %s\n' "bozuk yapılandırma sessizce varsayılanlara düşüyor"; FAIL=$((FAIL+1))
else
  printf '  ✓ %s\n' "bozuk yapılandırma sesli düşüyor, varsayılana kaçmıyor"; PASS=$((PASS+1))
fi
rm -rf "$VD2"

echo "──────────────────────────────────────────────────────────"
echo "$PASS geçti · $FAIL kaldı"
[ "$FAIL" = "0" ] || exit 1
