#!/usr/bin/env bash
#
# SCRIPT_NAME: post-install.sh
# SCRIPT_VERSION: 1.0.0
# Desteklenen dağıtım: Debian 13 (Trixie) — yalnızca bu sürüm
#
# Kullanım: normal kullanıcı olarak, sudo ile çalıştırın:
#   sudo ./post-install.sh
#
set -Eeuo pipefail

# ------------------------------------------------------------------
# Sabitler
# ------------------------------------------------------------------
SCRIPT_NAME="post-install.sh"
SCRIPT_VERSION="1.0.0"
SUPPORTED_DEBIAN_CODENAME="trixie"
SUPPORTED_DEBIAN_VERSION_ID="13"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
APT_BACKUP_DIR="/etc/apt/fsks-backup-${TIMESTAMP}"

# ------------------------------------------------------------------
# Renkli log fonksiyonları
# ------------------------------------------------------------------
COLOR_CYAN="\033[1;36m"
COLOR_GREEN="\033[1;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_RED="\033[1;31m"
COLOR_RESET="\033[0m"

info() { echo -e "${COLOR_CYAN}ℹ️  $*${COLOR_RESET}"; }
ok()   { echo -e "${COLOR_GREEN}✅ $*${COLOR_RESET}"; }
warn() { echo -e "${COLOR_YELLOW}⚠️  $*${COLOR_RESET}"; }
die()  { echo -e "${COLOR_RED}❌ $*${COLOR_RESET}" >&2; exit 1; }

trap 'die "Beklenmeyen hata: satır $LINENO. Script durduruldu."' ERR

# ------------------------------------------------------------------
# Root / sudo kontrolü
# ------------------------------------------------------------------
if [[ "${EUID}" -eq 0 && -z "${SUDO_USER:-}" ]]; then
    die "Bu scripti doğrudan root olarak çalıştırmayın. Normal kullanıcı olarak 'sudo ./${SCRIPT_NAME}' şeklinde çalıştırın."
fi

if [[ "${EUID}" -ne 0 ]]; then
    die "Bu script sudo yetkisi gerektiriyor. Lütfen 'sudo ./${SCRIPT_NAME}' ile çalıştırın."
fi

if [[ -z "${SUDO_USER:-}" ]]; then
    die "SUDO_USER değişkeni bulunamadı. Scripti sudo ile normal bir kullanıcı üzerinden çalıştırın."
fi

REAL_USER="${SUDO_USER}"
REAL_HOME="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
if [[ -z "${REAL_HOME}" || ! -d "${REAL_HOME}" ]]; then
    die "Gerçek kullanıcının (${REAL_USER}) home dizini bulunamadı."
fi

info "Gerçek kullanıcı: ${REAL_USER}, home: ${REAL_HOME}"

run_as_user() {
    sudo -u "${REAL_USER}" -H bash -c "$*"
}

# ------------------------------------------------------------------
# Debian / sürüm kontrolü
# ------------------------------------------------------------------
[[ -f /etc/os-release ]] || die "/etc/os-release bulunamadı, bu sistem Debian değil gibi görünüyor."

# shellcheck disable=SC1091
source /etc/os-release

[[ "${ID:-}" == "debian" ]] || die "Bu script yalnızca Debian üzerinde çalışır. Tespit edilen: ${ID:-bilinmiyor}"

DEBIAN_CODENAME="${VERSION_CODENAME:-}"
if [[ -z "${DEBIAN_CODENAME}" ]]; then
    DEBIAN_CODENAME="$(lsb_release -cs 2>/dev/null || true)"
fi

if [[ "${DEBIAN_CODENAME}" != "${SUPPORTED_DEBIAN_CODENAME}" || "${VERSION_ID:-}" != "${SUPPORTED_DEBIAN_VERSION_ID}" ]]; then
    die "Bu script yalnızca Debian 13 (Trixie) üzerinde çalışır. Tespit edilen: ${PRETTY_NAME:-bilinmiyor} (codename: ${DEBIAN_CODENAME:-bilinmiyor})"
fi

ok "Debian 13 (Trixie) tespit edildi, devam ediliyor."

# ------------------------------------------------------------------
# Yardımcı fonksiyonlar
# ------------------------------------------------------------------
package_exists() {
    apt-cache show "$1" >/dev/null 2>&1
}

install_if_available() {
    local pkgs_to_install=()
    local pkg
    for pkg in "$@"; do
        if dpkg -s "${pkg}" >/dev/null 2>&1; then
            info "Paket zaten kurulu, atlanıyor: ${pkg}"
            continue
        fi
        if package_exists "${pkg}"; then
            pkgs_to_install+=("${pkg}")
        else
            warn "Paket depoda bulunamadı, atlanıyor: ${pkg}"
        fi
    done

    if [[ "${#pkgs_to_install[@]}" -gt 0 ]]; then
        info "Kurulacak paketler: ${pkgs_to_install[*]}"
        if apt-get install -y "${pkgs_to_install[@]}"; then
            ok "Kuruldu: ${pkgs_to_install[*]}"
        else
            warn "Bazı paketlerin kurulumu başarısız oldu: ${pkgs_to_install[*]}"
        fi
    else
        info "Kurulacak yeni paket yok (${*})."
    fi
}

section() {
    echo
    echo -e "${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
    echo -e "${COLOR_CYAN}  $*${COLOR_RESET}"
    echo -e "${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
}

# ==================================================================
# 1. APT KAYNAK DÜZELTME
# ==================================================================
section "1/10 — APT kaynakları düzeltiliyor"

mkdir -p "${APT_BACKUP_DIR}"
[[ -f /etc/apt/sources.list ]] && cp -a /etc/apt/sources.list "${APT_BACKUP_DIR}/" || true
if [[ -d /etc/apt/sources.list.d ]]; then
    mkdir -p "${APT_BACKUP_DIR}/sources.list.d"
    cp -a /etc/apt/sources.list.d/. "${APT_BACKUP_DIR}/sources.list.d/" 2>/dev/null || true
fi
ok "APT kaynakları yedeklendi: ${APT_BACKUP_DIR}"

info "APT kaynak dosyaları taranıp yanlış/eski suite isimleri düzeltiliyor..."
CURRENT_CODENAME="${DEBIAN_CODENAME}" python3 - <<'PYEOF'
import glob
import os
import re

codename = os.environ["CURRENT_CODENAME"]

# Eski/yanlış suite isimleri -> güncel codename ile değiştirilecek
BAD_SUITES = {
    "stable", "testing", "unstable", "sid",
    "bullseye", "buster", "stretch", "jessie", "wheezy",
    "bookworm",  # bir önceki stable
}

HOST_PATTERN = re.compile(r"(deb\.debian\.org|security\.debian\.org)")

REQUIRED_COMPONENTS = ["main", "contrib", "non-free", "non-free-firmware"]


def fix_suite(suite: str) -> str:
    base = suite
    suffix = ""
    for variant in ("-updates", "-security", "-backports"):
        if suite.endswith(variant):
            base = suite[: -len(variant)]
            suffix = variant
            break
    if base in BAD_SUITES:
        return codename + suffix
    return suite


def ensure_components(components: list) -> list:
    comps = list(components)
    if not comps:
        comps = ["main"]
    if "main" not in comps:
        comps.insert(0, "main")
    if "contrib" not in comps:
        comps.append("contrib")
    if "non-free" not in comps:
        comps.append("non-free")
    if "non-free-firmware" not in comps:
        comps.append("non-free-firmware")
    return comps


def process_classic_line(line: str) -> str:
    # deb/deb-src satırlarını işle, satır sonu yorumunu koru
    stripped = line.rstrip("\n")
    if not re.match(r"^\s*deb(-src)?\s", stripped):
        return line

    comment = ""
    m = re.search(r"(\s+#.*)$", stripped)
    code_part = stripped
    if m:
        comment = m.group(1)
        code_part = stripped[: m.start()]

    tokens = code_part.split()
    if len(tokens) < 3:
        return line

    deb_kw = tokens[0]
    # options bloğu [ ... ] varsa atla
    idx = 1
    opts = ""
    if tokens[idx].startswith("["):
        opt_tokens = []
        while idx < len(tokens) and not tokens[idx].endswith("]"):
            opt_tokens.append(tokens[idx])
            idx += 1
        if idx < len(tokens):
            opt_tokens.append(tokens[idx])
            idx += 1
        opts = " ".join(opt_tokens)

    if idx >= len(tokens):
        return line
    url = tokens[idx]
    idx += 1
    if idx >= len(tokens):
        return line
    suite = tokens[idx]
    idx += 1
    components = tokens[idx:]

    if not HOST_PATTERN.search(url):
        return line

    new_suite = fix_suite(suite)
    new_components = ensure_components(components)

    parts = [deb_kw]
    if opts:
        parts.append(opts)
    parts.append(url)
    parts.append(new_suite)
    parts.extend(new_components)

    return " ".join(parts) + comment + "\n"


def process_classic_file(path: str):
    with open(path, "r") as f:
        lines = f.readlines()
    new_lines = [process_classic_line(l) for l in lines]
    if new_lines != lines:
        with open(path, "w") as f:
            f.writelines(new_lines)
        print(f"[python] Güncellendi: {path}")


def process_deb822_file(path: str):
    with open(path, "r") as f:
        content = f.read()

    blocks = re.split(r"\n\n+", content)
    changed = False
    new_blocks = []

    for block in blocks:
        if not block.strip():
            new_blocks.append(block)
            continue

        uris_match = re.search(r"^URIs:\s*(.+)$", block, re.MULTILINE)
        if not uris_match or not HOST_PATTERN.search(uris_match.group(1)):
            new_blocks.append(block)
            continue

        suites_match = re.search(r"^Suites:\s*(.+)$", block, re.MULTILINE)
        comps_match = re.search(r"^Components:\s*(.+)$", block, re.MULTILINE)

        new_block = block

        if suites_match:
            old_suites = suites_match.group(1).split()
            new_suites = [fix_suite(s) for s in old_suites]
            if new_suites != old_suites:
                new_block = new_block.replace(
                    suites_match.group(0),
                    "Suites: " + " ".join(new_suites),
                )
                changed = True

        if comps_match:
            old_comps = comps_match.group(1).split()
            new_comps = ensure_components(old_comps)
            if new_comps != old_comps:
                new_block = new_block.replace(
                    comps_match.group(0),
                    "Components: " + " ".join(new_comps),
                )
                changed = True

        new_blocks.append(new_block)

    if changed:
        with open(path, "w") as f:
            f.write("\n\n".join(new_blocks))
        print(f"[python] Güncellendi (deb822): {path}")


if os.path.exists("/etc/apt/sources.list"):
    process_classic_file("/etc/apt/sources.list")

for path in glob.glob("/etc/apt/sources.list.d/*.list"):
    process_classic_file(path)

for path in glob.glob("/etc/apt/sources.list.d/*.sources"):
    process_deb822_file(path)

print("[python] APT kaynak düzeltme tamamlandı.")
PYEOF

# Duplicate bileşen temizliği (ör. "non-free-firmware non-free-firmware")
for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [[ -f "${f}" ]] || continue
    sed -i -E 's/\b(main|contrib|non-free-firmware|non-free)( \1\b)+/\1/g' "${f}"
done
ok "Duplicate bileşenler temizlendi."

info "apt update çalıştırılıyor..."
apt-get update
ok "APT kaynakları güncellendi."

# ==================================================================
# 2. MİMARİ VE SAĞLIK KONTROLÜ
# ==================================================================
section "2/10 — Mimari ve APT sağlık kontrolü"

if dpkg --print-foreign-architectures | grep -qx "i386"; then
    info "i386 mimarisi zaten etkin."
else
    info "i386 mimarisi ekleniyor..."
    dpkg --add-architecture i386
    apt-get update
    ok "i386 mimarisi eklendi."
fi

info "apt-get check çalıştırılıyor..."
if ! apt-get check; then
    die "APT bütünlük kontrolü başarısız oldu. Lütfen önce APT sorununu manuel çözün (ör. 'sudo apt --fix-broken install'), sonra scripti tekrar çalıştırın."
fi
ok "APT sağlıklı görünüyor."

UPGRADABLE_COUNT="$(apt list --upgradable 2>/dev/null | grep -c '^[^L]' || true)"
info "Yükseltilebilir paket sayısı: ${UPGRADABLE_COUNT}"

if [[ "${UPGRADABLE_COUNT}" -gt 0 ]]; then
    read -r -p "$(echo -e "${COLOR_YELLOW}full-upgrade yapalım mı? [Y/n]${COLOR_RESET} ")" DO_UPGRADE
    DO_UPGRADE="${DO_UPGRADE:-Y}"
    if [[ "${DO_UPGRADE}" =~ ^[Yy]$ ]]; then
        info "apt full-upgrade çalıştırılıyor..."
        apt-get full-upgrade -y
        ok "Sistem yükseltildi."
    else
        info "full-upgrade atlandı."
    fi
else
    info "Yükseltilecek paket yok."
fi

info "apt-get check tekrar çalıştırılıyor..."
if ! apt-get check; then
    die "Yükseltme sonrası APT bütünlük kontrolü başarısız oldu."
fi
ok "APT sağlığı doğrulandı."

# ==================================================================
# 3. GRUB AYARLARI
# ==================================================================
section "3/10 — GRUB ayarları"

GRUB_FILE="/etc/default/grub"
if [[ -f "${GRUB_FILE}" ]]; then
    cp -a "${GRUB_FILE}" "${GRUB_FILE}.bak-${TIMESTAMP}"
    ok "GRUB dosyası yedeklendi: ${GRUB_FILE}.bak-${TIMESTAMP}"

    for param in "acpi_backlight=native" "nvme_core.default_ps_max_latency_us=0"; do
        if grep -q "GRUB_CMDLINE_LINUX_DEFAULT=" "${GRUB_FILE}"; then
            CURRENT_LINE="$(grep 'GRUB_CMDLINE_LINUX_DEFAULT=' "${GRUB_FILE}" | head -n1)"
            if echo "${CURRENT_LINE}" | grep -q -- "${param}"; then
                info "GRUB parametresi zaten mevcut: ${param}"
            else
                sed -i -E "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"(.*)\"|GRUB_CMDLINE_LINUX_DEFAULT=\"\1 ${param}\"|" "${GRUB_FILE}"
                # Baştaki fazladan boşlukları temizle
                sed -i -E 's/GRUB_CMDLINE_LINUX_DEFAULT="\s+/GRUB_CMDLINE_LINUX_DEFAULT="/' "${GRUB_FILE}"
                ok "GRUB parametresi eklendi: ${param}"
            fi
        else
            echo "GRUB_CMDLINE_LINUX_DEFAULT=\"${param}\"" >> "${GRUB_FILE}"
            ok "GRUB_CMDLINE_LINUX_DEFAULT satırı oluşturuldu: ${param}"
        fi
    done

    info "update-grub çalıştırılıyor..."
    update-grub
    ok "GRUB güncellendi."
else
    warn "${GRUB_FILE} bulunamadı, GRUB adımı atlanıyor."
fi

# ==================================================================
# 4. SİSTEM TEMİZLİĞİ
# ==================================================================
section "4/10 — Sistem temizliği"

if systemctl list-unit-files | grep -q '^NetworkManager-wait-online.service'; then
    if systemctl is-enabled NetworkManager-wait-online.service >/dev/null 2>&1; then
        systemctl disable NetworkManager-wait-online.service || warn "NetworkManager-wait-online.service devre dışı bırakılamadı."
        ok "NetworkManager-wait-online.service devre dışı bırakıldı (boot hızlandırma)."
    else
        info "NetworkManager-wait-online.service zaten devre dışı."
    fi
else
    info "NetworkManager-wait-online.service sistemde yok, atlanıyor."
fi

for pkg in thunderbird transmission-gtk warpinator rhythmbox; do
    if dpkg -s "${pkg}" >/dev/null 2>&1; then
        info "Kaldırılıyor: ${pkg}"
        apt-get purge -y "${pkg}" || warn "${pkg} purge edilirken hata oluştu, atlanıyor."
    else
        info "${pkg} zaten kurulu değil."
    fi
done

info "apt autoremove --purge çalıştırılıyor..."
apt-get autoremove --purge -y
ok "Sistem temizliği tamamlandı."

# ==================================================================
# 5. TEMEL PAKETLER
# ==================================================================
section "5/10 — Temel paketler kuruluyor"

install_if_available curl wget numlockx fish audacious btop rar unrar fastfetch

# ==================================================================
# 6. OYUN / WINE / NVIDIA
# ==================================================================
section "6/10 — Oyun, Wine ve NVIDIA kurulumu"

if package_exists steam-installer; then
    install_if_available steam-installer
else
    warn "steam-installer paketi depoda bulunamadı, atlanıyor."
fi

install_if_available wine wine32 winetricks

if package_exists nvidia-driver; then
    info "NVIDIA sürücüsü kurulacak..."
    install_if_available dkms build-essential

    KERNEL_HEADERS="linux-headers-$(uname -r)"
    if package_exists "${KERNEL_HEADERS}"; then
        install_if_available "${KERNEL_HEADERS}"
    else
        warn "${KERNEL_HEADERS} bulunamadı, kernel header kurulumu atlanıyor. NVIDIA modülleri derlenemeyebilir."
    fi

    install_if_available nvidia-driver nvidia-settings nvidia-xconfig

    NOUVEAU_BLACKLIST="/etc/modprobe.d/blacklist-nouveau.conf"
    if [[ -f "${NOUVEAU_BLACKLIST}" ]] && grep -q "blacklist nouveau" "${NOUVEAU_BLACKLIST}"; then
        info "Nouveau zaten blacklist'te."
    else
        cat > "${NOUVEAU_BLACKLIST}" <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
        ok "Nouveau blacklist'e eklendi: ${NOUVEAU_BLACKLIST}"
    fi

    info "initramfs güncelleniyor..."
    update-initramfs -u || warn "update-initramfs sırasında hata oluştu."

    info "dkms autoinstall çalıştırılıyor..."
    dkms autoinstall || warn "dkms autoinstall sırasında hata oluştu."

    depmod -a || warn "depmod sırasında hata oluştu."

    if modprobe nvidia 2>/dev/null; then
        ok "nvidia modülü yüklendi."
    else
        warn "nvidia modülü şu an yüklenemedi, muhtemelen yeniden başlatma gerekiyor."
    fi
else
    info "nvidia-driver paketi depoda bulunamadı, NVIDIA kurulumu atlanıyor."
fi

# Winetricks kurulumu (gerçek kullanıcı olarak)
WINE_PREFIX="${REAL_HOME}/.wine"
info "Wine prefix hazırlanıyor: ${WINE_PREFIX}"
run_as_user "WINEPREFIX='${WINE_PREFIX}' wineboot -u" || warn "wineboot çalıştırılırken hata oluştu."

WINETRICKS_VERBS="dotnet40 dotnet45 dotnet48 vcrun2022 vcrun6sp6 allfonts"
info "Winetricks bileşenleri kuruluyor: ${WINETRICKS_VERBS}"
run_as_user "WINEPREFIX='${WINE_PREFIX}' winetricks -q ${WINETRICKS_VERBS}" || warn "winetricks bileşenleri kurulurken hata oluştu."

if run_as_user "winetricks list-all" 2>/dev/null | grep -qx "dxvk2030"; then
    info "dxvk2030 mevcut, kuruluyor..."
    run_as_user "WINEPREFIX='${WINE_PREFIX}' winetricks -q dxvk2030" || warn "dxvk2030 kurulurken hata oluştu."
else
    info "dxvk2030 winetricks listesinde bulunamadı, atlanıyor."
fi

# ==================================================================
# 7. SHELL VE GÖRÜNÜM
# ==================================================================
section "7/10 — Shell ve görünüm ayarları"

FISH_PATH="$(command -v fish || true)"
if [[ -n "${FISH_PATH}" ]]; then
    CURRENT_SHELL="$(getent passwd "${REAL_USER}" | cut -d: -f7)"
    if [[ "${CURRENT_SHELL}" == "${FISH_PATH}" ]]; then
        info "Varsayılan shell zaten fish."
    else
        grep -qx "${FISH_PATH}" /etc/shells || echo "${FISH_PATH}" >> /etc/shells
        chsh -s "${FISH_PATH}" "${REAL_USER}"
        ok "Varsayılan shell fish olarak ayarlandı."
    fi
else
    warn "fish bulunamadı, shell değişikliği atlanıyor."
fi

if command -v starship >/dev/null 2>&1; then
    info "starship zaten kurulu."
else
    info "starship kuruluyor..."
    if curl -sS https://starship.rs/install.sh | sh -s -- -y; then
        ok "starship kuruldu."
    else
        warn "starship kurulumu başarısız oldu."
    fi
fi

if command -v flatpak >/dev/null 2>&1; then
    info "flatpak zaten kurulu."
else
    install_if_available flatpak
fi

if command -v flatpak >/dev/null 2>&1; then
    if flatpak remote-list | grep -q '^flathub'; then
        info "Flathub remote zaten ekli."
    else
        flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
        ok "Flathub remote eklendi."
    fi

    FLATPAK_APPS=(
        "org.kde.kdenlive"
        "org.audacityteam.Audacity"
        "org.nickvision.tubeconverter"
        "org.onlyoffice.desktopeditors"
        "net.davidotek.pupgui2"
        "com.spotify.Client"
        "com.heroicgameslauncher.hgl"
    )

    for app in "${FLATPAK_APPS[@]}"; do
        if flatpak list --app | grep -q "${app}"; then
            info "Flatpak uygulaması zaten kurulu: ${app}"
        else
            info "Kuruluyor: ${app}"
            if flatpak install -y flathub "${app}"; then
                ok "Kuruldu: ${app}"
            else
                warn "${app} kurulurken hata oluştu, atlanıyor."
            fi
        fi
    done
else
    warn "flatpak bulunamadı, Flatpak uygulamaları atlanıyor."
fi

# ==================================================================
# 8. BELLEK / PERFORMANS
# ==================================================================
section "8/10 — Bellek ve performans ayarları"

install_if_available zram-tools

ZRAM_CONF="/etc/default/zramswap"
if [[ -f "${ZRAM_CONF}" ]]; then
    cp -a "${ZRAM_CONF}" "${ZRAM_CONF}.bak-${TIMESTAMP}"
fi

declare -A ZRAM_SETTINGS=( [ALGO]="zstd" [PERCENT]="50" [PRIORITY]="100" )
touch "${ZRAM_CONF}"
for key in "${!ZRAM_SETTINGS[@]}"; do
    value="${ZRAM_SETTINGS[$key]}"
    if grep -qE "^${key}=" "${ZRAM_CONF}"; then
        sed -i -E "s|^${key}=.*|${key}=${value}|" "${ZRAM_CONF}"
    else
        echo "${key}=${value}" >> "${ZRAM_CONF}"
    fi
done
ok "zram-tools yapılandırıldı (${ZRAM_CONF})."

systemctl enable zramswap.service || warn "zramswap.service etkinleştirilemedi."
systemctl restart zramswap.service || warn "zramswap.service yeniden başlatılamadı."
ok "zramswap servisi etkin ve çalışıyor."

SWAPFILE="/swapfile"
SWAPFILE_TARGET_BYTES=$((4 * 1024 * 1024 * 1024))

need_new_swapfile=true
if [[ -f "${SWAPFILE}" ]]; then
    CURRENT_SIZE="$(stat -c%s "${SWAPFILE}")"
    if [[ "${CURRENT_SIZE}" -eq "${SWAPFILE_TARGET_BYTES}" ]]; then
        info "${SWAPFILE} zaten tam 4GB boyutunda."
        need_new_swapfile=false
    else
        info "${SWAPFILE} mevcut ama boyutu farklı (${CURRENT_SIZE} bayt), yeniden oluşturulacak."
        sudo swapoff "${SWAPFILE}" 2>/dev/null || true
        rm -f "${SWAPFILE}"
    fi
fi

if [[ "${need_new_swapfile}" == true ]]; then
    info "${SWAPFILE} oluşturuluyor (4GB)..."
    if command -v fallocate >/dev/null 2>&1 && fallocate -l 4G "${SWAPFILE}" 2>/dev/null; then
        :
    else
        dd if=/dev/zero of="${SWAPFILE}" bs=1M count=4096 status=progress
    fi
    chmod 600 "${SWAPFILE}"
    sudo mkswap "${SWAPFILE}"
    ok "${SWAPFILE} oluşturuldu."
fi

chmod 600 "${SWAPFILE}"

if grep -qE "^\s*${SWAPFILE}\s" /etc/fstab; then
    info "${SWAPFILE} zaten /etc/fstab içinde."
else
    echo "${SWAPFILE} none swap sw,pri=10 0 0" >> /etc/fstab
    ok "${SWAPFILE} /etc/fstab içine eklendi (pri=10)."
fi

if sudo swapon --show=NAME --noheadings | grep -qx "${SWAPFILE}"; then
    info "${SWAPFILE} zaten aktif."
else
    sudo swapon "${SWAPFILE}" || warn "${SWAPFILE} etkinleştirilemedi."
    ok "${SWAPFILE} etkinleştirildi."
fi

SYSCTL_FILE="/etc/sysctl.d/99-mozcelik-swappiness.conf"
if [[ -f "${SYSCTL_FILE}" ]] && grep -q "^vm.swappiness=4$" "${SYSCTL_FILE}"; then
    info "swappiness zaten 4 olarak ayarlı."
else
    echo "vm.swappiness=4" > "${SYSCTL_FILE}"
    ok "${SYSCTL_FILE} yazıldı."
fi
sudo sysctl --system >/dev/null
ok "sysctl ayarları uygulandı."

# ==================================================================
# 9. KONFİGÜRASYON DOSYALARI
# ==================================================================
section "9/10 — Konfigürasyon dosyaları"

FISH_CONF_DIR="${REAL_HOME}/.config/fish/conf.d"
mkdir -p "${FISH_CONF_DIR}"
FISH_CONF_FILE="${FISH_CONF_DIR}/mozcelik.fish"

cat > "${FISH_CONF_FILE}" <<'FISHEOF'
if status is-interactive
    fastfetch
    starship init fish | source
end

function güncelle
    sudo apt update; and sudo apt upgrade -y; and flatpak update -y
end

function temizle
    sudo apt autoremove --purge -y; and sudo apt autoclean -y; and flatpak uninstall --unused -y
end

function yükle
    sudo apt install -y $argv
end

function fyükle
    flatpak install -y flathub $argv
end

function sil
    sudo apt remove -y $argv
end

function fsil
    flatpak uninstall -y $argv
end

function kapa
    systemctl poweroff
end

function söyle
    echo $argv
end
FISHEOF
ok "Fish konfigürasyonu yazıldı: ${FISH_CONF_FILE}"

FASTFETCH_CONF_DIR="${REAL_HOME}/.config/fastfetch"
mkdir -p "${FASTFETCH_CONF_DIR}"
FASTFETCH_CONF_FILE="${FASTFETCH_CONF_DIR}/config.jsonc"

cat > "${FASTFETCH_CONF_FILE}" <<'FASTFETCHEOF'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "type": "kitty-direct",
        "source": "~/.config/fastfetch/logo.png"
    },
    "display": {
        "size": {
            "binaryPrefix": "jedec"
        },
        "key": {
            "width": 10
        }
    },
    "modules": [
        {
            "type": "os",
            "key": "  OS",
            "keyColor": "cyan"
        },
        {
            "type": "kernel",
            "key": "  Kernel",
            "keyColor": "cyan"
        },
        {
            "type": "packages",
            "key": "  Paket",
            "keyColor": "green"
        },
        {
            "type": "uptime",
            "key": "  Süre",
            "keyColor": "green"
        },
        {
            "type": "cpu",
            "key": "  CPU",
            "keyColor": "yellow",
            "format": "{1} ({3}) @ {7} GHz"
        },
        {
            "type": "gpu",
            "key": "  GPU",
            "keyColor": "yellow"
        },
        {
            "type": "memory",
            "key": "  RAM",
            "keyColor": "magenta",
            "format": "{used} / {total} ({percentage})"
        },
        {
            "type": "swap",
            "key": "  Swap",
            "keyColor": "magenta",
            "format": "{used} / {total} ({percentage})"
        },
        {
            "type": "disk",
            "key": "  Disk",
            "keyColor": "blue",
            "format": "{used} / {total} ({percentage})"
        },
        {
            "type": "custom",
            "format": "\u001b[1;36m─────────────────────────\u001b[0m"
        }
    ]
}
FASTFETCHEOF
ok "Fastfetch konfigürasyonu yazıldı: ${FASTFETCH_CONF_FILE}"

