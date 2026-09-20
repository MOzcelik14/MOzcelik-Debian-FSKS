#!/bin/bash
set -Eeuo pipefail
trap 'printf "❌ Satır %s: komut başarısız oldu (çıkış: %s).\n" "$LINENO" "$?" >&2' ERR

# ============================================================
# DEBIAN TRIXIE KURULUM / AYAR SCRIPTİ
# GNOME - X11 / Wayland
# (tek geçişli: kernel güncellemesi varsa kurar, reboot sonrası
#  script'i elle tekrar çalıştırman yeterli — otomatik terminal
#  açma / systemd resume mekanizması kaldırıldı)
# ============================================================

SCRIPT_PATH="$(realpath "$0")"
FSKS_PURGE_APPS="${FSKS_PURGE_APPS:-0}"
FSKS_GRUB_TUNING="${FSKS_GRUB_TUNING:-0}"
FSKS_WINETRICKS="${FSKS_WINETRICKS:-0}"

# ============================================================
# ROOT KONTROLÜ
# ============================================================

if [ "$EUID" -eq 0 ]; then
    echo "❌ Bu script root olarak çalıştırılmamalıdır."
    echo "   Normal kullanıcı ile çalıştırın."
    exit 1
fi

# Debian 13 dışındaki sistemlerin kaynaklarını değiştirmeyi reddet.
# shellcheck disable=SC1091
source /etc/os-release
if [[ "${ID:-}" != "debian" || "${VERSION_CODENAME:-}" != "trixie" || "$(dpkg --print-architecture)" != "amd64" ]]; then
    echo "❌ Yalnızca Debian 13 (trixie) amd64 desteklenir." >&2
    exit 1
fi
command -v sudo >/dev/null || { echo "❌ sudo bulunamadı." >&2; exit 1; }
sudo -v
TARGET_USER="$(id -un)"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

if [ -z "$TARGET_HOME" ]; then
    echo "❌ Kullanıcının home dizini bulunamadı."
    exit 1
fi

export HOME="$TARGET_HOME"
export USER="$TARGET_USER"

SUDO="sudo"

# ============================================================
# DEBIAN KAYNAKLARI / BACKPORTS / i386
# ============================================================

backup_once() {
    local file="$1"
    if [[ -f "$file" && ! -e "$file.fsks.bak" ]]; then
        sudo cp -a "$file" "$file.fsks.bak"
        echo "📦 Yedek: $file.fsks.bak"
    fi
}

