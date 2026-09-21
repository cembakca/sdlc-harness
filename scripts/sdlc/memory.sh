#!/usr/bin/env bash
# Kurum hafizasi — Cognee'ye tek giris noktasi.
#
#   scripts/sdlc/memory.sh remember <dosya> [dataset]
#   scripts/sdlc/memory.sh remember-ticket <TICKET>
#   scripts/sdlc/memory.sh recall "<soru>"
#   scripts/sdlc/memory.sh status
#
# Neden tek dosya: ayni hafizaya Claude, Codex, hook'lar ve workflow yaziyor.
# Uc yerde uc farkli curl olursa hafiza uc farkli sekle girer.
#
# Cognee kapaliysa komutlar sessizce 0 doner ve hat hafizasiz calismaya devam
# eder — hafiza katmani hattin onkosulu degil, hizlandiricisi.
set -euo pipefail

# Proje koku: harness'in nerede durdugundan bagimsiz (bkz. _root.sh).
_SDLC_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SDLC_CALLER_DIR/_root.sh"
ROOT="$(sdlc_root)" || exit 1
HARNESS="$(sdlc_harness_root)"
API="${COGNEE_API_URL:-http://localhost:8765}"
# Kimlik dogrulama acik (arayuz giris ekrani istiyor). Script'ler API anahtariyla
# konusur; anahtar .env'den okunur, Authorization degil X-Api-Key basligiyla
# gonderilir (Bearer 401 veriyor — olculdu 21 Eyl 2026).
if [ -z "${COGNEE_API_KEY:-}" ] && [ -f "$ROOT/.env" ]; then
  COGNEE_API_KEY="$(grep -m1 '^COGNEE_API_KEY=' "$ROOT/.env" 2>/dev/null | cut -d= -f2-)"
fi
# Rol kimligi: MEMORY_AS=architect ile o rolun anahtariyla yazilir/okunur.
# Hafizaya "birisi yazdi" degil "mimar yazdi" kaydi dussun diye.
ACTIVE_KEY="${COGNEE_API_KEY:-}"
if [ -n "${MEMORY_AS:-}" ]; then
  ROLE_KEY="$("$HARNESS/scripts/sdlc/agents.sh" key "$MEMORY_AS" 2>/dev/null)"
  [ -n "$ROLE_KEY" ] && ACTIVE_KEY="$ROLE_KEY"
fi
AUTH=(); [ -n "$ACTIVE_KEY" ] && AUTH=(-H "X-Api-Key: ${ACTIVE_KEY}")
cfgp() { node "$HARNESS/sdlc/project.ts" "$@" 2>/dev/null; }
PROC_DS="$(cfgp memory | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).processDataset||"sdlc")}catch{console.log("sdlc")}})')"
DATASET_DEFAULT="${COGNEE_DATASET:-$PROC_DS}"
CMD="${1:-status}"

up() { curl -sf -m "${COGNEE_HEALTH_TIMEOUT:-10}" -o /dev/null "$API/health" 2>/dev/null; }

# Dataset KIMLIGI: paylasilan bir dataset ada gore cozulmuyor ("Dataset names
# resolve only among the datasets you own"), yani rol kimligiyle calisirken
# isim yetmiyor. Kimligi bir kez cozup her cagriida onu kullaniyoruz.
dataset_id() {
  # ISIM PARAMETRE: global onbellege guvenmek 21 Eyl 2026'da urun belgelerinin
  # surec dataset'ine karismasina sebep oldu — cagri "crawlens_project" diyordu,
  # kimlik "crawlens_sdlc"ten cozuluyordu.
  #
  # "YOK" ILE "SORAMADIM" AYRI SEYLERDIR. Eskiden ikisi de bos string donuyordu:
  # liste ucu zaman asimina ugradiginda cagiran taraf bunu "boyle bir dataset
  # yok" saniyordu. Ilk gercek workflow kosusunda gorildu (21 Eyl 2026):
  # crawlens_sdlc REPODA VARDI, hat "dataset cozulemedi" deyip hafizasiz
  # calisti. Artik ulasılamama exit 3 ile ayrilir.
  local name="${1:-$DATASET_DEFAULT}"
  local body rc
  body="$(curl -s -m "${MEMORY_LIST_TIMEOUT:-30}" "${AUTH[@]}" "$API/api/v1/datasets" 2>&1)"; rc=$?
  if [ "$rc" != "0" ]; then
    echo "dataset listesi alinamadi (curl exit $rc) — hafiza ulasilamiyor" >&2
    return 3
  fi
  printf '%s' "$body" | node -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      let a=null;try{a=JSON.parse(s)}catch{}
      if(!Array.isArray(a)){process.stderr.write("dataset listesi cozulemedi\n");process.exit(3)}
      const m=a.find(x=>x.name===process.argv[1]);
      console.log(m?m.id:"")})' "$name"
}

