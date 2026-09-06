#!/bin/bash
set -Eeuo pipefail

# ============================================================
# MOzcelik-Debian-FSKS 2.0
# Debian 11 Bullseye
# Debian 12 Bookworm
# Debian 13 Trixie
# Debian 14 Forky
# ============================================================

SCRIPT_NAME="MOzcelik-Debian-FSKS"
SCRIPT_VERSION="2.0"

# ------------------------------------------------------------
# Renkler
# ------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

info() {
    echo -e "${CYAN}==> $*${RESET}"
}

ok() {
    echo -e "${GREEN}✅ $*${RESET}"
}

warn() {
    echo -e "${YELLOW}⚠️  $*${RESET}"
}

die() {
    echo -e "${RED}❌ $*${RESET}"
    exit 1
}

# ------------------------------------------------------------
# Root kontrolü
# ------------------------------------------------------------

if [[ $EUID -eq 0 ]]; then
    die "Script'i root olarak çalıştırma. Normal kullanıcıyla çalıştır."
fi

# ------------------------------------------------------------
# Debian kontrolü
# ------------------------------------------------------------

[[ -f /etc/os-release ]] || die "/etc/os-release bulunamadı."

source /etc/os-release

[[ "${ID:-}" == "debian" ]] || \
    die "Bu script yalnızca Debian içindir."

DEBIAN_CODENAME="${VERSION_CODENAME:-}"

[[ -n "$DEBIAN_CODENAME" ]] || \
    die "Debian codename algılanamadı."

case "$DEBIAN_CODENAME" in

    bullseye)
        DEBIAN_VERSION="11"
        NONFREE_FIRMWARE=0
        ;;

    bookworm)
        DEBIAN_VERSION="12"
        NONFREE_FIRMWARE=1
        ;;

    trixie)
        DEBIAN_VERSION="13"
        NONFREE_FIRMWARE=1
        ;;

    forky)
        DEBIAN_VERSION="14"
        NONFREE_FIRMWARE=1
        ;;

    sid|unstable)
        DEBIAN_VERSION="sid"
        NONFREE_FIRMWARE=1
        ;;

    *)
        die "Desteklenmeyen Debian sürümü: $DEBIAN_CODENAME"
        ;;

esac

# ------------------------------------------------------------
# Kullanıcı
# ------------------------------------------------------------

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

[[ -n "$REAL_HOME" && -d "$REAL_HOME" ]] || \
    die "Kullanıcı home dizini bulunamadı."

# ------------------------------------------------------------
# Başlangıç
# ------------------------------------------------------------

clear

echo
echo "============================================================"
echo "              $SCRIPT_NAME $SCRIPT_VERSION"
echo "============================================================"
echo
echo "Debian       : $DEBIAN_VERSION"
echo "Codename     : $DEBIAN_CODENAME"
echo "Kullanıcı    : $REAL_USER"
echo "Home         : $REAL_HOME"
echo
echo "============================================================"
echo

# ------------------------------------------------------------
# Yardımcı paket fonksiyonları
# ------------------------------------------------------------

package_exists() {
    apt-cache show "$1" >/dev/null 2>&1
}

