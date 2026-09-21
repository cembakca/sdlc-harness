#!/usr/bin/env bash
# Repoya SIR girmis mi — deterministik, modelsiz.
#
#   scripts/sdlc/secret-scan.sh            # izlenen dosyalari tara
#   scripts/sdlc/secret-scan.sh --staged   # yalnizca staged olanlari (commit oncesi)
#
# 21 Eylul 2026'da olculdu: ops/cognee/agents.env (8 ajan anahtari) bir PR'a
# girdi ve push edildi. Sebep sinsiydi — dosya CALISILAN dalin .gitignore'unda
# korunuyordu, ama PR dali BASKA bir taban (main) uzerinden acildi ve o tabanin
# .gitignore'unda o satir yoktu. "git add -- ops/cognee" dosyayi sessizce aldi.
#
# Kapilarin bu sinifi gormedigi ortaya cikti: kapilar KODU denetliyor, git
# komutlarini degil. Bir .gitignore satirina guvenmek koruma degildir — koruma,
# reponun GERCEK halini olcen bir kontroldur.
#
# Iki katman:
#   1) YOL: sir tasidigi bilinen dosya adlari izleniyor mu
#   2) ICERIK: izlenen metin dosyalarinda yuksek sinyalli anahtar imzalari
#
# Exit 0 temiz, 1 bulundu.
set -uo pipefail

# Proje koku: harness'in nerede durdugundan bagimsiz (bkz. _root.sh).
_SDLC_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SDLC_CALLER_DIR/_root.sh"
ROOT="$(sdlc_root)" || exit 1
cd "$ROOT" || exit 1
MODE="${1:-}"

if [ "$MODE" = "--staged" ]; then
  FILES="$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null)"
  SCOPE="staged"
else
  FILES="$(git ls-files 2>/dev/null)"
  SCOPE="izlenen"
fi

# --- izin verilenler: yapilandirmadan, projeye ozgu istisnalar icin -----------
ALLOW="$(node -e '
  try {
    const p = require("'"$ROOT"'/sdlc/project.json");
    const a = (p.secrets && p.secrets.allowPaths) || [];
    console.log(a.join("\n"));
  } catch { }
' 2>/dev/null)"

allowed() { # allowed <yol>
  [ -n "$ALLOW" ] || return 1
  printf '%s\n' "$ALLOW" | grep -qxF "$1"
}

# --- 1. YOL kaliplari --------------------------------------------------------
# Ornek/sablon dosyalari (.example, .sample, .template, .dist) HARIC: onlarin
# isi zaten "hangi degiskenler gerekiyor" demek ve deger tasimazlar.
PATH_PAT='(^|/)\.env$|(^|/)\.env\.(local|production|prod|dev|development|test)$|agents\.env$|(^|/)secrets?\.(env|json|ya?ml)$|\.(pem|key|p12|pfx|jks)$|(^|/)id_(rsa|dsa|ecdsa|ed25519)$|(^|/)\.npmrc$|(^|/)\.pypirc$|service[-_]account.*\.json$|(^|/)credentials(\.json)?$'
EXEMPT_PAT='\.(example|sample|template|dist)$|\.example\.|/examples?/'

# Tek gecis: dosya dosya donmek 13 bin dosyada ~12 saniye suruyordu.
HITS="$(printf '%s\n' "$FILES" \
  | grep -E "$PATH_PAT" \
  | grep -vE "$EXEMPT_PAT" \
  | while IFS= read -r f; do allowed "$f" || printf '%s ' "$f"; done)"

# --- 2. ICERIK imzalari ------------------------------------------------------
# Yuksek sinyalli, dusuk yanlis-alarm: saglayicilarin kendi onekleri ve ozel
# anahtar basliklari. Genel "password=" taramasi YAPILMAZ — gurultusu koruma
# degerinden buyuk ve insan onu yok saymayi ogrenir.
CONTENT_PAT='-----BEGIN [A-Z ]*PRIVATE KEY-----|sk-[A-Za-z0-9]{32,}|AIza[0-9A-Za-z_-]{33}|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{50,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}'
# git grep TEK GECISTE tarar: dosya dosya grep 13 bin dosyada ~12 saniye
# suruyordu, bu ~0.3 saniye. -I ikili dosyalari atlar.
#
# DIKKAT — BU KOD BIR KEZ SESSIZCE HIC CALISMADI: "--cached" desenden SONRA
# yazilmisti, git "unable to resolve revision: --cached" deyip cikiyordu, stderr
# /dev/null'a gidiyordu ve BOS CIKTI "temiz" sayiliyordu. Yani koruma, korudugunu
# soyleyerek hicbir sey yapmiyordu (olculdu 21 Eyl 2026 — tam da bu tarayicinin
# engellemek icin yazildigi hata sinifi).
#
# Bu yuzden artik CIKIS KODU okunuyor: git grep 0 = eslesme var, 1 = yok,
# >1 = HATA. Hatayi "eslesme yok" saymak, korumayi kapatmaktir.
if [ "$MODE" = "--staged" ]; then
  # -e SART: desen "-----BEGIN" ile basliyor, onsuz git onu SECENEK saniyor.
  RAW_HITS="$(git grep --cached -I -l -E -e "$CONTENT_PAT" -- ':!*.lock' ':!*.min.js' ':!*.map' 2>&1)"
