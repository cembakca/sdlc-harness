#!/usr/bin/env bash
# D6 — indeks disiplini kapisi.
#
# `ROADMAP.md` zaten yaziyor: "yeni koleksiyonlarin indeksleri
# `db_validators.get_index_specs_for_collection`'a kaydedilmeli, ad hoc
# olusturulmamali." Bu script o kurali otomatiklestirir.
#
# Neden onemli: ad hoc olusturulan bir indeks, olusturan kod yolu calismadigi
# surece YOKTUR. Uretimde o yol ilk kez gece yarisi calisirsa, indeks o an
# kurulur ve koleksiyon buyukse sorgular dakikalarca kilitlenir. Ayrica indeks
# migrasyonu (scripts/migrate_indexes.py) onu hic gormez: fark raporu "tamam"
# der, gercek ise oyle degildir.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; DIM=$'\033[2m'; NC=$'\033[0m'

# Izinli yerler: spesifikasyonun kendisi, migrasyon araci, acilistaki
# zamanlayici-kritik kume (gerekcesi main.py icinde yazili) ve seed script'i.
# Izinliler ve GEREKCELERI:
#   db_validators.py             tek dogru kaynak
#   migrate_indexes.py           deploy adimi
#   main.py                      zamanlayici-kritik kume (gerekcesi kodda yazili)
#   seed_dev_environment.py      gelistirme tohumlamasi
#   apply_integrity_validators   spec'i OKUYOR, kendi tanimlamiyor
#   migrate_billing_usage_*      ayni sekilde, D6'da donusturuldu
ALLOWED='server/app/core/db_validators.py|server/scripts/migrate_indexes.py|server/app/main.py|server/app/scripts/seed_dev_environment.py|server/scripts/apply_integrity_validators.py|server/scripts/migrate_billing_usage_collections.py'

hits="$(grep -rn "create_index\|createIndex" server/app server/scripts \
        --include='*.py' 2>/dev/null \
        | grep -vE "^($ALLOWED):" || true)"

printf "\n${DIM}indeks disiplini${NC}\n\n"

if [ -z "$hits" ]; then
  printf "  ${GREEN}ad hoc indeks olusturma yok.${NC}\n\n"
  exit 0
fi

printf "  ${RED}Spesifikasyon disinda indeks olusturuluyor:${NC}\n\n"
echo "$hits" | sed 's/^/    /'
cat <<'TXT'

  Bunlari `app/core/db_validators.py` icindeki `_INDEX_SPECS`'e tasiyin.
  Orada tanimlanan her indeks, deploy adimi tarafindan olusturulur ve
  `scripts/migrate_indexes.py` tarafindan denetlenir.

TXT
exit 1
