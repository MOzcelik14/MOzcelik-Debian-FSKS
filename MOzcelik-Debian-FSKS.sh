#!/bin/bash
set -Eeuo pipefail

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
FSKS_BACKPORTS_KERNEL="${FSKS_BACKPORTS_KERNEL:-0}"
FSKS_ALLOW_NVIDIA_BACKPORTS="${FSKS_ALLOW_NVIDIA_BACKPORTS:-0}"
FSKS_SWAPPINESS="${FSKS_SWAPPINESS:-4}"
FSKS_CHANGE_SHELL="${FSKS_CHANGE_SHELL:-1}"
FSKS_INSTALL_FLATPAKS="${FSKS_INSTALL_FLATPAKS:-1}"
FSKS_INSTALL_FONT="${FSKS_INSTALL_FONT:-1}"
FSKS_INSTALL_NVIDIA="${FSKS_INSTALL_NVIDIA:-1}"

# ============================================================
# FSKS TERMINAL UI (yerleşik, ek bağımlılık gerektirmez)
# ============================================================

FSKS_START_SECONDS=$SECONDS
FSKS_STAGE=0
FSKS_STAGE_TOTAL=13
FSKS_STAGE_NAME="Başlangıç"

if [[ -t 1 && "${TERM:-dumb}" != "dumb" && -z "${NO_COLOR+x}" ]]; then
    UI_RESET=$'\033[0m'
    UI_BOLD=$'\033[1m'
    UI_MUTED=$'\033[2m'
    UI_CYAN=$'\033[36m'
    UI_BLUE=$'\033[34m'
    UI_GREEN=$'\033[32m'
    UI_YELLOW=$'\033[33m'
    UI_RED=$'\033[31m'
else
    UI_RESET="" UI_BOLD="" UI_MUTED="" UI_CYAN=""
    UI_BLUE="" UI_GREEN="" UI_YELLOW="" UI_RED=""
fi

ui_line() {
    printf '%s\n' '  --------------------------------------------------'
}

ui_banner() {
    printf '\n'
    printf '  %s%s  F S K S  /  DEBIAN SETUP %s\n' "$UI_BOLD" "$UI_CYAN" "$UI_RESET"
    printf '  %s     Debian 13 · Trixie · GNOME%s\n' "$UI_MUTED" "$UI_RESET"
    ui_line
    printf '  %sKullanıcı%s  %s\n' "$UI_MUTED" "$UI_RESET" "$(id -un)"
    printf '  %sKernel%s    %s\n' "$UI_MUTED" "$UI_RESET" "$(uname -r)"
    printf '  %sAşamalar%s  %s\n' "$UI_MUTED" "$UI_RESET" "$FSKS_STAGE_TOTAL"
    printf '  %sBilgi:%s Paket yöneticisi çıktıları aşağıda gösterilir.\n' "$UI_CYAN" "$UI_RESET"
}

ui_step() {
    FSKS_STAGE=$((FSKS_STAGE + 1))
    FSKS_STAGE_NAME="$1"
    local filled empty done_bar todo_bar
    filled=$((FSKS_STAGE * 30 / FSKS_STAGE_TOTAL))
    empty=$((30 - filled))
    printf -v done_bar '%*s' "$filled" ''
    printf -v todo_bar '%*s' "$empty" ''
    done_bar="${done_bar// /#}"
    todo_bar="${todo_bar// /-}"
    printf '\n'
    ui_line
    printf '  %s%s[%02d/%02d]%s  %s\n' "$UI_BOLD" "$UI_CYAN" "$FSKS_STAGE" "$FSKS_STAGE_TOTAL" "$UI_RESET" "$FSKS_STAGE_NAME"
    printf '  %s[%s%s%s]%s  %d%%\n' "$UI_BLUE" "$UI_GREEN" "$done_bar" "$todo_bar" "$UI_RESET" \
        "$((FSKS_STAGE * 100 / FSKS_STAGE_TOTAL))"
    printf '\n'
}

ui_success() { printf '  %s[ OK ]%s %s\n' "$UI_GREEN" "$UI_RESET" "$*"; }
ui_info()    { printf '  %s[INFO]%s %s\n' "$UI_CYAN" "$UI_RESET" "$*"; }
ui_warn()    { printf '  %s[UYARI]%s %s\n' "$UI_YELLOW" "$UI_RESET" "$*" >&2; }
ui_error()   { printf '  %s[HATA]%s %s\n' "$UI_RED" "$UI_RESET" "$*" >&2; }

