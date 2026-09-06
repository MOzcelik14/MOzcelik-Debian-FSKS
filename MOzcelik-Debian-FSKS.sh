#!/bin/bash
set -Eeuo pipefail

# ============================================================
# MOzcelik Debian FSKS
# Debian 11 / 12 / 13 / 14
# ============================================================

if [[ $EUID -eq 0 ]]; then
    echo "❌ Script root olarak çalıştırılmamalıdır."
    echo "Normal kullanıcı olarak çalıştırın."
    exit 1
fi

if [[ ! -f /etc/debian_version ]]; then
    echo "❌ Bu script Debian içindir."
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

if [[ -z "$REAL_HOME" || ! -d "$REAL_HOME" ]]; then
    echo "❌ Kullanıcı home dizini bulunamadı."
    exit 1
fi

source /etc/os-release

if [[ "${ID:-}" != "debian" ]]; then
    echo "❌ Bu sistem Debian değil: ${ID:-bilinmiyor}"
    exit 1
fi

DEBIAN_VERSION="${VERSION_ID:-unknown}"
DEBIAN_CODENAME="${VERSION_CODENAME:-}"

echo
echo "======================================"
echo "       MOzcelik Debian FSKS"
echo "======================================"
echo
echo "Debian sürümü : $DEBIAN_VERSION"
echo "Codename      : ${DEBIAN_CODENAME:-otomatik algılanacak}"
echo "Kullanıcı     : $REAL_USER"
echo

# ------------------------------------------------------------
# Debian sürüm kontrolü
# ------------------------------------------------------------

case "$DEBIAN_VERSION" in
    11*)
        echo "✅ Debian 11 Bullseye algılandı."
        HAS_NONFREE_FIRMWARE=0
        ;;
    12*)
        echo "✅ Debian 12 Bookworm algılandı."
        HAS_NONFREE_FIRMWARE=1
        ;;
    13*)
        echo "✅ Debian 13 Trixie algılandı."
        HAS_NONFREE_FIRMWARE=1
        ;;
    14*)
        echo "✅ Debian 14 Forky algılandı."
        HAS_NONFREE_FIRMWARE=1
        ;;
    *)
        echo "⚠️ Tanınmayan Debian sürümü: $DEBIAN_VERSION"
        echo "Script devam edecek fakat bazı paket isimleri farklı olabilir."
        HAS_NONFREE_FIRMWARE=1
        ;;
esac

# ------------------------------------------------------------
# Yardımcı fonksiyonlar
# ------------------------------------------------------------

apt_install() {
    echo
    echo ">>> apt install: $*"
    sudo apt install -y "$@"
}

package_exists() {
    apt-cache show "$1" >/dev/null 2>&1
}

