# Arch Linux + KDE Plasma — instalare completă

Script care instalează Arch Linux de la zero cu KDE Plasma complet și toate aplicațiile KDE. Fără Steam.

> ⚠️ **Scriptul șterge complet discul pe care îl alegi.** Fă backup înainte.

## Cum îl folosești

1. Descarcă ISO-ul de pe [archlinux.org/download](https://archlinux.org/download/) și scrie-l pe un stick USB (Ventoy, Rufus sau `dd`).
2. Pornește calculatorul de pe stick.
3. Conectează-te la internet. Cablul merge singur; pentru Wi-Fi:
   ```
   iwctl
   station wlan0 connect NUMELE_RETELEI
   exit
   ```
4. Descarcă și pornește scriptul:
   ```
   curl -LO https://raw.githubusercontent.com/x11xx11x/Smth/main/install.sh
   bash install.sh
   ```
5. Răspunde la întrebări, scrie `DA` la confirmare, apoi așteaptă (10–30 min).
6. La final scrie `reboot` și scoate stick-ul.

## Discuri

Scriptul îți arată toate discurile, numerotate, cu partițiile de pe ele. Stick-ul de pe care ai pornit (inclusiv Ventoy) e detectat și ascuns automat, deci nu poate fi șters. Alte discuri USB sunt marcate cu `[USB]` și nu se șterg niciodată la opțiunile 2 și 3. Alegi discul pentru Arch, apoi, dacă ai mai multe discuri:

| Opțiune | Ce face |
|---|---|
| **1** | Șterge **doar** discul ales. Celelalte rămân neatinse (merge dual-boot cu Windows, apare singur în GRUB). |
| **2** | Șterge **toate** discurile. Celelalte devin discuri de date goale, montate în `/data/disk1`, `/data/disk2`... |
| **3** | Șterge **toate** discurile și le lasă neformatate. |

## Ce instalează

| Categorie | Pachete |
|---|---|
| Desktop | `plasma-meta`, `kde-applications-meta` (toate aplicațiile KDE), SDDM |
| Audio | PipeWire (+ ALSA, Pulse, JACK) |
| Drivere video | detectate automat: NVIDIA (`nvidia-open-dkms`), AMD, Intel, plus 32-bit |
| Rețea | NetworkManager, OpenVPN, WireGuard, Bluetooth |
| Imprimante | CUPS, HPLIP, scanare în rețea |
| Aplicații | Firefox, Thunderbird, LibreOffice, VLC, mpv, OBS, GIMP, Inkscape, qBittorrent, KeePassXC |
| Codecuri și fonturi | FFmpeg, GStreamer complet, Noto (inclusiv emoji și CJK), JetBrains Mono Nerd |
| Sistem | Btrfs + snapshot-uri automate (Snapper, vizibile în meniul GRUB), zram, firewall (ufw), Flatpak + Flathub, `yay` pentru AUR, fwupd |
| Kernel | `linux` + opțional `linux-lts` ca rezervă |

Funcționează atât pe UEFI cât și pe BIOS vechi. În mașini virtuale (QEMU/KVM, VirtualBox, VMware) instalează automat și utilitarele de guest.

## Dacă ceva se strică după un update

Fiecare update face un snapshot. La pornire, în GRUB alegi **Arch Linux snapshots** și pornești din starea de dinainte. Dacă problema e kernelul, alege **linux-lts** din *Advanced options*.

## Note

- Plăcile NVIDIA mai vechi de seria GTX 16xx / RTX 20xx nu sunt suportate de `nvidia-open`. Pentru ele, după instalare: `yay -S nvidia-580xx-dkms`.
- Dacă un pachet a fost redenumit în depozite, scriptul sare peste el și afișează care lipsește, în loc să se oprească.
