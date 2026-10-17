#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
#  MineOS Gaming Edition — Installateur
#  Lance l'interface graphique Web dans le navigateur,
#  puis exécute les commandes réelles selon les choix
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "$0")" && pwd)"
HTML_FILE="$INSTALLER_DIR/mineos-installer.html"
LOG_FILE="/tmp/mineos-install.log"
STATE_FILE="/tmp/mineos-install-state.json"

RED='\033[1;31m'; GRN='\033[1;32m'; CYN='\033[1;36m'; YLW='\033[1;33m'; RST='\033[0m'
log()  { echo -e "${GRN}[MineOS]${RST} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YLW}[WARN]${RST}  $*" | tee -a "$LOG_FILE"; }
die()  { echo -e "${RED}[FATAL]${RST} $*" | tee -a "$LOG_FILE"; exit 1; }

# ── Vérification root ────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    die "L'installateur doit être lancé en root : sudo bash mineos-install.sh"
fi

# ── Détecter les vrais disques et injecter dans le HTML ─────────────────────
log "Détection des disques..."
DISK_JSON="["
first=true
while IFS= read -r line; do
    NAME=$(echo "$line" | awk '{print $1}')
    SIZE=$(echo "$line" | awk '{print $2}')
    MODEL=$(echo "$line" | awk '{for(i=3;i<=NF;i++) printf $i" "; print ""}' | sed 's/[[:space:]]*$//')
    [ -z "$MODEL" ] && MODEL="Disque"
    # Pourcentage utilisé (approximatif)
    USED=0
    if lsblk -no MOUNTPOINT "/dev/$NAME" 2>/dev/null | grep -q "/"; then
        USED=$(df "/dev/$NAME" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%' || echo 0)
    fi
    [ "$first" = true ] && first=false || DISK_JSON+=","
    DISK_JSON+="{\"id\":\"$NAME\",\"name\":\"/dev/$NAME\",\"desc\":\"$MODEL\",\"size\":\"$SIZE\",\"used\":$USED,\"icon\":\"💿\"}"
done < <(lsblk -dno NAME,SIZE,MODEL --output NAME,SIZE,MODEL 2>/dev/null \
    | grep -vE "^(loop|sr|fd)" | head -8)
DISK_JSON+="]"

# Injecter les vrais disques dans le HTML
TEMP_HTML="/tmp/mineos-installer-runtime.html"
sed "s|const DISKS = \[.*\];|const DISKS = $DISK_JSON;|" "$HTML_FILE" > "$TEMP_HTML" 2>/dev/null \
    || cp "$HTML_FILE" "$TEMP_HTML"

# ── Ouvrir l'interface dans le navigateur ────────────────────────────────────
log "Lancement de l'interface graphique..."
for BROWSER in xdg-open opera-gx chromium-browser firefox; do
    if command -v "$BROWSER" &>/dev/null; then
        "$BROWSER" "file://$TEMP_HTML" &>/dev/null &
        break
    fi
done

# ── Attendre le fichier d'état (écrit par le bouton "Installer") ─────────────
log "En attente de vos choix dans l'interface..."
echo ""
echo -e "${CYN}  ⛏ MineOS Installateur${RST}"
echo "  L'interface s'est ouverte dans votre navigateur."
echo "  Sélectionnez vos options puis cliquez sur '🚀 Installer MineOS'."
echo ""

# Boucle d'attente du fichier d'état JSON (écrit par le bouton Installer)
TIMEOUT=300
COUNT=0
while [ ! -f "$STATE_FILE" ] && [ $COUNT -lt $TIMEOUT ]; do
    sleep 1
    COUNT=$((COUNT+1))
done

if [ ! -f "$STATE_FILE" ]; then
    warn "Timeout — aucune sélection reçue après ${TIMEOUT}s."
    echo ""
    echo "Pour lancer l'installation manuellement, exécutez :"
    echo "  sudo bash $INSTALLER_DIR/install-manual.sh <disque> <mode>"
    echo "  Exemple : sudo bash $INSTALLER_DIR/install-manual.sh /dev/sda full"
    exit 0
fi

# ── Lire l'état ──────────────────────────────────────────────────────────────
TARGET_DISK=$(python3 -c "import json,sys; d=json.load(open('$STATE_FILE')); print(d.get('disk',''))" 2>/dev/null || echo "")
INSTALL_MODE=$(python3 -c "import json,sys; d=json.load(open('$STATE_FILE')); print(d.get('mode','full'))" 2>/dev/null || echo "full")
OPT_GAMING=$(python3 -c "import json,sys; d=json.load(open('$STATE_FILE')); print(d.get('opts',{}).get('gaming','true'))" 2>/dev/null || echo "true")
OPT_GPU=$(python3 -c "import json,sys; d=json.load(open('$STATE_FILE')); print(d.get('opts',{}).get('gpu','true'))" 2>/dev/null || echo "true")
OPT_UPDATE=$(python3 -c "import json,sys; d=json.load(open('$STATE_FILE')); print(d.get('opts',{}).get('autoupdate','true'))" 2>/dev/null || echo "true")

[ -z "$TARGET_DISK" ] && die "Aucun disque sélectionné."
[ ! -b "$TARGET_DISK" ] && die "Disque introuvable : $TARGET_DISK"

# ── Lancer l'installation réelle ─────────────────────────────────────────────
bash "$INSTALLER_DIR/install-core.sh" \
    "$TARGET_DISK" "$INSTALL_MODE" "$OPT_GAMING" "$OPT_GPU" "$OPT_UPDATE"
