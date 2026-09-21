#!/usr/bin/env bash
# D3 — sir yonetimi (SOPS + age).
#
#   scripts/secrets.sh edit [ortam]     sifreli dosyayi duzenle   (varsayilan: prod)
#   scripts/secrets.sh check [ortam]    sablon ile fark raporu
#   scripts/secrets.sh cat [ortam]      coz ve stdout'a bas (dikkat)
#
# Cozme anahtari: ~/.config/sops/age/keys.txt
# O dosya kaybolursa secrets/ altindaki hicbir sey bir daha acilmaz. Yedekleyin.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; DIM=$'\033[2m'; NC=$'\033[0m'

ACTION="${1:-check}"
ENVNAME="${2:-prod}"
ENC="secrets/${ENVNAME}.enc.env"
TPL="secrets/${ENVNAME}.env.example"

command -v sops >/dev/null || { echo "${RED}sops kurulu degil${NC} — brew install sops age"; exit 1; }
[ -f "$SOPS_AGE_KEY_FILE" ] || { echo "${RED}age anahtari yok:${NC} $SOPS_AGE_KEY_FILE"; exit 1; }

case "$ACTION" in
  edit)
    [ -f "$ENC" ] || { echo "${RED}yok:${NC} $ENC"; exit 1; }
    sops "$ENC"
    ;;

  cat)
    [ -f "$ENC" ] || { echo "${RED}yok:${NC} $ENC"; exit 1; }
    sops --decrypt --input-type dotenv --output-type dotenv "$ENC"
    ;;

  check)
    # Uc soruyu birden sorar, hicbir deger basmadan:
    #   1. Sablonda olup sifreli dosyada olmayan anahtar var mi?
    #   2. Compose'un ZORUNLU tuttugu (${VAR:?}) bir degisken sirlarda yok mu?
    #   3. Bos kalan degerlerden hangileri kasitli ("# beklemede:"), hangileri hata?
    #
    # Sebebi: bir sirri sablona ekleyip sifreli dosyaya eklemeyi unutmak,
    # sunucuda "degisken tanimli degil" diye ancak deploy sirasinda ortaya
    # cikar — yani en pahali anda. Ikinci soru 14 Eylul 2026'da eklendi:
    # sablon ile sifreli dosya birbiriyle ortusuyordu ama compose.prod.yml'in
    # istedigi API_DOMAIN, RESTIC_* ve B2_* hicbirinde yoktu.
    for f in "$ENC" "$TPL"; do
      [ -f "$f" ] || { echo "${RED}yok:${NC} $f"; exit 1; }
    done

    plain="$(sops --decrypt --input-type dotenv --output-type dotenv "$ENC" 2>/dev/null)"
    [ -n "$plain" ] || { echo "${RED}cozulemedi:${NC} $ENC"; exit 1; }

    tpl_keys="$(grep -oE '^[A-Z_0-9]+=' "$TPL" | tr -d '=' | sort -u)"
    enc_keys="$(echo "$plain" | grep -oE '^[A-Z_0-9]+=' | tr -d '=' | sort -u)"

    # "# beklemede:" yorumu tasiyan anahtarlar — bos olmalari kasitli.
    pending="$(awk '/^# beklemede:/ {f=1; next} /^[A-Z_0-9]+=/ {if (f) {split($0,a,"="); print a[1]}; f=0} {if ($0 !~ /^#/) f=0}' "$TPL" | sort -u)"

    # Compose'un zorunlu tuttuklari. IMAGE_* haric: onlar surum etiketidir,
    # sir degil; CI manifestinden ya da `make prod-local RELEASE=` ile gelir.
    compose_req="$(grep -ohE '\$\{[A-Z_0-9]+:\?' compose.yml compose.prod.yml 2>/dev/null \
                    | sed 's/[${]//g; s/:?//' | grep -v '^IMAGE_' | sort -u)"

    missing="$(comm -23 <(echo "$tpl_keys") <(echo "$enc_keys"))"
    extra="$(comm -13 <(echo "$tpl_keys") <(echo "$enc_keys"))"
    compose_missing="$(comm -23 <(echo "$compose_req") <(echo "$enc_keys"))"
    empty_all="$(echo "$plain" | grep -E '^[A-Z_0-9]+=$' | tr -d '=' | sort -u)"
    empty_bad="$(comm -23 <(echo "$empty_all") <(echo "$pending"))"
    empty_pending="$(comm -12 <(echo "$empty_all") <(echo "$pending"))"

    printf "\n${DIM}sir raporu — %s${NC}\n\n" "$ENVNAME"
    rc=0
    if [ -n "$missing" ]; then
      printf "  ${RED}sifreli dosyada YOK${NC} (sablonda var):\n"
      echo "$missing" | sed 's/^/      /'
      rc=1
    fi
    if [ -n "$compose_missing" ]; then
      printf "  ${RED}compose ZORUNLU tutuyor, sirlarda yok${NC}:\n"
      echo "$compose_missing" | sed 's/^/      /'
      rc=1
    fi
    if [ -n "$extra" ]; then
      printf "  ${YELLOW}sablonda yok${NC} (sifreli dosyada fazladan):\n"
      echo "$extra" | sed 's/^/      /'
    fi
    if [ -n "$empty_bad" ]; then
      printf "  ${RED}degeri BOS ve beklemede degil${NC} — doldurulmali:\n"
      echo "$empty_bad" | sed 's/^/      /'
      rc=1
    fi
    if [ -n "$empty_pending" ]; then
      printf "  ${YELLOW}beklemede${NC} (saglayici hesabi acilinca doldurulur):\n"
      echo "$empty_pending" | sed 's/^/      /'
    fi
    if [ $rc -eq 0 ] && [ -z "$extra" ]; then
      printf "  ${GREEN}sablon, sifreli dosya ve compose ortusuyor.${NC}\n"
    fi
    echo
    exit $rc
    ;;

  *)
    echo "kullanim: $0 {edit|check|cat} [ortam]"; exit 1 ;;
esac
