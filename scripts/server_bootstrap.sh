#!/usr/bin/env bash
# D8 — sifir bir Ubuntu kutusunu Crawlens calistirmaya hazir hale getirir.
#
# SUNUCUDA, root olarak calistirilir:
#   curl -fsSL https://raw.githubusercontent.com/cembakca/crawlens/main/scripts/server_bootstrap.sh | sudo bash
# ya da depo klonlandiktan sonra:
#   sudo ./scripts/server_bootstrap.sh
#
# Idempotent: iki kez calistirmak zarar vermez, ikinci kosu "zaten yapilmis"
# der. Sunucu gunu, yarim kalan bir adimin tekrar calistirilabilir olmasi
# lazim — o an dogaclama yapilacak en kotu yerdir.
#
# Bu script Lima uzerinde Ubuntu 24.04'e karsi prova edildi (D8).

set -euo pipefail

SSH_PORT="${SSH_PORT:-22}"
SWAP_GB="${SWAP_GB:-2}"
ADMIN_USER="${ADMIN_USER:-${SUDO_USER:-}}"

GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; DIM=$'\033[2m'; NC=$'\033[0m'
step() { printf "\n${DIM}--- %s${NC}\n" "$1"; }
ok()   { printf "  ${GREEN}%s${NC}\n" "$1"; }
skip() { printf "  ${DIM}%s${NC}\n" "$1"; }
warn() { printf "  ${YELLOW}%s${NC}\n" "$1"; }

[ "$(id -u)" -eq 0 ] || { echo "root olarak calistirin (sudo)"; exit 1; }

START="$(date +%s)"

step "1/7 sistem paketleri"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg ufw fail2ban unattended-upgrades >/dev/null
ok "temel paketler kurulu"

step "2/7 otomatik guvenlik guncellemeleri"
if [ -f /etc/apt/apt.conf.d/20auto-upgrades ] && grep -q '"1"' /etc/apt/apt.conf.d/20auto-upgrades; then
  skip "zaten acik"
else
  cat > /etc/apt/apt.conf.d/20auto-upgrades <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
CONF
  ok "acildi"
fi

step "3/7 swap"
# Tek kutuda 8 GB RAM ve Playwright: bellek ani sicramalari oluyor. Swap,
# OOM killer'in worker yerine sistemi vurmasini onlemez ama sicramayi yumusatir.
if swapon --show | grep -q .; then
  skip "swap zaten var ($(swapon --show=SIZE --noheadings | tr -d ' ' | head -1))"
else
  fallocate -l "${SWAP_GB}G" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  sysctl -q -w vm.swappiness=10
  grep -q '^vm.swappiness' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf
  ok "${SWAP_GB}G swap acildi"
fi

step "4/7 guvenlik duvari"
# SIRA ONEMLI: once portlari ac, sonra etkinlestir. Tersi, SSH oturumunu
# kesip kutuyu erisilmez birakir — bu, sunucu gunu en sik yapilan hata.
ufw allow "${SSH_PORT}"/tcp >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null
ok "ufw acik: ${SSH_PORT}, 80, 443"

step "5/7 SSH sertlestirme"
sshd_conf=/etc/ssh/sshd_config.d/99-crawlens.conf
if [ -f "$sshd_conf" ]; then
  skip "zaten uygulanmis"
else
  # Anahtar tabanli giris SART. Bu dosya yazilmadan once anahtarinizin
  # calistigindan emin olun; parolayla girisi kapatmak geri donusu olan bir
  # islem degildir (konsol erisiminiz yoksa).
  # Ev dizinini VARSAYMA, sor. Prova sirasinda `/home/$USER` varsayimi yanlis
  # cikti (Lima'da ev dizini `/home/cembakca.linux`) ve adim sessizce atlandi —
  # yani sertlestirme yapildi sanilacakti.
  admin_home="$(getent passwd "${ADMIN_USER:-}" 2>/dev/null | cut -d: -f6)"
  if [ -n "$ADMIN_USER" ] && [ -n "$admin_home" ] && [ -s "${admin_home}/.ssh/authorized_keys" ]; then
    cat > "$sshd_conf" <<'CONF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
CONF
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
    ok "root girisi ve parola kapatildi (anahtar: ${admin_home}/.ssh/authorized_keys)"
  else
    warn "ATLANDI: ${ADMIN_USER:-kullanici} icin authorized_keys bulunamadi (${admin_home:-ev dizini yok})"
    warn "Parola girisini kapatmak, once anahtarla girebildiginizi dogrulamadan YAPILMAZ."
  fi
fi

step "6/7 fail2ban"
systemctl enable --now fail2ban >/dev/null 2>&1 || true
ok "fail2ban calisiyor"

step "7/7 docker"
if command -v docker >/dev/null 2>&1; then
  skip "docker zaten kurulu ($(docker --version | awk '{print $3}' | tr -d ,))"
else
  curl -fsSL https://get.docker.com | sh >/dev/null
  ok "docker kuruldu"
fi
systemctl enable --now docker >/dev/null 2>&1 || true
if [ -n "$ADMIN_USER" ] && ! id -nG "$ADMIN_USER" | grep -qw docker; then
  usermod -aG docker "$ADMIN_USER"
  ok "${ADMIN_USER} docker grubuna eklendi (yeniden giris gerekir)"
fi

ELAPSED=$(( $(date +%s) - START ))
cat <<TXT

${GREEN}kutu hazir${NC} (${ELAPSED} sn)

Sirada, docs/SERVER_DAY.md adim 3'ten devam:
  - Dokploy kurulumu
  - sirlarin yuklenmesi (secrets/prod.enc.env)
  - GHCR cekme kimligi
  - indeks adimi, ilk deploy, saglik kapisi
  - AYNI GUN: yedek zamanlayicisi + ilk geri yukleme provasi

TXT
