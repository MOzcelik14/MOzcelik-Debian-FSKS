# MOzcelik-Debian-FSKS

Bu betik, Debian 13 (Trixie) kurulumu sonrası sık yapılan ayarları otomatik olarak yapar.
Amaç: Yeni kurulan bir Debian 13 sistemini oyun, geliştirme ve günlük kullanım için hazır hale getirmek.


Neler Yapar?
------------

- APT depolarına contrib, non-free, non-free-firmware ekler.
- 32-bit mimari desteğini açar (i386).
- GRUB'a ek parametreler ekler.
- Gereksiz paketleri kaldırır (Thunderbird, Transmission, Rhythmbox, Warpinator).
- Sık kullanılan paketleri kurar: fish, starship, fastfetch, steam, wine, winetricks, audacious, btop, rar, unrar, numlockx.
- NVIDIA sürücülerini kurar, nouveau'yu blacklist'ler ve modülü derler.
- Flatpak ve Flathub'u kurar, popüler uygulamaları yükler (Kdenlive, Audacity, OnlyOffice, Heroic Games Launcher, Spotify, ProtonUp-Qt, Tube Converter).
- Winetricks ile .NET, vcrun, corefonts ve DXVK kurar.
- zRAM ayarlar (%50 RAM kadar, zstd sıkıştırma).
- 4GB swap dosyası oluşturur.
- vm.swappiness=4 ile swap kullanımını azaltır.
- Kullanıcı shell'ini fish olarak değiştirir.
- fish için alias'lar ve fastfetch yapılandırması oluşturur.


Gereksinimler
-------------

- Debian 13 (Trixie) veya daha yeni bir sürüm.
- İnternet bağlantısı.
- sudo yetkisi olan bir kullanıcı.
- NVIDIA ekran kartı varsa sürücü kurulur (isteğe bağlı, otomatik).


Özel Notlar
-----------

- NVIDIA Secure Boot etkinse, reboot sırasında MOK yönetimi ile modülü imzalamanız gerekir.
- Fastfetch varsayılan olarak ~/.config/fastfetch/marin.png arar. Kendi logonuzu koyabilirsiniz.
- fish kabuğunda şu alias'lar tanımlanır:
  güncelle, temizle, yükle, fyükle, sil, fsil, kapa, söyle
- zRAM %50 RAM kadar, ek olarak 4GB swap dosyası oluşturulur. Swappiness 4 olarak ayarlanır.


Kontroller (isteğe bağlı)
-------------------------

nvidia-smi      # NVIDIA sürücü durumu
fastfetch       # Sistem özeti
swapon --show   # Swap ve zRAM durumu
zramctl         # zRAM detayları
flatpak list    # Flatpak uygulamaları


Uyarılar
--------

- Betik /etc/apt/sources.list dosyasını düzenler. Yedek almak isterseniz manuel kopyalayın.
- Shell değiştirilir, oturumu kapatıp açmanız gerekebilir.
- NVIDIA kurulumu sırasında ekran kararabilir, bu normaldir.
- set -e ile çalışır, hata durumunda durur (öngörülen hatalar || true ile yönetilir).


Lisans
------

MIT Lisansı ile dağıtılmaktadır.


Katkı
-----

Hata bildirimi veya geliştirme önerileri için Issues / PR açabilirsiniz.


Hazırlayan: [Senin GitHub Kullanıcı Adın]
Tarih: Mart 2026
