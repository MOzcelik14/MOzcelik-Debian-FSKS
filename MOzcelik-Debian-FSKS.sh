
#!/bin/bash
set -e

# ============================================================
# DEBIAN TRIXIE KURULUM / AYAR SCRIPTİ
# GNOME - X11 / Wayland
# ============================================================

SCRIPT_PATH="$(realpath "$0")"
RESUME_SERVICE="/etc/systemd/system/debian-setup-resume.service"
RESUME_MARKER="/var/tmp/debian-setup-resume"

# ============================================================
# ROOT KONTROLÜ
# ============================================================

if [ "$EUID" -eq 0 ] && [ "${SETUP_RESUME:-0}" != "1" ]; then
    echo "❌ Bu script root olarak çalıştırılmamalıdır."
    echo "   Normal kullanıcı ile çalıştırın."
    exit 1
fi

# ============================================================
# KULLANICI
# ============================================================

if [ "${SETUP_RESUME:-0}" = "1" ]; then
    TARGET_USER="${SETUP_USER}"
else
    TARGET_USER="$USER"
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

if [ -z "$TARGET_HOME" ]; then
    echo "❌ Kullanıcının home dizini bulunamadı."
    exit 1
fi

export HOME="$TARGET_HOME"
export USER="$TARGET_USER"

