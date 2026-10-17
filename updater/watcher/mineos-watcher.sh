#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║          ⛏  MineOS Gaming — Update Watcher (Auto-Patch System)          ║
# ║                                                                           ║
# ║  Surveille /opt/mineos-updates/ en permanence.                           ║
# ║  Quand un fichier .MineOSUp apparaît → l'exécute → le supprime.         ║
# ║  Comme Windows Update, mais en mieux.                                    ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
#
#  INSTALLATION :
#    sudo cp mineos-watcher.sh /usr/local/bin/mineos-watcher
#    sudo chmod +x /usr/local/bin/mineos-watcher
#    sudo cp mineos-update-watcher.service /etc/systemd/system/
#    sudo systemctl daemon-reload
#    sudo systemctl enable --now mineos-update-watcher
#
#  UTILISATION :
#    Dépose un fichier .MineOSUp dans /opt/mineos-updates/
#    → Il est détecté, exécuté, puis supprimé automatiquement.
#
# ═══════════════════════════════════════════════════════════════════════════════

# ── Config ────────────────────────────────────────────────────────────────────
WATCH_DIR="/opt/mineos-updates"          # Dossier à surveiller
LOG_FILE="/var/log/mineos-watcher.log"   # Log du watcher
LOCK_FILE="/tmp/mineos-watcher.lock"     # Evite les exécutions simultanées
REBOOT_FLAG="/tmp/mineos-needs-reboot"   # Signale qu'un reboot est requis

# ── Couleurs ──────────────────────────────────────────────────────────────────
GRN='\033[1;32m'; CYN='\033[1;36m'; YLW='\033[1;33m'
RED='\033[1;31m'; MAG='\033[1;35m'; RST='\033[0m'; BLD='\033[1m'

# ── Logging ───────────────────────────────────────────────────────────────────
log()    { echo -e "${GRN}[$(date '+%Y-%m-%d %H:%M:%S')] [WATCH]${RST} $*" | tee -a "$LOG_FILE"; }
log_ok() { echo -e "${GRN}  ✅ $*${RST}" | tee -a "$LOG_FILE"; }
log_err(){ echo -e "${RED}  ❌ $*${RST}" | tee -a "$LOG_FILE"; }
warn()   { echo -e "${YLW}  ⚠️  $*${RST}" | tee -a "$LOG_FILE"; }
section(){ echo -e "\n${CYN}${BLD}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}" | tee -a "$LOG_FILE"; }

# ── Initialisation ────────────────────────────────────────────────────────────
mkdir -p "$WATCH_DIR"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "⛏  MineOS Update Watcher démarré"
log "   Surveillance de : ${WATCH_DIR}"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Vérifier que inotifywait est installé
if ! command -v inotifywait &>/dev/null; then
    log_err "inotifywait non trouvé — installation..."
    apt-get install -y -qq inotify-tools 2>/dev/null
    if ! command -v inotifywait &>/dev/null; then
        log_err "Impossible d'installer inotify-tools. Abandon."
        exit 1
    fi
    log_ok "inotify-tools installé"
fi

