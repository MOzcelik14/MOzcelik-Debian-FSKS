#!/bin/bash
set -e

# == Root kontrolü (script normal kullanıcı ile çalıştırılmalı) ==
if [ "$EUID" -eq 0 ]; then
    echo "❌ Bu script root olarak çalıştırılmamalıdır. Normal kullanıcı ile çalıştırın."
    exit 1
fi

echo "=============================="
echo "== APT REPOLARI (contrib/non-free) =="
echo "=============================="

# /etc/apt/sources.list içindeki tüm 'main' içeren deb satırlarına contrib/non-free ekle
sudo sed -i -E 's/^(deb .*)( main)(.*)$/\1\2 contrib non-free non-free-firmware\3/' /etc/apt/sources.list

# 32-bit mimari desteği (Steam/Wine)
sudo dpkg --add-architecture i386

sudo apt update

echo "=============================="
echo "== GRUB PARAMETRELERİ EKLENİYOR =="
echo "=============================="

sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 acpi_backlight=native nvme_core.default_ps_max_latency_us=0"/' /etc/default/grub
sudo update-grub

echo

echo "=============================="
echo "== GEREKSİZ BİLEŞENLER KALDIRILIYOR VE YENİ PAKETLER KURULUYOR =="
echo "=============================="

sudo systemctl disable NetworkManager-wait-online.service
sudo apt purge -y thunderbird transmission-gtk warpinator rhythmbox 2>/dev/null || true
sudo apt autoremove --purge -y

sudo apt update
sudo apt install -y numlockx fish steam-installer wine wine32 winetricks audacious btop rar unrar
sudo apt install -y fastfetch || echo "⚠️ fastfetch kurulamadı (belki backports gerekir)."

echo "=============================="
echo "== NVIDIA SÜRÜCÜ KURULUMU =="
echo "=============================="

# gerekli paketler (dkms, kernel headers, derleme araçları)
sudo apt install -y dkms build-essential linux-headers-$(uname -r)

# NVIDIA sürücü ve yardımcı araçlar
sudo apt install -y nvidia-driver nvidia-settings nvidia-xconfig

# nouveau blacklist
sudo tee /etc/modprobe.d/blacklist-nouveau.conf >/dev/null <<EOF
blacklist nouveau
options nouveau modeset=0
EOF

# initramfs'yi güncelle (nouveau kalıntılarını temizle)
sudo update-initramfs -u

# NVIDIA modülünü derle ve yükle
sudo dkms autoinstall
sudo depmod -a
sudo modprobe nvidia

# Kontrol
echo "NVIDIA sürücü durumu:"
if nvidia-smi; then
    echo "✅ NVIDIA sürücüsü başarıyla yüklendi ve çalışıyor."
else
    echo "⚠️ nvidia-smi çalıştırılamadı. Bu genellikle reboot sonrası düzelir."
    echo "   Sistemi yeniden başlattıktan sonra tekrar deneyin."
fi

echo "=============================="
echo "== SHELL AYARLANIYOR =="
echo "=============================="

sudo chsh -s /usr/bin/fish "$SUDO_USER"

curl -sS https://starship.rs/install.sh | sh -s -- -y

echo "=============================="
echo "== FlatPak Uygulamaları =="
echo "=============================="

sudo apt install -y flatpak
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
sudo flatpak install flathub -y \
    org.kde.kdenlive \
    org.audacityteam.Audacity \
    org.nickvision.tubeconverter \
    org.onlyoffice.desktopeditors \
    net.davidotek.pupgui2 \
    com.spotify.Client \
    com.heroicgameslauncher.hgl

echo "=============================="
echo "== Winetricks Kurulumları =="
echo "=============================="

winetricks -q dotnet40 dotnet45 dotnet48 vcrun2022 vcrun6sp6 corefonts

echo "=============================="
echo "== DXVK (FL için gerekli) =="
echo "=============================="

winetricks dxvk

echo "==> zRAM, Swap ve Swappiness ayarlanıyor..."

sudo apt install -y zram-tools

sudo tee /etc/default/zramswap >/dev/null <<EOF
ALGO=zstd
PERCENT=50
PRIORITY=100
EOF

sudo systemctl enable zramswap
sudo systemctl restart zramswap

sudo swapoff /swapfile 2>/dev/null || true
sudo rm -f /swapfile
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

sudo sed -i '\|^/swapfile|d' /etc/fstab
echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab >/dev/null

echo "vm.swappiness=4" | sudo tee /etc/sysctl.d/99-swappiness.conf >/dev/null
sudo sysctl --system

echo
echo "✅ Ayarlar tamamlandı."
echo

echo "Bellek durumu:"
sudo free -h

echo
echo "Aktif swap alanları:"
sudo swapon --show

echo
echo "zRAM durumu:"
sudo zramctl

echo
echo "Swappiness değeri:"
cat /proc/sys/vm/swappiness
echo

echo "Fish yapılandırılıyor..."

mkdir -p ~/.config/fish

cat > ~/.config/fish/config.fish <<'EOF'
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

echo

echo "Fastfetch yapılandırılıyor..."

mkdir -p ~/.config/fastfetch

cat > ~/.config/fastfetch/config.jsonc <<'EOF'
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

echo

echo "=============================="
echo "== BİTTİ =="
echo "=============================="

echo "✅ Her şey tamam!"
echo "⚠️  NVIDIA sürücüleri kuruldu. Eğer Secure Boot etkinse, yeniden başlatmada modülü imzalamanız gerekebilir."
echo "   (MOK yönetimi için ekranınızdaki talimatları izleyin.)"
echo "   Ayrıca nvidia-smi ile sürücünün çalıştığını kontrol edebilirsiniz."
echo
echo "🔄 Sistemi şimdi yeniden başlatın: sudo reboot"