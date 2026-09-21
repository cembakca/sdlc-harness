#!/usr/bin/env bash
# Hattin KOD TARAFINDAKI OMURGASI — TAM HAT DEGIL, KISMI OPERATOR YARDIMCISI.
#
# Bu script Workflow araci yokken sirayi ve kapilari koda birakir; ama ayni
# guvenceyi vermez: review, UAT ve kademe atamasi oturum gerektirir. Iki yolu
# "ayni" sanmak, zayif olanina guvenmek demektir.
#
#   scripts/sdlc/run.sh <TICKET> [--spec-only]
#
# Workflow araci olmadan da sira, kapilar ve durma kosullari kodda kalsin diye
# var. Model gerektiren fazlari (spec, plan, review, test, UAT) CALISTIRMAZ —
# onlar bir oturum ister. Onun yerine her durakta ne yapilacagini basar ve
# gecilemeyecek bir kapida DURUR.
#
# Cikis: 0 son duraga kadar geldi, 10 insan karari bekliyor, 20 kapi blokladi.
set -uo pipefail

# Proje koku: harness'in nerede durdugundan bagimsiz (bkz. _root.sh).
_SDLC_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SDLC_CALLER_DIR/_root.sh"
ROOT="$(sdlc_root)" || exit 1
HARNESS="$(sdlc_harness_root)"
TICKET="${1:?kullanim: run.sh <TICKET> [--spec-only]}"
SPEC_ONLY="${2:-}"
DIR="$ROOT/docs/sdlc/$TICKET"

say()  { printf "\n\033[1m== %s\033[0m\n" "$1"; }
need() { printf "   → %s\n" "$1"; }

gate() { # gate <ad> <artifact>
  local out code
  out="$(node "$HARNESS/gates/evaluate.ts" "$1" "$2" 2>&1)"; code=$?
  printf '%s\n' "$out" | node -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      try{const r=JSON.parse(s);console.log(`   ${r.decision.toUpperCase()} — ${r.reason}`)}
      catch{console.log("   kapı okunamadı:\n"+s.slice(0,300))}})'
  return $code
}

say "ön koşullar"
"$HARNESS/scripts/sdlc/doctor.sh" "$TICKET" || { echo "doctor kritik eksik buldu — devam edilmiyor"; exit 20; }
[ -f "$DIR/intent.md" ] || { need "docs/sdlc/$TICKET/intent.md yok. Bu dosyayı İNSAN yazar: make sdlc-new TICKET=$TICKET"; exit 20; }

say "hafıza"
if "$HARNESS/scripts/sdlc/memory.sh" status >/dev/null 2>&1; then
  MEMORY_AS=analyst "$HARNESS/scripts/sdlc/memory.sh" recall "$(head -30 "$DIR/intent.md" | tr '\n' ' ')" | head -20
else
  echo "   cognee kapalı — hat hafızasız devam eder (make cognee-up)"
fi

say "kademe (analiz)"
node "$HARNESS/gates/route.ts" "$DIR/intent.md" | node -e '
  let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const r=JSON.parse(s);
  const a=r.assignment||{};console.log(`   ${r.tier} — ${r.reason}`);
  console.log(`   analist ${(a.analyst||{}).model} · mimar ${(a.architect||{}).model}`)})'

if [ ! -f "$DIR/spec.md" ]; then
  need "spec.md yok. Oturumda: /brd-analyst docs/sdlc/$TICKET/intent.md"
  exit 10
fi

say "kapı: spec"
gate spec "$DIR/spec.md"; case $? in 20) exit 20;; 10) need "spec kapısı insana düştü — açık soruları kapat, sonra tekrar koş"; exit 10;; esac

if [ ! -f "$DIR/plan.md" ]; then
  need "plan.md yok. Oturumda: /architect docs/sdlc/$TICKET/spec.md"
  exit 10
fi

say "kapı: bölünme (scope)"
gate scope "$DIR/spec.md"; case $? in
  20) need "Bu ticket birden cok bagimsiz isi paketliyor — bolup her parcayi kendi ticket'ina tasi"; exit 20;;
  10) if "$HARNESS/scripts/sdlc/approve.sh" --check "$TICKET" scope >/dev/null 2>&1; then
        echo "   (insan onayi kayitli)"
      else
        need "Bolunme kapisi insan karari istiyor: scripts/sdlc/approve.sh $TICKET scope \"<neden bolmuyoruz>\""
        exit 10
      fi;;
esac

say "kapı: blast radius"
gate blast "$DIR/plan.md"; case $? in 20) exit 20;; 10) need "plan kritik yüzeye dokunuyor ya da ölçüm güvenilmez — İNSAN ONAYI olmadan build başlatma"; exit 10;; esac

[ "$SPEC_ONLY" = "--spec-only" ] && { say "specOnly istendi — burada duruldu"; exit 0; }

say "kademe (uygulama) + build"
if [ -d "$ROOT/.sdlc-worktrees/$TICKET" ] && [ -n "$(git -C "$ROOT/.sdlc-worktrees/$TICKET" status --porcelain 2>/dev/null | grep -v 'docs/sdlc')" ]; then
  echo "   worktree'de zaten değişiklik var, build atlanıyor (tekrar koşmak için worktree'yi temizle)"
else
  # DIKKAT: "if ! komut; then $?" HER ZAMAN 0 verir — $? negasyonun sonucudur,
  # komutun degil. Boyle yazildiginda basarisiz build sessizce review fazina
  # geciyordu (dis denetimde bulundu 21 Eyl 2026, kabukta dogrulandi).
  BUILD_EXIT=0
  "$HARNESS/scripts/sdlc/codex-build.sh" "$TICKET" || BUILD_EXIT=$?
  if [ "$BUILD_EXIT" -ne 0 ]; then
    # Build hatasini YOK SAYMA. Exit 10 = plan uygunlugu insan karari; 20 = ihlal.
    if [ "$BUILD_EXIT" -ge 20 ]; then
      need "Build plani karsilamiyor (exit $BUILD_EXIT) — review fazina gecme"
      exit 20
    fi
    echo "   (build exit $BUILD_EXIT — plan uygunlugu insan karari)"
  fi
fi

say "kapı: plan uygunluğu (modelsiz)"
node "$HARNESS/gates/postbuild.ts" "$TICKET" | node -e '
  let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const r=JSON.parse(s);
  console.log(`   ${r.decision.toUpperCase()} — ${r.changedFiles} dosya, ${r.testFilesTouched} test dosyası`);
  (r.problems||[]).forEach(p=>console.log("   ✗ "+p));
  (r.warnings||[]).forEach(p=>console.log("   ~ "+p))})'
POST=${PIPESTATUS[0]}
if [ "$POST" -ge 20 ]; then
  need "build planı karşılamıyor. Eksikleri plana bağlayıp build'i tekrar koş; review fazına GEÇME."
  exit 20
fi

if [ ! -f "$DIR/REVIEW.md" ]; then
  need "REVIEW.md yok. Oturumda çapraz review başlat (kodu Codex yazdı → denetçi Claude): güvenlik + spec lensleri paralel."
  exit 10
fi

say "kapı: review"
gate review "$DIR/REVIEW.md"; case $? in 20) exit 20;; 10) need "review kapısı insana düştü"; exit 10;; esac

say "kararlar hafızaya"
"$HARNESS/scripts/sdlc/memory.sh" remember-decisions "$TICKET" 2>/dev/null || echo "   (hafıza kapalı, atlandı)"

say "sıradaki"
need "test fazı (oturum, haiku) → UAT paketi (oturum, sonnet) → make sdlc-land TICKET=$TICKET"
exit 0
