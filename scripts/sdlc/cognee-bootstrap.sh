#!/usr/bin/env bash
# Cognee erisimini SIFIRDAN kurar: kullanici + API anahtari.
#
#   scripts/sdlc/cognee-bootstrap.sh
#
# Neden gerekti: anahtar bir kez ELLE uretilmis ve yalnizca docker biriminin
# icinde yasiyordu. Birimler silindiginde (embedding boyutu degistigi icin
# sifirlama sarttI) erisim de gitti ve API "Unauthorized" demeye basladi
# (olculdu 21 Eyl 2026). Script'lenmemis bir kurulum adimi, olmayan bir kurulum
# adimidir: baska bir makinede ya da her sifirlamada tekrar kesfedilmesi gerekir.
#
# Bu script iki kez kosturulabilir (idempotent): kullanici varsa gecer,
# anahtari .env icine yazar.
set -uo pipefail

# Proje koku: harness'in nerede durdugundan bagimsiz (bkz. _root.sh).
_SDLC_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SDLC_CALLER_DIR/_root.sh"
ROOT="$(sdlc_root)" || exit 1
API="${COGNEE_API_URL:-http://localhost:8765}"
ENV_FILE="$ROOT/.env"

envval() { grep -m1 "^$1=" "$ENV_FILE" 2>/dev/null | cut -d= -f2-; }

EMAIL="${COGNEE_USER_EMAIL:-$(envval COGNEE_USER_EMAIL)}"
PASS="${COGNEE_USER_PASSWORD:-$(envval COGNEE_USER_PASSWORD)}"
[ -n "$EMAIL" ] || EMAIL="sdlc-harness@example.com"  # .local/.test/.invalid ozel-kullanim alan adlari reddediliyor; hesap yereldir, posta gitmez
# Parola uretilirse .env'e yazilir; bir daha uretilmez.
if [ -z "$PASS" ]; then
  PASS="$(node -e 'console.log(require("node:crypto").randomBytes(24).toString("base64url"))')"
  GENERATED=1
fi

echo "== cognee erisimi kuruluyor ($API)"
curl -sf -m 10 -o /dev/null "$API/health" || { echo "cognee kapali — once: make cognee-up" >&2; exit 1; }

# 1. Kullanici (varsa zaten kayitli, hata yutulur)
REG="$(curl -s -m 20 -X POST "$API/api/v1/auth/register" \
  -H "content-type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\",\"is_superuser\":true}" 2>&1)"
case "$REG" in
  *REGISTER_USER_ALREADY_EXISTS*) echo "  kullanici zaten var: $EMAIL" ;;
  *\"id\"*)                       echo "  kullanici olusturuldu: $EMAIL" ;;
  *) echo "  kayit yaniti: $(printf '%s' "$REG" | head -c 200)" ;;
esac

# 2. Giris → Bearer token
TOKEN="$(curl -s -m 20 -X POST "$API/api/v1/auth/login" \
  -H "content-type: application/x-www-form-urlencoded" \
  --data-urlencode "username=$EMAIL" --data-urlencode "password=$PASS" \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      try{const r=JSON.parse(s);console.log(r.access_token||"")}catch{console.log("")}})')"
if [ -z "$TOKEN" ]; then
  echo "giris basarisiz: $EMAIL" >&2
  echo "  Parola .env ile uyusmuyorsa COGNEE_USER_PASSWORD'u duzelt ya da" >&2
  echo "  birimleri sifirla: make cognee-reset" >&2
  exit 2
fi
echo "  giris tamam"

# 3. API anahtari
KEY="$(curl -s -m 20 -X POST "$API/api/v1/auth/api-keys" \
  -H "Authorization: Bearer $TOKEN" -H "content-type: application/json" \
  -d '{"name":"sdlc-harness"}' \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      let r={};try{r=JSON.parse(s)}catch{}
      console.log(r.api_key||r.key||r.token||r.value||"")})')"
[ -n "$KEY" ] || { echo "anahtar uretilemedi" >&2; exit 3; }
echo "  anahtar uretildi"

# 4. .env guncelle (deger gosterilmez)
upsert() { # upsert <KEY> <VALUE>
  if grep -q "^$1=" "$ENV_FILE" 2>/dev/null; then
    node -e 'const f=require("node:fs"),[p,k,v]=process.argv.slice(1);
      const s=f.readFileSync(p,"utf8").replace(new RegExp("^"+k+"=.*$","m"),k+"="+v);
      f.writeFileSync(p,s)' "$ENV_FILE" "$1" "$2"
  else
    printf '%s=%s\n' "$1" "$2" >> "$ENV_FILE"
  fi
}
upsert COGNEE_API_KEY "$KEY"
upsert COGNEE_USER_EMAIL "$EMAIL"
[ "${GENERATED:-0}" = "1" ] && upsert COGNEE_USER_PASSWORD "$PASS"
echo "  .env guncellendi: COGNEE_API_KEY, COGNEE_USER_EMAIL${GENERATED:+, COGNEE_USER_PASSWORD}"

# 5. Rol kimlikleri de yenilenir: sifirlama onlari da gotururur ve agents.env'de
#    kalan eski satirlar "zaten var" sanilip rol kimligiyle yazan her cagri
#    Unauthorized aliyordu (olculdu 21 Eyl 2026). Kurulum eksik birakilmaz.
if [ -x "$ROOT/scripts/sdlc/agents.sh" ]; then
  echo "  rol kimlikleri kontrol ediliyor"
  COGNEE_API_KEY="$KEY" "$ROOT/scripts/sdlc/agents.sh" sync 2>&1 | sed 's/^/    /' || true
fi

# 6. Kanit: anahtar gercekten okuyor mu
if curl -sf -m 15 -H "X-Api-Key: $KEY" "$API/api/v1/datasets" >/dev/null 2>&1; then
  echo "DOGRULANDI — anahtar calisiyor."
else
  echo "anahtar uretildi ama okuma basarisiz" >&2; exit 4
fi
