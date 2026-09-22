#!/usr/bin/env bash
# Insan onayini KAYDA GECIRIR.
#
#   scripts/sdlc/approve.sh <TICKET> <kapi> "<gerekce>"
#   scripts/sdlc/approve.sh F4-1 blast "geri alinabilir, migration yok"
#   scripts/sdlc/approve.sh --check F4-1 blast      # onay var mi (exit 0/1)
#
# 21 Eylul 2026'da olculdu: blast kapisi insan onayi istedi, insan onayladi ve bu
# onay HICBIR YERE yazilmadi — yalnizca sohbette kaldi. Bir finans reposunda
# "kim, ne zaman, neden onayladi" sorusunun cevabi sohbet gecmisi olamaz.
#
# Onay bir bayrak degil bir KAYITTIR: workflow artik args.blastApproved yerine
# bu kaydi ariyor, yani onay izi birakmadan gecilemiyor.
set -uo pipefail

# Proje koku: harness'in nerede durdugundan bagimsiz (bkz. _root.sh).
_SDLC_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SDLC_CALLER_DIR/_root.sh"
ROOT="$(sdlc_root)" || exit 1
HARNESS="$(sdlc_harness_root)"

if [ "${1:-}" = "--check" ]; then
  TICKET="${2:?}"; GATE="${3:?}"
  node --input-type=module -e '
    const { read, verify } = await import("'"$HARNESS"'/gates/journal.ts");
    const [ticket, gate] = process.argv.slice(1);
    const verdict = verify(ticket);
    if (!verdict.ok) {
      console.error(`onay okunamadi: karar defteri bozuk: ${verdict.reason}`);
      process.exit(1);
    }
    const rows = read(ticket);
    // Onay, o kapinin SON olcumunden sonra verilmis olmali: kapi yeniden
    // olculup yine "human" dediyse eski onay gecerli degildir.
    const lastGate = [...rows].reverse().find((r) => r.gate === gate);
    const lastOk = [...rows].reverse().find((r) => r.gate === `approve:${gate}`);
    if (!lastOk || lastGate?.decision !== "human") process.exit(1);
    // Onay BELGEYE verilir, olcume degil. Kapinin her kosuda yeniden olculmesi
    // onayi bayatlatmamali — yoksa onay hicbir zaman gecerli olamaz (olculdu
    // 21 Eyl 2026: hat onayli oldugu halde ayni kapida durdu). Gecersiz kilan
    // sey belgenin DEGISMESIDIR.
    const fs = await import("node:fs"), crypto = await import("node:crypto");
    const hashOf = (p) => { try { return crypto.createHash("sha256")
      .update(fs.readFileSync(p.startsWith("/") ? p : `'"$ROOT"'/${p}`)).digest("hex").slice(0,16) }
      catch { return "" } };
    const approvedHash = lastOk.measures && lastOk.measures.artifactHash;
    const nowHash = lastGate ? hashOf(lastGate.artifact) : "";
    if (approvedHash && nowHash && approvedHash !== nowHash) {
      console.error("onay gecersiz: belge onaydan sonra degisti");
      process.exit(1);
    }
    console.log(`${lastOk.at.slice(0,16).replace("T"," ")} · ${lastOk.reason}`);
  ' "$TICKET" "$GATE"
  exit $?
fi

