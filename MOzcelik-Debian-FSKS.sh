#!/bin/bash
set -e

# ============================================================
# DEBIAN TRIXIE KURULUM / AYAR SCRIPTİ
# GNOME - X11 / Wayland
# (tek geçişli: kernel güncellemesi varsa kurar, reboot sonrası
#  script'i elle tekrar çalıştırman yeterli — otomatik terminal
#  açma / systemd resume mekanizması kaldırıldı)
# ============================================================

SCRIPT_PATH="$(realpath "$0")"

# ============================================================
# ROOT KONTROLÜ
# ============================================================

if [ "$EUID" -eq 0 ]; then
    echo "❌ Bu script root olarak çalıştırılmamalıdır."
    echo "   Normal kullanıcı ile çalıştırın."
    exit 1
fi

TARGET_USER="$USER"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

if [ -z "$TARGET_HOME" ]; then
    echo "❌ Kullanıcının home dizini bulunamadı."
    exit 1
fi

export HOME="$TARGET_HOME"
export USER="$TARGET_USER"

SUDO="sudo"

# ============================================================
# DEBIAN REPOSITORY
# ============================================================

echo
echo "=============================="
echo "== DEBIAN REPOSITORY =="
echo "=============================="

# ------------------------------------------------------------
# debian.sources (deb822) varsa Components satırını düzenle
# ------------------------------------------------------------

if [ -f /etc/apt/sources.list.d/debian.sources ]; then

    $SUDO awk '
    /^Components:/ {
        if ($0 !~ /(^| )contrib( |$)/)
            $0 = $0 " contrib"

        if ($0 !~ /(^| )non-free( |$)/)
            $0 = $0 " non-free"

        if ($0 !~ /(^| )non-free-firmware( |$)/)
            $0 = $0 " non-free-firmware"
    }
    { print }
    ' /etc/apt/sources.list.d/debian.sources |
    $SUDO tee /tmp/debian.sources.new >/dev/null

    $SUDO mv /tmp/debian.sources.new \
        /etc/apt/sources.list.d/debian.sources

    echo "✅ debian.sources güncellendi."

fi

# ------------------------------------------------------------
# Eski sources.list formatı varsa deb satırlarını düzenle
# ------------------------------------------------------------

if [ -f /etc/apt/sources.list ]; then

    $SUDO awk '
    /^deb / {
        if ($0 !~ /(^| )contrib( |$)/)
            $0 = $0 " contrib"

        if ($0 !~ /(^| )non-free( |$)/)
            $0 = $0 " non-free"

        if ($0 !~ /(^| )non-free-firmware( |$)/)
            $0 = $0 " non-free-firmware"
    }
    { print }
    ' /etc/apt/sources.list |
    $SUDO tee /tmp/sources.list.new >/dev/null

    $SUDO mv /tmp/sources.list.new \
        /etc/apt/sources.list

    echo "✅ sources.list güncellendi."

fi

echo
echo "APT kaynakları:"
$SUDO apt update

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
echo "APT güncelleniyor..."

$SUDO apt update

echo
echo "Kernel güncellemesi kontrol ediliyor..."

KERNEL_UPDATE_AVAILABLE=0

if $SUDO apt-get -s install \
    -t trixie-backports \
    linux-image-amd64 \
    linux-headers-amd64 2>/dev/null |
    grep -E '^Inst linux-(image|headers)' >/dev/null; then

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
# GRUB
# ============================================================

echo
echo "=============================="
echo "== GRUB AYARLARI =="
echo "=============================="

GRUB_EXTRA="acpi_backlight=native nvme_core.default_ps_max_latency_us=0"

# GRUB_TIMEOUT=0
if grep -q '^GRUB_TIMEOUT=' /etc/default/grub; then

    $SUDO sed -i \
        's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' \
        /etc/default/grub

else

    echo 'GRUB_TIMEOUT=0' |
        $SUDO tee -a /etc/default/grub >/dev/null

fi

# Kernel parametreleri
for PARAM in $GRUB_EXTRA; do

    if ! grep -q "$PARAM" /etc/default/grub; then

        # -E ile tek tırnak (') ve çift tırnak (") ikisini de destekler;
        # eski hali sadece çift tırnağı varsayıyordu ve bu sistemde
        # (tek tırnaklı) sessizce hiçbir şey eklemiyordu.
        $SUDO sed -i -E \
            "s|^(GRUB_CMDLINE_LINUX_DEFAULT=)([\"'])(.*)\2|\1\2\3 $PARAM\2|" \
            /etc/default/grub

    fi

done

$SUDO update-grub

echo
echo "GRUB_TIMEOUT:"
grep '^GRUB_TIMEOUT=' /etc/default/grub

echo
echo "GRUB kernel parametreleri:"
grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub

# ============================================================
# GEREKSİZ PAKETLER
# ============================================================

