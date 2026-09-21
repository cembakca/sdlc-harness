#!/usr/bin/env bash
# Kadrodaki her role Cognee'de bir kimlik acar.
#
#   scripts/sdlc/agents.sh sync    # kadroyu Cognee ajanlariyla eslestir
#   scripts/sdlc/agents.sh list    # kayitli ajanlar
#   scripts/sdlc/agents.sh key <rol>
#
# Neden: hafizaya kimin yazdigi izlenebilir olsun. Tek anahtarla yazdigimizda
# graf "birisi yazdi" diyor; rol basina kimlikle "mimar yazdi, denetci okudu"
# diyebiliyor — ve Cognee oturum/maliyet raporlarini ajan bazinda cikariyor.
#
# Anahtarlar varsayilan olarak ops/cognee/agents.env icinde, gitignore'lu ve 0600.
# Konum SABIT DEGIL: SDLC_AGENTS_ENV ile degistirilebilir — baska bir repoda
# ops/cognee/ dizini olmayabilir (dis denetimde bulundu 21 Eyl 2026).
set -uo pipefail

# Proje koku: harness'in nerede durdugundan bagimsiz (bkz. _root.sh).
_SDLC_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SDLC_CALLER_DIR/_root.sh"
ROOT="$(sdlc_root)" || exit 1
HARNESS="$(sdlc_harness_root)"
API="${COGNEE_API_URL:-http://localhost:8765}"
STORE="${SDLC_AGENTS_ENV:-$ROOT/ops/cognee/agents.env}"
mkdir -p "$(dirname "$STORE")" 2>/dev/null || true
ADMIN_KEY="${COGNEE_API_KEY:-$(grep -m1 '^COGNEE_API_KEY=' "$ROOT/.env" 2>/dev/null | cut -d= -f2-)}"

up() { curl -sf -m 10 -o /dev/null "$API/health" 2>/dev/null; }
roles() { node "$HARNESS/sdlc/roster.ts" | awk '{print $1}'; }

case "${1:-sync}" in
  sync)
    up || { echo "cognee kapali ($API)" >&2; exit 0; }
    [ -n "$ADMIN_KEY" ] || { echo ".env icinde COGNEE_API_KEY yok" >&2; exit 1; }
    touch "$STORE"; chmod 600 "$STORE"
    for role in $(roles); do
      VAR="COGNEE_AGENT_$(printf '%s' "$role" | tr '[:lower:]-' '[:upper:]_')"
      # KAYITLI ANAHTAR, GECERLI ANAHTAR DEMEK DEGILDIR. Birimler silindiginde
      # (embedding boyutu degisince sart oluyor) Cognee'deki ajanlar gider ama
      # agents.env'deki satirlar kalir; script "zaten var" deyip geciyor ve
      # rol kimligiyle yazan her cagri Unauthorized aliyordu (olculdu
      # 21 Eyl 2026 — remember-decisions sessizce dusuyordu). Artik anahtarin
      # CALISTIGI dogrulanir; calismiyorsa yenisi uretilir.
      EXIST="$(grep -m1 "^$VAR=" "$STORE" 2>/dev/null | cut -d= -f2-)"
      if [ -n "$EXIST" ]; then
        if curl -sf -m 10 -o /dev/null -H "X-Api-Key: $EXIST" "$API/api/v1/datasets"; then
          echo "zaten var: $role"
          continue
        fi
        echo "gecersiz anahtar, yenileniyor: $role"
        node -e 'const f=require("node:fs"),[p,v]=process.argv.slice(1);
          f.writeFileSync(p, f.readFileSync(p,"utf8").split("\n").filter(l=>!l.startsWith(v+"=")).join("\n"))' "$STORE" "$VAR"
      fi
      RESP="$(curl -s -m 20 -H "X-Api-Key: $ADMIN_KEY" -X POST "$API/api/v1/agents/create?name=sdlc-$role" 2>&1)"
      AKEY="$(printf '%s' "$RESP" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).agentApiKey||"")}catch{console.log("")}})')"
      if [ -n "$AKEY" ]; then
        printf '%s=%s\n' "$VAR" "$AKEY" >> "$STORE"
        echo "kimlik acildi: $role"
      else
        echo "basarisiz: $role — $(printf '%s' "$RESP" | head -c 120)" >&2
      fi
    done
    chmod 600 "$STORE"
    ;;

  list)
    up || { echo "cognee kapali" >&2; exit 0; }
    curl -s -m 15 -H "X-Api-Key: $ADMIN_KEY" "$API/api/v1/agents/list" | node -e '
      let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
        let a=[];try{a=JSON.parse(s)}catch{}
        if(!a.length){console.log("(kayitli ajan yok — scripts/sdlc/agents.sh sync)");return}
        for(const x of a) console.log(`${(x.name||x.agentName||"?").padEnd(28)} ${x.id||x.agentId||""}`)})'
    ;;

  key)
    ROLE="${2:?kullanim: agents.sh key <rol>}"
    VAR="COGNEE_AGENT_$(printf '%s' "$ROLE" | tr '[:lower:]-' '[:upper:]_')"
    grep -m1 "^$VAR=" "$STORE" 2>/dev/null | cut -d= -f2-
    ;;

  *) echo "bilinmeyen komut: $1 (sync | list | key)" >&2; exit 1 ;;
esac