ui_finish() {
    local elapsed=$((SECONDS - FSKS_START_SECONDS))
    printf '\n'
    ui_line
    printf '  %s%s  KURULUM TAMAMLANDI%s\n' "$UI_BOLD" "$UI_GREEN" "$UI_RESET"
    printf '  %sToplam süre:%s %02d:%02d\n' "$UI_MUTED" "$UI_RESET" "$((elapsed / 60))" "$((elapsed % 60))"
    printf '  %sEtkin kernel:%s %s\n' "$UI_MUTED" "$UI_RESET" "$(uname -r)"
    ui_line
    printf '\n'
}

fsks_on_error() {
    local code="$1" line="$2"
    ui_error "Aşama ${FSKS_STAGE}/${FSKS_STAGE_TOTAL} (${FSKS_STAGE_NAME}), satır ${line}; çıkış kodu ${code}."
    ui_info "Hata giderildikten sonra betiği yeniden çalıştırabilirsin." >&2
}
trap 'fsks_on_error "$?" "$LINENO"' ERR

# Gerçek kuruluma dokunmadan tasarım önizlemesi.
case "${1:-}" in
    --preview)
        ui_banner
        for stage in \
            "APT kaynakları" "Kernel kontrolü" "GRUB" "İsteğe bağlı temizlik" \
            "Temel paketler" "NVIDIA sürücüsü" "Fish & Starship" \
            "Flatpak uygulamaları" "Winetricks" "zRAM & swap" \
            "Fish yapılandırması" "Nerd Font" "Fastfetch"; do
            ui_step "$stage"
            ui_success "Örnek çıktı — gerçek kurulum yapılmadı."
        done
        ui_warn "Önizleme modu: hiçbir paket veya sistem ayarı değiştirilmedi."
        ui_finish
        exit 0
        ;;
    --help|-h)
        printf 'Kullanım: bash %s [--preview|--help]\n' "$(basename "$0")"
        printf '  --preview    Kurulumun görsel önizlemesi (değişiklik yapmaz).\n'
        printf '  --help       Bu yardım metni.\n'
        printf 'Renkleri kapatmak için NO_COLOR=1 kullan.\n'
        exit 0
        ;;
    "")
        ;;
    *)
        ui_error "Bilinmeyen argüman: $1 (kullanım için --help)."
        exit 2
        ;;
esac

ui_banner


for setting in FSKS_PURGE_APPS FSKS_GRUB_TUNING FSKS_WINETRICKS FSKS_BACKPORTS_KERNEL FSKS_ALLOW_NVIDIA_BACKPORTS FSKS_CHANGE_SHELL FSKS_INSTALL_FLATPAKS FSKS_INSTALL_FONT FSKS_INSTALL_NVIDIA; do
    if [[ "${!setting}" != "0" && "${!setting}" != "1" ]]; then
        printf '❌ %s yalnızca 0 veya 1 olabilir.\n' "$setting" >&2
        exit 1
    fi
done
if ! [[ "$FSKS_SWAPPINESS" =~ ^([0-9]|[1-9][0-9]|1[0-9][0-9]|200)$ ]]; then
    echo "❌ FSKS_SWAPPINESS 0–200 arasında olmalıdır." >&2
    exit 1
