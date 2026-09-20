# MOzcelik-Debian-FSKS

Debian **13 (Trixie) amd64** GNOME sistemini oyun, geliştirme ve günlük kullanım için hazırlayan kişisel kurulum betiği. Debian testing/Forky, Ubuntu veya Linux Mint üzerinde **çalıştırmayın**.

## Kurulum

```bash
git clone https://github.com/MOzcelik14/MOzcelik-Debian-FSKS.git
cd MOzcelik-Debian-FSKS
bash MOzcelik-Debian-FSKS.sh
```

Root olarak değil, sudo yetkili normal kullanıcıyla çalıştırın. Kernel değişirse betik durur; yeniden başlatıp aynı komutu yeniden çalıştırın. Sistem üzerinde APT, NVIDIA, Flatpak, shell ve bellek yapılandırmasını değiştirir; önce yedek alın.

## Görsel kurulum arayüzü

Kurulum, ek bağımlılık gerektirmeyen ve **betiğin içinde bulunan** renkli terminal arayüzüyle çalışır. 13 numaralı aşama, ilerleme çubuğu, başarı/bilgi/uyarı mesajları ve toplam süreyi içeren bitiş ekranı vardır. APT ve diğer araçların çıktıları gizlenmez; hata durumunda aşama ve satır bilgisi gösterilir.

**Sistemde hiçbir değişiklik yapmadan arayüzü gör:**

```bash
bash MOzcelik-Debian-FSKS.sh --preview
```

Yardım: `bash MOzcelik-Debian-FSKS.sh --help`. Çıktıyı dosyaya yönlendirdiğinizde, terminal renk desteklemediğinde veya `NO_COLOR=1` tanımladığınızda ANSI renk kodları kullanılmaz:

```bash
NO_COLOR=1 bash MOzcelik-Debian-FSKS.sh --preview
```

## Ne yapar?

- APT kaynaklarına contrib, non-free, non-free-firmware ekler; **trixie-backports** kaynağını etkinleştirir ve i386 mimarisini açar.
- **Varsayılan olarak trixie-backports kernel + header kurar.** Kernel güncellendiyse yeniden başlatma için durur. Önce çalışan kernel paketini manuel işaretleyerek kurtarma seçeneğini korur.
- Fish, Starship, Fastfetch gibi temel paketleri APT'den yükler; Steam, Wine/Wine32, Winetricks ve multimedya araçlarını birbirinden bağımsız kurar. İsteğe bağlı bir paket başarısız olursa uyarır ve diğerlerine devam eder.
- NVIDIA GPU varsa önce aktif kernel header'larını, ardından NVIDIA'nın **resmî Debian 13 deposundan `nvidia-open`** sürücüsünü ve Steam/Proton için `nvidia-driver-libs:i386` paketini kurmayı dener; ancak ardından backports kernel kurar. `nvidia-open` Turing ve sonrası (RTX 3050 dahil) içindir. Secure Boot açıksa MOK imzası ayrıca gerekebilir.
- Flathub ile Kdenlive, Audacity, OnlyOffice, Heroic, Android Studio vb. Flatpak uygulamalarını kurar.
- Fish'e tekrar eklenmeyen bir FSKS bloğu, alias'lar ve Starship ekler; var olan Fish ve Fastfetch yapılandırmalarını korur.
- JetBrainsMono Nerd Font'u yalnızca eksikse indirir; zRAM'i RAM'in %50'si ve zstd ile ayarlar; varsayılan swappiness=4 uygular (değiştirilebilir).

zRAM kullanımdayken ayar değişmişse hizmeti zorla yeniden başlatmaz; yeni zRAM ayarları yeniden başlatma sonrasında uygulanır.

**Swap dosyası oluşturmaz.** Önceden var olan swap dosyası/bölümü korunur. Fastfetch'te yeni bir yapılandırma üretirken yerleşik Debian logosunu kullanır.

## İsteğe bağlı kişisel işlemler