install_if_available() {
    local packages=()

    for pkg in "$@"; do
        if package_exists "$pkg"; then
            packages+=("$pkg")
        else
            echo "⚠️ Paket bulunamadı: $pkg"
        fi
    done

    if ((${#packages[@]})); then
        sudo apt install -y "${packages[@]}"
    fi
}

# ------------------------------------------------------------
# APT kaynakları
# ------------------------------------------------------------

echo
echo "======================================"
echo "== APT REPOLARI"
echo "======================================"

echo "APT kaynaklarının yedeği alınıyor..."

BACKUP="/etc/apt/sources.backup-$(date +%Y%m%d-%H%M%S)"

sudo mkdir -p "$BACKUP"

[[ -f /etc/apt/sources.list ]] &&
    sudo cp -a /etc/apt/sources.list "$BACKUP/sources.list"

if compgen -G "/etc/apt/sources.list.d/*" >/dev/null; then
    sudo cp -a /etc/apt/sources.list.d "$BACKUP/"
fi

echo "Yedek: $BACKUP"

# ------------------------------------------------------------
# Eski sources.list formatı
# ------------------------------------------------------------

if [[ -f /etc/apt/sources.list ]]; then

    sudo sed -i -E \
        's/^([[:space:]]*deb(-src)?[[:space:]]+[^#]+[[:space:]])main([[:space:]]*.*)$/\1main contrib non-free\4/' \
        /etc/apt/sources.list

fi

# ------------------------------------------------------------
# .sources deb822 formatı
# ------------------------------------------------------------

for file in /etc/apt/sources.list.d/*.sources; do

    [[ -f "$file" ]] || continue

    # Sadece Debian kaynaklarına dokun.
    if grep -qiE 'URIs?:[[:space:]]*https?://([^[:space:]]+\.)?debian\.org' "$file"; then

        sudo sed -i -E \
            '/^[[:space:]]*Components:/ {
                /(^|[[:space:]])contrib([[:space:]]|$)/! s/$/ contrib/
                /(^|[[:space:]])non-free([[:space:]]|$)/! s/$/ non-free/
            }' "$file"

        if [[ "$HAS_NONFREE_FIRMWARE" -eq 1 ]]; then
            sudo sed -i -E \
                '/^[[:space:]]*Components:/ {
                    /(^|[[:space:]])non-free-firmware([[:space:]]|$)/! s/$/ non-free-firmware/
                }' "$file"
        fi

    fi

done

# sources.list içindeki firmware bileşeni
if [[ "$HAS_NONFREE_FIRMWARE" -eq 1 && -f /etc/apt/sources.list ]]; then
    sudo sed -i -E \
        's/^([[:space:]]*deb(-src)?[[:space:]]+[^#]+[[:space:]])main([[:space:]]+contrib[[:space:]]+non-free)([[:space:]]*)$/\1main contrib non-free non-free-firmware/' \
        /etc/apt/sources.list
fi

echo
echo "APT güncelleniyor..."

sudo apt update

# ------------------------------------------------------------
# APT sağlık kontrolü
# ------------------------------------------------------------

echo
echo "APT bağımlılıkları kontrol ediliyor..."

if ! sudo apt-get check; then
    echo
    echo "❌ APT şu anda tutarsız."
    echo
    echo "Önce mevcut APT sorunlarını çözmek gerekiyor."
    echo "Script güvenlik nedeniyle durduruldu."
    echo
    exit 1
fi

echo "✅ APT sağlıklı."

# ------------------------------------------------------------
# i386
# ------------------------------------------------------------

echo
echo "======================================"
echo "== i386 DESTEĞİ"
echo "======================================"

if ! dpkg --print-foreign-architectures | grep -qx i386; then
    sudo dpkg --add-architecture i386
    sudo apt update
    echo "✅ i386 eklendi."
else
    echo "✅ i386 zaten aktif."
fi

# i386 ekledikten sonra tekrar kontrol
if ! sudo apt-get check; then
    echo
    echo "❌ i386 eklendikten sonra APT bağımlılıkları bozuldu."
    echo "Kurulum durduruldu."
    exit 1
fi

# ------------------------------------------------------------
# GRUB
# ------------------------------------------------------------

echo
echo "======================================"
echo "== GRUB"
echo "======================================"

GRUB_FILE="/etc/default/grub"

if [[ -f "$GRUB_FILE" ]]; then

    sudo cp -a "$GRUB_FILE" \
        "$GRUB_FILE.backup-$(date +%Y%m%d-%H%M%S)"

    CURRENT_CMDLINE="$(
        grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE" |
        head -n1 |
        sed -E 's/^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"$/\1/'
    )"

    add_grub_param() {
        local param="$1"

        if [[ "$CURRENT_CMDLINE" != *"$param"* ]]; then
            CURRENT_CMDLINE="$CURRENT_CMDLINE $param"
        fi
    }

    add_grub_param "acpi_backlight=native"
    add_grub_param "nvme_core.default_ps_max_latency_us=0"

    sudo sed -i \
        "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$CURRENT_CMDLINE\"|" \
        "$GRUB_FILE"

    sudo update-grub

    echo "✅ GRUB ayarlandı."

fi

# ------------------------------------------------------------
# NetworkManager
# ------------------------------------------------------------

echo
echo "======================================"
echo "== NETWORKMANAGER"
echo "======================================"

if systemctl list-unit-files NetworkManager-wait-online.service \
    >/dev/null 2>&1; then

    sudo systemctl disable NetworkManager-wait-online.service \
        2>/dev/null || true

    echo "✅ NetworkManager-wait-online devre dışı."

else
    echo "ℹ️ NetworkManager-wait-online bulunamadı."
fi

# ------------------------------------------------------------
# Gereksiz paketler
# ------------------------------------------------------------

echo
echo "======================================"
echo "== GEREKSİZ PAKETLER"
echo "======================================"

sudo apt purge -y \
    thunderbird \
    transmission-gtk \
    warpinator \
    rhythmbox \
    2>/dev/null || true

sudo apt autoremove --purge -y

# ------------------------------------------------------------
# Temel paketler
# ------------------------------------------------------------

echo
echo "======================================"
echo "== TEMEL PAKETLER"
echo "======================================"

install_if_available \
    numlockx \
    fish \
    audacious \
    btop \
    rar \
    unrar \
    fastfetch

# ------------------------------------------------------------
# Steam / Wine
# ------------------------------------------------------------

echo
echo "======================================"
echo "== STEAM / WINE"
echo "======================================"

if package_exists steam-installer; then
    sudo apt install -y steam-installer
else
    echo "⚠️ steam-installer bu Debian sürümünde bulunamadı."
fi

if package_exists wine; then
    sudo apt install -y wine
else
    echo "⚠️ wine bulunamadı."
fi

if package_exists wine32:i386; then
    sudo apt install -y wine32:i386
elif package_exists wine32; then
    sudo apt install -y wine32
else
    echo "⚠️ wine32 bulunamadı."
fi

install_if_available winetricks

# ------------------------------------------------------------
# NVIDIA
# ------------------------------------------------------------

echo
echo "======================================"
echo "== NVIDIA"
echo "======================================"

if package_exists nvidia-driver; then

    install_if_available \
        dkms \
        build-essential

    # Çalışan kernel için headers
    if package_exists "linux-headers-$(uname -r)"; then
        sudo apt install -y "linux-headers-$(uname -r)"
    else
        echo "⚠️ Mevcut kernel için exact headers bulunamadı."
        echo "   Genel headers paketi deneniyor..."

        if package_exists "linux-headers-amd64"; then
            sudo apt install -y linux-headers-amd64
        fi
    fi

    sudo apt install -y nvidia-driver

    install_if_available \
        nvidia-settings \
        nvidia-xconfig

    sudo tee /etc/modprobe.d/blacklist-nouveau.conf >/dev/null <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

    sudo update-initramfs -u

    sudo dkms autoinstall || \
        echo "⚠️ DKMS bazı modülleri derleyemedi."

    sudo depmod -a

    if modprobe nvidia 2>/dev/null; then
        echo "✅ NVIDIA kernel modülü yüklendi."
    else
        echo "⚠️ NVIDIA modülü şu anda yüklenemedi."
        echo "   Reboot sonrası tekrar denenecek."
    fi

    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi || \
            echo "⚠️ nvidia-smi şu anda çalışmıyor; reboot gerekebilir."
    fi

else
    echo "⚠️ nvidia-driver bu Debian sürümünde mevcut değil."
    echo "   NVIDIA kurulumu atlandı."
fi

# ------------------------------------------------------------
# Fish
# ------------------------------------------------------------

echo
echo "======================================"
echo "== FISH"
echo "======================================"

if command -v fish >/dev/null 2>&1; then

    CURRENT_SHELL="$(getent passwd "$REAL_USER" | cut -d: -f7)"

    if [[ "$CURRENT_SHELL" != "/usr/bin/fish" ]]; then
        sudo chsh -s /usr/bin/fish "$REAL_USER"
        echo "✅ Fish varsayılan shell yapıldı."
    else
        echo "✅ Fish zaten varsayılan shell."
    fi

else
    echo "⚠️ Fish kurulmadığı için shell değiştirilmiyor."
fi

# ------------------------------------------------------------
# Starship
# ------------------------------------------------------------

echo
echo "======================================"
echo "== STARSHIP"
echo "======================================"

if ! command -v starship >/dev/null 2>&1; then

    echo "Starship kuruluyor..."

    curl -sS https://starship.rs/install.sh |
        sh -s -- -y

else
    echo "✅ Starship zaten kurulu."
fi

# ------------------------------------------------------------
# Flatpak
# ------------------------------------------------------------

echo
echo "======================================"
echo "== FLATPAK"
echo "======================================"

install_if_available flatpak

if command -v flatpak >/dev/null 2>&1; then

    if ! flatpak remote-list |
        awk '{print $1}' |
        grep -qx flathub; then

        sudo flatpak remote-add \
            --if-not-exists \
            flathub \
            https://flathub.org/repo/flathub.flatpakrepo

    fi

    FLATPAKS=(
        org.kde.kdenlive
        org.audacityteam.Audacity
        org.nickvision.tubeconverter
        org.onlyoffice.desktopeditors
        net.davidotek.pupgui2
        com.spotify.Client
        com.heroicgameslauncher.hgl
    )

    for app in "${FLATPAKS[@]}"; do
        if flatpak info "$app" >/dev/null 2>&1; then
            echo "✅ $app zaten kurulu."
        else
            echo "Kuruluyor: $app"
            flatpak install -y flathub "$app" || \
                echo "⚠️ Kurulamadı: $app"
        fi
    done

fi

# ------------------------------------------------------------
# Winetricks bileşenleri
# ------------------------------------------------------------

echo
echo "======================================"
echo "== WINETRICKS"
echo "======================================"

if command -v winetricks >/dev/null 2>&1; then

    export WINEPREFIX="$REAL_HOME/.wine"

    if [[ ! -d "$WINEPREFIX" ]]; then
        echo "Wine prefix oluşturuluyor..."
        sudo -u "$REAL_USER" \
            env HOME="$REAL_HOME" \
            WINEPREFIX="$WINEPREFIX" \
            wineboot -u || true
    fi

    sudo -u "$REAL_USER" \
        env HOME="$REAL_HOME" \
        WINEPREFIX="$WINEPREFIX" \
        winetricks -q \
        dotnet40 \
        dotnet45 \
        dotnet48 \
        vcrun2022 \
        vcrun6sp6 \
        allfonts || \
        echo "⚠️ Bazı Winetricks bileşenleri kurulamadı."

    sudo -u "$REAL_USER" \
        env HOME="$REAL_HOME" \
        WINEPREFIX="$WINEPREFIX" \
        winetricks dxvk2030 || \
        echo "⚠️ DXVK kurulamadı."

else
    echo "⚠️ Winetricks kurulu değil."
fi

# ------------------------------------------------------------
# zRAM
# ------------------------------------------------------------

echo
echo "======================================"
echo "== zRAM"
echo "======================================"

if package_exists zram-tools; then

    sudo apt install -y zram-tools

    sudo tee /etc/default/zramswap >/dev/null <<'EOF'
ALGO=zstd
PERCENT=50
PRIORITY=100
EOF

    sudo systemctl enable zramswap.service
    sudo systemctl restart zramswap.service

    echo "✅ zRAM yapılandırıldı."

else
    echo "⚠️ zram-tools bulunamadı."
fi

# ------------------------------------------------------------
# Swap
# ------------------------------------------------------------

echo
echo "======================================"
echo "== SWAP"
echo "======================================"

# Mevcut swapfile varsa SİLME.
# Yoksa 4 GB oluştur.
if [[ -f /swapfile ]]; then

    echo "✅ /swapfile zaten mevcut."
    echo "   Mevcut swapfile korunuyor."

else

    echo "4 GB swapfile oluşturuluyor..."

    sudo fallocate -l 4G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile

fi

if ! grep -qE '^/swapfile[[:space:]]' /etc/fstab; then
    echo "/swapfile none swap sw 0 0" |
        sudo tee -a /etc/fstab >/dev/null
fi

# ------------------------------------------------------------
# Swappiness
# ------------------------------------------------------------

echo
echo "======================================"
echo "== SWAPPINESS"
echo "======================================"

sudo tee /etc/sysctl.d/99-swappiness.conf >/dev/null <<'EOF'
vm.swappiness=4
EOF

sudo sysctl --system >/dev/null

echo "✅ vm.swappiness = 4"

# ------------------------------------------------------------
# Fish config
# ------------------------------------------------------------

echo
echo "======================================"
echo "== FISH CONFIG"
echo "======================================"

sudo -u "$REAL_USER" mkdir -p \
    "$REAL_HOME/.config/fish"

sudo -u "$REAL_USER" tee \
    "$REAL_HOME/.config/fish/config.fish" >/dev/null <<'EOF'
if status is-interactive
    echo " "
    set_color normal

    if command -v fastfetch >/dev/null
        fastfetch
    end

    echo
end

if command -v starship >/dev/null
    starship init fish | source
end

alias güncelle='sudo apt update && sudo apt upgrade -y && flatpak update'
alias temizle='sudo apt autoremove && sudo apt autoclean -y && flatpak uninstall --unused'
alias yükle='sudo apt install'
alias fyükle='sudo flatpak install'
alias sil='sudo apt remove'
alias fsil='sudo flatpak remove'
alias kapa='poweroff'
alias söyle='echo'
EOF

echo "✅ Fish yapılandırıldı."

# ------------------------------------------------------------
# Fastfetch
# ------------------------------------------------------------

echo
echo "======================================"
echo "== FASTFETCH"
echo "======================================"

sudo -u "$REAL_USER" mkdir -p \
    "$REAL_HOME/.config/fastfetch"

sudo -u "$REAL_USER" tee \
    "$REAL_HOME/.config/fastfetch/config.jsonc" >/dev/null <<'EOF'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/master/doc/json_schema.json",

  "display": {
    "key": {
      "width": 10
    },
    "size": {
      "binaryPrefix": "jedec"
    },
    "separator": ""
  },

  "logo": {
    "type": "kitty-direct",
    "source": "~/.config/fastfetch/marin.png",
    "width": 20,
    "height": 10
  },

  "modules": [
    "break",

    {
      "type": "os",
      "key": "is",
      "keyColor": "yellow",
      "format": "{name}"
    },

    {
      "type": "kernel",
      "key": "lnx",
      "keyColor": "green"
    },

    {
      "type": "packages",
      "key": "pkgs",
      "keyColor": "cyan"
    },

    {
      "type": "uptime",
      "key": "çs",
      "keyColor": "green"
    },

    {
      "type": "cpu",
      "key": "mib",
      "keyColor": "red",
      "format": "{name}"
    },

    {
      "type": "gpu",
      "key": "gib",
      "keyColor": "red",
      "format": "{name}"
    },

    {
      "type": "memory",
      "key": "ram",
      "keyColor": "yellow",
      "format": "{used} / {total}"
    },

    {
      "type": "swap",
      "key": "swp-zram",
      "keyColor": "yellow",
      "format": "{used} / {total}"
    },

    {
      "type": "disk",
      "key": "dep",
      "keyColor": "cyan",
      "folders": [
        "/"
      ],
      "format": "{size-used} / {size-total}"
    },

    "break",

    {
      "type": "custom",
      "format": "\u001b[33m󰮯 \u001b[32m󰊠 \u001b[34m󰊠 \u001b[31m󰊠 \u001b[36m󰊠 \u001b[35m󰊠 \u001b[37m󰊠 \u001b[97m󰊠"
    }
  ]
}
EOF

# ------------------------------------------------------------
# Son kontroller
# ------------------------------------------------------------

echo
echo "======================================"
echo "== SON KONTROLLER"
echo "======================================"

echo
echo "APT:"
sudo apt-get check

echo
echo "i386:"
dpkg --print-foreign-architectures

echo
echo "Kernel:"
uname -r

echo
echo "RAM / Swap:"
free -h

echo
echo "Aktif swap:"
swapon --show

echo
echo "zRAM:"
zramctl 2>/dev/null || true

echo
echo "Swappiness:"
cat /proc/sys/vm/swappiness

echo
echo "NVIDIA:"
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi || echo "⚠️ NVIDIA henüz aktif değil; reboot gerekebilir."
else
    echo "nvidia-smi bulunamadı."
fi

echo
echo "======================================"
echo "== TAMAMLANDI =="
echo "======================================"

echo
echo "✅ Debian $DEBIAN_VERSION yapılandırması tamamlandı."
echo
echo "⚠️ NVIDIA/kernel/GRUB değişikliklerinin tamamı için:"
echo
echo "    sudo reboot"
echo
