#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
#  MineOS Gaming Edition — Installation réelle sur disque
#  install-core.sh <disque> <mode> <gaming> <gpu> <autoupdate>
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

TARGET="$1"        # ex: /dev/sda ou /dev/nvme0n1
MODE="$2"          # full | minimal | update
OPT_GAMING="$3"    # true | false
OPT_GPU="$4"       # true | false
OPT_UPDATE="$5"    # true | false

LOG="/tmp/mineos-install.log"
MOUNT="/mnt/mineos-install"

RED='\033[1;31m'; GRN='\033[1;32m'; CYN='\033[1;36m'; YLW='\033[1;33m'; RST='\033[0m'
log()      { echo -e "${GRN}[$(date +%H:%M:%S)] $*${RST}"              | tee -a "$LOG"; }
log_step() { echo -e "\n${CYN}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}" | tee -a "$LOG"; }
warn()     { echo -e "${YLW}[WARN]${RST} $*"                            | tee -a "$LOG"; }
die()      { echo -e "${RED}[FATAL]${RST} $*"                           | tee -a "$LOG"; exit 1; }

# Détecter si NVMe (partitions = p1/p2) ou SATA (partitions = 1/2)
if echo "$TARGET" | grep -q "nvme"; then
    PART_EFI="${TARGET}p1"
    PART_ROOT="${TARGET}p2"
else
    PART_EFI="${TARGET}1"
    PART_ROOT="${TARGET}2"
fi

# ═══════════════════════════════════════════════════════════════════════════════
log_step "1/8 — Vérifications préliminaires"
# ═══════════════════════════════════════════════════════════════════════════════
[ "$EUID" -ne 0 ]     && die "Nécessite root"
[ ! -b "$TARGET" ]    && die "Disque introuvable : $TARGET"
command -v debootstrap &>/dev/null || apt-get install -y debootstrap &>/dev/null
command -v mkfs.vfat   &>/dev/null || apt-get install -y dosfstools   &>/dev/null

DISK_SIZE=$(lsblk -dno SIZE "$TARGET" 2>/dev/null | head -1)
log "  Disque : $TARGET ($DISK_SIZE)"
log "  Mode   : $MODE"

# ═══════════════════════════════════════════════════════════════════════════════
log_step "2/8 — Partitionnement GPT (EFI + root)"
# ═══════════════════════════════════════════════════════════════════════════════

# Démonter toute partition déjà montée sur la cible
for PART in $(lsblk -lno NAME "$TARGET" 2>/dev/null | tail -n+2); do
    umount -f "/dev/$PART" 2>/dev/null || true
    swapoff  "/dev/$PART"  2>/dev/null || true
done
wipefs -a "$TARGET" 2>/dev/null || true

# Table GPT : 512 MB EFI + reste en ext4
parted -s "$TARGET" \
    mklabel gpt \
    mkpart ESP  fat32  1MiB    513MiB \
    mkpart ROOT ext4   513MiB  100% \
    set 1 esp on

sleep 1
partprobe "$TARGET"
sleep 1

log "  Partition EFI  : $PART_EFI"
log "  Partition ROOT : $PART_ROOT"

# ═══════════════════════════════════════════════════════════════════════════════
log_step "3/8 — Formatage"
# ═══════════════════════════════════════════════════════════════════════════════
mkfs.vfat -F32 -n "MINEOS_EFI"  "$PART_EFI"  || die "mkfs.vfat échoué"
mkfs.ext4 -F   -L "MINEOS_ROOT" "$PART_ROOT" || die "mkfs.ext4 échoué"

mkdir -p "$MOUNT"
mount "$PART_ROOT" "$MOUNT"
mkdir -p "$MOUNT/boot/efi"
mount "$PART_EFI"  "$MOUNT/boot/efi"

log "  ext4 et FAT32 formatés — montés sur $MOUNT"

# ═══════════════════════════════════════════════════════════════════════════════
log_step "4/8 — Installation système de base (debootstrap Ubuntu 22.04)"
# ═══════════════════════════════════════════════════════════════════════════════
debootstrap \
    --arch=amd64 \
    --variant=minbase \
    --include=systemd,systemd-sysv,udev,dbus,sudo,locales,ca-certificates,wget,curl,gnupg,apt-transport-https \
    jammy "$MOUNT" \
    "http://archive.ubuntu.com/ubuntu" \
    || die "debootstrap échoué"

log "  Système de base Ubuntu 22.04 installé"

# ── Préparer le chroot ───────────────────────────────────────────────────────
mount --bind /proc    "$MOUNT/proc"
mount --bind /sys     "$MOUNT/sys"
mount --bind /dev     "$MOUNT/dev"
mount --bind /dev/pts "$MOUNT/dev/pts"
cp /etc/resolv.conf "$MOUNT/etc/resolv.conf"

