# shellcheck shell=bash
# Proje kokunu bulur — harness'in NEREDE durdugundan bagimsiz.
#
#   . "$(dirname "${BASH_SOURCE[0]}")/_root.sh"
#   ROOT="$(sdlc_root)"
#
# Neden. Harness 21 kabuk script'i ve 9 gate'te kokunu "kendi konumumun iki
# ustu" diye buluyordu. Bu, "ben projenin ICINDE yasiyorum" varsayimini koda
# gomuyor: harness ayri bir repoya alinip submodule olarak baglandiginda
# (<proje>/sdlc-harness/scripts/sdlc/test.sh) iki ust artik proje koku degil,
# harness koku olur ve her sey sessizce yanlis dizinde calisir.
#
# Sira (ilk bulunan kazanir):
#   1. SDLC_PROJECT_ROOT — acikca soylenmis. Test ve CI icin de bu kullanilir.
#   2. Yukari yuru: sdlc/project.json TASIYAN ilk dizin. Projeyi proje yapan
#      sey yapilandirmasidir; harness'in kendi reposunda bu dosya YOKTUR.
#   3. Git ust dizini — yapilandirma henuz uretilmemisse (init.sh ilk kosusu).
#
# Bulamazsa SESSIZCE devam etmez: yanlis kokte calismak, calismamaktan beterdir.

sdlc_root() {
  if [ -n "${SDLC_PROJECT_ROOT:-}" ]; then
    [ -d "$SDLC_PROJECT_ROOT" ] || {
      echo "SDLC_PROJECT_ROOT dizin degil: $SDLC_PROJECT_ROOT" >&2
      return 1
    }
    (cd "$SDLC_PROJECT_ROOT" && pwd)
    return 0
  fi

  # Cagiran script'in bulundugu yerden yukari yuru.
  local here="${_SDLC_CALLER_DIR:-$PWD}"
  local d
  d="$(cd "$here" 2>/dev/null && pwd)" || d="$PWD"
  while [ "$d" != "/" ]; do
    if [ -f "$d/sdlc/project.json" ]; then
      printf '%s\n' "$d"
      return 0
    fi
    d="$(dirname "$d")"
  done

  # Yapilandirma yoksa git ust dizinine dus (init.sh ilk kosusu).
  local top
  if top="$(git -C "$here" rev-parse --show-toplevel 2>/dev/null)" && [ -n "$top" ]; then
    printf '%s\n' "$top"
    return 0
  fi

  echo "proje koku bulunamadi: sdlc/project.json yok ve git deposu degil" >&2
  echo "  acikca soylemek icin: SDLC_PROJECT_ROOT=/yol/proje" >&2
  return 1
}

# Harness'in KENDI koku — proje kokunden farkli olabilir.
#
# Ayirma sonrasi iki ayri sey var ve karistirilirsa her sey sessizce yanlis
# dizine bakar:
#   proje koku    : <proje>/            (sdlc/project.json burada)
#   harness koku  : <proje>/sdlc-harness/  (gates/, scripts/sdlc/ burada)
# Ayni repoda ikisi ayni dizindir; ayrildiginda degildir.
sdlc_harness_root() {
  local d
  d="$(cd "${_SDLC_CALLER_DIR:-$PWD}" && pwd)"
  # scripts/sdlc/<script> → iki ust harness koku
  printf '%s\n' "$(cd "$d/../.." && pwd)"
}