info "Kullanıcı dosyalarının sahipliği düzeltiliyor..."
chown -R "${REAL_USER}:${REAL_USER}" "${REAL_HOME}/.config/fish" "${REAL_HOME}/.config/fastfetch" 2>/dev/null || true
ok "Sahiplik ${REAL_USER} kullanıcısına ayarlandı."

# ==================================================================
# 10. KAPANIŞ RAPORU
# ==================================================================
section "10/10 — Kurulum tamamlandı, özet rapor"

echo
echo -e "${COLOR_CYAN}════════════════ DURUM RAPORU ════════════════${COLOR_RESET}"

echo -e "Debian sürümü      : ${PRETTY_NAME:-bilinmiyor} (${DEBIAN_CODENAME})"
echo -e "Kernel sürümü      : $(uname -r)"

if apt-get check >/dev/null 2>&1; then
    echo -e "APT sağlığı        : ${COLOR_GREEN}Sağlıklı${COLOR_RESET}"
else
    echo -e "APT sağlığı        : ${COLOR_RED}Sorunlu${COLOR_RESET}"
fi

if dpkg --print-foreign-architectures | grep -qx "i386"; then
    echo -e "i386 mimarisi      : ${COLOR_GREEN}Etkin${COLOR_RESET}"
else
    echo -e "i386 mimarisi      : ${COLOR_YELLOW}Etkin değil${COLOR_RESET}"