install_if_available() {

    local packages=()

    for package in "$@"; do

        if package_exists "$package"; then
            packages+=("$package")
        else
            warn "Paket bulunamadı: $package"
        fi

    done

    if ((${#packages[@]})); then
        sudo apt install -y "${packages[@]}"
    fi
}

# ------------------------------------------------------------
# APT kaynak yedeği
# ------------------------------------------------------------

info "APT kaynakları yedekleniyor..."

APT_BACKUP="/etc/apt/fsks-backup-$(date +%Y%m%d-%H%M%S)"

sudo mkdir -p "$APT_BACKUP"

[[ ! -e /etc/apt/sources.list ]] || \
    sudo cp -a /etc/apt/sources.list "$APT_BACKUP/"

[[ ! -d /etc/apt/sources.list.d ]] || \
    sudo cp -a /etc/apt/sources.list.d "$APT_BACKUP/"

ok "APT yedeği oluşturuldu: $APT_BACKUP"

# ------------------------------------------------------------
# Debian repository codename düzeltme
# ------------------------------------------------------------

info "Debian repository'leri kontrol ediliyor..."

sudo python3 - "$DEBIAN_CODENAME" "$NONFREE_FIRMWARE" <<'PY'
import sys
from pathlib import Path
import re

codename = sys.argv[1]
has_firmware = sys.argv[2] == "1"

valid_suites = {
    codename,
    f"{codename}-updates",
    f"{codename}-security",
    f"{codename}-backports",
}

def fix_list_file(path):

    if not path.exists():
        return

    lines = path.read_text().splitlines()
    output = []

    for line in lines:

        stripped = line.strip()

        # Yorumlar
        if not stripped or stripped.startswith("#"):
            output.append(line)
            continue

        # Sadece Debian repository'leri
        if not re.match(r"^\s*deb(?:-src)?\s+", line):
            output.append(line)
            continue

        if (
            "deb.debian.org" not in line
            and "security.debian.org" not in line
        ):
            output.append(line)
            continue

        parts = line.split()

        if len(parts) < 4:
            output.append(line)
            continue

        # deb [options] URI suite components
        uri_index = 1

        if parts[1].startswith("["):
            while uri_index < len(parts) and not parts[uri_index].startswith("http"):
                uri_index += 1

        if uri_index >= len(parts) - 2:
            output.append(line)
            continue

        suite_index = uri_index + 1

        old_suite = parts[suite_index]

        # Debian suite'i mevcut sistemle eşleştir.
        if old_suite in {
            "stable",
            "oldstable",
            "testing",
            "trixie",
            "bookworm",
            "bullseye",
            "forky",
            "sid",
            "unstable",
            "trixie-updates",
            "trixie-security",
            "trixie-backports",
            "bookworm-updates",
            "bookworm-security",
            "bookworm-backports",
            "bullseye-updates",
            "bullseye-security",
            "bullseye-backports",
            "forky-updates",
            "forky-security",
            "forky-backports",
        }:
            if old_suite.endswith("-updates"):
                parts[suite_index] = f"{codename}-updates"
            elif old_suite.endswith("-security"):
                parts[suite_index] = f"{codename}-security"
            elif old_suite.endswith("-backports"):
                parts[suite_index] = f"{codename}-backports"
            else:
                parts[suite_index] = codename

        components = parts[suite_index + 1:]

        # Yorum varsa ayır.
        if "#" in components:
            comment_index = components.index("#")
            real_components = components[:comment_index]
            comment = components[comment_index:]
        else:
            real_components = components
            comment = []

        for component in ("main", "contrib", "non-free"):
            if component not in real_components:
                real_components.append(component)

        if has_firmware and "non-free-firmware" not in real_components:
            real_components.append("non-free-firmware")

        parts = parts[:suite_index + 1] + real_components + comment

        output.append(" ".join(parts))

    path.write_text("\n".join(output) + "\n")


# sources.list
fix_list_file(Path("/etc/apt/sources.list"))

# sources.list.d/*.list
sources_dir = Path("/etc/apt/sources.list.d")

if sources_dir.exists():

    for path in sources_dir.glob("*.list"):
        fix_list_file(path)

    # Modern deb822 .sources dosyaları
    for path in sources_dir.glob("*.sources"):

        text = path.read_text()

        if (
            "deb.debian.org" not in text
            and "security.debian.org" not in text
        ):
            continue

        lines = text.splitlines()
        output = []

        for line in lines:

            if line.startswith("Suites:"):

                suites = line.split()[1:]
                new_suites = []

                for suite in suites:

                    if suite.endswith("-updates"):
                        new_suites.append(f"{codename}-updates")

                    elif suite.endswith("-security"):
                        new_suites.append(f"{codename}-security")

                    elif suite.endswith("-backports"):
                        new_suites.append(f"{codename}-backports")

                    elif suite in {
                        "stable",
                        "oldstable",
                        "testing",
                        "unstable",
                        "bullseye",
                        "bookworm",
                        "trixie",
                        "forky",
                        "sid",
                    }:
                        new_suites.append(codename)

                    else:
                        new_suites.append(suite)

                line = "Suites: " + " ".join(dict.fromkeys(new_suites))

            elif line.startswith("Components:"):

                components = line.split()[1:]

                for component in ("main", "contrib", "non-free"):
                    if component not in components:
                        components.append(component)

                if has_firmware and \
                   "non-free-firmware" not in components:
                    components.append("non-free-firmware")

                line = "Components: " + " ".join(components)

            output.append(line)

        path.write_text("\n".join(output) + "\n")
PY

# ------------------------------------------------------------
# Duplicate repository component temizliği
# ------------------------------------------------------------

sudo sed -i \
    -E 's/(^|[[:space:]])non-free-firmware([[:space:]]+non-free-firmware)+/\1non-free-firmware/g' \
    /etc/apt/sources.list 2>/dev/null || true

ok "Debian repository'leri $DEBIAN_CODENAME ile hizalandı."

# ------------------------------------------------------------
# APT update
# ------------------------------------------------------------

info "APT indeksleri güncelleniyor..."

sudo apt update

# ------------------------------------------------------------
# i386
# ------------------------------------------------------------

info "i386 mimarisi kontrol ediliyor..."

if dpkg --print-foreign-architectures | grep -qx "i386"; then

    ok "i386 zaten aktif."

else

    sudo dpkg --add-architecture i386
    sudo apt update

    ok "i386 etkinleştirildi."

fi

# ------------------------------------------------------------
# APT sağlık kontrolü
# ------------------------------------------------------------

info "APT bağımlılıkları kontrol ediliyor..."

if ! sudo apt-get check; then

    echo
    warn "APT'de bağımlılık problemi bulundu."
    echo
    echo "Sistem otomatik olarak zorlanmayacak."
    echo "Önce APT problemi çözülmeli."
    echo

    exit 1

fi

ok "APT sağlıklı."

# ------------------------------------------------------------
# Paket yükseltme
# ------------------------------------------------------------

info "Sistem paketleri kontrol ediliyor..."

UPGRADABLE="$(apt list --upgradable 2>/dev/null | tail -n +2 | wc -l)"

echo
echo "Yükseltilebilir paket sayısı: $UPGRADABLE"
echo

if (( UPGRADABLE > 0 )); then

    read -rp \
        "Sistemi $DEBIAN_CODENAME paketleriyle güncelleyelim mi? [Y/n]: " \
        ANSWER

    ANSWER="${ANSWER:-Y}"

    if [[ "$ANSWER" =~ ^[YyEe]$ ]]; then

        sudo apt full-upgrade -y

    else

        warn "full-upgrade atlandı."

    fi

fi

sudo apt-get check

ok "APT tekrar kontrol edildi."

# ------------------------------------------------------------
# GRUB
# ------------------------------------------------------------

info "GRUB ayarlanıyor..."

GRUB="/etc/default/grub"

if [[ -f "$GRUB" ]]; then

    sudo cp -a "$GRUB" \
        "$GRUB.backup-$(date +%Y%m%d-%H%M%S)"

    CURRENT="$(
        grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB" |
        sed -E 's/^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"$/\1/' |
        head -n1
    )"

    [[ -n "$CURRENT" ]] || CURRENT=""

    add_grub_param() {

        local param="$1"

        if [[ ! " $CURRENT " == *" $param "* ]]; then
            CURRENT="$CURRENT $param"
        fi

    }

    add_grub_param "acpi_backlight=native"
    add_grub_param "nvme_core.default_ps_max_latency_us=0"

    sudo sed -i \
        "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$CURRENT\"|" \
        "$GRUB"

    sudo update-grub

    ok "GRUB ayarlandı."

fi

# ------------------------------------------------------------
# NetworkManager
# ------------------------------------------------------------

info "NetworkManager wait-online kontrol ediliyor..."

if systemctl list-unit-files \
    --no-legend \
    NetworkManager-wait-online.service \
    >/dev/null 2>&1; then

    sudo systemctl disable \
        NetworkManager-wait-online.service \
        2>/dev/null || true

    ok "NetworkManager-wait-online devre dışı."

else

    warn "NetworkManager-wait-online bulunamadı."

fi

# ------------------------------------------------------------
# Gereksiz paketler
# ------------------------------------------------------------

info "Gereksiz paketler kaldırılıyor..."

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

info "Temel paketler kuruluyor..."

install_if_available \
    curl \
    wget \
    numlockx \
    fish \
    audacious \
    btop \
    rar \
    unrar \
    fastfetch

# ------------------------------------------------------------
# Steam
# ------------------------------------------------------------

info "Steam kurulumu..."

if package_exists steam-installer; then

    if sudo apt install -y steam-installer; then
        ok "Steam kuruldu."
    else
        warn "Steam kurulamadı."
    fi

else

    warn "steam-installer repository'de bulunamadı."

fi

# ------------------------------------------------------------
# Wine
# ------------------------------------------------------------

info "Wine kurulumu..."

install_if_available \
    wine \
    wine32 \
    winetricks

# ------------------------------------------------------------
# NVIDIA
# ------------------------------------------------------------

info "NVIDIA kurulumu..."

if package_exists nvidia-driver; then

    install_if_available \
        dkms \
        build-essential

    # Bilerek tam kernel header kullanıyoruz.
    if package_exists "linux-headers-$(uname -r)"; then

        sudo apt install -y \
            "linux-headers-$(uname -r)"

        ok "Kernel header kuruldu: $(uname -r)"

    else

        warn "linux-headers-$(uname -r) bulunamadı."
        warn "NVIDIA DKMS kurulumu yine de deneniyor."

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
        warn "DKMS bazı modülleri derleyemedi."

    sudo depmod -a

    if sudo modprobe nvidia 2>/dev/null; then
        ok "NVIDIA kernel modülü yüklendi."
    else
        warn "NVIDIA modülü şu anda yüklenemedi."
    fi

else

    warn "nvidia-driver bulunamadı."

fi

# ------------------------------------------------------------
# Fish shell
# ------------------------------------------------------------

info "Fish ayarlanıyor..."

if command -v fish >/dev/null 2>&1; then

    FISH_PATH="$(command -v fish)"

    CURRENT_SHELL="$(getent passwd "$REAL_USER" | cut -d: -f7)"

    if [[ "$CURRENT_SHELL" != "$FISH_PATH" ]]; then
        sudo chsh -s "$FISH_PATH" "$REAL_USER"
    fi

    ok "Fish varsayılan shell olarak ayarlandı."

fi

# ------------------------------------------------------------
# Starship
# ------------------------------------------------------------

info "Starship kontrol ediliyor..."

if command -v starship >/dev/null 2>&1; then

    ok "Starship zaten kurulu."

else

    if command -v curl >/dev/null 2>&1; then

        curl -sS https://starship.rs/install.sh |
            sudo sh -s -- -y

        ok "Starship kuruldu."

    else

        warn "curl bulunamadığı için Starship kurulamadı."

    fi

fi

# ------------------------------------------------------------
# Flatpak
# ------------------------------------------------------------

info "Flatpak kuruluyor..."

install_if_available flatpak

if command -v flatpak >/dev/null 2>&1; then

    if ! flatpak remotes --columns=name 2>/dev/null |
        grep -qx "flathub"; then

        sudo flatpak remote-add \
            --if-not-exists \
            flathub \
            https://flathub.org/repo/flathub.flatpakrepo

    fi

    FLATPAK_APPS=(
        org.kde.kdenlive
        org.audacityteam.Audacity
        org.nickvision.tubeconverter
        org.onlyoffice.desktopeditors
        net.davidotek.pupgui2
        com.spotify.Client
        com.heroicgameslauncher.hgl
    )

    for app in "${FLATPAK_APPS[@]}"; do

        if flatpak info "$app" >/dev/null 2>&1; then

            ok "$app zaten kurulu."

        else

            if flatpak install -y flathub "$app"; then
                ok "$app kuruldu."
            else
                warn "$app kurulamadı."
            fi

        fi

    done

fi

# ------------------------------------------------------------
# Wine / Winetricks
# ------------------------------------------------------------

info "Winetricks ayarlanıyor..."

if command -v winetricks >/dev/null 2>&1; then

    export WINEPREFIX="$REAL_HOME/.wine"

    sudo -u "$REAL_USER" \
        HOME="$REAL_HOME" \
        WINEPREFIX="$WINEPREFIX" \
        wineboot -u 2>/dev/null || true

    sudo -u "$REAL_USER" \
        HOME="$REAL_HOME" \
        WINEPREFIX="$WINEPREFIX" \
        winetricks -q \
            dotnet40 \
            dotnet45 \
            dotnet48 \
            vcrun2022 \
            vcrun6sp6 \
            allfonts \
        || warn "Bazı Winetricks bileşenleri kurulamadı."

    if sudo -u "$REAL_USER" \
        HOME="$REAL_HOME" \
        WINEPREFIX="$WINEPREFIX" \
        winetricks list-all 2>/dev/null |
        grep -qx "dxvk2030"; then

        sudo -u "$REAL_USER" \
            HOME="$REAL_HOME" \
            WINEPREFIX="$WINEPREFIX" \
            winetricks dxvk2030 \
            || warn "DXVK 2.3.0 kurulamadı."

    else

        warn "Bu Winetricks sürümünde dxvk2030 bulunamadı."

    fi

fi

# ------------------------------------------------------------
# zRAM
# ------------------------------------------------------------

info "zRAM ayarlanıyor..."

if package_exists zram-tools; then

    sudo apt install -y zram-tools

    sudo tee /etc/default/zramswap >/dev/null <<'EOF'
ALGO=zstd
PERCENT=50
PRIORITY=100
EOF

    sudo systemctl enable zramswap.service

    sudo systemctl restart zramswap.service \
        || warn "zram-tools servisi yeniden başlatılamadı."

    ok "zRAM yapılandırıldı."

else

    warn "zram-tools bulunamadı."

fi

# ------------------------------------------------------------
# Swapfile
# ------------------------------------------------------------

info "Swapfile kontrol ediliyor..."

SWAPFILE="/swapfile"
TARGET_SIZE_GB=4
TARGET_SIZE_BYTES=$((TARGET_SIZE_GB * 1024 * 1024 * 1024))

# Aktif swapfile'ı kapat
if swapon --show=NAME --noheadings 2>/dev/null |
    grep -qx "$SWAPFILE"; then

    sudo swapoff "$SWAPFILE"

fi

if [[ -f "$SWAPFILE" ]]; then

    CURRENT_SIZE="$(stat -c '%s' "$SWAPFILE")"

    echo
    echo "Mevcut /swapfile:"
    echo "  Boyut: $((CURRENT_SIZE / 1024 / 1024 / 1024)) GB"
    echo "  Hedef: 4 GB"
    echo

    if [[ "$CURRENT_SIZE" -ne "$TARGET_SIZE_BYTES" ]]; then

        info "Swapfile 4 GB'a ayarlanıyor..."

        sudo rm -f "$SWAPFILE"

        sudo fallocate -l 4G "$SWAPFILE"
        sudo chmod 600 "$SWAPFILE"
        sudo mkswap "$SWAPFILE" >/dev/null

    else

        ok "Swapfile zaten 4 GB."

        sudo chmod 600 "$SWAPFILE"

    fi

else

    info "4 GB swapfile oluşturuluyor..."

    sudo fallocate -l 4G "$SWAPFILE"
    sudo chmod 600 "$SWAPFILE"
    sudo mkswap "$SWAPFILE" >/dev/null

fi

# fstab
if grep -qE '^[[:space:]]*/swapfile[[:space:]]' /etc/fstab; then

    ok "/swapfile zaten fstab'da."

else

    echo "/swapfile none swap sw,pri=10 0 0" |
        sudo tee -a /etc/fstab >/dev/null

fi

sudo swapon "$SWAPFILE" 2>/dev/null || true

# ------------------------------------------------------------
# Swappiness
# ------------------------------------------------------------

info "Swappiness ayarlanıyor..."

sudo tee /etc/sysctl.d/99-mozcelik-swappiness.conf >/dev/null <<'EOF'
vm.swappiness=4
EOF

sudo sysctl --system >/dev/null

ok "vm.swappiness = 4"

# ------------------------------------------------------------
# Fish config
# ------------------------------------------------------------

info "Fish yapılandırılıyor..."

FISH_CONF="$REAL_HOME/.config/fish/conf.d"

sudo -u "$REAL_USER" mkdir -p "$FISH_CONF"

sudo -u "$REAL_USER" tee \
    "$FISH_CONF/mozcelik.fish" >/dev/null <<'EOF'

# MOzcelik Debian FSKS

if status is-interactive

    if command -v fastfetch >/dev/null
        fastfetch
    end

end

if command -v starship >/dev/null
    starship init fish | source
end

alias güncelle='sudo apt update && sudo apt upgrade -y && flatpak update'
alias temizle='sudo apt autoremove --purge -y && sudo apt autoclean -y && flatpak uninstall --unused'
alias yükle='sudo apt install'
alias fyükle='flatpak install flathub'
alias sil='sudo apt remove'
alias fsil='flatpak uninstall'
alias kapa='poweroff'
alias söyle='echo'

EOF

sudo chown -R "$REAL_USER:$REAL_USER" \
    "$REAL_HOME/.config/fish"

ok "Fish config oluşturuldu."

# ------------------------------------------------------------
# Fastfetch
# ------------------------------------------------------------

info "Fastfetch yapılandırılıyor..."

FASTFETCH_DIR="$REAL_HOME/.config/fastfetch"

sudo -u "$REAL_USER" mkdir -p "$FASTFETCH_DIR"

sudo -u "$REAL_USER" tee \
    "$FASTFETCH_DIR/config.jsonc" >/dev/null <<'EOF'
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
      "key": "upt",
      "keyColor": "green"
    },

    {
      "type": "cpu",
      "key": "cpu",
      "keyColor": "red",
      "format": "{name}"
    },

    {
      "type": "gpu",
      "key": "gpu",
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
      "key": "swap",
      "keyColor": "yellow",
      "format": "{used} / {total}"
    },

    {
      "type": "disk",
      "key": "disk",
      "keyColor": "cyan",
      "folders": [
        "/"
      ],
      "format": "{size-used} / {size-total}"
    },

    "break",

    {
      "type": "custom",
      "format": "\u001b[33m󰮯 \u001b[32m󰊠 \u001b[34m󰊠 \u001b[31m󰊠 \u001b[36m󰊠 \u001b[35m󰊠 \u001b[37m󰊠"
    }
  ]
}
EOF