else
  RAW_HITS="$(git grep -I -l -E -e "$CONTENT_PAT" -- ':!*.lock' ':!*.min.js' ':!*.map' 2>&1)"
fi
GREP_RC=$?
if [ "$GREP_RC" -gt 1 ]; then
  echo "SIR TARAMASI KOSULAMADI (git grep exit $GREP_RC):" >&2
  printf '%s\n' "$RAW_HITS" | head -3 >&2
  echo "Bunu 'temiz' saymiyorum — tarama calismadan gecis yok." >&2
  exit 2
fi
[ "$GREP_RC" = "1" ] && RAW_HITS=""

# BILINEN BELGE ORNEKLERI alarm degildir. AWS kendi dokumantasyonunda
# AKIAIOSFODNN7EXAMPLE / wJalrXUtnFEMI/... yayinliyor ve bunlar gercek anahtar
# BICIMINE birebir uyuyor. Olculdu (21 Eyl 2026): tarayici bunu "gercek AWS
# kimlik bilgisi" diye raporladi. Yanlis alarm, korumanin en pahali arizasidir —
# insan alarmi yok saymayi ogrenir ve gercegini de kacirir.
EXAMPLE_PAT='EXAMPLE|example\.com|YOUR_|<[a-z_-]+>|xxxx+|REPLACE_ME|changeme|placeholder'

CONTENT_HITS=""
for f in $RAW_HITS; do
  printf '%s' "$f" | grep -qE "$EXEMPT_PAT" && continue
  allowed "$f" && continue
  # Dosyadaki EŞLEŞMELERİ cikar; hepsi bilinen ornekse alarm verme.
  # "-e" SART. Desen "-----BEGIN" ile basliyor ve onsuz grep onu SECENEK sanip
  # hata veriyor; eslesme bos donuyor ve dosya sessizce "temiz" sayiliyordu.
  # Ayni hata bu script'te UC KEZ tekrarlandi (git grep --cached sirasi, git grep
  # -e, buradaki grep -e) ve ucunde de SESSIZ kaldi: bos cikti "sorun yok" gibi
  # okunuyor. Bu yuzden asagida cikis kodu da kontrol ediliyor.
  MATCHES="$(grep -oE -e "$CONTENT_PAT" "$f" 2>&1)"; MRC=$?
  if [ "$MRC" -gt 1 ]; then
    echo "SIR TARAMASI KOSULAMADI ($f, grep exit $MRC): $(printf '%s' "$MATCHES" | head -1)" >&2
    exit 2
  fi
  REAL="$(printf '%s\n' "$MATCHES" | grep -vE "$EXAMPLE_PAT" | sed '/^$/d')"
  [ -z "$REAL" ] && continue
  CONTENT_HITS="$CONTENT_HITS $f"
done

if [ -z "${HITS// /}" ] && [ -z "${CONTENT_HITS// /}" ]; then
  echo "sir taramasi temiz ($SCOPE dosyalar)"
  exit 0
fi

echo "SIR BULUNDU — repoya girmemeli:" >&2
for f in $HITS; do echo "  · yol:     $f" >&2; done
for f in $CONTENT_HITS; do echo "  · icerik:  $f (anahtar imzasi)" >&2; done
echo "" >&2
echo "Ne yapmali:" >&2
echo "  1. Takipten cikar:  git rm --cached <dosya>" >&2
echo "  2. .gitignore'a ekle (HER dalin .gitignore'unda olsun — tabani farkli" >&2
echo "     bir dal actiginda koruma birlikte GELMEZ)" >&2
echo "  3. Push edildiyse anahtarlari DONDUR; gecmisten silmek yetmez." >&2
echo "  4. Bilerek duruyorsa: sdlc/project.json -> secrets.allowPaths" >&2
exit 1