update_components() {
    local file="$1" tmp
    [[ -f "$file" ]] || return 0
    tmp="$(mktemp)"
    awk '
      /^Components:[[:space:]]/ {
        for (i=1; i<=3; i++) {
          c=(i==1 ? "contrib" : i==2 ? "non-free" : "non-free-firmware")
          if (index(" " $0 " ", " " c " ") == 0) $0=$0 " " c
        }
      }
      /^deb(-src)?[[:space:]]/ {
        # Eski tip apt satırlarında mevcut alanları muhafaza et.
        split($0, parts, /[[:space:]]+#/)
        line=parts[1]
        for (i=1; i<=3; i++) {
          c=(i==1 ? "contrib" : i==2 ? "non-free" : "non-free-firmware")
          if (index(" " line " ", " " c " ") == 0) line=line " " c
        }
        if (length(parts[2])) line=line " #" parts[2]
        $0=line
      }
      {print}
    ' "$file" > "$tmp"
    if ! cmp -s "$tmp" "$file"; then
        backup_once "$file"
        sudo install -m 0644 "$tmp" "$file"
        echo "✅ Depo bileşenleri: $file"
    fi
    rm -f "$tmp"
}

update_components /etc/apt/sources.list.d/debian.sources
update_components /etc/apt/sources.list

if ! grep -RsEq '^(Suites:.*trixie-backports|deb[[:space:]].*[[:space:]]trixie-backports[[:space:]])' \
        /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
    sudo tee /etc/apt/sources.list.d/fsks-backports.sources >/dev/null <<'EOF'
Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
    echo "✅ trixie-backports eklendi."
fi

if ! dpkg --print-foreign-architectures | grep -qx i386; then
    sudo dpkg --add-architecture i386
fi
sudo apt-get update

# ============================================================
# KERNEL KONTROLÜ
# ============================================================

echo
echo "=============================="
echo "== KERNEL KONTROLÜ =="
echo "=============================="

echo "Mevcut kernel:"
uname -r

echo
echo "Kernel güncellemesi kontrol ediliyor..."

KERNEL_UPDATE_AVAILABLE=0

KERNEL_SIMULATION="$($SUDO apt-get -s install -t trixie-backports \
    linux-image-amd64 linux-headers-amd64)" || {
    echo "❌ Backports kernel paketleri kontrol edilemedi." >&2
    exit 1
}
if grep -Eq '^Inst linux-(image|headers)' <<< "$KERNEL_SIMULATION"; then
    KERNEL_UPDATE_AVAILABLE=1
fi

if [ "$KERNEL_UPDATE_AVAILABLE" -eq 1 ]; then

    echo
    echo "🆕 Yeni kernel bulundu (trixie-backports)."
    echo "Kernel ve header paketleri kuruluyor..."
    echo

    $SUDO apt-get install -y \
        -t trixie-backports \
        linux-image-amd64 \
        linux-headers-amd64

    echo
    echo "✅ Yeni kernel kuruldu."
    echo
    echo "========================================"
    echo "== YENİDEN BAŞLATMA GEREKİYOR =="
    echo "========================================"
    echo
    echo "🔄 Yeni kernel'in aktif olması için sistemi"
    echo "   yeniden başlatman gerekiyor."
    echo
    echo "▶️  Yeniden başlattıktan sonra bu script'i"
    echo "    tekrar çalıştır:"
    echo
    echo "    $SCRIPT_PATH"
    echo
    echo "    (kernel artık güncel olduğu için bu adım"
    echo "     atlanacak ve script GRUB ayarlarından"
    echo "     devam edecek.)"
    echo

    exit 0

else

    echo
    echo "✅ Yeni kernel bulunamadı."
    echo "Mevcut kernel ile devam ediliyor."

fi

# ============================================================
# GRUB: makineye özgü ayarlar varsayılan kapalı
# ============================================================

if [[ "$FSKS_GRUB_TUNING" == "1" ]]; then
    backup_once /etc/default/grub
    if ! grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub; then
        echo "❌ GRUB_CMDLINE_LINUX_DEFAULT yok; dosya değiştirilmedi." >&2
        exit 1
    fi
    for PARAM in acpi_backlight=native nvme_core.default_ps_max_latency_us=0; do
        if ! grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | grep -Fqw -- "$PARAM"; then
            sudo sed -i -E "s|^(GRUB_CMDLINE_LINUX_DEFAULT=)([\"'])(.*)\2|\1\2\3 $PARAM\2|" /etc/default/grub
        fi
    done
    # Kurtarma menüsü kullanılabilsin.
    if grep -q '^GRUB_TIMEOUT=' /etc/default/grub; then
        sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub
    else
        echo 'GRUB_TIMEOUT=3' | sudo tee -a /etc/default/grub >/dev/null
    fi
    sudo update-grub
else
    echo "ℹ️ GRUB korundu (FSKS_GRUB_TUNING=1 ile etkinleştirilebilir)."
fi

# ============================================================
# İSTEĞE BAĞLI PAKET TEMİZLİĞİ
# ============================================================

if [[ "$FSKS_PURGE_APPS" == "1" ]]; then
    sudo systemctl disable NetworkManager-wait-online.service 2>/dev/null || true
    sudo apt-get purge -y thunderbird transmission-gtk warpinator rhythmbox
    sudo apt-get autoremove --purge -y
else
    echo "ℹ️ Mevcut uygulamalar korundu (FSKS_PURGE_APPS=1 ile temizlik)."
fi

# ============================================================
# i386, ilk APT güncellemesinden önce etkinleştirildi.
# ============================================================

# ============================================================
# TEMEL PAKETLER
# ============================================================

echo
echo "=============================="
echo "== TEMEL PAKETLER =="
echo "=============================="

$SUDO apt install -y \
    numlockx \
    fish \
    starship \
    fastfetch \
    pciutils \
    fontconfig \
    steam-installer \
    wine \
    wine32 \
    winetricks \
    audacious \
    btop \
    rar \
    unrar \
    unzip \
    curl

# ============================================================
# NVIDIA
# ============================================================

echo
echo "=============================="
echo "== NVIDIA SÜRÜCÜSÜ =="
echo "=============================="

# ============================================================
# NVIDIA DONANIM KONTROLÜ
# ============================================================

if lspci | grep -qi "NVIDIA"; then

    echo "✅ NVIDIA GPU tespit edildi."
    echo "NVIDIA sürücüsü kurulumu başlatılıyor..."

    $SUDO apt-get install -y \
        dkms \
        build-essential

    echo
    echo "Kurulu kernel'lerin header'ları kontrol ediliyor..."

    for KERNEL in /lib/modules/*; do

        KERNEL_VERSION="$(basename "$KERNEL")"

        if [ -f "$KERNEL/build/Makefile" ]; then
            echo "✅ Header mevcut: $KERNEL_VERSION"
        else
            echo "🆕 Header eksik: $KERNEL_VERSION"

            if apt-cache show "linux-headers-$KERNEL_VERSION" >/dev/null 2>&1; then
                $SUDO apt-get install -y "linux-headers-$KERNEL_VERSION"
            else
                echo "⚠️ $KERNEL_VERSION için header artık depoda yok; eski kernel atlandı."
            fi
        fi

    done

    echo
    echo "NVIDIA sürücüsü kuruluyor..."
    echo "Kaynak: trixie-backports"

    $SUDO apt-get install -y \
        -t trixie-backports \
        nvidia-driver \
        nvidia-settings \
        nvidia-kernel-dkms

    echo
    echo "DKMS tüm kurulu kernel'ler için çalıştırılıyor..."

    $SUDO dkms autoinstall -k "$(uname -r)"

    $SUDO depmod -a

    echo
    echo "Aktif kernel:"
    uname -r

    if $SUDO modprobe nvidia 2>/dev/null; then
        echo "✅ NVIDIA kernel modülü yüklendi."
    else
        echo "⚠️ NVIDIA modülü şu anda yüklenemedi."
    fi

else

    echo "ℹ️ NVIDIA GPU tespit edilmedi."
    echo "ℹ️ Sanal makine / NVIDIA'sız sistem olduğu varsayılıyor."
    echo "⏭️ NVIDIA sürücüsü kurulumu atlanıyor."

fi

# ============================================================
# FISH
# ============================================================

echo
echo "=============================="
echo "== FISH =="
echo "=============================="

$SUDO chsh -s /usr/bin/fish "$TARGET_USER"

echo "✅ Starship APT üzerinden kuruldu; uzaktan script çalıştırılmıyor."

# ============================================================
# FLATPAK
# ============================================================

echo
echo "=============================="
echo "== FLATPAK =="
echo "=============================="

$SUDO apt install -y flatpak

$SUDO flatpak remote-add \
    --if-not-exists \
    flathub \
    https://flathub.org/repo/flathub.flatpakrepo

$SUDO flatpak install flathub -y \
    org.kde.kdenlive \
    app.zen_browser.zen \
    org.audacityteam.Audacity \
    org.nickvision.tubeconverter \
    org.onlyoffice.desktopeditors \
    net.davidotek.pupgui2 \
    com.google.AndroidStudio \
    com.heroicgameslauncher.hgl

# ============================================================
# WINETRICKS (isteğe bağlı, ayrı ve güvenli prefix)
# ============================================================

if [[ "$FSKS_WINETRICKS" == "1" ]]; then
    mkdir -p "$HOME/.local/share/wineprefixes"
    export WINEPREFIX="$HOME/.local/share/wineprefixes/fsks"
    winetricks -q dotnet48 vcrun2022 corefonts
else
    echo "ℹ️ Wine prefix'i korunuyor (FSKS_WINETRICKS=1 ile kurulum)."
fi

# ============================================================
# zRAM / SWAP
# ============================================================

echo
echo "=============================="
echo "== zRAM / SWAP =="
echo "=============================="

$SUDO apt install -y zram-tools

backup_once /etc/default/zramswap
$SUDO tee /etc/default/zramswap >/dev/null <<EOF
ALGO=zstd
PERCENT=50
PRIORITY=100
EOF

$SUDO systemctl enable zramswap
$SUDO systemctl restart zramswap

echo "vm.swappiness=4" |
    $SUDO tee /etc/sysctl.d/99-swappiness.conf >/dev/null

$SUDO sysctl --system

echo
echo "Bellek durumu:"
$SUDO free -h

echo
echo "Aktif swap:"
$SUDO swapon --show

echo
echo "zRAM:"
$SUDO zramctl

echo
echo "Swappiness:"
cat /proc/sys/vm/swappiness

# ============================================================
# FISH CONFIG: kullanıcı ayarlarını ezmeden FSKS bloğu ekle
# ============================================================

mkdir -p "$HOME/.config/fish"
FISH_CONFIG="$HOME/.config/fish/config.fish"
if [[ -f "$FISH_CONFIG" ]] && grep -Fq '# >>> FSKS >>>' "$FISH_CONFIG"; then
    echo "✅ FSKS Fish bloğu zaten var."
else
    if [[ -f "$FISH_CONFIG" ]]; then
        cp -a "$FISH_CONFIG" "$FISH_CONFIG.fsks.bak"
    fi
    cat >> "$FISH_CONFIG" <<'EOF'

# >>> FSKS >>>
if status is-interactive
    if type -q fastfetch
        fastfetch
    end
    if type -q starship
        starship init fish | source
    end
end

alias güncelle='sudo apt update && sudo apt upgrade -y && flatpak update'
alias temizle='sudo apt autoremove && sudo apt autoclean -y && flatpak uninstall --unused'
alias yükle='sudo apt install'
alias fyükle='flatpak install'
alias sil='sudo apt remove'
alias fsil='flatpak remove'
alias kapa='poweroff'
alias söyle='echo'
# <<< FSKS <<<
EOF
fi

# ============================================================
# JETBRAINS MONO NERD FONT
# ============================================================

echo
echo "=============================="
echo "== JetBrainsMono Nerd Font =="
echo "=============================="

mkdir -p "$HOME/.local/share/fonts"

FONT_TMP="$(mktemp --suffix=.zip)"
if curl --fail --location --silent --show-error --retry 3 \
        -o "$FONT_TMP" \
        https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip \
    && unzip -tq "$FONT_TMP" >/dev/null; then
    unzip -oq "$FONT_TMP" -d "$HOME/.local/share/fonts"
else
    echo "⚠️ Font indirilemedi / arşiv bozuk; kuruluma devam."
fi
rm -f "$FONT_TMP"

fc-cache -fv

# ============================================================
# FASTFETCH
# ============================================================

echo
echo "=============================="
echo "== FASTFETCH =="
echo "=============================="

mkdir -p "$HOME/.config/fastfetch"

if [[ ! -e "$HOME/.config/fastfetch/config.jsonc" ]]; then
cat > "$HOME/.config/fastfetch/config.jsonc" <<'EOF'
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
    "type": "builtin",
    "source": "debian"
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
fi

# ============================================================
# BİTİŞ
# ============================================================

echo
echo
echo "========================================"
echo "==              BİTTİ                  =="
echo "========================================"
echo
echo "✅ Tüm ayarlar tamamlandı."
echo
echo "Kernel:"
uname -r

echo
echo "NVIDIA:"
nvidia-smi 2>/dev/null ||
    echo "⚠️ nvidia-smi şu anda çalışmıyor."

echo
echo "GRUB:"
grep '^GRUB_TIMEOUT=' /etc/default/grub || true
grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub || true

echo
echo "========================================"
echo "==        HER ŞEY TAMAMLANDI          =="
echo "========================================"
echo
echo "Çıkmak için herhangi bir tuşa basın..."

if [ -t 0 ]; then
    read -n 1 -s -r
    echo
fi

exit 0
