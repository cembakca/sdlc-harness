#!/usr/bin/env bash
# D3 kabul kriteri: prova yigini ile uretim tanimi arasindaki fark
# YALNIZCA alan adlari ve sir degerleri olmali.
#
# Bu script o farki basar. Anlatilan degil, olculen bir kriter olsun diye var:
# "prova uretime benziyor" cumlesi, benzemedigi gun de ayni sekilde soylenir.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

DIM=$'\033[2m'; GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; NC=$'\033[0m'
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Uretim compose'u zorunlu degiskenler ister; farki GORMEK icin yer tutucu
# veriyoruz. Degerler zaten karsilastirmanin disinda tutuluyor.
PLACEHOLDER_ENV=(
  JWT_SECRET_KEY=PLACEHOLDER
  IMAGE_SERVER=PLACEHOLDER-server IMAGE_CRAWLER=PLACEHOLDER-crawler
  IMAGE_CLIENT=PLACEHOLDER-client IMAGE_LANDING=PLACEHOLDER-landing
  IMAGE_BACKUP=PLACEHOLDER-backup
  API_DOMAIN=api.example APP_DOMAIN=app.example LANDING_DOMAIN=example
  RESTIC_REPOSITORY=PLACEHOLDER RESTIC_PASSWORD=PLACEHOLDER
  B2_ACCOUNT_ID=PLACEHOLDER B2_ACCOUNT_KEY=PLACEHOLDER
)

# Karsilastirilan alanlar: ne calisiyor ve nasil calisiyor. Adresler, sirlar ve
# imaj etiketleri disarida — onlarin farkli olmasi zaten beklenen tek sey.
FIELDS='^\s+(command|user|shm_size|restart|entrypoint):'

env "${PLACEHOLDER_ENV[@]}" docker compose -f compose.yml -f compose.prod.yml --profile frontend --profile backup --profile observability config 2>/dev/null \
  | grep -E "$FIELDS" | sed 's/^[[:space:]]*//' | sort -u > "$TMP/prod.txt"

env "${PLACEHOLDER_ENV[@]}" docker compose -f compose.yml -f compose.prod.yml --profile frontend --profile backup --profile observability config --services 2>/dev/null \
  | sort > "$TMP/prod-services.txt"

docker compose --env-file .env.development -f compose.yml -f compose.local-prod.yml --profile local --profile frontend --profile backup --profile observability config 2>/dev/null \
  | grep -E "$FIELDS" | sed 's/^[[:space:]]*//' | sort -u > "$TMP/local.txt"

docker compose --env-file .env.development -f compose.yml -f compose.local-prod.yml --profile local --profile frontend --profile backup --profile observability config --services 2>/dev/null \
  | sort > "$TMP/local-services.txt"

printf "\n${DIM}prova (compose.local-prod) <-> uretim (compose.prod)${NC}\n"
printf "${DIM}karsilastirilan: imaj, komut, kullanici, shm — adresler ve sirlar disarida${NC}\n\n"

# Provada fazladan olmasi BEKLENEN servisler. Liste burada duruyor ki fark
# "her zaman biraz farkli" diye normallesmesin: bu dorduden baska bir sey
# cikarsa kontrol kirmizi yanar.
# grafana: D7 karari — uretimde arayuz calistirmak 256 MB eder ve bakilacak bir
# sey oldugunda ayni veriye lokalde bakilabilir. Gozlem katmaninin GERI KALANI
# (loki, alloy, prometheus, alertmanager, node-exporter) uretimde de calisir ve
# bu yuzden karsilastirmaya dahil.
EXPECTED_LOCAL_ONLY="canary celery-exporter mailpit traefik grafana"

rc=0
printf "${DIM}-- servisler --${NC}\n"
only_prod="$(comm -23 "$TMP/prod-services.txt" "$TMP/local-services.txt")"
only_local="$(comm -13 "$TMP/prod-services.txt" "$TMP/local-services.txt")"

if [ -n "$only_prod" ]; then
  echo "$only_prod" | sed 's/^/  yalnizca URETIMDE: /' 
  printf "  ${RED}Uretimde olup provada olmayan bir servis, hic prova edilmemis demektir.${NC}\n"
  rc=1
fi

unexpected=""
for svc in $only_local; do
  case " $EXPECTED_LOCAL_ONLY " in
    *" $svc "*) printf "  ${DIM}yalnizca provada: %s (beklenen)${NC}\n" "$svc" ;;
    *) printf "  yalnizca PROVADA: %s\n" "$svc"; unexpected="$unexpected $svc" ;;
  esac
done
if [ -n "$unexpected" ]; then
  printf "  ${RED}Beklenmeyen:%s — ya uretime eklenmeli ya bu listeye.${NC}\n" "$unexpected"
  rc=1
fi
if [ -z "$only_prod" ] && [ -z "$unexpected" ]; then
  printf "  ${GREEN}servis kumesi beklendigi gibi.${NC}\n"
fi

printf "\n${DIM}-- calisma bicimi (komut, kullanici, restart, shm) --${NC}\n"
if diff -u "$TMP/prod.txt" "$TMP/local.txt" > "$TMP/diff.txt"; then
  printf "  ${GREEN}fark yok.${NC}\n\n"
  exit $rc
fi
rc=1
sed -n '3,$p' "$TMP/diff.txt" | sed 's/^/  /'
cat <<'TXT'

  Not: bu listedeki her satir bir sorudur — "prova neden uretimden farkli
  bir sey calistiriyor?". Cevabi "olmali" olan satirlar (ornegin canary ve
  mailpit yalnizca provada bulunur) buraya yazilmali, sessizce birakilmamali.

TXT
exit $rc
