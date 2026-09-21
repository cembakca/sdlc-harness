#!/usr/bin/env bash
# DEVREDEN CIKTI (D1) — start.sh artik `make` arayuzune yonlendiriyor.
#
# Bu script eski `docker-compose.dev.yml` yigininin uzerinde calisiyordu.
# Yigin tek bir tanima tasindi (compose.yml + overlay'ler) ve ikisi ayni anda
# calisamaz: ayni portlari isterler. Eski surum 14 Eylul 2026'da silindi.
echo "scripts/start.sh devreden cikti — karsiligi: make up" >&2

exec make -C "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" up "$@"