# fstab
ROOT_UUID=$(blkid -s UUID -o value "$PART_ROOT")
EFI_UUID=$(blkid -s UUID -o value "$PART_EFI")
cat > "$MOUNT/etc/fstab" << FSTAB
# MineOS Gaming fstab
UUID=$ROOT_UUID  /          ext4  defaults,noatime  0  1
UUID=$EFI_UUID   /boot/efi  vfat  umask=0077        0  2
FSTAB

# ═══════════════════════════════════════════════════════════════════════════════
log_step "5/8 — Installation des paquets MineOS"
# ═══════════════════════════════════════════════════════════════════════════════
chroot "$MOUNT" /bin/bash -s "$OPT_GAMING" "$OPT_GPU" "$OPT_UPDATE" << 'CHROOT_SCRIPT'
#!/bin/bash
OPT_GAMING="$1"; OPT_GPU="$2"; OPT_UPDATE="$3"
export DEBIAN_FRONTEND=noninteractive
set -e

cat > /etc/apt/sources.list << 'SOURCES'
deb http://archive.ubuntu.com/ubuntu jammy main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu jammy-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu jammy-security main restricted universe multiverse
SOURCES

dpkg --add-architecture i386
apt-get update -qq

# Packages de base
apt-get install -y \
    linux-image-generic linux-headers-generic \
    grub-efi-amd64 grub-efi-amd64-bin shim-signed efibootmgr \
    sudo policykit-1 network-manager \
    xfce4 xfce4-goodies lightdm lightdm-gtk-greeter \
    xfce4-terminal thunar \
    xorg xserver-xorg xinit fonts-noto fonts-liberation \
    papirus-icon-theme pulseaudio pavucontrol alsa-utils \
    wget curl zenity htop neofetch bash-completion nano vim \
    xdg-utils xdg-user-dirs gvfs gvfs-backends udisks2 \
    python3-pil imagemagick pciutils flatpak

# Gaming
if [ "$OPT_GAMING" = "true" ]; then
    apt-get install -y \
        gamemode mangohud \
        mesa-vulkan-drivers mesa-va-drivers mesa-vdpau-drivers \
        libvulkan1 vulkan-tools libgl1-mesa-dri \
        wine wine64 wine32:i386 libwine libwine:i386 fonts-wine \
        libvulkan1:i386 libgl1-mesa-dri:i386 \
        winetricks lutris
fi

# GPU universal
if [ "$OPT_GPU" = "true" ]; then
    apt-get install -y ubuntu-drivers-common linux-firmware
fi

# Kernel Liquorix (optionnel)
if wget -q --spider 'https://liquorix.net/liquorix-keyring.gpg' 2>/dev/null; then
    wget -qO /tmp/liq.gpg 'https://liquorix.net/liquorix-keyring.gpg'
    install -D -m644 /tmp/liq.gpg /usr/share/keyrings/liquorix-keyring.gpg
    rm -f /tmp/liq.gpg
    . /etc/os-release
    echo "deb [signed-by=/usr/share/keyrings/liquorix-keyring.gpg] https://liquorix.net/debian ${VERSION_CODENAME} main" \
        > /etc/apt/sources.list.d/liquorix.list
    apt-get update -qq
    apt-get install -y linux-image-liquorix-amd64 linux-headers-liquorix-amd64 2>/dev/null \
        && echo 'Kernel Liquorix installé !' \
        || echo 'Liquorix indisponible — kernel Ubuntu conservé'
fi

echo ">>> Paquets OK"
CHROOT_SCRIPT

# ═══════════════════════════════════════════════════════════════════════════════
log_step "6/8 — Configuration système MineOS"
# ═══════════════════════════════════════════════════════════════════════════════

# Copier les scripts de config depuis le répertoire source (monté en live)
SCRIPTS_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
if [ -f "$SCRIPTS_DIR/configure-chroot.sh" ]; then
    cp "$SCRIPTS_DIR/configure-chroot.sh" "$MOUNT/tmp/configure-chroot.sh"
    chroot "$MOUNT" bash /tmp/configure-chroot.sh / "installed"
    rm -f "$MOUNT/tmp/configure-chroot.sh"
else
    warn "configure-chroot.sh introuvable — config minimale appliquée"
    # Config minimale
    echo "mineos" > "$MOUNT/etc/hostname"
    mkdir -p "$MOUNT/etc/lightdm"
    cat > "$MOUNT/etc/lightdm/lightdm.conf" << 'LDM'
[Seat:*]
autologin-user=user
autologin-user-timeout=0
greeter-session=lightdm-gtk-greeter
user-session=xfce
LDM
fi

