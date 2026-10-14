#!/bin/bash
# ============================================================
#  MineOS — Installation des paquets (build local)
# ============================================================
set -euo pipefail

echo "Vérification des dépendances de build..."

DEPS=(live-build debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools isolinux syslinux-common rsync wget curl)
MISSING=()

for dep in "${DEPS[@]}"; do
  if ! dpkg -l "$dep" &>/dev/null; then
    MISSING+=("$dep")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "Installation des dépendances manquantes : ${MISSING[*]}"
  sudo apt-get update -qq
  sudo apt-get install -y "${MISSING[@]}"
else
  echo "Toutes les dépendances sont déjà installées."
fi

echo "Prêt à builder ! Lance: sudo ./scripts/build.sh"