require_up() {
  up && return 0

  # ON-DEMAND: hafiza kapaliysa KENDISI acar. Olculdu 21 Eyl 2026 — backend
  # 2.3 GB tutuyor (e5-large yuklu) ve bu makinede ~200 MB bos kaliyor, yani
  # surekli acik durmasi dogru degil. Ama "acmayi unuttun" diye hatti hafizasiz
  # birakmak da dogru degil: insanin hatirlamak zorunda oldugu her adim, er gec
  # unutulan bir adimdir.
  #
  # Kapatmak isteyen: make cognee-down (2.3 GB geri gelir).
  # Otomatik acilis opt-in. Baska repoda compose dosyasi olmayabilir.
  # compose.yml HARNESS'in altyapisi, projenin degil: harness ayri repoya
  # alindiginda $ROOT/ops/cognee altinda DURMAZ. Once proje koku (eski duzen
  # ve projeye ozel ozelleştirme), sonra harness koku.
  COMPOSE="${SDLC_MEMORY_COMPOSE:-}"
  if [ -z "$COMPOSE" ]; then
    if [ -f "$ROOT/ops/cognee/compose.yml" ]; then COMPOSE="$ROOT/ops/cognee/compose.yml"
    else COMPOSE="$(sdlc_harness_root)/ops/cognee/compose.yml"; fi
  fi
  if [ "${MEMORY_AUTOSTART:-0}" = "1" ] && [ -f "$COMPOSE" ]; then
    echo "cognee kapali — aciliyor (e5-large yuklenecek, ~60-90 sn)" >&2
    PROJECT_NAME="$(cfgp name)"
    (cd "$ROOT" && docker compose -p "${SDLC_MEMORY_PROJECT:-${PROJECT_NAME}-cognee}" --env-file .env \
       -f "$COMPOSE" up -d "${SDLC_MEMORY_SERVICE:-cognee-backend}" >/dev/null 2>&1) || true
    for _ in $(seq 1 "${MEMORY_START_TRIES:-24}"); do
      up && { echo "cognee hazir" >&2; return 0; }
      sleep 5
    done
    echo "cognee acilamadi ($API) — hafiza adimi atlandi" >&2
    exit 0
  fi

  echo "cognee kapali ($API) — hafiza adimi atlandi" >&2
  exit 0
}