fi

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    echo -e "NVIDIA             : ${COLOR_GREEN}Çalışıyor${COLOR_RESET}"
elif package_exists nvidia-driver; then
    echo -e "NVIDIA             : ${COLOR_YELLOW}Kurulu ama şu an aktif değil (reboot gerekebilir)${COLOR_RESET}"
else
    echo -e "NVIDIA             : Kurulmadı"
fi

if command -v steam >/dev/null 2>&1 || dpkg -s steam-installer >/dev/null 2>&1; then
    echo -e "Steam              : ${COLOR_GREEN}Kurulu${COLOR_RESET}"
else
    echo -e "Steam              : Kurulmadı"
fi

if command -v wine >/dev/null 2>&1; then
    echo -e "Wine               : ${COLOR_GREEN}Kurulu ($(wine --version 2>/dev/null))${COLOR_RESET}"
else
    echo -e "Wine               : Kurulmadı"
fi

if command -v fish >/dev/null 2>&1; then
    echo -e "Fish               : ${COLOR_GREEN}Kurulu${COLOR_RESET}"
else
    echo -e "Fish               : Kurulmadı"
fi

if command -v zramctl >/dev/null 2>&1; then
    echo -e "Zram durumu        :"
    sudo zramctl || true
fi

echo -e "Aktif swap listesi :"
sudo swapon --show || true

CURRENT_SWAPPINESS="$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "bilinmiyor")"
echo -e "Swappiness         : ${CURRENT_SWAPPINESS}"

echo -e "${COLOR_CYAN}════════════════════════════════════════════════${COLOR_RESET}"
echo
ok "Kurulum tamamlandı. Değişikliklerin tam olarak etkili olması için:"
echo -e "  ${COLOR_YELLOW}sudo reboot${COLOR_RESET}"
echo
