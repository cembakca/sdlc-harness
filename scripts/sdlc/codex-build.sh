#!/usr/bin/env bash
# Build fazı — Codex'i izole bir git worktree'de yazma yetkisiyle koşturur.
#
#   scripts/sdlc/codex-build.sh HKA-123
#
# Worktree harness'e ait: branch'e hiçbir şey land edilmez, sonuç reviewable
# bir diff olarak kalır. Codex resmi CLI ile çağrılır (codex exec) — mevcut
# ChatGPT aboneliği ve ~/.codex/config.toml aynen kullanılır.
set -euo pipefail

TICKET="${1:?usage: codex-build.sh <TICKET>}"
ROOT="$(git rev-parse --show-toplevel)"
DIR="$ROOT/docs/sdlc/$TICKET"
WT="${SDLC_WORKTREE_ROOT:-$ROOT/.sdlc-worktrees}/$TICKET"
BRANCH="sdlc/$TICKET"

[ -f "$DIR/plan.md" ] || { echo "plan.md yok: $DIR/plan.md — build fazı başlayamaz" >&2; exit 20; }

# Durum dosyasi: bekleyen taraf surec adina degil buna baksin. Surec adiyla
# beklemek 21 Eyl 2026'da yanlis "build bitti" sinyali uretti.
STATUS="$DIR/.codex-build.status"
printf 'running %s\n' "$(date -u +%FT%TZ)" > "$STATUS"
finish() {
  printf '%s %s exit=%s\n' "$1" "$(date -u +%FT%TZ)" "${2:-0}" >> "$STATUS"
}
trap 'finish interrupted 130' INT TERM

if [ ! -d "$WT" ]; then
  # Dal ticket acilisinda dogmus olmali (scripts/sdlc/new.sh). Yoksa burada
  # aciyoruz ama bu bir GERI DONUS yolu: ticket ile dal arasindaki bag
  # build'e kadar gorunmez kalmis demektir.
  if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git -C "$ROOT" worktree add "$WT" "$BRANCH" >&2
  else
    echo "UYARI: $BRANCH dali yok, build acıyor — ticket acilisinda acilmaliydi (make sdlc-new)" >&2
    git -C "$ROOT" worktree add -B "$BRANCH" "$WT" HEAD >&2
  fi
fi

# Taban dali KAYDET. Worktree HEAD'den aciliyor ama "HEAD" zamanla baska bir sey
# olur; birlesme kontrolu hangi dala karsi yapilacagini tahmin etmemeli
# (olculdu 21 Eyl 2026: sdlc/F4-1 main'e gore guncel ama calisilan dalin
# 2 commit gerisindeydi).
[ -f "$DIR/.base-branch" ] || git -C "$ROOT" rev-parse --abbrev-ref HEAD > "$DIR/.base-branch"