TICKET="${1:?kullanim: approve.sh <TICKET> <kapi> \"<gerekce>\"}"
GATE="${2:?kapi adi: spec | scope | blast | review | postbuild}"
REASON="${3:?gerekce zorunlu — neden onayladigin kaydin kendisi kadar onemli}"
# ONAY NEREDEN GELDI — ve neyin garantisi neyle sagleniyor.
#
# Once TTY sartti: "onay interaktif terminalde verilmeli". O kontrol TEK bir
# seyi engellemeye calisiyordu — ajanin kendi kosusunun icinde kendi kapisini
# onaylamasi. Ama TTY bunun zayif bir vekili (PTY taklit edilebilir) ve gercek
# bir bedeli var: sohbet uzerinden calisan insani KENDI aracinda kilitliyor
# (olculdu 22 Eyl 2026: kullanici onayi verdi, hat gecirmedi).
#
# Asil garantiler zaten baska yerlerde ve daha guclu:
#   - onay SON kapi satirina baglanir ve o satir "human" degilse reddedilir
#   - artifact hash'i yazilir; kapi yeniden olculurse onay duser (readiness)
#   - defter muhur zinciri kurcalamayi gosterir
#   - ORKESTRATOR approve.sh'i yalnizca --check ile cagirir (selftest zorlar)
# Sonuncusu, TTY'nin yapmaya calistigi seyi YAPISAL olarak yapar.
#
# Geriye "onay nasil geldi" kaliyor; o da artik kayda geciyor. Okuyan kisi
# terminal onayiyla sohbet onayini ayirt edebilsin diye.
if [ -t 0 ] && [ -t 1 ]; then
  CHANNEL="terminal"
  WHO="$(id -un)"
  printf '%s\n' "Insan onayi: $TICKET · $GATE · $WHO" "Gerekce: $REASON"
  printf 'Kaydetmek icin EVET yaz: '
  read -r CONFIRM
  [ "$CONFIRM" = "EVET" ] || { echo "onay kaydedilmedi" >&2; exit 2; }
else
  CHANNEL="${SDLC_APPROVE_CHANNEL:-}"
  WHO="${SDLC_APPROVE_AS:-}"
  if [ -z "$WHO" ] || [ -z "$CHANNEL" ]; then
    echo "onay terminalsiz kaydedilecekse KIMIN verdigi ve NEREDEN geldigi yazilmalidir:" >&2
    echo "  SDLC_APPROVE_AS=\"<isim>\" SDLC_APPROVE_CHANNEL=chat scripts/sdlc/approve.sh $TICKET $GATE \"<gerekce>\"" >&2
    echo "  (terminalde koşarsan ikisi de gerekmez; kanal 'terminal' yazilir)" >&2
    exit 2
  fi
  case "$CHANNEL" in
    chat|ci|terminal) ;;
    *) echo "bilinmeyen onay kanali: $CHANNEL (chat | ci | terminal)" >&2; exit 2 ;;
  esac
  echo "onay kaydediliyor · kanal: $CHANNEL · veren: $WHO" >&2
fi

node --input-type=module -e '
  const { record, read, verify } = await import("'"$HARNESS"'/gates/journal.ts");
  const [ticket, gate, reason, who, channel] = process.argv.slice(1);
  const verdict = verify(ticket);
  if (!verdict.ok) {
    console.error(`onay reddedildi: karar defteri bozuk: ${verdict.reason}`);
    process.exit(2);
  }
  const rows = read(ticket);
  const lastGate = [...rows].reverse().find((r) => r.gate === gate);
  if (!lastGate) {
    console.error(`onay reddedildi: ${ticket} icin "${gate}" kapisi hic olculmemis — once kapiyi kostur`);
    process.exit(2);
  }
  if (lastGate.decision !== "human") {
    console.error(`onay reddedildi: ${gate} kapisi "human" demedi (${lastGate.decision})`);
    process.exit(2);
  }
  const fs = await import("node:fs"), crypto = await import("node:crypto");
  let artifactHash = "";
  try {
    const p = lastGate.artifact.startsWith("/") ? lastGate.artifact : `'"$ROOT"'/${lastGate.artifact}`;
    artifactHash = crypto.createHash("sha256").update(fs.readFileSync(p)).digest("hex").slice(0, 16);
  } catch { /* artifact dosya degil (ornegin worktree) — hash yok, onay olcume bagli kalir */ }
  record({
    gate: `approve:${gate}`,
    ticket,
    artifact: lastGate.artifact,
    decision: "approved",
    reason: `${who}: ${reason}`,
    // Kanal da kayda girer: terminal onayi ile sohbet onayini okuyan biri
    // ayirt edebilmeli. Ikisi de gecerlidir, ama ayni sey degildir.
    measures: { ...(lastGate.measures ?? {}), channel, ...(artifactHash ? { artifactHash } : {}) },
  });
  console.log(`onay kaydedildi — ${ticket} · ${gate} · ${who} · kanal: ${channel}`);
  console.log(`kapinin gerekcesi: ${lastGate.reason}`);
' "$TICKET" "$GATE" "$REASON" "$WHO" "$CHANNEL"
