# MOzcelik-Debian-FSKS

Debian **13 (Trixie) amd64** GNOME sistemini oyun, geliştirme ve günlük kullanım için hazırlayan kişisel kurulum betiği. Debian testing/Forky, Ubuntu veya Linux Mint üzerinde **çalıştırmayın**.

## Kurulum

```bash
git clone https://github.com/MOzcelik14/MOzcelik-Debian-FSKS.git
cd MOzcelik-Debian-FSKS
bash MOzcelik-Debian-FSKS.sh
```

Root olarak değil, sudo yetkili normal kullanıcıyla çalıştırın. Kernel değişirse betik durur; yeniden başlatıp aynı komutu yeniden çalıştırın. Sistem üzerinde APT, NVIDIA, Flatpak, shell ve bellek yapılandırmasını değiştirir; önce yedek alın.

## Ne yapar?

- APT kaynaklarına contrib, non-free, non-free-firmware ekler; **trixie-backports** kaynağını etkinleştirir ve i386 mimarisini açar.
- Backports kernel ve header paketlerini kontrol eder; yeni kernel kurulduğunda yeniden başlatma için durur.
- Oyun ve geliştirme paketlerini (Steam, Wine/Wine32, Winetricks, Fish, Starship, Fastfetch vb.) APT'den yükler.
- NVIDIA GPU varsa backports sürücüsü, DKMS ve bulunabilir kernel header paketlerini kurmayı dener. Secure Boot açıksa modül imzası ayrıca gerekebilir.
- Flathub ile Kdenlive, Audacity, OnlyOffice, Heroic, Android Studio vb. Flatpak uygulamalarını kurar.
- Fish'e tekrar eklenmeyen bir FSKS bloğu, alias'lar ve Starship ekler; var olan Fish ve Fastfetch yapılandırmalarını korur.
- JetBrainsMono Nerd Font indirir; zRAM'i RAM'in %50'si ve zstd ile ayarlar; swappiness=4 uygular.

**Swap dosyası oluşturmaz.** Önceden var olan swap dosyası/bölümü korunur. Fastfetch'te yeni bir yapılandırma üretirken yerleşik Debian logosunu kullanır.

## İsteğe bağlı kişisel işlemler

Varsayılan çalıştırma var olan uygulamaları ve GRUB ayarlarını değiştirmez; Wine'ın varsayılan prefix'ine dokunmaz. Şu değişkenlerle isteğe bağlı işlemleri açabilirsiniz:

| Değişken | Etki |
| --- | --- |
| `FSKS_PURGE_APPS=1` | Thunderbird, Transmission, Warpinator, Rhythmbox kaldırılır; autoremove yapılır ve NetworkManager-wait-online kapatılır. |
| `FSKS_GRUB_TUNING=1` | `acpi_backlight=native` ve `nvme_core.default_ps_max_latency_us=0` ekler; GRUB menü süresini 3 saniye yapar. Bunlar cihaz özelidir. |
| `FSKS_WINETRICKS=1` | Dotnet48, vcrun2022, corefonts'u yalnızca `~/.local/share/wineprefixes/fsks` içine kurar. |

Örnek: `FSKS_GRUB_TUNING=1 bash MOzcelik-Debian-FSKS.sh`

## Yedekler ve kontroller

Betik, değiştirdiği mevcut APT kaynakları, GRUB ve Fish dosyaları için bir defalık `.fsks.bak` yedeği oluşturur. **Bu, tam sistem yedeğinin yerini tutmaz.**

```bash
nvidia-smi
uname -r
swapon --show
zramctl
flatpak list
```

NVIDIA sürücüsü, kernel ve Wi-Fi gibi donanıma bağlı işlemleri gerçek Debian kurulumunda ayrıca doğrulayın. GitHub Actions yalnızca statik kontroller yapar.

MIT lisansı.