fi

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
        line=$0
        comment=""
        if (match(line, /[[:space:]]+#/)) {
          comment=substr(line, RSTART)
          line=substr(line, 1, RSTART-1)
        }
        # Modify only Debian archive/mirror Trixie entries.
        if (line !~ /(^|[[:space:]])trixie(-updates|-security|-backports)?([[:space:]]|$)/ ||
            line !~ /(deb\.debian\.org|security\.debian\.org|\/debian([\/[:space:]]|$)|\/debian-security([\/[:space:]]|$))/) {
          print
          next
        }
        gsub(/[[:space:]]+$/, "", line)
        for (i=1; i<=3; i++) {
          c=(i==1 ? "contrib" : i==2 ? "non-free" : "non-free-firmware")
          if (index(" " line " ", " " c " ") == 0) line=line " " c
        }
        $0=line comment
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
# KERNEL: Trixie stable varsayılan; backports açıkça istenirse
# ============================================================

echo
echo "=============================="
echo "== KERNEL KONTROLÜ =="
echo "=============================="
echo "Aktif kernel: $(uname -r)"

if [[ "$FSKS_BACKPORTS_KERNEL" == "1" ]]; then
    # NVIDIA 550 DKMS ve yeni backports kernel'leri birlikte garanti edilmez.
    if grep -sqi '^0x10de$' /sys/bus/pci/devices/*/vendor 2>/dev/null \
            && [[ "$FSKS_ALLOW_NVIDIA_BACKPORTS" != "1" ]]; then
        echo "❌ NVIDIA algılandı. Backports kernel ve NVIDIA DKMS uyumu garanti edilemez." >&2
        echo "   Stable kernel ile devam etmek için FSKS_BACKPORTS_KERNEL=0 kullan." >&2
        echo "   Bilinçli olarak denemek için FSKS_ALLOW_NVIDIA_BACKPORTS=1 kullan." >&2
        exit 1
    fi

    KERNEL_SIMULATION="$(sudo apt-get -s install -t trixie-backports \
        linux-image-amd64 linux-headers-amd64)" || {
        echo "❌ Backports kernel simülasyonu başarısız." >&2
        exit 1
    }

    if grep -Eq '^Inst linux-(image|headers)' <<< "$KERNEL_SIMULATION"; then
        echo "🆕 Backports kernel + header yükleniyor."
        sudo apt-get install -y -t trixie-backports \
            linux-image-amd64 linux-headers-amd64
    fi

    # Kaldığı yerden eski kernel ile sürücü kurmaya devam ETME.
    EXPECTED_KERNEL="$(dpkg-query -W -f='${Depends}' linux-image-amd64 2>/dev/null \
        | grep -oE 'linux-image-[^ ,(]+' | head -n 1 || true)"
    EXPECTED_KERNEL="${EXPECTED_KERNEL#linux-image-}"
    if [[ -n "$EXPECTED_KERNEL" && "$EXPECTED_KERNEL" != "$(uname -r)" ]]; then
        echo "🔄 Kernel kurulu fakat aktif değil: $EXPECTED_KERNEL"
        echo "   Yeniden başlat, sonra betiği tekrar çalıştır: $SCRIPT_PATH"
        exit 0
    fi
else
    echo "✅ Stable kernel korunuyor (FSKS_BACKPORTS_KERNEL=1 ile isteğe bağlı backports)."
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

$SUDO apt-get install -y \
    fish starship fastfetch pciutils fontconfig btop unzip curl

# Eksik bir oyun/multimedya paketi kalan kurulum adımlarını engellemesin.
for pkg in numlockx steam-installer wine wine32 winetricks audacious rar unrar; do
    if ! $SUDO apt-get install -y "$pkg"; then
        echo "⚠️ İsteğe bağlı APT paketi kurulamadı: $pkg"
    fi
done

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

if [[ "$FSKS_INSTALL_NVIDIA" == "1" ]] && lspci | grep -i "NVIDIA" >/dev/null; then

    echo "✅ NVIDIA GPU tespit edildi."
    echo "NVIDIA sürücüsü kurulumu başlatılıyor..."

    $SUDO apt-get install -y \
        dkms \
        build-essential

    echo
    echo "Aktif kernel header'ları kontrol ediliyor..."
    ACTIVE_HEADERS="linux-headers-$(uname -r)"
    if [[ ! -f "/lib/modules/$(uname -r)/build/Makefile" ]]; then
        if apt-cache show "$ACTIVE_HEADERS" >/dev/null 2>&1; then
            $SUDO apt-get install -y "$ACTIVE_HEADERS"
        else
            echo "❌ Aktif kernel için header bulunamadı: $ACTIVE_HEADERS" >&2
            exit 1
        fi
    fi

    echo
    echo "NVIDIA sürücüsü kuruluyor..."
    echo "Kaynak: Debian Trixie (APT sürüm adayı)"

    $SUDO apt-get install -y \
        nvidia-driver \
        nvidia-settings \
        nvidia-kernel-dkms

    echo
    echo "DKMS aktif kernel için kontrol ediliyor..."

    $SUDO dkms autoinstall -k "$(uname -r)"

    $SUDO depmod -a

    echo
    echo "Aktif kernel:"
    uname -r

    if $SUDO modprobe nvidia 2>/dev/null; then
        echo "✅ NVIDIA kernel modülü yüklendi."
    else
        echo "⚠️ NVIDIA modülü henüz yüklenemedi; nouveau / Secure Boot / reboot durumunu kontrol et."
        if command -v mokutil >/dev/null && mokutil --sb-state 2>/dev/null | grep -qi enabled; then
            echo "⚠️ Secure Boot açık. DKMS modülü için imzalama / MOK kaydı gerekebilir."
        fi
    fi

else

    echo "ℹ️ NVIDIA GPU tespit edilmedi."
    echo "⏭️ NVIDIA sürücüsü kurulumu atlandı (GPU yok veya FSKS_INSTALL_NVIDIA=0)."

fi

# ============================================================
# FISH
# ============================================================

echo
echo "=============================="
echo "== FISH =="
echo "=============================="

if [[ "$FSKS_CHANGE_SHELL" == "1" ]]; then
    FISH_PATH="$(command -v fish)"
    if [[ "$(getent passwd "$TARGET_USER" | cut -d: -f7)" != "$FISH_PATH" ]]; then
        $SUDO chsh -s "$FISH_PATH" "$TARGET_USER"
    fi
else
    echo "ℹ️ Varsayılan shell korunuyor (FSKS_CHANGE_SHELL=1 ile değiştirilir)."
fi

echo "✅ Starship APT üzerinden kuruldu; uzaktan script çalıştırılmıyor."

# ============================================================
# FLATPAK
# ============================================================

if [[ "$FSKS_INSTALL_FLATPAKS" == "1" ]]; then
    sudo apt-get install -y flatpak
    sudo flatpak remote-add --if-not-exists flathub \
        https://flathub.org/repo/flathub.flatpakrepo

    OPTIONAL_FLATPAKS=(
        org.kde.kdenlive
        app.zen_browser.zen
        org.audacityteam.Audacity
        org.nickvision.tubeconverter
        org.onlyoffice.desktopeditors
        net.davidotek.pupgui2
        com.google.AndroidStudio
        com.heroicgameslauncher.hgl
    )
    for app in "${OPTIONAL_FLATPAKS[@]}"; do
        if ! sudo flatpak install --noninteractive -y flathub "$app"; then
            echo "⚠️ Flatpak kurulamadı: $app (diğer uygulamalara devam)."
        fi
    done
else
    echo "ℹ️ Flatpak uygulamaları atlandı (FSKS_INSTALL_FLATPAKS=1)."
fi

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

ZRAM_CONFIG="$(printf 'ALGO=zstd\nPERCENT=50\nPRIORITY=100\n')"
ZRAM_CHANGED=0
if [[ ! -f /etc/default/zramswap ]] || [[ "$(cat /etc/default/zramswap)" != "$ZRAM_CONFIG" ]]; then
    backup_once /etc/default/zramswap
    printf '%s\n' "$ZRAM_CONFIG" | sudo tee /etc/default/zramswap >/dev/null
    ZRAM_CHANGED=1
fi

sudo systemctl enable zramswap
if [[ "$ZRAM_CHANGED" == "1" ]] && swapon --noheadings --raw --output NAME | grep -q '^/dev/zram'; then
    echo "⚠️ zRAM kullanımda: swapoff yapılmadı. Yeni yapılandırma reboot sonrası etkin."
elif ! systemctl is-active --quiet zramswap || [[ "$ZRAM_CHANGED" == "1" ]]; then
    sudo systemctl restart zramswap
fi

echo "vm.swappiness=$FSKS_SWAPPINESS" |
    $SUDO tee /etc/sysctl.d/99-swappiness.conf >/dev/null

$SUDO sysctl -w "vm.swappiness=$FSKS_SWAPPINESS"

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

if [[ "$FSKS_INSTALL_FONT" == "1" ]]; then
    mkdir -p "$HOME/.local/share/fonts"
    if compgen -G "$HOME/.local/share/fonts/JetBrainsMonoNerdFont*.ttf" >/dev/null; then
        echo "✅ JetBrainsMono Nerd Font zaten mevcut."
    else
        FONT_TMP="$(mktemp --suffix=.zip)"
        if curl --fail --location --silent --show-error --retry 3 \
                -o "$FONT_TMP" \
                https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip \
            && unzip -tq "$FONT_TMP" >/dev/null; then
            unzip -oq "$FONT_TMP" -d "$HOME/.local/share/fonts"
            fc-cache -f
        else
            echo "⚠️ Font indirilemedi / arşiv bozuk; kuruluma devam."
        fi
        rm -f "$FONT_TMP"
    fi
else
    echo "ℹ️ Font kurulumu atlandı (FSKS_INSTALL_FONT=1 ile etkin)."
fi

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
if lspci | grep -i "NVIDIA" >/dev/null; then
    nvidia-smi 2>/dev/null || echo "⚠️ NVIDIA GPU algılandı ancak nvidia-smi çalışmıyor."
else
    echo "NVIDIA GPU bulunmadı."
fi

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
