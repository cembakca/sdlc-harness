#!/usr/bin/env bash
# client + landing'i host uzerinde arka planda calistirir.
#
# Neden host'ta: macOS'ta bind mount uzerinden Vite/Next HMR belirgin yavas.
# Parite testi gerektiginde `make up-all` ayni arayuzleri konteynerde kaldirir.
#
# Neden ayri bir script: sureci make recipe'i icinde arka plana atmak iki tuzak
# barindiriyor — (1) cocuk surec make'in stdout borusunu miras alirsa `make up`
# hic donmez, (2) `( cd x && cmd & echo $! )` yazildiginda `&` tum AND-listesine
# baglanir ve $! yanlis sureci gosterir. Ikisi de burada, tek yerde cozuldu.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RUN_DIR="$ROOT/.run"
CLIENT_PORT="${CLIENT_PORT:-5173}"
LANDING_PORT="${LANDING_PORT:-3001}"
mkdir -p "$RUN_DIR"

is_alive() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }

start_one() { # ad, dizin, komut...
  local name="$1" dir="$2"; shift 2
  local pidfile="$RUN_DIR/$name.pid" log="$RUN_DIR/$name.log"

  if is_alive "$pidfile"; then
    echo "  $name zaten calisiyor (pid $(cat "$pidfile"))"
    return 0
  fi

  # Tum akislar yonlendirilir (</dev/null dahil): cagiranin borusu acik kalmaz.
  # `;` ile ayrildi ki `&` yalnizca nohup satirina baglansin.
  ( cd "$ROOT/$dir"; nohup "$@" >"$log" 2>&1 </dev/null & echo $! >"$pidfile" )

  sleep 1
  if is_alive "$pidfile"; then
    echo "  $name baslatildi (pid $(cat "$pidfile")) -> .run/$name.log"
  else
    echo "  $name BASLAYAMADI — son satirlar:"
    tail -5 "$log" | sed 's/^/      /'
    return 1
  fi
}

stop_one() {
  local name="$1" pidfile="$RUN_DIR/$1.pid"
  if ! [ -f "$pidfile" ]; then echo "  $name zaten durmus"; return 0; fi
  local pid; pid="$(cat "$pidfile")"
  if kill -0 "$pid" 2>/dev/null; then
    # npm, asil sunucuyu cocuk surec olarak calistirir; once onlar.
    pkill -TERM -P "$pid" 2>/dev/null || true
    kill -TERM "$pid" 2>/dev/null || true
    for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
    pkill -KILL -P "$pid" 2>/dev/null || true
    kill -KILL "$pid" 2>/dev/null || true
  fi
  rm -f "$pidfile"
  echo "  $name durduruldu"
}

status_one() {
  local name="$1" port="$2" pidfile="$RUN_DIR/$1.pid"
  if is_alive "$pidfile"; then
    echo "  $name: calisiyor (pid $(cat "$pidfile"), http://localhost:$port)"
  else
    echo "  $name: durmus"
  fi
}

case "${1:-start}" in
  start)
    rc=0
    start_one client   client      npm run dev -- --port "$CLIENT_PORT" --strictPort || rc=1
    start_one landing  landingpage npm run dev -- --port "$LANDING_PORT" || rc=1
    exit $rc
    ;;
  stop)    stop_one client; stop_one landing ;;
  status)  status_one client "$CLIENT_PORT"; status_one landing "$LANDING_PORT" ;;
  *)       echo "kullanim: $0 {start|stop|status}"; exit 1 ;;
esac
