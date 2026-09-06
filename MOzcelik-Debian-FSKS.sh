#!/bin/bash
set -Eeuo pipefail

# ============================================================
# MOzcelik Debian FSKS
# Debian 11 / 12 / 13 / 14
# ============================================================

if [[ $EUID -eq 0 ]]; then
    echo "❌ Script root olarak çalıştırılmamalıdır."
    exit 1
fi

# ------------------------------------------------------------
# Sistem bilgileri
# ------------------------------------------------------------

if [[ ! -f /etc/os-release ]]; then
    echo "❌ /etc/os-release bulunamadı."
    exit 1
fi

source /etc/os-release

if [[ "${ID:-}" != "debian" ]]; then
    echo "❌ Bu script yalnızca Debian içindir."
    echo "Algılanan sistem: ${PRETTY_NAME:-unknown}"
    exit 1
fi

DEBIAN_CODENAME="${VERSION_CODENAME:-}"

if [[ -z "$DEBIAN_CODENAME" ]]; then
    echo "❌ Debian codename algılanamadı."
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

if [[ -z "$REAL_HOME" || ! -d "$REAL_HOME" ]]; then
    echo "❌ Kullanıcı home dizini bulunamadı."
    exit 1
fi

case "$DEBIAN_CODENAME" in
    bullseye)
        DEBIAN_VERSION="11"
        HAS_NONFREE_FIRMWARE=0
        ;;
    bookworm)
        DEBIAN_VERSION="12"
        HAS_NONFREE_FIRMWARE=1
        ;;
    trixie)
        DEBIAN_VERSION="13"
        HAS_NONFREE_FIRMWARE=1
        ;;
    forky)
        DEBIAN_VERSION="14"
        HAS_NONFREE_FIRMWARE=1
        ;;
    sid|unstable)
        DEBIAN_VERSION="sid"
        HAS_NONFREE_FIRMWARE=1
        ;;
    *)
        echo "❌ Desteklenmeyen Debian codename: $DEBIAN_CODENAME"
        exit 1
        ;;
esac

echo
echo "======================================"
echo "       MOzcelik Debian FSKS"
echo "======================================"
echo
echo "Debian       : $DEBIAN_VERSION"
echo "Codename     : $DEBIAN_CODENAME"
echo "Kullanıcı    : $REAL_USER"
echo "Home         : $REAL_HOME"
echo

# ------------------------------------------------------------
# Yardımcı fonksiyonlar
# ------------------------------------------------------------

package_exists() {
    apt-cache show "$1" >/dev/null 2>&1
}

