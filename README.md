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
- Trixie stable kernelini varsayılan olarak korur. Backports kernel isteğe bağlıdır ve NVIDIA bulunan sistemlerde ek güvenlik onayı gerektirir. Kernel güncellendiyse yeniden başlatma için durur.
- Fish, Starship, Fastfetch gibi temel paketleri APT'den yükler; Steam, Wine/Wine32, Winetricks ve multimedya araçlarını birbirinden bağımsız kurar. İsteğe bağlı bir paket başarısız olursa uyarır ve diğerlerine devam eder.
- NVIDIA GPU varsa Trixie sürücü paketlerini ve **aktif kernel** header'larını kurar. Secure Boot açıksa modül imzası ayrıca gerekebilir. Yeni kernelde 550 sürücüsünün derlenmesi garanti edilmez.
- Flathub ile Kdenlive, Audacity, OnlyOffice, Heroic, Android Studio vb. Flatpak uygulamalarını kurar.
- Fish'e tekrar eklenmeyen bir FSKS bloğu, alias'lar ve Starship ekler; var olan Fish ve Fastfetch yapılandırmalarını korur.
- JetBrainsMono Nerd Font'u yalnızca eksikse indirir; zRAM'i RAM'in %50'si ve zstd ile ayarlar; varsayılan swappiness=100 uygular (değiştirilebilir).

**Swap dosyası oluşturmaz.** Önceden var olan swap dosyası/bölümü korunur. Fastfetch'te yeni bir yapılandırma üretirken yerleşik Debian logosunu kullanır.

## İsteğe bağlı kişisel işlemler

Varsayılan çalıştırma var olan uygulamaları ve GRUB ayarlarını değiştirmez; Wine'ın varsayılan prefix'ine dokunmaz. Şu değişkenlerle isteğe bağlı işlemleri açabilirsiniz:

| Değişken | Etki |
| --- | --- |
| `FSKS_PURGE_APPS=1` | Thunderbird, Transmission, Warpinator, Rhythmbox kaldırılır; autoremove yapılır ve NetworkManager-wait-online kapatılır. |
| `FSKS_GRUB_TUNING=1` | `acpi_backlight=native` ve `nvme_core.default_ps_max_latency_us=0` ekler; GRUB menü süresini 3 saniye yapar. Bunlar cihaz özelidir. |
| `FSKS_WINETRICKS=1` | Dotnet48, vcrun2022, corefonts'u yalnızca `~/.local/share/wineprefixes/fsks` içine kurar. |
| `FSKS_BACKPORTS_KERNEL=1` | En yeni backports kernel ve header'larını kurar. NVIDIA bulunan makinelerde ek onay gerektirir. |
| `FSKS_ALLOW_NVIDIA_BACKPORTS=1` | Backports kerneli NVIDIA ile deneme riskini açıkça kabul eder. **DKMS derlemesi başarısız olabilir.** |
| `FSKS_SWAPPINESS=4` | İstenirse kişisel swappiness değerini kullanır (0–200); varsayılan 100. |
| `FSKS_INSTALL_NVIDIA=0` | NVIDIA sürücüsünü kurmayı atlar (GPU bulunsa bile). |
| `FSKS_CHANGE_SHELL=0` | Varsayılan shell'in Fish olarak değiştirilmesini engeller. |
| `FSKS_INSTALL_FLATPAKS=0` | Flatpak uygulamalarını atlar. |
| `FSKS_INSTALL_FONT=0` | Font indirmesini atlar. |

Örnek: `FSKS_GRUB_TUNING=1 FSKS_SWAPPINESS=4 bash MOzcelik-Debian-FSKS.sh`

**NVIDIA kullananlar için:** `FSKS_BACKPORTS_KERNEL=1` seçimini zorunlu olmadıkça kullanmayın. Script, `FSKS_ALLOW_NVIDIA_BACKPORTS=1` verilmedikçe NVIDIA'lı sistemde bu işlemi reddeder. Bu bayrak uyumluluğu garanti etmez.

## Yedekler ve kontroller

Betik, değiştirdiği mevcut APT kaynakları, GRUB ve Fish dosyaları için bir defalık `.fsks.bak` yedeği oluşturur. **Bu, tam sistem yedeğinin yerini tutmaz.**

```bash
nvidia-smi
uname -r
swapon --show
zramctl
flatpak list
```

NVIDIA sürücüsü, kernel ve Wi-Fi gibi donanıma bağlı işlemleri gerçek Debian kurulumunda ayrıca doğrulayın. GitHub Actions Bash, ShellCheck ve depo kaynak dönüştürme/tekrar çalıştırma gibi statik ve izole regresyon testleri yapar; canlı bir Debian kurulumunun yerini tutmaz.

MIT lisansı.