# Ticket artifact'lerini worktree'ye kopyala. Sebep: worktree HEAD'den aciliyor
# ve docs/sdlc/** cogu zaman henuz commit edilmemis oluyor; Codex plani
# okuyamazsa faz sessizce yanlis isi yapar.
mkdir -p "$WT/docs/sdlc/$TICKET"
cp "$DIR"/*.md "$WT/docs/sdlc/$TICKET/" 2>/dev/null || true

# Bagimliliklari worktree'ye baglа. Sebep: 21 Eyl 2026'daki ilk kosuda Codex
# "testleri kosturamadim, client bagimliliklari yok" dedi ve plandaki test
# sartlarini atladi. Test kosturamayan bir worktree'de "Done when: test gecer"
# sarti fiilen uygulanamaz — eksik olan disiplin degil, ortamdi.
link_dep() {
  [ -e "$ROOT/$1" ] || return 0
  [ -e "$WT/$1" ] && return 0
  mkdir -p "$(dirname "$WT/$1")"
  ln -s "$ROOT/$1" "$WT/$1" 2>/dev/null || true
}
# Bagimliliklar yapilandirmadan: her yigin kendi deps listesini soyler.
cfg() { node "$ROOT/sdlc/project.ts" "$@" 2>/dev/null; }
for st in $(cfg stacks | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{JSON.parse(s).forEach(x=>console.log(x.name))}catch{}})'); do
  SROOT="$(cfg stack "$st" root)"
  for dep in $(cfg stack "$st" deps | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log((JSON.parse(s)||[]).join(" "))}catch{}})'); do
    link_dep "$SROOT/$dep"
  done
done
# Harness script'leri: worktree HEAD'den aciliyor ve bu dosyalar henuz commit
# edilmemis olabiliyor. Codex plandaki "scripts/sdlc/test.sh calistir" sartini
# "dosya mevcut degil" diye atladi (olculdu 21 Eyl 2026).
link_dep "scripts/sdlc"
link_dep "gates"

env_files_of() { # env_files_of <yigin> -> satir satir env dosya adlari
  # envFiles (dizi) ya da envFile (tek) — ikisi de desteklenir.
  cfg stack "$1" envFiles | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
    try{const a=JSON.parse(s); if(Array.isArray(a)) a.forEach(x=>console.log(x))}catch{}})'
  EF1="$(cfg stack "$1" envFile | tr -d '"')"
  [ -n "$EF1" ] && printf '%s\n' "$EF1"
  true
}

# Baglanan bagimliliklar git'e gorunmesin: worktree'nin KENDI exclude dosyasina
# yaziyoruz (ana repo'nun .gitignore'una dokunmadan). Aksi halde postbuild
# "planda olmayan dosyalar degismis" diyor ve diff sayisi sisiyor
# (olculdu 21 Eyl 2026: 8 gercek dosya, 10 sayildi).
# DIKKAT: worktree'de --git-dir ayri bir dizin verir (.git/worktrees/<ad>) ama
# git exclude dosyasini ORTAK dizinden okur. --git-common-dir sart
# (olculdu 21 Eyl 2026: yanlis dosyaya yazinca bagimliliklar diff'te kalmisti).
GITDIR="$(git -C "$WT" rev-parse --git-common-dir 2>/dev/null)"
if [ -n "$GITDIR" ]; then
  EXCL="$GITDIR/info/exclude"
  mkdir -p "$(dirname "$EXCL")"
  # Haric tutulacak yollar: her yiginin deps + env dosyalari.
  EXCLUDES=""
  for st in $(cfg stacks | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{JSON.parse(s).forEach(x=>console.log(x.name))}catch{}})'); do
    SR="$(cfg stack "$st" root)"
    for dep in $(cfg stack "$st" deps | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log((JSON.parse(s)||[]).join(" "))}catch{}})'); do
      EXCLUDES="$EXCLUDES $SR/$dep"
    done
    for ef in $(env_files_of "$st"); do EXCLUDES="$EXCLUDES $SR/$ef"; done
  done
  for pat in $EXCLUDES; do
    grep -qxF "$pat" "$EXCL" 2>/dev/null || printf '%s\n' "$pat" >> "$EXCL"
  done
fi

# Test ayarlari: GERCEK .env baglanmaz. Build ajaninin sirlari gormesi gerekmiyor;
# testlerin ihtiyaci olan sey degerlerin dogru olmasi degil, VAR olmasi.
# Sirlar temizlenmis bir kopya cikariyoruz (finans reposu: sir sizdirmanin
# maliyeti, testin kolayligindan buyuk).
# Her yiginin env dosyalari kopyalanir — COGUL. Eski surumde tek bir ENV_FILE
# degiskeni vardi ve dongu her yiginda uzerine yaziyordu: pratikte yalnizca SON
# yigin env alabiliyordu. Sonucu ilk gercek turda olculdu (21 Eyl 2026):
# client/.env.local worktree'ye hic gitmedi, VITE_MARKETING_URL tanimsiz kaldi ve
# bir test worktree'de kirmizi, ana agacta yesil oldu — kod degismeden. Test
# ortami uretilebilir degilse test sonucu da bilgi degildir.
scrub_env_to() { # scrub_env_to <kaynak> <hedef>
  # Sayisal ayarlari ELLEME: JWT_REFRESH_TOKEN_EXPIRE_DAYS gibi isimler de
  # "TOKEN" iceriyor ve yer tutucu koyunca pydantic int parse hatasi veriyor.
  awk '
    /^[A-Z0-9_]*(KEY|SECRET|TOKEN|PASSWORD)[A-Z0-9_]*=/ {
      i = index($0, "=");
      name = substr($0, 1, i - 1);
      value = substr($0, i + 1);
      if (value ~ /^[0-9]+$/ || value == "" || value == "true" || value == "false" ||
          value == "True" || value == "False" || value == "1" || value == "0") { print; next }
      print name "=test-placeholder";
      next
    }
    { print }
  ' "$1" > "$2"
}

for st in $(cfg stacks | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{JSON.parse(s).forEach(x=>console.log(x.name))}catch{}})'); do
  SR="$(cfg stack "$st" root)"
  for ef in $(env_files_of "$st"); do
    SRC_ENV="$ROOT/$SR/$ef"; DST_ENV="$WT/$SR/$ef"
    [ -f "$SRC_ENV" ] || continue
    [ -f "$DST_ENV" ] && continue
    mkdir -p "$(dirname "$DST_ENV")"
    scrub_env_to "$SRC_ENV" "$DST_ENV"
    echo "--- env kopyalandi (sirlar temizlendi): $SR/$ef"
  done
done

# Not: komut ikamesi ($(cat <<EOF)) KULLANILMIYOR. Metindeki tek bir kesme
# isareti ("plan's word") $( ) icinde tirnak sayisini tek yapip bash
# ayristiricisini kiriyor (olculdu 21 Eyl 2026). read -d '' bundan bagimsiz.
read -r -d '' PROMPT <<'PROMPT_EOF' || true
You are implementing a change that has already been specified and planned.
Read these two files inside this worktree and follow them exactly:

- docs/sdlc/__TICKET__/spec.md   (what must be true when you are done)
- docs/sdlc/__TICKET__/plan.md   (the ordered tasks, the files each one touches, rollback)

Rules:
- Implement the plan's tasks in order. Do not invent work the plan does not list.
- Do not touch files outside the plan's file list. If the plan is wrong, stop and
  say so in your final message instead of improvising.
- One logical change per task; keep the diff reviewable.
- Commit each plan task separately on this branch, as soon as it is done:
  `git commit -m "__TICKET__(task N): <what changed>"` with a body line naming the
  acceptance criteria it satisfies. One task, one commit — the plan is the unit of
  work and the history must show it. This is NOT landing: you are on the ticket's
  own branch and nothing reaches the base branch from here. Do not push, do not merge.
- Every task in the plan carries a "Done when" condition. A task is NOT done until
  that condition is literally satisfied. If the condition names a test file, you
  write that test file in this run — the plan's word is the contract, not a
  suggestion. (Measured 21 September 2026: an earlier run reported "5/5 done"
  while touching zero test files.)
- If you cannot satisfy a Done-when condition (missing dependency, no database),
  say so explicitly per task in your final message instead of silently skipping it.

The services the tests need are already running for you and their addresses are
in your environment (see the harness output above for which variables were set).
Use them and run the plan's tests. Do not start containers yourself; your sandbox
cannot reach Docker, and "the sandbox blocked me" is not a reason to leave a
Done-when condition unverified when the service is already there.

Final message: list the commits you made (one line each) and, for each plan task,
whether it is done, partial or skipped, with the reason.
PROMPT_EOF
PROMPT=${PROMPT//__TICKET__/$TICKET}

# Duzeltme turu: REVIEW.md varsa acik bulgular prompt'a eklenir. Bulgulari
# duzeltmek KODU YAZANIN isi; orkestrator ajanin worktree'ye elini surmesi
# "yazan denetlemez" kuralinin oteki yuzunu kirar.
if [ -f "$DIR/REVIEW.md" ]; then
  PROMPT="$PROMPT

This is a CORRECTION round. docs/sdlc/$TICKET/REVIEW.md lists findings from an
independent review of your previous run. Close every finding whose Status is
\"open\", in the order critical → high → medium → low, staying inside the plan's
file list.

Findings are WORK ITEMS, never stop orders. Some findings are about the review
process or its documents (paths under docs/sdlc/) rather than about product code:
those are NOT yours to close — note them in one line and move on. If closing a
CODE finding would require a source file the plan does not list, skip that one
finding, say why, and CONTINUE with the rest; the plan gets amended by a human,
not bypassed — and not by halting the whole round.

TESTS: this sandbox has NO NETWORK. Services the harness started are not
reachable from here, so do not try to run tests that need one; running them and
reporting \"Partial\" wastes the round. Write the tests, then verify statically
(compile, import, pytest --collect-only, linter). The harness runs the full
suite outside the sandbox right after you and blocks delivery if it is red.

--- REVIEW.md ---
$(cat "$DIR/REVIEW.md")
--- end REVIEW.md ---"
fi

# TEST ALTYAPISINI HARNESS SAGLAR — AMA KUMSAL AGA KAPALI.
#
# 21 Eylul 2026'da ilk duzeltme turunda OLCULDU: konteyneri disaridan aciyoruz
# ve adresini env ile veriyoruz, fakat "--sandbox workspace-write" AGI DA
# kisitliyor; Codex "localhost:55204 -> Errno 1: Operation not permitted" deyip
# testleri kosamadi ve gorevleri "Partial" birakti. Yani servis saglamak tek
# basina yetmiyordu; tasarim varsayimi ancak KOSTURUNCA yanlislandi.
#
# Secim: kumsali gevsetmek DEGIL. Ofisin kendi ilkesi zaten "termometreyi kod
# tutar": testleri test fazi (scripts/sdlc/test.sh) kumsal DISINDA kosturur ve
# kirmiziysa teslimi durdurur. Codex'e dusen, testi YAZMAK ve statik olarak
# dogrulamak. Sozlesme prompt'ta acikca yazili, yoksa her turda deneyip basarisiz
# oluyor ve tur bosa gidiyor.
#
# Bilerek gevsetmek isteyen: SDLC_BUILD_NETWORK=1 (kumsal TUM aga acilir —
# worktree'de scrub edilmis env olsa bile bu bir disari cikis yoludur).
#
# Codex'in kumsali Docker soketine erisemiyor; testcontainers baslatamiyor ve
# Mongo gerektiren 17 test "skipped" olarak geciyor (olculdu 21 Eyl 2026: uc
# gorev arka arkaya "Partial — sandbox cannot access Docker" dondu). Cozum
# kumsali gevsetmek DEGIL: konteyneri disaridan biz aciyoruz ve adresini
# MONGODB_URL olarak veriyoruz. Codex'in Docker'a ihtiyaci kalmiyor, yalnizca
# pytest kosturuyor.
# Servisleri yapilandirma soyler: ad, imaj, port, hangi env degiskenine yazilacak.
SERVICE_ENVS=""
SERVICE_CONTAINERS=""
if command -v docker >/dev/null 2>&1; then
  for st in $(cfg stacks | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{JSON.parse(s).forEach(x=>console.log(x.name))}catch{}})'); do
    SVCJSON="$(cfg stack "$st" services)"
    [ -n "$SVCJSON" ] && [ "$SVCJSON" != '""' ] || continue
    COUNT="$(printf '%s' "$SVCJSON" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log((JSON.parse(s)||[]).length)}catch{console.log(0)}})')"
    i=0
    while [ "$i" -lt "${COUNT:-0}" ]; do
      FIELD() { printf '%s' "$SVCJSON" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const a=JSON.parse(s);console.log(a[Number(process.argv[1])][process.argv[2]]??"")})' "$i" "$1"; }
      SVC_NAME="$(FIELD name)"; SVC_IMAGE="$(FIELD image)"; SVC_PORT="$(FIELD containerPort)"
      SVC_ENV="$(FIELD envVar)"; SVC_URL="$(FIELD urlTemplate)"; SVC_READY="$(FIELD readyCheck)"
      CNAME="sdlc-${SVC_NAME}-${TICKET}"
      docker rm -f "$CNAME" >/dev/null 2>&1 || true
      if docker run -d --name "$CNAME" -P "$SVC_IMAGE" >/dev/null 2>&1; then
        HOSTPORT="$(docker port "$CNAME" "$SVC_PORT/tcp" 2>/dev/null | head -1 | sed 's/.*://')"
        if [ -n "$HOSTPORT" ]; then
          for _ in $(seq 1 30); do
            [ -z "$SVC_READY" ] && break
            docker exec "$CNAME" sh -c "$SVC_READY" >/dev/null 2>&1 && break
            sleep 1
          done
          SERVICE_ENVS="$SERVICE_ENVS $SVC_ENV=$(printf '%s' "$SVC_URL" | sed "s/{port}/$HOSTPORT/")"
          SERVICE_CONTAINERS="$SERVICE_CONTAINERS $CNAME"
          echo "--- test servisi: $SVC_NAME → localhost:$HOSTPORT ($SVC_ENV)" >&2
        fi
      fi
      i=$((i+1))
    done
  done
fi

cleanup_services() { for c in $SERVICE_CONTAINERS; do docker rm -f "$c" >/dev/null 2>&1 || true; done; }
trap 'cleanup_services' EXIT

# Model ve efor OLCULEREK secilir: gates/route.ts plani siniflandirir
# (mechanical | standard | deep), kademe sdlc/roster.json'dan role cevrilir.
# Her isi yuksek eforda kosturmak da, her isi ucuz modelde kosturmak da
# ayni hata — isin zorlugunu olcmemek. TEK cagri, uc deger.
eval "$(node "$ROOT/gates/assign.ts" "$TICKET" 2>/dev/null | node -e '
let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
  let r={}; try{ r=JSON.parse(s) }catch{}
  const a=(r.assignment||{}).implementer||{};
  if(!r.tier && r.measured) r.tier=r.measured.complexity;
  const q=v=>String(v||"").replace(/[^A-Za-z0-9._:-]/g,"");
  console.log(`TIER=${q(r.tier)}; MODEL=${q(a.model)}; EFFORT=${q(a.effort)}`);
})' || true)"

# Olcum basarisizsa kadronun standart kademesine dus (sessizce en ucuza degil).
MODEL="${SDLC_CODEX_MODEL:-$MODEL}"
EFFORT="${SDLC_CODEX_EFFORT:-$EFFORT}"
[ -n "${MODEL:-}" ]  || MODEL="$(node "$ROOT/sdlc/roster.ts" implementer model)"
[ -n "${EFFORT:-}" ] || EFFORT="$(node "$ROOT/sdlc/roster.ts" implementer effort)"
echo "--- kademe: ${TIER:-bilinmiyor} → model $MODEL, efor $EFFORT" >&2

NET_ARGS=()
if [ "${SDLC_BUILD_NETWORK:-0}" = "1" ]; then
  NET_ARGS=(-c 'sandbox_workspace_write.network_access=true')
  echo "--- DIKKAT: kumsal agi acik (SDLC_BUILD_NETWORK=1)"
fi

env $SERVICE_ENVS codex exec \
  -C "$WT" \
  --sandbox workspace-write \
  "${NET_ARGS[@]+"${NET_ARGS[@]}"}" \
  ${MODEL:+--model "$MODEL"} \
  ${EFFORT:+-c model_reasoning_effort="$EFFORT"} \
  -o "$DIR/.codex-build.md" \
  "$PROMPT" >&2

finish finished "$?"

# COMMIT DISIPLINI HEMEN BURADA olculur. Prompt gorev basina commit istiyor ama
# istemek denetlemek degildir: F4-1'de 10 plan gorevi icin 0 gorev commit'i
# uretildi ve bunu ancak CI'da, gunler sonra gorduk (olculdu 21 Eyl 2026).
# Burada durdurmuyor — build'in kendisi basarili olabilir — ama GORUNUYOR.
# Hangi modelde kostugu DEFTERE girer: atanan kademe ile kosani karsilastirmak
# ancak boyle mumkun (gates/readiness.ts "kademe uyumu" satiri).
"$ROOT/scripts/sdlc/ran.sh" "$TICKET" implementer "$MODEL" "$EFFORT" || true

echo "--- commit disiplini (bir plan gorevi = bir commit)"
"$ROOT/scripts/sdlc/commit-lint.sh" "$TICKET" || echo "   ^ CI bunu ZORUNLU tutuyor; birlestirmeden once duzelt"

echo "--- plan uygunluk denetimi (model yok, deterministik)"
POSTBUILD_EXIT=0
node "$ROOT/gates/postbuild.ts" "$TICKET" || POSTBUILD_EXIT=$?

# CHECKPOINT COMMIT: her build turu ticket dalinda bir commit birakir.
# Sebebi olculdu (21 Eyl 2026): review deltasi iki commit arasindaki farktan
# hesaplaniyor, ama Codex commit atmiyordu ve worktree HEAD'i hic ilerlemiyordu
# — delta review hicbir zaman devreye giremiyordu. Bu LAND DEGILDIR: ticket'in
# kendi dalina yazilir, ana dala degil.
if ! git -C "$WT" diff --quiet HEAD 2>/dev/null || [ -n "$(git -C "$WT" status --porcelain 2>/dev/null)" ]; then
  # docs/sdlc HARIC: artifact'lerin tek kaynagi ana agac. Worktree'deki
  # kopyalar yalnizca Codex okusun diye var; commit edilirse ayni belgenin iki
  # surumu olusuyor ve taban dalla birlesirken cakisiyor (olculdu 21 Eyl 2026:
  # REVIEW.md, TESTS.md ve UAT.md ucu birden cakisti).
  git -C "$WT" add -A -- . ':!docs/sdlc' >/dev/null 2>&1
  ROUND="$(git -C "$WT" rev-list --count HEAD 2>/dev/null || echo 0)"
  git -C "$WT" -c user.name="sdlc-harness" -c user.email="sdlc@local" \
    commit -q -m "$TICKET: build round (checkpoint $ROUND)" >/dev/null 2>&1 \
    && echo "--- checkpoint commit: $(git -C "$WT" rev-parse --short HEAD)"
fi

echo "--- worktree: $WT (branch $BRANCH)"
echo "--- diff --stat:"
git -C "$WT" add -A
git -C "$WT" diff --cached --stat
echo "--- codex son mesajı: $DIR/.codex-build.md"
if [ "$POSTBUILD_EXIT" -ge 20 ]; then
  echo "--- BUILD PLANA UYMUYOR: yukaridaki problems maddeleri kapatilmadan review fazina gecme." >&2
fi
exit "$POSTBUILD_EXIT"