if [ "$EUID" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

# ============================================================
# REBOOT SONRASI DEVAM
# ============================================================

if [ "${SETUP_RESUME:-0}" = "1" ]; then

    echo
    echo "========================================"
    echo "== KERNEL REBOOT SONRASI DEVAM EDİYOR =="
    echo "========================================"
    echo

    echo "Aktif kernel:"
    uname -r

    rm -f "$RESUME_MARKER" 2>/dev/null || true
fi

# ============================================================
# KERNEL KONTROLÜ
# ============================================================

if [ "${SETUP_RESUME:-0}" != "1" ] && [ ! -f "$RESUME_MARKER" ]; then

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
        linux-image-amd64 \
        linux-headers-amd64 2>/dev/null |
        grep -E '^Inst linux-(image|headers)' >/dev/null; then

        KERNEL_UPDATE_AVAILABLE=1
    fi

    if [ "$KERNEL_UPDATE_AVAILABLE" -eq 1 ]; then

        echo
        echo "🆕 Yeni kernel bulundu."
        echo "Kernel ve header paketleri kuruluyor..."
        echo

        $SUDO apt-get install -y \
            linux-image-amd64 \
            linux-headers-amd64

        echo
        echo "✅ Yeni kernel kuruldu."

        # ----------------------------------------------------
        # RESUME MARKER
        # ----------------------------------------------------

        $SUDO touch "$RESUME_MARKER"

        # ----------------------------------------------------
        # SYSTEMD RESUME SERVICE
        # ----------------------------------------------------

        $SUDO tee "$RESUME_SERVICE" >/dev/null <<EOF
[Unit]
Description=Debian Setup Script - Resume After Kernel Reboot
After=graphical.target
Wants=graphical.target

[Service]
Type=oneshot
Environment="SETUP_RESUME=1"
Environment="SETUP_USER=$TARGET_USER"

ExecStart=/bin/bash -c '
USER_NAME="$TARGET_USER"
SCRIPT="$SCRIPT_PATH"

echo "GNOME oturumu bekleniyor..."

# ============================================================
# GNOME OTURUMUNU BUL
# ============================================================

while true; do

    SESSION_ID=\$(loginctl list-sessions --no-legend 2>/dev/null |
        awk -v u="\$USER_NAME" "\$3 == u {print \$1; exit}")

    if [ -n "\$SESSION_ID" ]; then

        SESSION_TYPE=\$(loginctl show-session "\$SESSION_ID" \
            -p Type --value 2>/dev/null || true)

        SESSION_STATE=\$(loginctl show-session "\$SESSION_ID" \
            -p State --value 2>/dev/null || true)

        SESSION_LEADER=\$(loginctl show-session "\$SESSION_ID" \
            -p Leader --value 2>/dev/null || true)

        if [ "\$SESSION_STATE" = "active" ] &&
           { [ "\$SESSION_TYPE" = "x11" ] ||
             [ "\$SESSION_TYPE" = "wayland" ]; } &&
           [ -n "\$SESSION_LEADER" ]; then

            break
        fi
    fi

    sleep 2
done

echo "✅ GNOME oturumu bulundu."
echo "Oturum tipi: \$SESSION_TYPE"

# ============================================================
# KULLANICI OTURUM ORTAMINI AL
# ============================================================

ENV_FILE="/proc/\$SESSION_LEADER/environ"

DISPLAY_VALUE=""
WAYLAND_VALUE=""
DBUS_VALUE=""
XAUTHORITY_VALUE=""
XDG_CURRENT_DESKTOP_VALUE=""
XDG_SESSION_DESKTOP_VALUE=""

if [ -r "\$ENV_FILE" ]; then

    DISPLAY_VALUE=\$(tr "\\0" "\\n" < "\$ENV_FILE" |
        grep "^DISPLAY=" |
        head -n1 |
        cut -d= -f2- || true)

    WAYLAND_VALUE=\$(tr "\\0" "\\n" < "\$ENV_FILE" |
        grep "^WAYLAND_DISPLAY=" |
        head -n1 |
        cut -d= -f2- || true)

    DBUS_VALUE=\$(tr "\\0" "\\n" < "\$ENV_FILE" |
        grep "^DBUS_SESSION_BUS_ADDRESS=" |
        head -n1 |
        cut -d= -f2- || true)

    XAUTHORITY_VALUE=\$(tr "\\0" "\\n" < "\$ENV_FILE" |
        grep "^XAUTHORITY=" |
        head -n1 |
        cut -d= -f2- || true)

    XDG_CURRENT_DESKTOP_VALUE=\$(tr "\\0" "\\n" < "\$ENV_FILE" |
        grep "^XDG_CURRENT_DESKTOP=" |
        head -n1 |
        cut -d= -f2- || true)

    XDG_SESSION_DESKTOP_VALUE=\$(tr "\\0" "\\n" < "\$ENV_FILE" |
        grep "^XDG_SESSION_DESKTOP=" |
        head -n1 |
        cut -d= -f2- || true)

fi

RUNTIME_DIR="/run/user/\$(id -u "\$USER_NAME")"

if [ -z "\$DBUS_VALUE" ]; then
    DBUS_VALUE="unix:path=\$RUNTIME_DIR/bus"
fi

# ============================================================
# GNOME TERMINAL AÇ
# ============================================================

echo "GNOME Terminal açılıyor..."

runuser -u "\$USER_NAME" -- env \
    HOME="/home/\$USER_NAME" \
    USER="\$USER_NAME" \
    LOGNAME="\$USER_NAME" \
    XDG_RUNTIME_DIR="\$RUNTIME_DIR" \
    DBUS_SESSION_BUS_ADDRESS="\$DBUS_VALUE" \
    DISPLAY="\$DISPLAY_VALUE" \
    WAYLAND_DISPLAY="\$WAYLAND_VALUE" \
    XAUTHORITY="\$XAUTHORITY_VALUE" \
    XDG_CURRENT_DESKTOP="\$XDG_CURRENT_DESKTOP_VALUE" \
    XDG_SESSION_DESKTOP="\$XDG_SESSION_DESKTOP_VALUE" \
    gnome-terminal --wait -- \
    bash -c "
        export SETUP_RESUME=1
        export SETUP_USER='$USER_NAME'
        export HOME='/home/$USER_NAME'
        export USER='$USER_NAME'
        export LOGNAME='$USER_NAME'

        echo
        echo '========================================'
        echo '== DEBIAN SETUP RESUME =='
        echo '========================================'
        echo

        bash '$SCRIPT'

        RC=\\$?

        echo
        echo '========================================'

        if [ \\$RC -eq 0 ]; then
            echo '✅ SCRIPT BAŞARIYLA TAMAMLANDI'
        else
            echo \"❌ SCRIPT HATA İLE SONLANDI - Kod: \\$RC\"
        fi

        echo '========================================'
        echo
        read -n 1 -s -r -p 'Çıkmak için herhangi bir tuşa basın...'
        echo

        exit \\$RC
    "

exit \$?
'

[Install]
WantedBy=graphical.target
EOF

        # ----------------------------------------------------
        # SERVICE ENABLE
        # ----------------------------------------------------

        $SUDO systemctl daemon-reload
        $SUDO systemctl enable debian-setup-resume.service

        echo
        echo "========================================"
        echo "== YENİDEN BAŞLATILIYOR =="
        echo "========================================"
        echo
        echo "✅ Yeni kernel kuruldu."
        echo
        echo "🔄 Sistem yeniden başlatılacak."
        echo "🖥️  GNOME'a giriş yaptıktan sonra"
        echo "    terminal otomatik açılacak."
        echo
        echo "▶️  Script kaldığı yerden devam edecek."
        echo

        $SUDO reboot
        exit 0

    else

        echo
        echo "✅ Yeni kernel bulunamadı."
        echo "Mevcut kernel ile devam ediliyor."

    fi
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

        $SUDO sed -i \
            "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"|GRUB_CMDLINE_LINUX_DEFAULT=\"\1 $PARAM\"|" \
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
    build-essential \
    linux-headers-$(uname -r)

$SUDO apt install -y \
    nvidia-driver \
    nvidia-settings

echo
echo "DKMS çalıştırılıyor..."

$SUDO dkms autoinstall || true
$SUDO depmod -a

if $SUDO modprobe nvidia 2>/dev/null; then
    echo "✅ NVIDIA kernel modülü yüklendi."
else
    echo "⚠️ NVIDIA modülü şu anda yüklenemedi."
fi

echo
echo "NVIDIA durumu:"

if nvidia-smi; then
    echo "✅ NVIDIA sürücüsü çalışıyor."
else
    echo "⚠️ nvidia-smi şu anda çalışmıyor."
    echo "   Bu durum reboot sonrası değişebilir."
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
# RESUME SERVICE TEMİZLİĞİ
# ============================================================

if [ "${SETUP_RESUME:-0}" = "1" ]; then

    echo
    echo "=============================="
    echo "== RESUME SERVICE TEMİZLENİYOR =="
    echo "=============================="

    $SUDO systemctl disable \
        debian-setup-resume.service \
        2>/dev/null || true

    $SUDO rm -f "$RESUME_SERVICE"
    $SUDO rm -f "$RESUME_MARKER"

    $SUDO systemctl daemon-reload

    echo "✅ Resume service silindi."
    echo "✅ Bir daha otomatik çalışmayacak."

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