# Créer l'utilisateur "user"
chroot "$MOUNT" /bin/bash << 'USERADD'
useradd -m -s /bin/bash -G sudo,audio,video,plugdev,netdev user 2>/dev/null || true
echo "user:mineos" | chpasswd
echo "user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/mineos-user
USERADD

# Copier les configs skeleton vers l'utilisateur
chroot "$MOUNT" /bin/bash << 'SKEL_COPY'
if [ -d /etc/skel ]; then
    cp -rn /etc/skel/. /home/user/ 2>/dev/null || true
    chown -R user:user /home/user/
fi
SKEL_COPY

# ═══════════════════════════════════════════════════════════════════════════════
log_step "7/8 — GRUB EFI"
# ═══════════════════════════════════════════════════════════════════════════════
chroot "$MOUNT" /bin/bash -s "$TARGET" << 'GRUBINSTALL'
TARGET="$1"
export DEBIAN_FRONTEND=noninteractive

cat > /etc/default/grub << 'GRUB_DEFAULTS'
GRUB_DEFAULT=0
GRUB_TIMEOUT=8
GRUB_TIMEOUT_STYLE=menu
GRUB_DISTRIBUTOR="MineOS Gaming"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
GRUB_TERMINAL_OUTPUT="gfxterm"
GRUB_GFXMODE="1920x1080,1280x720,auto"
GRUB_GFXPAYLOAD_LINUX="keep"
GRUB_DISABLE_OS_PROBER=false
GRUB_DEFAULTS

# Entrées GRUB personnalisées MineOS
cat > /etc/grub.d/40_custom << 'CUSTOM'
#!/bin/sh
exec tail -n +4 $0
# MineOS Gaming custom entries
CUSTOM

grub-install --target=x86_64-efi --efi-directory=/boot/efi \
    --bootloader-id="MineOS Gaming" \
    --recheck 2>&1 || true
update-grub 2>&1 || grub-mkconfig -o /boot/grub/grub.cfg 2>&1
echo ">>> GRUB EFI installé"
GRUBINSTALL

# ═══════════════════════════════════════════════════════════════════════════════
log_step "8/8 — Auto-update (si activé)"
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$OPT_UPDATE" = "true" ]; then
    # Copier le script de mise à jour
    UPDATER_DIR="$(cd "$(dirname "$0")/.." && pwd)/updater"
    if [ -f "$UPDATER_DIR/MineOS-Update.sh" ]; then
        cp "$UPDATER_DIR/MineOS-Update.sh" "$MOUNT/usr/local/bin/MineOS-Update"
        chmod +x "$MOUNT/usr/local/bin/MineOS-Update"
    fi

    # Timer systemd : vérification hebdomadaire
    cat > "$MOUNT/etc/systemd/system/mineos-update.service" << 'SVC'
[Unit]
Description=MineOS Gaming Update Check
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=user
ExecStart=/usr/local/bin/MineOS-Update --check
StandardOutput=journal
SVC

    cat > "$MOUNT/etc/systemd/system/mineos-update.timer" << 'TIMER'
[Unit]
Description=MineOS Update Check — hebdomadaire

[Timer]
OnBootSec=5min
OnUnitActiveSec=7d
Persistent=true

[Install]
WantedBy=timers.target
TIMER

    chroot "$MOUNT" systemctl enable mineos-update.timer 2>/dev/null || true
    log "  Vérification auto des mises à jour activée (hebdomadaire)"
fi

# ── Nettoyage ────────────────────────────────────────────────────────────────
chroot "$MOUNT" apt-get clean 2>/dev/null || true
rm -f "$MOUNT/etc/resolv.conf"
cat > "$MOUNT/etc/resolv.conf" << 'DNS'
nameserver 1.1.1.1
nameserver 8.8.8.8
DNS

# Démonter
for MP in dev/pts dev proc sys; do
    umount "$MOUNT/$MP" 2>/dev/null || true
done
umount "$MOUNT/boot/efi" 2>/dev/null || true
umount "$MOUNT"           2>/dev/null || true

# Écrire le fichier d'état pour l'interface
cat > /tmp/mineos-install-done.json << DONE
{
  "status":  "success",
  "disk":    "$TARGET",
  "mode":    "$MODE",
  "gaming":  "$OPT_GAMING",
  "gpu":     "$OPT_GPU",
  "update":  "$OPT_UPDATE"
}
DONE

echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║  ✅  MineOS Gaming — INSTALLATION RÉUSSIE !           ║"
echo "╠═══════════════════════════════════════════════════════╣"
printf "║  Disque : %-45s ║\n" "$TARGET"
printf "║  Mode   : %-45s ║\n" "$MODE"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "  Retirez la clé USB et redémarrez l'ordinateur."
echo "  MineOS Gaming démarrera automatiquement sur $TARGET"
echo ""