echo
echo "=============================="
echo "== GEREKSİZ PAKETLER =="
echo "=============================="

$SUDO systemctl disable \
    NetworkManager-wait-online.service \
    2>/dev/null || true

$SUDO apt purge -y \
    thunderbird \
    transmission-gtk \
    warpinator \
    rhythmbox \
    2>/dev/null || true

$SUDO apt autoremove --purge -y

# ============================================================
# i386 MULTIARCH (wine32 için gerekli)
# ============================================================

echo
echo "=============================="
echo "== i386 MİMARİSİ =="
echo "=============================="

$SUDO dpkg --add-architecture i386
$SUDO apt update

echo
echo "Etkin mimariler:"
dpkg --print-foreign-architectures
dpkg --print-architecture

# ============================================================
# TEMEL PAKETLER
# ============================================================

echo
echo "=============================="
echo "== TEMEL PAKETLER =="
echo "=============================="

$SUDO apt update

$SUDO apt install -y \
    numlockx \
    fish \
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

$SUDO apt install -y fastfetch ||
    echo "⚠️ fastfetch kurulamadı."

# ============================================================
# NVIDIA
# ============================================================

echo
echo "=============================="
echo "== NVIDIA SÜRÜCÜSÜ =="
echo "=============================="

$SUDO apt install -y \
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
        $SUDO apt-get install -y \
            -t trixie-backports \
            "linux-headers-$KERNEL_VERSION"
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

$SUDO dkms autoinstall || true

$SUDO depmod -a

echo
echo "Aktif kernel:"
uname -r

if $SUDO modprobe nvidia 2>/dev/null; then
    echo "✅ NVIDIA kernel modülü yüklendi."
else
    echo "⚠️ NVIDIA modülü şu anda yüklenemedi."
fi

# ============================================================
# FISH
# ============================================================

echo
echo "=============================="
echo "== FISH =="
echo "=============================="

$SUDO chsh -s /usr/bin/fish "$TARGET_USER"

curl -sS https://starship.rs/install.sh |
    sh -s -- -y

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
# WINETRICKS
# ============================================================

echo
echo "=============================="
echo "== WINETRICKS =="
echo "=============================="

winetricks -q \
    dotnet40 \
    dotnet45 \
    dotnet48 \
    vcrun2022 \
    vcrun6sp6 \
    allfonts \
    dxvk2030

# ============================================================
# zRAM / SWAP
# ============================================================

echo
echo "=============================="
echo "== zRAM / SWAP =="
echo "=============================="

$SUDO apt install -y zram-tools

$SUDO tee /etc/default/zramswap >/dev/null <<EOF
ALGO=zstd
PERCENT=50
PRIORITY=100
EOF

$SUDO systemctl enable zramswap
$SUDO systemctl restart zramswap

$SUDO swapoff /swapfile 2>/dev/null || true
$SUDO rm -f /swapfile

$SUDO fallocate -l 4G /swapfile
$SUDO chmod 600 /swapfile
$SUDO mkswap /swapfile
$SUDO swapon /swapfile

$SUDO sed -i '\|^/swapfile|d' /etc/fstab

echo "/swapfile none swap sw 0 0" |
    $SUDO tee -a /etc/fstab >/dev/null

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
# FISH CONFIG
# ============================================================

echo
echo "=============================="
echo "== FISH YAPILANDIRMASI =="
echo "=============================="

mkdir -p "$HOME/.config/fish"

cat > "$HOME/.config/fish/config.fish" <<'EOF'
if status is-interactive
    echo " "
    set_color normal
    fastfetch
    echo
end

starship init fish | source

alias güncelle='sudo apt update || true && sudo apt upgrade -y && sudo flatpak update'
alias temizle='sudo apt autoremove && sudo apt autoclean -y && flatpak uninstall --unused'
alias yükle='sudo apt install'
alias fyükle='sudo flatpak install'
alias sil='sudo apt remove'
alias fsil='sudo flatpak remove'
alias kapa='poweroff'
alias söyle='echo'
EOF

# ============================================================
# JETBRAINS MONO NERD FONT
# ============================================================

echo
echo "=============================="
echo "== JetBrainsMono Nerd Font =="
echo "=============================="

mkdir -p "$HOME/.local/share/fonts"

curl -sSL \
    -o /tmp/JetBrainsMono.zip \
    https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip

unzip -o \
    /tmp/JetBrainsMono.zip \
    -d "$HOME/.local/share/fonts"

rm -f /tmp/JetBrainsMono.zip

fc-cache -fv

# ============================================================
# FASTFETCH
# ============================================================

echo
echo "=============================="
echo "== FASTFETCH =="
echo "=============================="

mkdir -p "$HOME/.config/fastfetch"

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
grep '^GRUB_TIMEOUT=' /etc/default/grub
grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub

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
