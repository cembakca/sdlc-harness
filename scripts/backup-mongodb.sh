#!/usr/bin/env bash
# DEVREDEN CIKTI (D5) — karsiligi: make backup
#
# Eskisi mongodump alip istege bagli olarak S3'e kopyaliyordu: sifreleme yok,
# tekillestirme yok, kanit arsivi (MinIO) yok ve en onemlisi GERI YUKLEME
# PROVASI yok. Iki ayri yedek yolu birakmak, hangisinin gercekten calistigini
# bilmemek demek. Eski surum 14 Eylul 2026'da silindi.
echo "scripts/backup-mongodb.sh devreden cikti — karsiligi: make backup" >&2
echo "geri yukleme provasi:                            make backup-drill" >&2

exec make -C "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" backup