sudo chown -R "$REAL_USER:$REAL_USER" \
    "$FASTFETCH_DIR"

ok "Fastfetch yapılandırıldı."

# ------------------------------------------------------------
# SON KONTROLLER
# ------------------------------------------------------------

echo
echo "============================================================"
echo "                    SON DURUM"
echo "============================================================"
echo

echo "Debian:"
echo "  Sürüm    : $DEBIAN_VERSION"
echo "  Codename : $DEBIAN_CODENAME"

echo
echo "Kernel:"
echo "  $(uname -r)"

echo
echo "APT:"
if sudo apt-get check >/dev/null 2>&1; then
    echo "  ✅ Sağlıklı"
else
    echo "  ❌ Sorun var"
fi

echo
echo "i386:"
if dpkg --print-foreign-architectures |
    grep -qx i386; then
    echo "  ✅ Aktif"
else
    echo "  ❌ Aktif değil"
fi

echo
echo "NVIDIA:"
if command -v nvidia-smi >/dev/null 2>&1 &&
   nvidia-smi >/dev/null 2>&1; then
    echo "  ✅ NVIDIA çalışıyor"
else
    echo "  ⚠️ NVIDIA doğrulanamadı"
fi

echo
echo "Steam:"
if command -v steam >/dev/null 2>&1 ||
   dpkg-query -W steam-installer >/dev/null 2>&1; then
    echo "  ✅ Kurulu"
else
    echo "  ⚠️ Kurulu değil"
fi

echo
echo "Wine:"
if command -v wine >/dev/null 2>&1; then
    echo "  ✅ Kurulu"
else
    echo "  ⚠️ Kurulu değil"
fi

echo
echo "Fish:"
if command -v fish >/dev/null 2>&1; then
    echo "  ✅ Kurulu"
else
    echo "  ⚠️ Kurulu değil"
fi

echo
echo "zRAM:"
if command -v zramctl >/dev/null 2>&1; then
    zramctl 2>/dev/null || true
else
    echo "  ⚠️ zramctl bulunamadı"
fi

echo
echo "Swap:"
swapon --show 2>/dev/null || true

echo
echo "Swappiness:"
cat /proc/sys/vm/swappiness

echo
echo "============================================================"
echo "              FSKS $SCRIPT_VERSION TAMAMLANDI"
echo "============================================================"
echo
echo "🔄 Sistemi yeniden başlatman önerilir:"
echo
echo "sudo reboot"
echo
