#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
#  MineOS v13 — Construction de l'ISO finale
#  xorriso + grub EFI/BIOS — sans live-build
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

WORK_DIR="$1"
OUT_DIR="$2"
VERSION="$3"
KVER="$4"

ISO_DIR="$WORK_DIR/iso-new"
EFI_DIR="$WORK_DIR/efi-build"
ISO_OUT="$OUT_DIR/MineOS-Gaming-${VERSION}-x86_64.iso"

log()  { echo -e "\n  \033[1;35m[iso]\033[0m $*"; }
die()  { echo -e "\033[1;31m[FATAL]\033[0m $*" >&2; exit 1; }

mkdir -p "$ISO_DIR"/{boot/grub,EFI/boot}
mkdir -p "$EFI_DIR"

# ─── GRUB config ───────────────────────────────────────────────────────────
log "Config GRUB"
cat > "$ISO_DIR/boot/grub/grub.cfg" << GRUBEOF
set default=0
set timeout=8
set gfxmode=1920x1080,1280x720,auto
set gfxpayload=keep
insmod all_video
insmod gfxterm
insmod png
insmod part_gpt
insmod part_msdos
insmod fat
insmod iso9660
terminal_output gfxterm

# Couleurs MineOS
set color_normal=white/black
set color_highlight=light-green/black

menuentry "⛏  MineOS Gaming (Live — démarrer sans installer)" --class ubuntu --class gnu-linux {
    linux  /casper/vmlinuz boot=live components quiet splash hostname=mineos username=user ---
    initrd /casper/initrd
}

menuentry "⛏  MineOS Gaming (mode sans échec — nomodeset)" --class ubuntu {
    linux  /casper/vmlinuz boot=live components nomodeset hostname=mineos username=user ---
    initrd /casper/initrd
}

menuentry "⛏  MineOS Gaming (RAM — tout en mémoire vive)" --class ubuntu {
    linux  /casper/vmlinuz boot=live components toram quiet splash hostname=mineos username=user ---
    initrd /casper/initrd
}

menuentry "Démarrer depuis le disque dur" --class hdd {
    chainloader +1
}
GRUBEOF

# ─── GRUB EFI image (bootx64.efi) ──────────────────────────────────────────
log "Création image GRUB EFI"
# Crée une image EFI standalone avec tous les modules nécessaires
grub-mkimage \
    --format=x86_64-efi \
    --output="$EFI_DIR/bootx64.efi" \
    --prefix="(cd)/boot/grub" \
    all_video boot cat chain configfile echo efifwsetup efinet ext2 \
    fat font gfxmenu gfxterm gfxterm_background gzio halt hfsplus \
    iso9660 jpeg keylayouts linuxefi loadenv loopback mdraid09 \
    mdraid1x memdisk minicmd normal part_apple part_gpt part_msdos \
    png probe reboot search search_fs_file search_fs_uuid search_label \
    sleep squash4 test tpm true video_bochs video_cirrus \
    2>/dev/null || {
    # Fallback si certains modules manquent
    grub-mkimage \
        --format=x86_64-efi \
        --output="$EFI_DIR/bootx64.efi" \
        --prefix="(cd)/boot/grub" \
        all_video boot cat chain configfile echo ext2 fat font \
        gfxmenu gfxterm iso9660 jpeg linuxefi loadenv loopback \
        memdisk minicmd normal part_gpt part_msdos png reboot \
        search search_fs_uuid sleep test true
}

cp "$EFI_DIR/bootx64.efi" "$ISO_DIR/EFI/boot/bootx64.efi"

# Créer l'image EFI (FAT) pour xorriso
EFI_IMG="$WORK_DIR/efi.img"
dd if=/dev/zero of="$EFI_IMG" bs=1M count=10 2>/dev/null
mkfs.vfat -F12 "$EFI_IMG" >/dev/null
mmd -i "$EFI_IMG"  ::EFI ::EFI/BOOT
mcopy -i "$EFI_IMG" "$EFI_DIR/bootx64.efi" ::EFI/BOOT/BOOTX64.EFI

