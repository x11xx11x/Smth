#!/usr/bin/env bash
# =============================================================================
#  Arch Linux + KDE Plasma - instalare completa (fara Steam)
#  Ruleaza din ISO-ul live de Arch Linux:
#     curl -LO https://raw.githubusercontent.com/x11xx11x/Smth/main/install.sh
#     bash install.sh
#
#  ATENTIE: scriptul STERGE COMPLET discul ales.
# =============================================================================
set -Eeuo pipefail

# ---------- culori / mesaje ----------
R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'; N=$'\e[0m'
info() { printf '%s==>%s %s\n' "$B" "$N" "$*"; }
ok()   { printf '%s ok%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%s !!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '%sEROARE:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }
trap 'die "a esuat la linia $LINENO: $BASH_COMMAND"' ERR

ask() { # ask "intrebare" "implicit" -> REPLY
    local prompt=$1 def=${2:-}
    if [[ -n $def ]]; then read -rp "$prompt [$def]: " REPLY; REPLY=${REPLY:-$def}
    else read -rp "$prompt: " REPLY; fi
}
ask_pass() { # ask_pass "pentru cine" -> PASS
    local p1 p2
    while true; do
        read -rsp "Parola pentru $1: " p1; echo
        read -rsp "Repeta parola: " p2; echo
        [[ -n $p1 && $p1 == "$p2" ]] && { PASS=$p1; return; }
        warn "Parolele nu coincid sau sunt goale. Mai incearca."
    done
}

# ---------- verificari ----------
[[ $EUID -eq 0 ]] || die "Ruleaza ca root (din ISO-ul live)."
[[ -f /etc/arch-release ]] || die "Ruleaza din ISO-ul live de Arch Linux."

if [[ -d /sys/firmware/efi/efivars ]]; then BOOT_MODE=uefi; else BOOT_MODE=bios; fi
info "Mod de boot: $BOOT_MODE"

info "Verific conexiunea la internet..."
if ! ping -c1 -W3 archlinux.org &>/dev/null; then
    warn "Nu ai internet. Pentru Wi-Fi ruleaza:  iwctl  ->  station wlan0 connect NUMEWIFI"
    die "Conecteaza-te la internet si porneste din nou scriptul."
fi
ok "Internet OK"

timedatectl set-ntp true || true

# ---------- intrebari ----------
# --- gasesc stick-ul de pe care ai pornit, ca sa nu fie sters niciodata ---
top_disk() { lsblk -lnpso NAME,TYPE "$1" 2>/dev/null | awk '$2=="disk"{print $1; exit}'; }
declare -A LIVE=()
for mp in /run/archiso/bootmnt /run/archiso/img_dev /run/archiso/cowspace; do
    src=$(findmnt -no SOURCE "$mp" 2>/dev/null || true)
    if [[ -n $src && -b $src ]]; then d=$(top_disk "$src"); [[ -n $d ]] && LIVE[$d]=1; fi
done
# orice disc care contine ISO-ul de Arch sau Ventoy e tot stick-ul de instalare
for p in $(lsblk -lnpo NAME); do
    fs=$(lsblk -dno FSTYPE "$p" 2>/dev/null || true)
    lb=$(lsblk -dno LABEL  "$p" 2>/dev/null || true)
    if [[ $fs == iso9660 || $lb =~ ^(ARCH_|ARCHISO|Ventoy|VTOYEFI) ]]; then
        d=$(top_disk "$p"); [[ -n $d ]] && LIVE[$d]=1
    fi
done

is_usb() { [[ $(lsblk -dno TRAN "$1" 2>/dev/null) == usb ]]; }

DISKS=()
while read -r d; do
    [[ $d =~ (loop|sr[0-9]|zram|ram[0-9]) ]] && continue
    [[ -n ${LIVE[$d]:-} ]] && continue
    DISKS+=("$d")
done < <(lsblk -dpno NAME,TYPE | awk '$2=="disk"{print $1}')
((${#DISKS[@]})) || die "Nu am gasit niciun disc pe care sa instalez."

echo
info "Discuri gasite:"
for i in "${!DISKS[@]}"; do
    d=${DISKS[$i]}
    tag=""; is_usb "$d" && tag="${Y}[USB]${N}"
    printf '  %s) %-15s %8s  %s %s\n' "$((i+1))" "$d" "$(lsblk -dno SIZE "$d")" "$(lsblk -dno MODEL "$d" | xargs)" "$tag"
    lsblk -no NAME,SIZE,FSTYPE,LABEL "$d" | tail -n +2 | sed 's/^/        /'
done
for d in "${!LIVE[@]}"; do
    echo "  ${G}(stick-ul de instalare $d e ascuns si protejat - nu se sterge)${N}"
done
echo

ask "Numarul discului pe care instalez Arch" "1"
[[ $REPLY =~ ^[0-9]+$ ]] && (( REPLY >= 1 && REPLY <= ${#DISKS[@]} )) || die "Numar invalid."
DISK=${DISKS[$((REPLY-1))]}
if is_usb "$DISK"; then
    warn "$DISK e un disc USB. Esti sigur ca vrei sa instalezi Arch pe el?"
    ask "Continui? (d/n)" "n"; [[ $REPLY =~ ^[dDyY] ]] || die "Anulat."
fi

# celelalte discuri interne; discurile USB nu se sterg niciodata automat
OTHER_DISKS=(); USB_KEEP=()
for d in "${DISKS[@]}"; do
    [[ $d == "$DISK" ]] && continue
    if is_usb "$d"; then USB_KEEP+=("$d"); else OTHER_DISKS+=("$d"); fi
done

WIPE_MODE=1
if ((${#OTHER_DISKS[@]})); then
    echo
    info "Ce fac cu celelalte discuri interne: ${OTHER_DISKS[*]} ?"
    ((${#USB_KEEP[@]})) && echo "  (discurile USB ${USB_KEEP[*]} raman oricum neatinse)"
    echo "  1) Le las NEATINSE - sterg doar $DISK  (bun pentru dual-boot cu Windows)"
    echo "  2) Le sterg si le fac discuri de date goale (apar in /data, gata de folosit)"
    echo "  3) Le sterg complet si le las neformatate"
    ask "Alege" "1"; WIPE_MODE=$REPLY
    [[ $WIPE_MODE =~ ^[123]$ ]] || die "Optiune invalida."
fi

WIPE_DISKS=("$DISK")
DATA_DISKS=()
case $WIPE_MODE in
    2) WIPE_DISKS+=("${OTHER_DISKS[@]}"); DATA_DISKS=("${OTHER_DISKS[@]}") ;;
    3) WIPE_DISKS+=("${OTHER_DISKS[@]}") ;;
esac

# ultima plasa de siguranta: stick-ul live nu ajunge niciodata in lista de sters
for d in "${WIPE_DISKS[@]}"; do
    [[ -n ${LIVE[$d]:-} ]] && die "Refuz sa sterg stick-ul de instalare $d."
done

ask "Nume calculator (hostname)" "arch"; HOSTNAME=$REPLY
ask "Nume utilizator (litere mici)" "theodor"; USERNAME=$REPLY
[[ $USERNAME =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Nume utilizator invalid."
ask_pass "$USERNAME"; USER_PASS=$PASS
ask "Parola root e aceeasi cu a utilizatorului? (d/n)" "d"
if [[ $REPLY =~ ^[dDyY] ]]; then ROOT_PASS=$USER_PASS; else ask_pass "root"; ROOT_PASS=$PASS; fi

ask "Fus orar" "Europe/Brussels"; TIMEZONE=$REPLY
[[ -f /usr/share/zoneinfo/$TIMEZONE ]] || die "Fus orar invalid: $TIMEZONE"
ask "Limba sistemului (ro_RO.UTF-8 sau en_US.UTF-8)" "ro_RO.UTF-8"; LANG_SYS=$REPLY
ask "Layout tastatura in consola" "us"; KEYMAP=$REPLY
ask "Instalez si kernelul LTS ca rezerva (recomandat)? (d/n)" "d"
[[ $REPLY =~ ^[dDyY] ]] && LTS=1 || LTS=0

# ---------- detectare hardware ----------
CPU_VENDOR=$(grep -m1 vendor_id /proc/cpuinfo | awk '{print $3}')
case $CPU_VENDOR in
    GenuineIntel) MICROCODE=intel-ucode ;;
    AuthenticAMD) MICROCODE=amd-ucode ;;
    *) MICROCODE="" ;;
esac

GPU_INFO=$(lspci -nn | grep -Ei 'vga|3d|display' || true)
GPU_PKGS="mesa lib32-mesa vulkan-icd-loader lib32-vulkan-icd-loader vulkan-tools mesa-utils"
NVIDIA=0
grep -qi nvidia <<<"$GPU_INFO" && { NVIDIA=1; GPU_PKGS+=" nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings libva-nvidia-driver"; }
grep -qE 'AMD/ATI|Advanced Micro Devices|Radeon' <<<"$GPU_INFO" && GPU_PKGS+=" vulkan-radeon lib32-vulkan-radeon"
grep -q 'Intel Corporation' <<<"$GPU_INFO" && GPU_PKGS+=" vulkan-intel lib32-vulkan-intel intel-media-driver"

VIRT=$(systemd-detect-virt || true)
VM_PKGS=""; VM_SERVICES=""
case $VIRT in
    kvm|qemu) VM_PKGS="qemu-guest-agent spice-vdagent"; VM_SERVICES="qemu-guest-agent" ;;
    oracle)   VM_PKGS="virtualbox-guest-utils"; VM_SERVICES="vboxservice" ;;
    vmware)   VM_PKGS="open-vm-tools"; VM_SERVICES="vmtoolsd" ;;
esac

# ---------- rezumat ----------
echo
echo "================= REZUMAT ================="
echo " Arch pe:     $DISK"
echo " SE STERG:    ${WIPE_DISKS[*]}"
((${#DATA_DISKS[@]})) && echo " Discuri date: ${DATA_DISKS[*]}  -> /data/disk1, /data/disk2..."
KEEP=("${USB_KEEP[@]}"); [[ $WIPE_MODE == 1 ]] && KEEP+=("${OTHER_DISKS[@]}")
((${#KEEP[@]})) && echo " Neatinse:    ${KEEP[*]}"
((${#LIVE[@]})) && echo " Stick live:  ${!LIVE[*]} (protejat)"
echo " Boot:        $BOOT_MODE"
echo " Hostname:    $HOSTNAME"
echo " Utilizator:  $USERNAME"
echo " Fus orar:    $TIMEZONE"
echo " Limba:       $LANG_SYS"
echo " CPU:         $CPU_VENDOR  ($MICROCODE)"
echo " GPU:         $(echo "$GPU_INFO" | sed 's/^[^:]*: //' | paste -sd ';')"
echo " NVIDIA:      $([[ $NVIDIA == 1 ]] && echo da || echo nu)"
echo " Masina virt: ${VIRT}"
echo " Kernel LTS:  $([[ $LTS == 1 ]] && echo da || echo nu)"
echo "==========================================="
echo
warn "TOT ce e pe ${WIPE_DISKS[*]} se pierde definitiv."
read -rp "${R}Scrie DA (cu majuscule) ca sa continui: ${N}" CONFIRM
[[ $CONFIRM == "DA" ]] || die "Anulat."

# ---------- partitionare ----------
part() { if [[ $DISK =~ [0-9]$ ]]; then echo "${DISK}p$1"; else echo "${DISK}$1"; fi; }
partof() { if [[ $1 =~ [0-9]$ ]]; then echo "${1}p$2"; else echo "${1}$2"; fi; }

wipe_disk() {
    local d=$1
    info "Sterg $d ..."
    # demonteaza orice partitie de pe disc
    lsblk -lnpo NAME "$d" | tail -n +2 | while read -r p; do
        umount -f "$p" 2>/dev/null || true; swapoff "$p" 2>/dev/null || true
        wipefs -af "$p" 2>/dev/null || true
    done
    wipefs -af "$d"
    sgdisk --zap-all "$d"
    partprobe "$d" 2>/dev/null || true
}

umount -R /mnt 2>/dev/null || true
swapoff -a 2>/dev/null || true
for d in "${WIPE_DISKS[@]}"; do wipe_disk "$d"; done

info "Partitionez $DISK ..."

if [[ $BOOT_MODE == uefi ]]; then
    sgdisk -n1:0:+1G -t1:ef00 -c1:EFI  "$DISK"
    sgdisk -n2:0:0   -t2:8300 -c2:ROOT "$DISK"
    partprobe "$DISK"; sleep 2
    EFI_PART=$(part 1); ROOT_PART=$(part 2)
    mkfs.fat -F32 -n EFI "$EFI_PART"
else
    sgdisk -n1:0:+1M -t1:ef02 -c1:BIOSBOOT "$DISK"
    sgdisk -n2:0:0   -t2:8300 -c2:ROOT     "$DISK"
    partprobe "$DISK"; sleep 2
    ROOT_PART=$(part 2)
fi

# Btrfs cu subvolume (permite snapshot-uri cu Snapper)
mkfs.btrfs -f -L ARCH "$ROOT_PART"
mount "$ROOT_PART" /mnt
for sv in @ @home @log @pkg @snapshots; do btrfs subvolume create "/mnt/$sv"; done
umount /mnt

OPTS="noatime,compress=zstd:1,space_cache=v2"
mount -o "$OPTS,subvol=@" "$ROOT_PART" /mnt
mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,.snapshots,boot}
mount -o "$OPTS,subvol=@home"      "$ROOT_PART" /mnt/home
mount -o "$OPTS,subvol=@log"       "$ROOT_PART" /mnt/var/log
mount -o "$OPTS,subvol=@pkg"       "$ROOT_PART" /mnt/var/cache/pacman/pkg
mount -o "$OPTS,subvol=@snapshots" "$ROOT_PART" /mnt/.snapshots
[[ $BOOT_MODE == uefi ]] && mount "$EFI_PART" /mnt/boot

# discuri de date (optiunea 2)
n=0
for d in "${DATA_DISKS[@]}"; do
    n=$((n+1))
    info "Pregatesc $d ca disc de date /data/disk$n ..."
    sgdisk -n1:0:0 -t1:8300 -c1:"DATA$n" "$d"
    partprobe "$d"; sleep 1
    mkfs.ext4 -F -L "DATA$n" "$(partof "$d" 1)"
    mkdir -p "/mnt/data/disk$n"
    mount "$(partof "$d" 1)" "/mnt/data/disk$n"
done
ok "Partitii gata"

# ---------- oglinzi + sistem de baza ----------
info "Aleg cele mai rapide oglinzi..."
reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist || warn "reflector a esuat, folosesc lista implicita"
sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
pacman -Sy --noconfirm archlinux-keyring

KERNELS="linux linux-headers"
[[ $LTS == 1 ]] && KERNELS+=" linux-lts linux-lts-headers"

info "Instalez sistemul de baza (pacstrap)..."
# shellcheck disable=SC2086
pacstrap -K /mnt base base-devel $KERNELS linux-firmware sof-firmware $MICROCODE \
    btrfs-progs networkmanager sudo nano vim git

genfstab -U /mnt >> /mnt/etc/fstab
# discurile de date nu blocheaza pornirea daca lipsesc
sed -i -E '/[[:space:]]\/data\/disk[0-9]+[[:space:]]/ s/(ext4[[:space:]]+)([^[:space:]]+)/\1\2,nofail/' /mnt/etc/fstab
ok "Sistem de baza instalat"

# ---------- configurare pentru chroot ----------
cat > /mnt/root/install.conf <<EOF
HOSTNAME='$HOSTNAME'
USERNAME='$USERNAME'
TIMEZONE='$TIMEZONE'
LANG_SYS='$LANG_SYS'
KEYMAP='$KEYMAP'
BOOT_MODE='$BOOT_MODE'
DISK='$DISK'
DATA_COUNT='${#DATA_DISKS[@]}'
NVIDIA='$NVIDIA'
GPU_PKGS='$GPU_PKGS'
VM_PKGS='$VM_PKGS'
VM_SERVICES='$VM_SERVICES'
EOF
chmod 600 /mnt/root/install.conf
# parolele se transmit separat, prin stdin, ca sa nu ramana in fisiere
printf 'root:%s\n%s:%s\n' "$ROOT_PASS" "$USERNAME" "$USER_PASS" > /mnt/root/.pw
chmod 600 /mnt/root/.pw

cat > /mnt/root/chroot.sh <<'CHROOT'
#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "EROARE in chroot la linia $LINENO: $BASH_COMMAND" >&2' ERR
# shellcheck disable=SC1091
source /root/install.conf

# --- timp, limba, retea ---
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc
sed -i -E 's/^#(en_US\.UTF-8 UTF-8)/\1/; s/^#(ro_RO\.UTF-8 UTF-8)/\1/' /etc/locale.gen
locale-gen
echo "LANG=$LANG_SYS" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<H
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
H

# --- pacman: multilib, descarcari paralele, culori ---
sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/; s/^#Color/Color/' /etc/pacman.conf
grep -q '^ILoveCandy' /etc/pacman.conf || sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
sed -i '/^#\[multilib\]/{N;s/#//g}' /etc/pacman.conf
pacman -Syu --noconfirm

# --- pachete ---
PKGS=(
  # KDE Plasma complet + toate aplicatiile KDE
  plasma-meta kde-applications-meta sddm sddm-kcm
  xdg-desktop-portal-kde xdg-desktop-portal-gtk xdg-user-dirs
  qt6-wayland egl-wayland
  phonon-qt6-vlc

  # Audio (PipeWire)
  pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber
  gst-plugin-pipewire

  # Retea, Bluetooth, imprimante, scanner
  networkmanager networkmanager-openvpn wireguard-tools
  bluez bluez-utils
  cups cups-pdf system-config-printer hplip sane-airscan
  avahi nss-mdns

  # Fisiere si sisteme de fisiere
  dosfstools exfatprogs ntfs-3g e2fsprogs xfsprogs udisks2 gvfs gvfs-mtp gvfs-smb
  p7zip unrar unzip zip

  # Codecuri multimedia
  ffmpeg gst-libav gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly
  libdvdcss x264 x265

  # Fonturi
  noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra
  ttf-dejavu ttf-liberation ttf-roboto ttf-fira-code ttf-jetbrains-mono-nerd

  # Aplicatii
  firefox thunderbird
  libreoffice-fresh libreoffice-fresh-ro hunspell hunspell-en_us
  vlc mpv obs-studio gimp inkscape
  qbittorrent keepassxc

  # Unelte sistem
  bash-completion man-db man-pages tealdeer
  htop btop fastfetch wget curl rsync reflector
  openssh git-lfs
  flatpak fwupd power-profiles-daemon
  zram-generator ufw
  snapper snap-pac
  pacman-contrib

  # Bootloader
  grub os-prober
)
[[ $BOOT_MODE == uefi ]] && PKGS+=(efibootmgr grub-btrfs inotify-tools) || PKGS+=(grub-btrfs inotify-tools)

# shellcheck disable=SC2206
PKGS+=($GPU_PKGS $VM_PKGS)

# sare peste pachetele care nu (mai) exista in depozite, ca instalarea sa nu se opreasca
OK_PKGS=(); MISSING=()
for p in "${PKGS[@]}"; do
  if pacman -Si "$p" &>/dev/null || pacman -Sg "$p" &>/dev/null; then OK_PKGS+=("$p"); else MISSING+=("$p"); fi
done
((${#MISSING[@]})) && echo "Sar peste pachete inexistente: ${MISSING[*]}"

pacman -S --needed --noconfirm "${OK_PKGS[@]}"

# --- NVIDIA: modesetting + fara hook-ul kms (evita nouveau) ---
if [[ $NVIDIA == 1 ]]; then
  sed -i -E 's/\bkms ?//' /etc/mkinitcpio.conf
  echo "options nvidia_drm modeset=1 fbdev=1" > /etc/modprobe.d/nvidia.conf
fi
mkinitcpio -P

# --- utilizator + parole ---
useradd -m -G wheel,audio,video,storage,optical,network,lp,scanner -s /bin/bash "$USERNAME"
chpasswd < /root/.pw
if (( DATA_COUNT > 0 )); then chown "$USERNAME:$USERNAME" /data/disk*; fi
shred -u /root/.pw
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel

# --- zram (swap comprimat in RAM) ---
cat > /etc/systemd/zram-generator.conf <<Z
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
Z

# --- mDNS pentru imprimante in retea ---
sed -i 's/^hosts:.*/hosts: mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns/' /etc/nsswitch.conf

# --- firewall: blocheaza intrarile, permite iesirile ---
ufw default deny incoming || true
ufw default allow outgoing || true
sed -i 's/^ENABLED=no/ENABLED=yes/' /etc/ufw/ufw.conf

# --- Snapper (snapshot-uri automate inainte/dupa fiecare update) ---
umount /.snapshots
rm -rf /.snapshots
snapper --no-dbus -c root create-config /
btrfs subvolume delete /.snapshots
mkdir /.snapshots
mount -a
chmod 750 /.snapshots
sed -i 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="5"/;
        s/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="7"/;
        s/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="0"/;
        s/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="0"/;
        s/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/' /etc/snapper/configs/root

# --- GRUB ---
sed -i 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub
if [[ $NVIDIA == 1 ]]; then
  sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 nvidia_drm.modeset=1"/' /etc/default/grub
fi
if [[ $BOOT_MODE == uefi ]]; then
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
  # copie de rezerva pe calea implicita (unele placi de baza o cer)
  grub-install --target=x86_64-efi --efi-directory=/boot --removable
else
  grub-install --target=i386-pc "$DISK"
fi
grub-mkconfig -o /boot/grub/grub.cfg

# --- servicii ---
SERVICES=(NetworkManager sddm bluetooth cups avahi-daemon fstrim.timer
          reflector.timer paccache.timer ufw power-profiles-daemon
          snapper-timeline.timer snapper-cleanup.timer grub-btrfsd)
for s in "${SERVICES[@]}" $VM_SERVICES; do systemctl enable "$s" || echo "nu am putut activa $s"; done

# --- SDDM cu tema Breeze ---
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/kde.conf <<S
[Theme]
Current=breeze
S

# --- reflector: oglinzi rapide automat ---
cat > /etc/xdg/reflector/reflector.conf <<RF
--save /etc/pacman.d/mirrorlist
--protocol https
--latest 20
--sort rate
RF

# --- Flathub ---
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true

# --- yay (pentru pachete din AUR) ---
echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/99-install-temp
sudo -u "$USERNAME" bash -c '
  cd /tmp && rm -rf yay-bin &&
  git clone --depth 1 https://aur.archlinux.org/yay-bin.git &&
  cd yay-bin && makepkg -si --noconfirm
' || echo "yay nu s-a instalat; il poti instala manual mai tarziu"
rm -f /etc/sudoers.d/99-install-temp

# --- foldere utilizator (Documente, Descarcari...) ---
sudo -u "$USERNAME" LANG="$LANG_SYS" xdg-user-dirs-update || true

rm -f /root/install.conf
echo "CHROOT GATA"
CHROOT
chmod +x /mnt/root/chroot.sh

info "Configurez sistemul si instalez KDE Plasma complet (dureaza 10-30 min)..."
arch-chroot /mnt /root/chroot.sh
rm -f /mnt/root/chroot.sh

umount -R /mnt
echo
ok "INSTALARE TERMINATA!"
echo "  Scoate stick-ul USB si scrie:  reboot"
echo "  La pornire alegi utilizatorul $USERNAME in ecranul de logare."
echo "  Recomand sesiunea 'Plasma (Wayland)'."