install_available() {
    local packages=()

    for pkg in "$@"; do
        if package_exists "$pkg"; then
            packages+=("$pkg")
        else
            echo "⚠️ Paket bulunamadı: $pkg"
        fi
    done

    if ((${#packages[@]} > 0)); then
        sudo apt install -y "${packages[@]}"
    fi
}

# ------------------------------------------------------------
# APT kaynakları
# ------------------------------------------------------------

echo "======================================"
echo "== APT REPOLARI"
echo "======================================"

BACKUP="/etc/apt/sources.backup-$(date +%Y%m%d-%H%M%S)"

sudo mkdir -p "$BACKUP"

if [[ -f /etc/apt/sources.list ]]; then
    sudo cp -a /etc/apt/sources.list "$BACKUP/"
fi

if [[ -d /etc/apt/sources.list.d ]]; then
    sudo cp -a /etc/apt/sources.list.d "$BACKUP/"
fi

echo "✅ APT yedeği: $BACKUP"

# ------------------------------------------------------------
# Eski sources.list formatı
# ------------------------------------------------------------

if [[ -f /etc/apt/sources.list ]]; then

    sudo python3 - <<PY
from pathlib import Path

p = Path("/etc/apt/sources.list")

lines = p.read_text().splitlines()

out = []

for line in lines:
    stripped = line.strip()

    if stripped.startswith(("deb ", "deb-src ")):
        parts = line.split()

        if len(parts) >= 4:
            components = parts[3:]

            for component in ("contrib", "non-free"):
                if component not in components:
                    components.append(component)

            if $HAS_NONFREE_FIRMWARE:
                if "non-free-firmware" not in components:
                    components.append("non-free-firmware")

            line = " ".join(parts[:3] + components)

    out.append(line)

p.write_text("\n".join(out) + "\n")
PY

fi

# ------------------------------------------------------------
# Modern .sources dosyaları
# ------------------------------------------------------------

for file in /etc/apt/sources.list.d/*.sources; do

    [[ -f "$file" ]] || continue

    sudo python3 - "$file" "$HAS_NONFREE_FIRMWARE" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
firmware = sys.argv[2] == "1"

text = path.read_text()

# Sadece Debian kaynaklarına dokun.
if "deb.debian.org" not in text and \
   "security.debian.org" not in text:
    sys.exit(0)

lines = text.splitlines()
out = []

for line in lines:

    if line.startswith("Components:"):
        components = line.split()[1:]

        for component in ("contrib", "non-free"):
            if component not in components:
                components.append(component)

        if firmware and "non-free-firmware" not in components:
            components.append("non-free-firmware")

        line = "Components: " + " ".join(components)

    out.append(line)

path.write_text("\n".join(out) + "\n")
PY

done

echo "✅ contrib + non-free yapılandırıldı."

if [[ "$HAS_NONFREE_FIRMWARE" -eq 1 ]]; then
    echo "✅ non-free-firmware etkin."
fi

sudo apt update

# ------------------------------------------------------------
# APT sağlık kontrolü
# ------------------------------------------------------------

echo
echo "======================================"
echo "== APT SAĞLIK KONTROLÜ"
echo "======================================"

if ! sudo apt-get check; then
    echo
    echo "❌ APT bağımlılıkları bozuk."
    echo
    echo "Script burada durduruldu."
    echo "Önce APT problemi çözülmeli."
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

if dpkg --print-foreign-architectures | grep -qx i386; then
    echo "✅ i386 zaten aktif."
else
    sudo dpkg --add-architecture i386
    sudo apt update

    if ! sudo apt-get check; then
        echo "❌ i386 eklenince APT bozuldu."
        exit 1
    fi

    echo "✅ i386 etkinleştirildi."
fi

# ------------------------------------------------------------
# GRUB
# ------------------------------------------------------------

echo
echo "======================================"
echo "== GRUB"
echo "======================================"

GRUB="/etc/default/grub"

if [[ -f "$GRUB" ]]; then

    sudo cp -a "$GRUB" "$GRUB.backup-$(date +%Y%m%d-%H%M%S)"

    CURRENT="$(
        grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB" |
        sed -E 's/^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"$/\1/' |
        head -n1
    )"

    add_param() {
        local param="$1"

        if [[ ! " $CURRENT " =~ [[:space:]]"$param"[[:space:]] ]]; then
            CURRENT="$CURRENT $param"
        fi
    }

    add_param "acpi_backlight=native"
    add_param "nvme_core.default_ps_max_latency_us=0"

    sudo sed -i \
        "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$CURRENT\"|" \
        "$GRUB"

    sudo update-grub

    echo "✅ GRUB parametreleri eklendi."

fi

# ------------------------------------------------------------
# NetworkManager
# ------------------------------------------------------------

echo
echo "======================================"
echo "== NETWORKMANAGER"
echo "======================================"

if systemctl list-unit-files \
    NetworkManager-wait-online.service >/dev/null 2>&1; then

    sudo systemctl disable NetworkManager-wait-online.service \
        2>/dev/null || true

    echo "✅ NetworkManager-wait-online devre dışı."

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

install_available \
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
    echo "⚠️ steam-installer bulunamadı."
fi

if package_exists wine; then
    sudo apt install -y wine
else
    echo "⚠️ wine bulunamadı."
fi

if package_exists wine32; then
    sudo apt install -y wine32
else
    echo "⚠️ wine32 bulunamadı."
fi

install_available winetricks

# ------------------------------------------------------------
# NVIDIA
# ------------------------------------------------------------

echo
echo "======================================"
echo "== NVIDIA"
echo "======================================"

if package_exists nvidia-driver; then

    install_available \
        dkms \
        build-essential

    if package_exists "linux-headers-$(uname -r)"; then
        sudo apt install -y "linux-headers-$(uname -r)"
    elif package_exists linux-headers-amd64; then
        sudo apt install -y linux-headers-amd64
    else
        echo "⚠️ Kernel headers bulunamadı."
    fi

    sudo apt install -y nvidia-driver

    install_available \
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

    if sudo modprobe nvidia 2>/dev/null; then
        echo "✅ NVIDIA modülü yüklendi."
    else
        echo "⚠️ NVIDIA modülü şu anda yüklenemedi."
    fi

    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi || \
            echo "⚠️ nvidia-smi reboot sonrasında çalışabilir."
    fi

else
    echo "⚠️ nvidia-driver bulunamadı."
fi

# ------------------------------------------------------------
# Fish
# ------------------------------------------------------------

echo
echo "======================================"
echo "== FISH"
echo "======================================"

if command -v fish >/dev/null 2>&1; then
    sudo chsh -s /usr/bin/fish "$REAL_USER"
    echo "✅ Fish varsayılan shell."
fi

# ------------------------------------------------------------
# Starship
# ------------------------------------------------------------

echo
echo "======================================"
echo "== STARSHIP"
echo "======================================"

if ! command -v starship >/dev/null 2>&1; then
    curl -sS https://starship.rs/install.sh | sh -s -- -y
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

install_available flatpak

if command -v flatpak >/dev/null 2>&1; then

    if ! flatpak remotes --columns=name |
        grep -qx flathub; then

        sudo flatpak remote-add \
            --if-not-exists \
            flathub \
            https://flathub.org/repo/flathub.flatpakrepo
    fi

    APPS=(
        org.kde.kdenlive
        org.audacityteam.Audacity
        org.nickvision.tubeconverter
        org.onlyoffice.desktopeditors
        net.davidotek.pupgui2
        com.spotify.Client
        com.heroicgameslauncher.hgl
    )

    for app in "${APPS[@]}"; do

        if flatpak info "$app" >/dev/null 2>&1; then
            echo "✅ $app zaten kurulu."
        else
            flatpak install -y flathub "$app" || \
                echo "⚠️ $app kurulamadı."
        fi

    done

fi

# ------------------------------------------------------------
# Winetricks
# ------------------------------------------------------------

echo
echo "======================================"
echo "== WINETRICKS"
echo "======================================"

if command -v winetricks >/dev/null 2>&1; then

    export WINEPREFIX="$REAL_HOME/.wine"

    if [[ ! -d "$WINEPREFIX" ]]; then
        sudo -u "$REAL_USER" \
            HOME="$REAL_HOME" \
            WINEPREFIX="$WINEPREFIX" \
            wineboot -u || true
    fi

    sudo -u "$REAL_USER" \
        HOME="$REAL_HOME" \
        WINEPREFIX="$WINEPREFIX" \
        winetricks -q \
        dotnet40 \
        dotnet45 \
        dotnet48 \
        vcrun2022 \
        vcrun6sp6 \
        allfonts || true

    sudo -u "$REAL_USER" \
        HOME="$REAL_HOME" \
        WINEPREFIX="$WINEPREFIX" \
        winetricks dxvk2030 || true

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

    echo "✅ zRAM ayarlandı."

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

if [[ -f /swapfile ]]; then

    echo "✅ Mevcut /swapfile korunuyor."

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
# Son kontrol
# ------------------------------------------------------------

echo
echo "======================================"
echo "== SON KONTROLLER"
echo "======================================"

echo
echo "APT:"
sudo apt-get check

echo
echo "Debian:"
cat /etc/os-release | grep -E '^(PRETTY_NAME|VERSION_ID|VERSION_CODENAME)='

echo
echo "i386:"
dpkg --print-foreign-architectures

echo
echo "Kernel:"
uname -r

echo
echo "RAM:"
free -h

echo
echo "Swap:"
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
    nvidia-smi || true
else
    echo "nvidia-smi bulunamadı."
fi

echo
echo "======================================"
echo "== TAMAMLANDI =="
echo "======================================"
echo
echo "✅ Debian $DEBIAN_VERSION ($DEBIAN_CODENAME) yapılandırıldı."
echo
echo "🔄 Önerilen:"
echo "sudo reboot"
echo