# ── Fonction : Exécuter un patch .MineOSUp ───────────────────────────────────
apply_patch() {
    local PATCH_FILE="$1"
    local PATCH_NAME
    PATCH_NAME=$(basename "$PATCH_FILE")

    # Vérification du verrou (évite 2 patchs simultanés)
    if [ -f "$LOCK_FILE" ]; then
        warn "Un patch est déjà en cours d'application. $PATCH_NAME mis en attente 5s..."
        sleep 5
        # Réessayer une fois
        if [ -f "$LOCK_FILE" ]; then
            warn "$PATCH_NAME toujours en attente — repoussé."
            return 1
        fi
    fi

    touch "$LOCK_FILE"

    section "Patch détecté : $PATCH_NAME"
    log "Taille : $(du -sh "$PATCH_FILE" | cut -f1)"
    log "Hash SHA256 : $(sha256sum "$PATCH_FILE" | cut -d' ' -f1)"

    # ── Notification desktop (si session graphique active) ────────────────────
    local DISPLAY_USER
    DISPLAY_USER=$(who | grep -m1 '(:0)' | awk '{print $1}')
    if [ -n "$DISPLAY_USER" ]; then
        DBUS_ADDR=$(cat /proc/$(pgrep -u "$DISPLAY_USER" dbus-daemon | head -1)/environ 2>/dev/null \
                   | tr '\0' '\n' | grep DBUS_SESSION_BUS_ADDRESS | cut -d= -f2-)
        sudo -u "$DISPLAY_USER" \
            DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
            notify-send "⛏ MineOS Update" \
            "Application du patch : $PATCH_NAME" \
            --icon=software-update-available --urgency=normal 2>/dev/null || true
    fi

    # ── Sauvegarde du patch avant exécution ──────────────────────────────────
    local BACKUP_DIR="/var/lib/mineos-updates/applied"
    mkdir -p "$BACKUP_DIR"
    cp "$PATCH_FILE" "$BACKUP_DIR/${PATCH_NAME%.MineOSUp}_$(date +%Y%m%d_%H%M%S).MineOSUp.bak"

    # ── Exécution du patch ────────────────────────────────────────────────────
    log "▶ Exécution de $PATCH_NAME ..."
    chmod +x "$PATCH_FILE"

    local EXIT_CODE=0
    bash "$PATCH_FILE" 2>&1 | tee -a "$LOG_FILE" || EXIT_CODE=$?

    # ── Résultat ──────────────────────────────────────────────────────────────
    if [ "$EXIT_CODE" -eq 0 ]; then
        log_ok "$PATCH_NAME appliqué avec succès (exit 0)"

        # Notification succès
        if [ -n "$DISPLAY_USER" ]; then
            sudo -u "$DISPLAY_USER" \
                DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
                notify-send "⛏ MineOS Update" \
                "✅ Patch appliqué : $PATCH_NAME" \
                --icon=emblem-default --urgency=low 2>/dev/null || true
        fi

    elif [ "$EXIT_CODE" -eq 42 ]; then
        # Code de sortie spécial 42 = succès + reboot requis
        log_ok "$PATCH_NAME appliqué — REBOOT REQUIS"
        touch "$REBOOT_FLAG"
        echo "$PATCH_NAME" >> "$REBOOT_FLAG"

    else
        log_err "$PATCH_NAME a échoué (exit $EXIT_CODE)"
        warn "Le patch échoué est conservé dans $BACKUP_DIR pour diagnostic"

        if [ -n "$DISPLAY_USER" ]; then
            sudo -u "$DISPLAY_USER" \
                DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
                notify-send "⛏ MineOS Update" \
                "❌ Échec du patch : $PATCH_NAME\nVoir /var/log/mineos-watcher.log" \
                --icon=dialog-error --urgency=critical 2>/dev/null || true
        fi
    fi

    # ── Suppression du fichier .MineOSUp ─────────────────────────────────────
    rm -f "$PATCH_FILE"
    log "🗑️  $PATCH_NAME supprimé de $WATCH_DIR"

    rm -f "$LOCK_FILE"

    # ── Reboot automatique si requis ──────────────────────────────────────────
    if [ -f "$REBOOT_FLAG" ]; then
        log "🔄 Reboot dans 30 secondes (patch kernel/système)..."

        if [ -n "$DISPLAY_USER" ]; then
            sudo -u "$DISPLAY_USER" \
                DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
                notify-send "⛏ MineOS Update" \
                "🔄 Redémarrage dans 30 secondes pour finaliser le patch..." \
                --icon=system-reboot --urgency=critical 2>/dev/null || true
        fi

        sleep 30
        rm -f "$REBOOT_FLAG"
        log "🔄 Reboot système..."
        /sbin/reboot
    fi

    log "━━━ Patch terminé ━━━"
}

# ── Traitement des fichiers déjà présents au démarrage ───────────────────────
# (cas où un .MineOSUp a été déposé pendant que le service était arrêté)
log "Scan initial du dossier $WATCH_DIR..."
for EXISTING in "$WATCH_DIR"/*.MineOSUp; do
    if [ -f "$EXISTING" ]; then
        log "Patch existant trouvé : $(basename "$EXISTING")"
        apply_patch "$EXISTING"
    fi
done

log "Surveillance en cours... (attente de fichiers .MineOSUp)"

# ── Boucle principale inotify ─────────────────────────────────────────────────
# Surveille : création de fichier ET déplacement dans le dossier (mv/cp)
inotifywait -m -e close_write -e moved_to "$WATCH_DIR" \
    --format '%w%f' \
    2>/dev/null | \
while read -r NEW_FILE; do
    # Ignorer tout ce qui n'est pas .MineOSUp
    if [[ "$NEW_FILE" != *.MineOSUp ]]; then
        continue
    fi

    # Petit délai pour s'assurer que l'écriture est complète
    sleep 1

    if [ -f "$NEW_FILE" ]; then
        log "🔔 Nouveau patch détecté : $(basename "$NEW_FILE")"
        apply_patch "$NEW_FILE"
    fi
done