case "$CMD" in
  status)
    if up; then echo "cognee ayakta: $API"; else echo "cognee kapali: $API"; exit 1; fi
    ;;

  remember)
    FILE="${2:?usage: memory.sh remember <dosya> [dataset]}"
    DATASET="${3:-$DATASET_DEFAULT}"
    [ -f "$FILE" ] || { echo "dosya yok: $FILE" >&2; exit 1; }
    require_up
    # Cognee 1.0 API: tek ucta ingest + graf insasi (v1 add/cognify hala var ama
    # iki adim, iki hata yuzeyi).
    #
    # VARSAYILAN ARKA PLAN, bilerek: senkron cagri 20 Eyl 2026'da olculdu ve
    # ~36 saniyede baglanti dusuyor (sunucu isci zaman asimi). Arka planda ise
    # ayni dosya ~12 saniyede grafa giriyor ve durum
    # GET /api/v1/datasets/status ile izlenebiliyor. MEMORY_SYNC=1 yalnizca
    # kucuk dosyalarda hata ayiklamak icin.
    BG=true; [ "${MEMORY_SYNC:-0}" = "1" ] && BG=false
    DSID="$(dataset_id "$DATASET")"
    if [ -n "$DSID" ]; then TARGET=(-F "datasetId=$DSID"); else TARGET=(-F "datasetName=$DATASET"); fi
    RESP="$(curl -s -m "${MEMORY_TIMEOUT:-600}" "${AUTH[@]}" -X POST "$API/api/v1/remember" \
      -F "data=@$FILE" \
      "${TARGET[@]}" \
      -F "run_in_background=$BG" \
      -F "self_improvement=false" \
      2>&1)" || { echo "remember basarisiz (baglanti): $FILE" >&2; exit 11; }
    # BASARISIZLIK BASARI GIBI GORUNMEMELI. Eskiden iki hata yolu da "exit 0"
    # veriyordu: cagiran taraf belgenin hafizaya girdigini saniyordu, oysa graf
    # bos kaliyordu (dis denetimde bulundu 21 Eyl 2026). Hafizaya yazamamak
    # hatti durdurmaz — ama SESSIZ de kalmaz; cagiran karar verir.
    case "$RESP" in
      *error*|*Error*|*detail*)
        echo "remember REDDEDILDI: $FILE → $DATASET" >&2
        echo "  yanit: $(printf '%s' "$RESP" | head -c 300)" >&2
        exit 12 ;;
      *) echo "hafizaya alindi: $FILE → $DATASET" ;;
    esac
    ;;

  remember-ticket)
    TICKET="${2:?usage: memory.sh remember-ticket <TICKET>}"
    require_up
    FAILED=""
    for f in intent.md spec.md plan.md REVIEW.md UAT.md; do
      P="$ROOT/docs/sdlc/$TICKET/$f"
      [ -f "$P" ] || continue
      "$0" remember "$P" "$DATASET_DEFAULT" || FAILED="$FAILED $f"
    done
    if [ -n "$FAILED" ]; then
      echo "hafizaya ALINAMAYAN belgeler:$FAILED" >&2
      exit 12
    fi
    ;;

  recall)
    Q="${2:?usage: memory.sh recall \"<soru>\"}"
    require_up
    DSID="$(dataset_id "$DATASET_DEFAULT")"; DS_RC=$?
    if [ "$DS_RC" = "3" ]; then
      echo "recall BASARISIZ: hafizaya ulasilamadi (dataset listesi)." >&2
      echo "  Bu 'emsal yok' DEMEK DEGILDIR — soru sorulamadi." >&2
      exit 14
    fi
    # Dataset kimligi cozulemezse sorgu API varsayilanina duserdi: cok projeli
    # bir kurulumda bu, BASKA BIR PROJENIN hafizasindan cevap almak demektir
    # (dis denetimde bulundu 21 Eyl 2026). Sinir belirsizse sormayiz.
    if [ -z "$DSID" ]; then
      echo "recall yapilmadi: \"$DATASET_DEFAULT\" dataset'i cozulemedi." >&2
      echo "  Sorgunun hangi projeye ait oldugu garanti edilemez; sinirsiz sorgu yapilmaz." >&2
      echo "  Once: scripts/sdlc/memory.sh datasets   (bilerek sinirsiz sormak icin MEMORY_ANY_DATASET=1)" >&2
      [ "${MEMORY_ANY_DATASET:-0}" = "1" ] || exit 13
      echo "  MEMORY_ANY_DATASET=1 — sinirsiz sorguya devam ediliyor." >&2
    fi
    BODY="$(node -e '
      const [q,id]=process.argv.slice(1);
      const body={query:q,topK:8,includeReferences:true};
      if(id) body.datasetIds=[id]; // isim degil kimlik: paylasilan dataset boyle cozuluyor
      console.log(JSON.stringify(body))' "$Q" "$DSID")"
    # ISTEGIN BASARISIZ OLDUGUNU SOYLE. Eskiden curl'un sonucuna hic bakilmiyordu:
    # saglayici kotasi bittiginde (olculdu 21 Eyl 2026: Gemini 402
    # RESOURCE_EXHAUSTED, LiteLLM 32s/64s geri cekilmeyle yeniden deniyor) istek
    # zaman asimina ugruyor, script "(hafizadan cevap alinamadi)" yazip EXIT 0
    # donuyordu — cagiran taraf bunu "emsal yok" saniyordu. "Bilmiyorum" ile
    # "soramadim" ayri seylerdir; ikincisi kararin dayanagini degistirir.
    RESP_FILE="$(mktemp)"
    # DIKKAT: script "set -e" ile kosuyor; "CMD; RC=$?" kalibi burada CALISMAZ —
    # curl hata verince satira hic gelinmeden script oluyordu (olculdu).
    CURL_RC=0
    HTTP="$(curl -s -m "${MEMORY_TIMEOUT:-180}" "${AUTH[@]}" -X POST "$API/api/v1/recall" \
      -H "content-type: application/json" -d "$BODY" \
      -o "$RESP_FILE" -w '%{http_code}' 2>/dev/null)" || CURL_RC=$?
    if [ "$CURL_RC" != "0" ] || [ "${HTTP:-000}" = "000" ]; then
      rm -f "$RESP_FILE"
      echo "recall BASARISIZ: hafiza ${MEMORY_TIMEOUT:-180}s icinde yanit vermedi." >&2
      echo "  Bu 'emsal yok' DEMEK DEGILDIR — soru sorulamadi." >&2
      echo "  Bak: docker compose -p ${SDLC_COMPOSE_PROJECT:-sdlc-cognee} logs --tail 30 cognee-backend   (sik sebep: saglayici kotasi/anahtari)" >&2
      exit 14
    fi
    if [ "${HTTP:-0}" -ge 400 ] 2>/dev/null; then
      echo "recall REDDEDILDI (HTTP $HTTP): $(head -c 300 "$RESP_FILE")" >&2
      rm -f "$RESP_FILE"; exit 14
    fi
    # Ham JSON ajanin contextini bosuna yer; yalnizca cevabi ve kaynagini birak.
    node -e '
