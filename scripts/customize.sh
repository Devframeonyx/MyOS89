#!/bin/bash
# ============================================================
#  MineOS — Customisation post-install
#  Utilisé pour installer sur disque (optionnel)
# ============================================================
set -euo pipefail

echo ">>> Customisation MineOS..."

# Appliquer le thème GTK
gsettings set org.gnome.desktop.interface gtk-theme "MineOS-Dark" 2>/dev/null || true
gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark" 2>/dev/null || true

# Configurer Wine de base
WINEPREFIX="$HOME/.wine"
if [ ! -d "$WINEPREFIX" ]; then
  WINEDEBUG=-all wineboot --init 2>/dev/null || true
fi

# Configurer les associations de fichiers
xdg-mime default wine-exe.desktop application/x-ms-dos-executable
xdg-mime default wine-exe.desktop application/x-msi

echo ">>> Customisation terminée"
