#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║        ⛏  MineOS Update Watcher — Script d'installation                 ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
#
#  Lance ce script UNE SEULE FOIS après l'installation de MineOS Gaming.
#  Il installe le daemon qui surveille les patchs automatiquement.
#
#  Usage : sudo bash install-watcher.sh
# ═══════════════════════════════════════════════════════════════════════════════

set -e

GRN='\033[1;32m'; CYN='\033[1;36m'; YLW='\033[1;33m'
RED='\033[1;31m'; RST='\033[0m'; BLD='\033[1m'

ok()  { echo -e "${GRN}  ✅ $*${RST}"; }
err() { echo -e "${RED}  ❌ $*${RST}"; exit 1; }
log() { echo -e "${CYN}  ▶ $*${RST}"; }

if [ "$EUID" -ne 0 ]; then
    err "Ce script doit être lancé en root : sudo bash install-watcher.sh"
fi

echo ""
echo -e "${GRN}${BLD}  ╔═══════════════════════════════════════════════════════╗"
echo "  ║      ⛏  MineOS Update Watcher — Installation          ║"
echo -e "  ╚═══════════════════════════════════════════════════════╝${RST}"
echo ""

# 1. Dépendances
log "Installation de inotify-tools..."
apt-get install -y -qq inotify-tools
ok "inotify-tools prêt"

# 2. Dossier de surveillance
log "Création de /opt/mineos-updates/ (dossier de dépôt des patchs)..."
mkdir -p /opt/mineos-updates
chmod 755 /opt/mineos-updates
ok "Dossier /opt/mineos-updates/ créé"

# 3. Dossier historique des patchs appliqués
mkdir -p /var/lib/mineos-updates/applied
ok "Historique des patchs : /var/lib/mineos-updates/applied/"

# 4. Copie du watcher
log "Installation du watcher dans /usr/local/bin/..."
cp "$(dirname "$0")/mineos-watcher.sh" /usr/local/bin/mineos-watcher
chmod +x /usr/local/bin/mineos-watcher
ok "Watcher installé : /usr/local/bin/mineos-watcher"

# 5. Service systemd
log "Installation du service systemd..."
cp "$(dirname "$0")/mineos-update-watcher.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable mineos-update-watcher
systemctl start  mineos-update-watcher
ok "Service mineos-update-watcher activé et démarré"

# 6. Vérification
sleep 1
STATUS=$(systemctl is-active mineos-update-watcher)
if [ "$STATUS" = "active" ]; then
    ok "Service actif ✅"
else
    err "Le service ne s'est pas démarré correctement. Vérifie : journalctl -u mineos-update-watcher"
fi

echo ""
echo -e "${GRN}${BLD}  ╔═══════════════════════════════════════════════════════╗"
echo "  ║          ✅  Watcher installé avec succès !            ║"
echo -e "  ╚═══════════════════════════════════════════════════════╝${RST}"
echo ""
echo -e "  ${CYN}Comment déposer un patch :${RST}"
echo "    Copie un fichier .MineOSUp dans /opt/mineos-updates/"
echo "    → Il sera exécuté automatiquement, puis supprimé."
echo ""
echo -e "  ${CYN}Suivre les logs :${RST}"
echo "    tail -f /var/log/mineos-watcher.log"
echo "    journalctl -u mineos-update-watcher -f"
echo ""