let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
  let r; try { r = JSON.parse(s) } catch { console.error("(hafiza yaniti cozulemedi)"); process.exit(14) }
  const rows = Array.isArray(r) ? r : [r];
  const text = rows.map(x => x && x.text).filter(Boolean).join("\n\n").trim();
  console.log(text || "(hafizada bu konuda kayit yok)");
})' < "$RESP_FILE" || RC=$?
    rm -f "$RESP_FILE"; exit "${RC:-0}"
    ;;

  skills)
    # Ofisin is tariflerini hafizaya Skill dugumu olarak yazar. 21 Eyl 2026'da
    # fark edildi: graf yalnizca ticket belgelerini biliyordu, calisanlarin ne
    # yapip ne yapmadigini bilmiyordu — yani hafiza isi hatirliyor ama SURECI
    # hatirlamiyordu.
    require_up
    for f in "$ROOT"/.claude/skills/*/SKILL.md; do
      [ -f "$f" ] || continue
      NAME="$(basename "$(dirname "$f")")"
      RESP="$(curl -s -m 300 "${AUTH[@]}" -X POST "$API/api/v1/skills" \
        -H "content-type: application/json" \
        --data-binary "$(node -e '
          const fs=require("fs");
          console.log(JSON.stringify({
            skills_text: fs.readFileSync(process.argv[1],"utf8"),
            skill_name: process.argv[2],
            dataset_name: process.argv[3]
          }))' "$f" "$NAME" "$DATASET_DEFAULT")" 2>&1)"
      case "$RESP" in
        *error*|*detail*) echo "skill reddedildi ($NAME): $(printf '%s' "$RESP" | head -c 160)" >&2 ;;
        *) echo "skill hafizaya alindi: $NAME" ;;
      esac
    done
    ;;

  remember-decisions)
    # Kapi kararlarini hafizaya yazar: hat kendi gecmisini sorgulayabilsin.
    TICKET="${2:?usage: memory.sh remember-decisions <TICKET>}"
    require_up
    TMP="$(mktemp -t decisions).md"
    node "$HARNESS/gates/history.ts" "$TICKET" > "$TMP"
    if MEMORY_AS="${MEMORY_AS:-gatekeeper}" "$0" remember "$TMP" >/dev/null; then
      echo "kararlar hafizaya alindi: $TICKET"
    else
      RC=$?; rm -f "$TMP"
      echo "kararlar hafizaya ALINAMADI: $TICKET (exit $RC)" >&2
      exit "$RC"
    fi
    rm -f "$TMP"
    ;;

  remember-project)
    # URUN hafizasi — SUREC hafizasindan AYRI dataset.
    #
    # Neden ayri: "bu is daha once yapildi mi" sorusu urunu bilmeyi gerektirir,
    # ama surec belgeleriyle urun belgeleri ayni grafta karisirsa ikisi de
    # bulaniklasir — spec sablonu bir urun karari gibi, bir urun karari da
    # surec kurali gibi geri gelir. Iki dataset, iki soru tipi.
    require_up
    PDS="${COGNEE_PROJECT_DATASET:-$(cfgp memory | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).productDataset||"product")}catch{console.log("product")}})')}"
    FILES="$(cfgp memory | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log((JSON.parse(s).productDocs||[]).join(" "))}catch{}})')"

    # ARTIMLI INGEST. Eskiden her cagri butun belgeleri yeniden gonderiyordu;
    # degismemis bir dosyayi yeniden gommek hem LLM hem embedding isini bosuna
    # tekrarlar — tekrarlanan maliyetin asil kaynagi buydu (olculdu 21 Eyl 2026:
    # urun korpusu 352 KB, %83'u seyrek degisen roadmap dosyalari).
    #
    # Defter: ops/cognee/.ingest-state.json  (yol -> icerik hash'i)
    # Zorla hepsini: memory.sh remember-project --all
    STATE="${SDLC_INGEST_STATE:-$ROOT/ops/cognee/.ingest-state.json}"
    mkdir -p "$(dirname "$STATE")" 2>/dev/null || true
    [ -f "$STATE" ] || echo '{}' > "$STATE"
    FORCE_ALL=""; [ "${3:-}" = "--all" ] || [ "${2:-}" = "--all" ] && FORCE_ALL=1
    hash_of() { node -e 'const c=require("node:crypto"),f=require("node:fs");
      try{console.log(c.createHash("sha256").update(f.readFileSync(process.argv[1])).digest("hex").slice(0,16))}catch{console.log("")}' "$1"; }
    state_get() { node -e 'const f=require("node:fs");let j={};try{j=JSON.parse(f.readFileSync(process.argv[1],"utf8"))}catch{}
      console.log(j[process.argv[2]]||"")' "$STATE" "$1"; }
    state_set() { node -e 'const f=require("node:fs");let j={};try{j=JSON.parse(f.readFileSync(process.argv[1],"utf8"))}catch{}
      j[process.argv[2]]=process.argv[3];f.writeFileSync(process.argv[1],JSON.stringify(j,null,1))' "$STATE" "$1" "$2"; }

    SKIPPED=0
    for f in $FILES; do
      [ -f "$ROOT/$f" ] || { echo "atlandi (yok): $f"; continue; }
      H="$(hash_of "$ROOT/$f")"
      if [ -z "$FORCE_ALL" ] && [ -n "$H" ] && [ "$H" = "$(state_get "$f")" ]; then
        SKIPPED=$((SKIPPED+1)); continue
      fi
      if COGNEE_DATASET="$PDS" "$0" remember "$ROOT/$f" "$PDS" >/dev/null; then
        echo "urun hafizasina alindi: $f"
        [ -n "$H" ] && state_set "$f" "$H"
      else
        echo "basarisiz: $f (yukaridaki gerekce)" >&2
        PFAILED="${PFAILED:-} $f"
      fi
    done
    [ "$SKIPPED" = "0" ] || echo "degismedigi icin atlandi: $SKIPPED dosya (hepsini zorlamak: --all)"
    echo "dataset: $PDS — graf arka planda kuruluyor (memory.sh graph ile izle)"
    [ -z "${PFAILED:-}" ] || { echo "urun hafizasina ALINAMAYAN belgeler:$PFAILED" >&2; exit 12; }
    ;;

  recall-project)
    Q="${2:?usage: memory.sh recall-project \"<soru>\"}"
    COGNEE_DATASET="${COGNEE_PROJECT_DATASET:-$(cfgp memory | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).productDataset||"product")}catch{console.log("product")}})')}" "$0" recall "$Q"
    ;;

  forget-ticket)
    # Ofisin cop kutusu. Reddedilen ya da iptal edilen bir isin belgeleri
    # grafta kalirsa, gelecekteki analist REDDEDILMIS bir mimariyi emsal
    # olarak hatirlar — hafizanin en sinsi hata bicimi budur.
    TICKET="${2:?usage: memory.sh forget-ticket <TICKET>}"
    require_up
    DSID="$(dataset_id "$DATASET_DEFAULT")"
    [ -n "$DSID" ] || { echo "dataset yok"; exit 1; }
    IDS="$(curl -s -m 20 "${AUTH[@]}" "$API/api/v1/datasets/$DSID/data" | node -e '
      let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
        let a=[];try{a=JSON.parse(s)}catch{}
        const t=process.argv[1];
        for(const x of (Array.isArray(a)?a:[])) {
          const n=String(x.name||x.filename||x.id||"");
          if (n.includes(t)) console.log(x.id);
        }})' "$TICKET")"
    [ -n "$IDS" ] || { echo "$TICKET icin grafta kayit bulunamadi"; exit 0; }
    COUNT=0
    for id in $IDS; do
      curl -s -m 30 "${AUTH[@]}" -X POST "$API/api/v1/forget" \
        -H "content-type: application/json" \
        -d "{\"dataId\":\"$id\",\"datasetId\":\"$DSID\"}" >/dev/null 2>&1 && COUNT=$((COUNT+1))
    done
    echo "$TICKET: $COUNT kayit hafizadan silindi (graf yeniden kurulmali: memory.sh rebuild)"
    ;;

  rebuild)
    # Grafi sifirdan kurar (ham belgeler kalir). Gerekiyor cunku cognify
    # islenmis belgeleri atliyor: saglayici, embedding boyutu ya da kimlik
    # dogrulama degisince graf bosalir ve yeniden "remember" cagirmak
    # ONU GERI GETIRMEZ (olculdu 21 Eyl 2026).
    require_up
    curl -s -m 120 "${AUTH[@]}" -X POST "$API/api/v1/forget" \
      -H "content-type: application/json" \
      -d "{\"datasetId\":\"$(dataset_id "$DATASET_DEFAULT")\",\"memoryOnly\":true}" | head -c 200; echo
    curl -s -m 120 "${AUTH[@]}" -X POST "$API/api/v1/cognify" \
      -H "content-type: application/json" \
      -d "{\"datasets\":[\"$DATASET_DEFAULT\"],\"run_in_background\":true}" >/dev/null
    echo "graf yeniden kuruluyor — 'memory.sh graph' ile izle"
    ;;

  graph)
    require_up
    DSID="$(dataset_id "$DATASET_DEFAULT")"
    [ -n "$DSID" ] || { echo "dataset bulunamadi: $DATASET_DEFAULT"; exit 1; }
    curl -s -m 30 "${AUTH[@]}" "$API/api/v1/datasets/$DSID/graph" | node -e '
      let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
        let g={};try{g=JSON.parse(s)}catch{}
        const n=g.nodes||[],e=g.edges||[];
        console.log(`düğüm ${n.length} · kenar ${e.length}`);
        const c={};for(const x of n){const t=x.type||x.label||"?";c[t]=(c[t]||0)+1}
        Object.entries(c).sort((a,b)=>b[1]-a[1]).slice(0,10)
          .forEach(([t,k])=>console.log(`  ${String(k).padStart(4)}  ${t}`));
        if(!n.length) console.log("  (graf boş — scripts/sdlc/memory.sh rebuild)");
      })'
    ;;

  verify)
    # "Hafiza calisiyor" bir IDDIA degil, OLCUM olmali.
    #
    # /health 200 donerken hafiza fiilen olu olabilir: 21 Eyl 2026'da saglayici
    # kotasi bitmisti (402 RESOURCE_EXHAUSTED), embedding her cagride basarisiz
    # oluyordu, recall sonsuz yeniden deniyordu — ve doctor yesildi. Saglik
    # kontrolu sunucunun ayakta oldugunu soyler; bu komut hafizanin ISINI
    # yaptigini soyler: YAZ → GRAFA GIR → GERI OKU.
    #
    # Gecici bir dataset kullanir ve isi bitince temizler; kurum hafizasina
    # dokunmaz. Exit 0 = tam tur calisti, 15 = yazamadi, 16 = geri okuyamadi.
    require_up
    VDS="sdlc_verify_$$"
    TOKEN="sdlc-verify-$(date +%s)-$$"
    TMPV="$(mktemp -t verify).md"
    printf '# Hafiza dogrulama\n\nBu belge yalnizca dogrulama icindir.\nIsaret: %s\n' "$TOKEN" > "$TMPV"
    echo "1/3 yaziliyor (dataset: $VDS)"
    if ! MEMORY_SYNC=1 COGNEE_DATASET="$VDS" "$0" remember "$TMPV" "$VDS" >/dev/null 2>&1; then
      rm -f "$TMPV"; echo "HAFIZA DOGRULANAMADI: yazma basarisiz." >&2
      echo "  bak: docker compose -p ${SDLC_COMPOSE_PROJECT:-sdlc-cognee} logs --tail 30 cognee-backend" >&2; exit 15
    fi
    rm -f "$TMPV"
    echo "2/3 graf kuruluyor"
    VID="$(dataset_id "$VDS")"
    [ -n "$VID" ] && curl -s -m 60 "${AUTH[@]}" -X POST "$API/api/v1/cognify" \
      -H "content-type: application/json" -d "{\"datasets\":[\"$VDS\"],\"run_in_background\":false}" >/dev/null 2>&1
    echo "3/3 geri okunuyor"
    ANS=""
    TRIES="${MEMORY_VERIFY_TRIES:-3}"
    i=0
    while [ "$i" -lt "$TRIES" ]; do
      ANS="$(COGNEE_DATASET="$VDS" MEMORY_TIMEOUT="${MEMORY_TIMEOUT:-90}" "$0" recall "Isaret nedir?" 2>/dev/null || true)"
      printf '%s' "$ANS" | grep -q "$TOKEN" && break
      i=$((i+1)); sleep 3
    done
    # Temizlik: dogrulama verisi kurum hafizasinda kalmaz.
    if [ -n "${VID:-}" ]; then
      curl -s -m 30 "${AUTH[@]}" -X DELETE "$API/api/v1/datasets/$VID" >/dev/null 2>&1 || true
    fi
    if printf '%s' "$ANS" | grep -q "$TOKEN"; then
      echo "HAFIZA DOGRULANDI — yazilan belge geri okundu (tam tur)."
    else
      echo "HAFIZA DOGRULANAMADI: belge yazildi ama GERI OKUNAMADI." >&2
      echo "  Bu 'emsal yok' degil, hafiza calismiyor demektir." >&2
      echo "  bak: docker compose -p ${SDLC_COMPOSE_PROJECT:-sdlc-cognee} logs --tail 30 cognee-backend (sik sebep: saglayici kotasi/anahtari)" >&2
      exit 16
    fi
    ;;

  quality)
    # GERI GETIRME KALITESI — "verify" boruyu olcer, bu SUYU olcer.
    #
    # 21 Eyl 2026'da olculdu: verify yesil derken hafiza belgelerin yarisini
    # bulamiyordu (embedding modeli Ingilizce odakliydi, korpus Turkce). Bir
    # kontrolun yesil olmasi, OLCTUGU SEYIN dogru sey oldugu anlamina gelmez.
    #
    # Sinav sdlc/quality-probe.json icinde: her soru icin KAYNAK BELGE onceden
    # yazili. Sorular belgenin kelimeleriyle DEGIL, insanin soracagi gibi
    # yazilmali — aksi halde yontem kendi sinavini yazmis olur ve hep kazanir
    # (FTS5 ayni sinavda 14/14'ten 4/14'e dustu).
    require_up
    PROBE="${SDLC_QUALITY_PROBE:-$ROOT/sdlc/quality-probe.json}"
    [ -f "$PROBE" ] || { echo "sinav dosyasi yok: $PROBE" >&2; exit 1; }
    DSNAME="${COGNEE_DATASET:-$DATASET_DEFAULT}"
    DSID="$(dataset_id "$DSNAME")" || { echo "hafizaya ulasilamadi" >&2; exit 14; }
    [ -n "$DSID" ] || { echo "dataset yok: $DSNAME" >&2; exit 13; }
    node -e '
      const { execSync } = require("node:child_process");
      const fs = require("node:fs");
      const [probe, key, api, dsid, min] = process.argv.slice(1);
      const qs = JSON.parse(fs.readFileSync(probe, "utf8")).questions || [];
      let t1 = 0, t3 = 0;
      for (const { q, want } of qs) {
        const body = JSON.stringify({ query: q, searchType: "CHUNKS", topK: 3, datasetIds: [dsid] });
        let out = "";
        try {
          out = execSync(
            `curl -s -m 90 -H "X-Api-Key: ${key}" -H "content-type: application/json" -X POST ${api}/api/v1/recall -d ${JSON.stringify(body)}`,
            { encoding: "utf8", maxBuffer: 10e6 }
          );
        } catch { /* ag hatasi: kacirilmis sayilir */ }
        let a = []; try { a = JSON.parse(out) } catch {}
        a = Array.isArray(a) ? a : [a];
        const names = a.map((c) => String(c?.metadata?.document_name || "?").toUpperCase());
        const hit = (n) => names.slice(0, n).some((x) => x.includes(want.toUpperCase()));
        if (hit(1)) t1++;
        if (hit(3)) t3++;
        console.log(`  ${hit(3) ? "OK " : "-- "} ${want.padEnd(16)} -> ${names.slice(0,3).join(", ")}`);
      }
      const pct = qs.length ? Math.round((100 * t3) / qs.length) : 0;
      console.log(`\n  top1 ${t1}/${qs.length} · top3 ${t3}/${qs.length} (%${pct})`);
      if (pct < Number(min)) {
        console.error(`GERI GETIRME KALITESI DUSUK: %${pct} < %${min}`);
        console.error("  Muhtemel sebep: embedding modeli korpusun diline uymuyor, ya da");
        console.error("  buyuk belgeler parca havuzunu domine ediyor (korpusu daralt).");
        process.exit(16);
      }
      console.log("KALITE YETERLI");
    ' "$PROBE" "${COGNEE_API_KEY:-}" "$API" "$DSID" "${QUALITY_MIN:-60}"
    ;;

  datasets)
    require_up
    curl -s -m 15 "${AUTH[@]}" "$API/api/v1/datasets" | head -c 2000
    ;;

  *)
    echo "bilinmeyen komut: $CMD (remember | remember-ticket | skills | recall | recall-project | graph | rebuild | forget-ticket | datasets | status | verify | quality)" >&2
    exit 1
    ;;
esac