Varsayılan çalıştırma var olan uygulamaları ve GRUB ayarlarını değiştirmez; Wine'ın varsayılan prefix'ine dokunmaz. Şu değişkenlerle isteğe bağlı işlemleri açabilirsiniz:

| Değişken | Etki |
| --- | --- |
| `FSKS_PURGE_APPS=1` | Thunderbird, Transmission, Warpinator, Rhythmbox kaldırılır; autoremove yapılır ve NetworkManager-wait-online kapatılır. |
| `FSKS_GRUB_TUNING=1` | `acpi_backlight=native` ve `nvme_core.default_ps_max_latency_us=0` ekler; GRUB menü süresini 3 saniye yapar. Bunlar cihaz özelidir. |
| `FSKS_WINETRICKS=1` | Dotnet48, vcrun2022, corefonts'u yalnızca `~/.local/share/wineprefixes/fsks` içine kurar. |
| `FSKS_BACKPORTS_KERNEL=0` | Backports kernel kurulumunu kapatır, çalışan kerneli korur. Varsayılan 1. |
| `FSKS_NVIDIA_SOURCE=debian` | NVIDIA resmî deposu yerine Debian'ın kendi sürücü paketlerini kurar. Yeni kernelde eski 550 sürücüsü için ayrıca onay gerekir. |
| `FSKS_ALLOW_NVIDIA_BACKPORTS=1` | **Yalnızca** `FSKS_NVIDIA_SOURCE=debian` ile eski NVIDIA sürücüsünü backports kernel üzerinde denemeye izin verir; uyumu garanti etmez. |
| `FSKS_SWAPPINESS=100` | İstenirse zRAM'i daha aktif kullanmak için farklı swappiness değeri seçer (0–200); varsayılan 4. |
| `FSKS_INSTALL_NVIDIA=0` | NVIDIA sürücüsünü kurmayı atlar (GPU bulunsa bile). |
| `FSKS_CHANGE_SHELL=0` | Varsayılan shell'in Fish olarak değiştirilmesini engeller. |
| `FSKS_INSTALL_FLATPAKS=0` | Flatpak uygulamalarını atlar. |
| `FSKS_INSTALL_FONT=0` | Font indirmesini atlar. |

Örnek: `FSKS_GRUB_TUNING=1 FSKS_SWAPPINESS=100 bash MOzcelik-Debian-FSKS.sh`

**RTX 3050 kullananlar için:** Varsayılan akış `NVIDIA resmî nvidia-open → backports kernel → reboot → betiği tekrar çalıştır` şeklindedir. 6.12 serisi kurulu kernel paketini korur. Yeni kernelde DKMS başarısız olursa kurulum durur; önceki kernelle GRUB üzerinden açarak sorunu giderebilirsin. **Gerçek donanımda başarı garantisi değildir.**

## NVIDIA kurulumu ve uyumluluk

NVIDIA'nın [Debian 13 kurulum kılavuzu](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/debian.html), `cuda-keyring` kullanarak resmî depoyu etkinleştirmeyi ve açık modüller için `nvidia-open` kurulmasını tarif eder. Script, bu yöntemi kullanır ve **CUDA Toolkit'i yüklemez**. Oyunlar için NVIDIA'nın [32-bit kütüphane önerisini](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/optional-components.html) ayrıca uygular.

- Resmî depo paketleri, AMD64 için `https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/` adresinden alınır.
- Yeniden başlatma öncesi mevcut kernel modülü doğrulanır; yeni kernel kurulurken DKMS derlemesi hata verirse betik durur.
- CUDA deposu `cuda-keyring` ile imzalı olarak eklenir; başka dağıtımın NVIDIA deposu kullanılmaz.
- NVIDIA sürücüsü ve kernelin **çalıştığı** yalnızca gerçek Debian 13 kurulumu üzerinde `nvidia-smi` ve oyunlarla doğrulanabilir.
- Steam/Proton için 32-bit kütüphane kurulumu başarısız olursa uyarı verilir; bunu göz ardı etmeyin.

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