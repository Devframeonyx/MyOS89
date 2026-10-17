#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
#  MineOS Gaming Edition v13 — Build ISO (approche chroot direct, sans live-build)
#
#  POURQUOI CETTE APPROCHE :
#    live-build (v1→v12) plante toujours au même endroit sur GitHub Actions :
#    lb_chroot_hacks cherche chroot/boot/initrd.img-* qui n'existe jamais
#    correctement car update-initramfs est "deferred" dans un chroot Debian/Ubuntu.
#
#  NOUVELLE MÉTHODE (identique à Linux Mint / Pop!_OS / Zorin OS) :
#    1. Télécharger l'ISO Ubuntu officielle (mini/server → on contrôle tout)
#    2. Extraire le squashfs existant
#    3. Entrer en chroot → installer nos paquets + configs
#    4. Reconstruire squashfs → reconstruire l'ISO avec xorriso
#    Plus de live-build, plus de lb_chroot_hacks, plus de bug initrd.
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

VERSION="${1:-1.0.0}"
WORK_DIR="/opt/mineos-work"
OUT_DIR="/opt/mineos-output"
ISO_URL="https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso"
ISO_CACHE="/opt/mineos-cache/ubuntu-22.04-server.iso"

log()  { echo -e "\n\033[1;32m[MineOS v${VERSION}]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
die()  { echo -e "\033[1;31m[FATAL]\033[0m $*" >&2; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
log "0/10 — Préparation des dossiers"
# ─────────────────────────────────────────────────────────────────────────────
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"/{iso-orig,iso-new,squashfs-root,efi}
mkdir -p "$OUT_DIR"
mkdir -p "$(dirname "$ISO_CACHE")"

# ─────────────────────────────────────────────────────────────────────────────
log "1/10 — Téléchargement ISO Ubuntu 22.04 LTS"
# ─────────────────────────────────────────────────────────────────────────────
if [ ! -f "$ISO_CACHE" ]; then
    log "  Téléchargement depuis Ubuntu CDN..."
    wget -q --show-progress -O "$ISO_CACHE" "$ISO_URL" \
        || die "Échec téléchargement ISO Ubuntu"
else
    log "  ISO Ubuntu déjà en cache : $ISO_CACHE"
fi

# ─────────────────────────────────────────────────────────────────────────────
log "2/10 — Montage ISO source + extraction squashfs"
# ─────────────────────────────────────────────────────────────────────────────
MOUNT_ISO="$WORK_DIR/iso-mount"
mkdir -p "$MOUNT_ISO"
mount -o loop,ro "$ISO_CACHE" "$MOUNT_ISO"

# Détecter le chemin du squashfs (varie selon la version/variante Ubuntu)
log "  Détection du squashfs dans l'ISO..."
SQUASHFS_PATH=""
for CANDIDATE in \
    "casper/filesystem.squashfs" \
    "casper/ubuntu-server-minimal.squashfs" \
    "casper/minimal.squashfs" \
    "live/filesystem.squashfs" \
    "install/filesystem.squashfs"; do
    if [ -f "$MOUNT_ISO/$CANDIDATE" ]; then
        SQUASHFS_PATH="$CANDIDATE"
        log "  squashfs trouvé : $CANDIDATE"
        break
    fi
done

if [ -z "$SQUASHFS_PATH" ]; then
    # Recherche exhaustive en fallback
    SQUASHFS_FOUND=$(find "$MOUNT_ISO" -name "*.squashfs" 2>/dev/null | head -1)
    if [ -n "$SQUASHFS_FOUND" ]; then
        SQUASHFS_PATH="${SQUASHFS_FOUND#$MOUNT_ISO/}"
        log "  squashfs détecté (fallback) : $SQUASHFS_PATH"
    else
        log "  Contenu de l'ISO :"
        find "$MOUNT_ISO" -maxdepth 3 | head -40
        die "Aucun fichier .squashfs trouvé dans l'ISO"
    fi
fi

# Copier le contenu de l'ISO (boot, EFI, etc.) en excluant le squashfs source
rsync -a --exclude="$SQUASHFS_PATH" "$MOUNT_ISO/" "$WORK_DIR/iso-new/"

# Extraire le squashfs Ubuntu dans notre chroot
log "  Extraction squashfs Ubuntu (peut prendre 5-10 min)..."
unsquashfs -f -d "$WORK_DIR/squashfs-root" "$MOUNT_ISO/$SQUASHFS_PATH"

umount "$MOUNT_ISO"
rmdir  "$MOUNT_ISO"

# ─────────────────────────────────────────────────────────────────────────────
log "3/10 — Préparation chroot (mount proc/sys/dev)"
# ─────────────────────────────────────────────────────────────────────────────
CHROOT="$WORK_DIR/squashfs-root"

# Monter les systèmes de fichiers virtuels
mount --bind /proc     "$CHROOT/proc"
mount --bind /sys      "$CHROOT/sys"
mount --bind /dev      "$CHROOT/dev"
mount --bind /dev/pts  "$CHROOT/dev/pts"
mount --bind /run      "$CHROOT/run"

# Résolution DNS dans le chroot
cp /etc/resolv.conf "$CHROOT/etc/resolv.conf"

# Éviter que les daemons démarrent pendant le build
cat > "$CHROOT/usr/sbin/policy-rc.d" << 'POLICY'
#!/bin/sh
exit 101
POLICY
chmod +x "$CHROOT/usr/sbin/policy-rc.d"

# Wrapper pour éviter que update-initramfs soit appelé sans /boot réel
cat > "$CHROOT/usr/local/bin/update-initramfs" << 'UINIT'
#!/bin/bash
# Stub — l'initrd est généré par rebuild-initramfs.sh à la fin du chroot
echo "[stub] update-initramfs appelé avec : $*"
exit 0
UINIT
chmod +x "$CHROOT/usr/local/bin/update-initramfs"

# ─────────────────────────────────────────────────────────────────────────────
log "4/10 — Installation des paquets dans le chroot"
# ─────────────────────────────────────────────────────────────────────────────
chroot "$CHROOT" /bin/bash -c "
set -e
export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

# ── APT repos complets ──────────────────────────────────────────────────
cat > /etc/apt/sources.list << 'SOURCES'
deb http://archive.ubuntu.com/ubuntu jammy main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu jammy-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu jammy-security main restricted universe multiverse
SOURCES

dpkg --add-architecture i386
apt-get update -qq

# ── Base système ─────────────────────────────────────────────────────────
apt-get install -y \
    systemd systemd-sysv udev dbus policykit-1 sudo \
    wget curl ca-certificates gnupg apt-transport-https \
    software-properties-common locales tzdata rsync \
    pciutils lsb-release ubuntu-keyring

# ── Locale FR ────────────────────────────────────────────────────────────
sed -i 's/# fr_FR.UTF-8/fr_FR.UTF-8/' /etc/locale.gen
locale-gen fr_FR.UTF-8
update-locale LANG=fr_FR.UTF-8 LC_ALL=fr_FR.UTF-8

# ── XFCE + affichage ─────────────────────────────────────────────────────
apt-get install -y \
    xfce4 xfce4-goodies xfce4-panel xfce4-session xfce4-settings \
    xfce4-terminal xfce4-whiskermenu-plugin xfce4-notifyd \
    xfce4-screenshooter xfce4-taskmanager xfce4-power-manager \
    xfce4-clipman-plugin xfce4-pulseaudio-plugin \
    thunar thunar-archive-plugin thunar-volman \
    gvfs gvfs-backends udisks2 \
    lightdm lightdm-gtk-greeter \
    xorg xserver-xorg xinit x11-xserver-utils x11-utils \
    xdg-utils xdg-user-dirs \
    network-manager network-manager-gnome \
    pulseaudio pavucontrol alsa-utils \
    fonts-noto fonts-noto-color-emoji fonts-liberation \
    papirus-icon-theme gtk2-engines-murrine gtk2-engines-pixbuf

# ── Applications ─────────────────────────────────────────────────────────
apt-get install -y \
    mousepad geany vlc gimp file-roller zip unzip p7zip-full \
    htop neofetch bash-completion nano vim \
    zenity scrot nitrogen picom rofi dunst \
    python3-pil imagemagick

# ── Gaming ───────────────────────────────────────────────────────────────
apt-get install -y \
    gamemode mangohud \
    mesa-vulkan-drivers mesa-va-drivers mesa-vdpau-drivers \
    libvulkan1 vulkan-tools libgl1-mesa-dri \
    lutris \
    linux-firmware

# ── Wine + DXVK support ──────────────────────────────────────────────────
apt-get install -y \
    wine wine64 wine32:i386 \
    libwine libwine:i386 fonts-wine \
    libvulkan1:i386 libgl1-mesa-dri:i386 \
    winetricks playonlinux

# ── Flatpak ──────────────────────────────────────────────────────────────
apt-get install -y flatpak gnome-software-plugin-flatpak

# ── GPU drivers — tous installés (détection au démarrage) ────────────────
apt-get install -y ubuntu-drivers-common

# ── Boot / live ──────────────────────────────────────────────────────────
apt-get install -y \
    casper lupin-casper \
    grub-efi-amd64 grub-efi-amd64-bin grub-pc-bin \
    shim-signed mtools syslinux syslinux-common isolinux efibootmgr

# Kernel générique Ubuntu (PAS de live-build derrière)
apt-get install -y linux-image-generic linux-headers-generic

echo '>>> Tous les paquets installés avec succès'
"

# ─────────────────────────────────────────────────────────────────────────────
log "5/10 — Génération RÉELLE de l'initramfs (dans le chroot)"
# ─────────────────────────────────────────────────────────────────────────────
# Supprimer le stub, laisser le vrai update-initramfs
rm -f "$CHROOT/usr/local/bin/update-initramfs"

KVER=$(ls "$CHROOT/lib/modules/" 2>/dev/null | sort -V | tail -1)
[ -z "$KVER" ] && die "Aucun kernel trouvé dans $CHROOT/lib/modules/"
log "  Kernel détecté : $KVER"

# Générer l'initramfs directement (chroot, sans live-build entre les deux)
chroot "$CHROOT" /bin/bash -c "
export DEBIAN_FRONTEND=noninteractive
dpkg --configure -a 2>/dev/null || true
mkinitramfs -v -o /boot/initrd.img-${KVER} ${KVER}
ls -lh /boot/initrd.img-${KVER}
echo '>>> initramfs généré : OK'
"

# Vérifier que l'initrd existe vraiment
[ -f "$CHROOT/boot/initrd.img-${KVER}" ] \
    || die "initrd.img-${KVER} absent après mkinitramfs — build stoppé"

log "  initrd.img-${KVER} : OK ($(du -sh "$CHROOT/boot/initrd.img-${KVER}" | cut -f1))"

# ─────────────────────────────────────────────────────────────────────────────
log "6/10 — Configuration système MineOS"
# ─────────────────────────────────────────────────────────────────────────────
# -- Injecter tous les scripts et configs via heredoc --
# Génération dans un script séparé pour lisibilité
bash "$(dirname "$0")/configure-chroot.sh" "$CHROOT" "$VERSION"

# ─────────────────────────────────────────────────────────────────────────────
log "7/10 — Kernel Liquorix (optionnel, non bloquant)"
# ─────────────────────────────────────────────────────────────────────────────
chroot "$CHROOT" /bin/bash -c "
set -e
export DEBIAN_FRONTEND=noninteractive
if wget -q --spider 'https://liquorix.net/liquorix-keyring.gpg' 2>/dev/null; then
    wget -qO /tmp/liq.gpg 'https://liquorix.net/liquorix-keyring.gpg'
    install -D -m 644 /tmp/liq.gpg /usr/share/keyrings/liquorix-keyring.gpg
    rm -f /tmp/liq.gpg
    . /etc/os-release
    echo \"deb [signed-by=/usr/share/keyrings/liquorix-keyring.gpg] https://liquorix.net/debian \${VERSION_CODENAME} main\" \
        > /etc/apt/sources.list.d/liquorix.list
    apt-get update -qq
    apt-get install -y linux-image-liquorix-amd64 linux-headers-liquorix-amd64 2>/dev/null \
        && echo '>>> Kernel Liquorix installé !' \
        || echo '>>> Liquorix indisponible — kernel Ubuntu générique conservé'
else
    echo '>>> liquorix.net inaccessible — kernel Ubuntu générique conservé'
fi
" || warn "Liquorix échec non bloquant — kernel Ubuntu conservé"

# Regénérer l'initrd si Liquorix a installé un nouveau kernel
NEW_KVER=$(ls "$CHROOT/lib/modules/" 2>/dev/null | sort -V | tail -1)
if [ "$NEW_KVER" != "$KVER" ]; then
    log "  Nouveau kernel détecté : $NEW_KVER — regénération initramfs"
    chroot "$CHROOT" /bin/bash -c "
        mkinitramfs -o /boot/initrd.img-${NEW_KVER} ${NEW_KVER}
    "
    KVER="$NEW_KVER"
fi

# ─────────────────────────────────────────────────────────────────────────────
log "8/10 — Construction du nouveau squashfs + layout ISO"
# ─────────────────────────────────────────────────────────────────────────────

# Nettoyage chroot avant squash
rm -f "$CHROOT/usr/sbin/policy-rc.d"
rm -f "$CHROOT/etc/resolv.conf"
chroot "$CHROOT" apt-get clean
rm -rf "$CHROOT/tmp/"* "$CHROOT/var/cache/apt/archives/"*.deb 2>/dev/null || true

# Démonter les systèmes de fichiers virtuels
for MP in dev/pts dev proc sys run; do
    umount "$CHROOT/$MP" 2>/dev/null || true
done

# Copier kernel + initrd dans l'ISO
mkdir -p "$WORK_DIR/iso-new/casper"
cp "$CHROOT/boot/vmlinuz-${KVER}"    "$WORK_DIR/iso-new/casper/vmlinuz"
cp "$CHROOT/boot/initrd.img-${KVER}" "$WORK_DIR/iso-new/casper/initrd"

# Rebuild squashfs (compression xz maximale)
log "  Compression squashfs xz (peut prendre 15-30 min)..."
mksquashfs "$CHROOT" "$WORK_DIR/iso-new/casper/filesystem.squashfs" \
    -comp xz -Xbcj x86 -b 1M -noappend \
    -e boot -e proc -e sys -e dev -e run \
    || die "mksquashfs a échoué"

# Taille du système de fichiers
du -sx --block-size=1 "$CHROOT" | cut -f1 \
    > "$WORK_DIR/iso-new/casper/filesystem.size"

# Manifeste des paquets installés
chroot "$CHROOT" dpkg-query -W --showformat='${Package} ${Version}\n' \
    > "$WORK_DIR/iso-new/casper/filesystem.manifest" 2>/dev/null || true

# ─────────────────────────────────────────────────────────────────────────────
log "9/10 — GRUB EFI + BIOS + génération ISO finale avec xorriso"
# ─────────────────────────────────────────────────────────────────────────────
bash "$(dirname "$0")/build-iso.sh" "$WORK_DIR" "$OUT_DIR" "$VERSION" "$KVER"

# ─────────────────────────────────────────────────────────────────────────────
log "10/10 — SHA256 + rapport final"
# ─────────────────────────────────────────────────────────────────────────────
ISO_OUT="$OUT_DIR/MineOS-Gaming-${VERSION}-x86_64.iso"
sha256sum "$ISO_OUT" > "$OUT_DIR/SHA256SUMS"
SIZE=$(du -sh "$ISO_OUT" | cut -f1)

echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║  ⛏  MineOS Gaming v${VERSION} — BUILD RÉUSSI !          ║"
echo "╠═══════════════════════════════════════════════════════╣"
printf "║  ISO  : %-47s ║\n" "$(basename "$ISO_OUT")"
printf "║  Taille : %-45s ║\n" "$SIZE"
printf "║  Kernel : %-45s ║\n" "$KVER"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "Flash USB :"
echo "  sudo dd if=$ISO_OUT of=/dev/sdX bs=4M status=progress oflag=sync"