log "EFI image : $EFI_IMG ($(du -sh "$EFI_IMG" | cut -f1))"

# ─── GRUB BIOS (eltorito) ───────────────────────────────────────────────────
log "GRUB BIOS (eltorito)"
mkdir -p "$ISO_DIR/boot/grub/i386-pc"

# Copier les fichiers GRUB BIOS
for f in /usr/lib/grub/i386-pc/boot.img /usr/lib/grub/i386-pc/core.img; do
    [ -f "$f" ] && cp "$f" "$ISO_DIR/boot/grub/i386-pc/"
done

# Générer l'image de démarrage BIOS
grub-mkstandalone \
    --format=i386-pc \
    --output="$ISO_DIR/boot/grub/bios.img" \
    --modules="linux16 normal iso9660 biosdisk memdisk search tar ls" \
    "boot/grub/grub.cfg=$ISO_DIR/boot/grub/grub.cfg" \
    2>/dev/null || true

# Fallback : créer bios.img depuis les fichiers GRUB système
if [ ! -f "$ISO_DIR/boot/grub/bios.img" ]; then
    GRUB_DIR=""
    for d in /usr/lib/grub/i386-pc /usr/share/grub; do
        [ -f "$d/cdboot.img" ] && GRUB_DIR="$d" && break
    done
    if [ -n "$GRUB_DIR" ]; then
        cat "$GRUB_DIR/cdboot.img" "$GRUB_DIR/core.img" \
            > "$ISO_DIR/boot/grub/bios.img" 2>/dev/null \
            || cp "$GRUB_DIR/core.img" "$ISO_DIR/boot/grub/bios.img"
    fi
fi

# ─── md5sum.txt ─────────────────────────────────────────────────────────────
log "Checksums"
(cd "$ISO_DIR" && find . -type f ! -name 'md5sum.txt' -print0 \
    | xargs -0 md5sum > md5sum.txt 2>/dev/null)

# ─── xorriso : construction de l'ISO finale ─────────────────────────────────
log "xorriso — génération ISO finale"
mkdir -p "$OUT_DIR"

xorriso -as mkisofs \
    -iso-level 3 \
    -r -J \
    -joliet-long \
    -full-iso9660-filenames \
    -volid "MINEOS_${VERSION}" \
    -appid "MineOS Gaming ${VERSION}" \
    -publisher "MineOS Project" \
    -preparer "MineOS Build System" \
    \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    \
    -eltorito-boot boot/grub/bios.img \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    --grub2-boot-info \
    --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
    \
    -eltorito-catalog boot/grub/boot.cat \
    \
    -eltorito-alt-boot \
    -e /efi.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    \
    -o "$ISO_OUT" \
    "$ISO_DIR" \
    "$EFI_IMG" \
    2>&1 | tail -20 \
    || {
        # Fallback xorriso simplifié si certaines options non supportées
        log "Fallback xorriso simplifié..."
        xorriso -as mkisofs \
            -iso-level 3 -r -J \
            -volid "MINEOS_${VERSION}" \
            -appid "MineOS Gaming ${VERSION}" \
            -publisher "MineOS Project" \
            -eltorito-boot boot/grub/bios.img \
            -no-emul-boot -boot-load-size 4 -boot-info-table \
            -eltorito-catalog boot/grub/boot.cat \
            -eltorito-alt-boot \
            -e /efi.img \
            -no-emul-boot \
            -o "$ISO_OUT" \
            "$ISO_DIR" "$EFI_IMG" 2>&1 | tail -10
    }

[ -f "$ISO_OUT" ] || die "ISO non créée par xorriso"

# Rendre l'ISO USB-bootable (hybride MBR)
if command -v isohybrid &>/dev/null; then
    isohybrid --uefi "$ISO_OUT" 2>/dev/null || true
fi

log "ISO générée : $ISO_OUT ($(du -sh "$ISO_OUT" | cut -f1))"
