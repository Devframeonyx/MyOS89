#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║              ⛏  MineOS Gaming — Script de mise à jour                   ║
# ║                    Double-clic pour lancer                               ║
# ║          (équivalent .bat Windows, mais pour Linux)                      ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
#
#  UTILISATION :
#    Double-clic depuis le bureau (raccourci) → Interface graphique
#    Terminal : bash MineOS-Update.sh         → Interface graphique
#    Terminal : bash MineOS-Update.sh --check → Vérification silencieuse
#    Terminal : bash MineOS-Update.sh --force → Applique tout sans demander
#
# ═══════════════════════════════════════════════════════════════════════════════

# ── Couleurs terminal ─────────────────────────────────────────────────────────
GRN='\033[1;32m'; CYN='\033[1;36m'; YLW='\033[1;33m'
RED='\033[1;31m'; MAG='\033[1;35m'; RST='\033[0m'; BLD='\033[1m'

# ── Config ────────────────────────────────────────────────────────────────────
MINEOS_VERSION_FILE="/etc/mineos-version"
MINEOS_UPDATE_URL="https://raw.githubusercontent.com/TON-USER/mineos-gaming/main/updater/updates.json"
LOG_FILE="/var/log/mineos-update.log"
MODE="${1:-gui}"

# Version actuelle (écrite à l'installation)
CURRENT_VERSION=$(cat "$MINEOS_VERSION_FILE" 2>/dev/null || echo "1.0.0")

log()    { echo -e "${GRN}[$(date +%H:%M:%S)]${RST} $*" | tee -a "$LOG_FILE"; }
log_ok() { echo -e "${GRN}  ✅ $*${RST}"                | tee -a "$LOG_FILE"; }
warn()   { echo -e "${YLW}  ⚠️  $*${RST}"               | tee -a "$LOG_FILE"; }
section(){ echo -e "\n${CYN}${BLD}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}" | tee -a "$LOG_FILE"; }

mkdir -p "$(dirname "$LOG_FILE")" && touch "$LOG_FILE"

# ═══════════════════════════════════════════════════════════════════════════════
# LISTE DES UPDATES DISPONIBLES
# (quand hébergé sur GitHub, ce bloc sera remplacé par le JSON distant)
# ═══════════════════════════════════════════════════════════════════════════════
# Chaque update a :
#   ID        : identifiant unique
#   NAME      : nom affiché
#   DESC      : description courte
#   VERSION   : version minimale requise
#   CMD       : commande bash à exécuter
#   NEEDS_ROOT: true/false

declare -A UPDATE_IDS=(
    [0]="gaming-stack"
    [1]="mangohud-v2"
    [2]="dxvk-latest"
    [3]="kernel-liquorix"
    [4]="new-taskbar"
    [5]="flatpak-apps"
    [6]="tweaks-v2"
    [7]="heroic-games"
)

declare -A UPDATE_NAMES=(
    [0]="🎮 Gaming Stack complet"
    [1]="📊 MangoHud amélioré"
    [2]="🔷 DXVK dernière version"
    [3]="⚡ Kernel Liquorix"
    [4]="🖥️  Nouvelle barre des tâches"
    [5]="📦 Apps Flatpak (Discord, Spotify, OBS)"
    [6]="⚙️  Tweaks système v2"
    [7]="🎮 Heroic Games Launcher (Epic/GOG)"
)

declare -A UPDATE_DESCS=(
    [0]="Met à jour Steam, Lutris, Wine, GameMode et MangoHud"
    [1]="Overlay FPS avec GPU clock, VRAM, latence réseau"
    [2]="DXVK 2.4 — meilleures performances DirectX 11/12"
    [3]="Kernel optimisé gaming — meilleure latence"
    [4]="Barre des tâches repensée avec accès rapide aux jeux"
    [5]="Discord, Spotify, OBS Studio via Flatpak"
    [6]="Nouveaux tweaks sysctl + audio low-latency v2"
    [7]="Installer des jeux Epic Games et GOG sans Steam"
)

declare -A UPDATE_CMDS=(
    [0]="update_gaming_stack"
    [1]="update_mangohud"
    [2]="update_dxvk"
    [3]="update_kernel_liquorix"
    [4]="update_taskbar"
    [5]="update_flatpak_apps"
    [6]="update_tweaks_v2"
    [7]="update_heroic"
)

declare -A UPDATE_ROOT=(
    [0]="true" [1]="true" [2]="true" [3]="true"
    [4]="false" [5]="false" [6]="true" [7]="false"
)

INSTALLED_FILE="/etc/mineos-installed-updates"
touch "$INSTALLED_FILE" 2>/dev/null || INSTALLED_FILE="$HOME/.mineos-updates"
touch "$INSTALLED_FILE"

is_installed() { grep -q "^$1$" "$INSTALLED_FILE" 2>/dev/null; }
mark_installed() { echo "$1" >> "$INSTALLED_FILE"; }

# ═══════════════════════════════════════════════════════════════════════════════
# FONCTIONS D'UPDATE
# ═══════════════════════════════════════════════════════════════════════════════

update_gaming_stack() {
    section "Mise à jour Gaming Stack"
    apt-get update -qq
    apt-get install -y --only-upgrade \
        steam-installer gamemode mangohud lutris \
        wine wine64 winetricks 2>/dev/null || true
    log_ok "Gaming Stack à jour"
}

update_mangohud() {
    section "MangoHud amélioré"
    apt-get install -y --only-upgrade mangohud 2>/dev/null || true

    mkdir -p /etc/MangoHud
    cat > /etc/MangoHud/MangoHud.conf << 'EOF'
# MineOS MangoHud v2 — overlay complet
fps
fps_limit=0
frame_timing
cpu_load
gpu_load
ram
vram
cpu_temp
gpu_temp
gpu_core_clock
gpu_mem_clock
network
engine_version
vulkan_driver
position=top-left
font_size=18
background_alpha=0.5
toggle_hud=Shift_R+F12
toggle_fps_limit=Shift_L+F1
no_display=0
EOF
    log_ok "MangoHud v2 configuré (Shift+F12 pour afficher)"
}

update_dxvk() {
    section "DXVK mise à jour"
    DXVK_VER="2.4"
    URL="https://github.com/doitsujin/dxvk/releases/download/v${DXVK_VER}/dxvk-${DXVK_VER}.tar.gz"
    if wget -qO /tmp/dxvk.tar.gz "$URL" 2>/dev/null; then
        mkdir -p /tmp/dxvk-new
        tar -xzf /tmp/dxvk.tar.gz -C /tmp/dxvk-new --strip-components=1
        mkdir -p /usr/share/dxvk
        cp -r /tmp/dxvk-new/x32 /tmp/dxvk-new/x64 /usr/share/dxvk/
        rm -rf /tmp/dxvk.tar.gz /tmp/dxvk-new
        log_ok "DXVK ${DXVK_VER} installé dans /usr/share/dxvk/"
        log_ok "Lancez 'wine-dxvk-setup' pour activer dans un préfixe Wine"
    else
        warn "GitHub inaccessible — DXVK non mis à jour"
    fi
}

update_kernel_liquorix() {
    section "Kernel Liquorix"
    if ! dpkg -l | grep -q "linux-image-liquorix"; then
        if wget -q --spider 'https://liquorix.net/liquorix-keyring.gpg' 2>/dev/null; then
            wget -qO /tmp/liq.gpg 'https://liquorix.net/liquorix-keyring.gpg'
            install -D -m644 /tmp/liq.gpg /usr/share/keyrings/liquorix-keyring.gpg
            rm -f /tmp/liq.gpg
            . /etc/os-release
            echo "deb [signed-by=/usr/share/keyrings/liquorix-keyring.gpg] https://liquorix.net/debian ${VERSION_CODENAME} main" \
                > /etc/apt/sources.list.d/liquorix.list
            apt-get update -qq
            apt-get install -y linux-image-liquorix-amd64 linux-headers-liquorix-amd64
            log_ok "Kernel Liquorix installé — redémarrez pour l'utiliser"
        else
            warn "liquorix.net inaccessible"
        fi
    else
        apt-get install -y --only-upgrade linux-image-liquorix-amd64 2>/dev/null || true
        log_ok "Kernel Liquorix déjà installé — mis à jour"
    fi
}

update_taskbar() {
    section "Nouvelle barre des tâches"
    # Mise à jour du panel XFCE avec nouveaux plugins
    SKEL="/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml"
    USER_CONF="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
    mkdir -p "$USER_CONF"

    cat > "$USER_CONF/xfce4-panel.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
  </property>
  <property name="panel-1" type="empty">
    <property name="position"         type="string" value="p=8;x=0;y=0"/>
    <property name="length"           type="uint"   value="100"/>
    <property name="position-locked"  type="bool"   value="true"/>
    <property name="size"             type="uint"   value="40"/>
    <property name="background-style" type="uint"   value="1"/>
    <property name="background-rgba"  type="array">
      <value type="double" value="0.04"/>
      <value type="double" value="0.04"/>
      <value type="double" value="0.10"/>
      <value type="double" value="0.95"/>
    </property>
    <property name="plugin-ids" type="array">
      <value type="int" value="1"/>
      <value type="int" value="2"/>
      <value type="int" value="3"/>
      <value type="int" value="4"/>
      <value type="int" value="5"/>
      <value type="int" value="6"/>
      <value type="int" value="7"/>
      <value type="int" value="8"/>
      <value type="int" value="9"/>
      <value type="int" value="10"/>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1"  type="string" value="whiskermenu"/>
    <property name="plugin-2"  type="string" value="separator">
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-3"  type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="steam.desktop"/>
      </property>
    </property>
    <property name="plugin-4"  type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="lutris.desktop"/>
      </property>
    </property>
    <property name="plugin-5"  type="string" value="tasklist"/>
    <property name="plugin-6"  type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style"  type="uint" value="0"/>
    </property>
    <property name="plugin-7"  type="string" value="systray"/>
    <property name="plugin-8"  type="string" value="pulseaudio"/>
    <property name="plugin-9"  type="string" value="power-manager-plugin"/>
    <property name="plugin-10" type="string" value="clock">
      <property name="digital-format" type="string" value="%H:%M  %d/%m"/>
    </property>
  </property>
</channel>
EOF
    log_ok "Barre des tâches mise à jour avec accès rapide Steam + Lutris"
    log_ok "Relancez la session XFCE pour voir les changements"
}

update_flatpak_apps() {
    section "Applications Flatpak"
    flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
    flatpak update -y 2>/dev/null || true

    APPS=(
        "com.discordapp.Discord"
        "com.spotify.Client"
        "com.obsproject.Studio"
    )
    for app in "${APPS[@]}"; do
        flatpak install -y flathub "$app" 2>/dev/null \
            && log_ok "$app installé" \
            || warn "$app : échec non bloquant"
    done
}

update_tweaks_v2() {
    section "Tweaks système v2"
    cat > /etc/sysctl.d/99-mineos-gaming-v2.conf << 'EOF'
# MineOS Gaming Tweaks v2
vm.swappiness=5
vm.dirty_ratio=10
vm.dirty_background_ratio=3
kernel.sched_autogroup_enabled=1
kernel.sched_min_granularity_ns=500000
kernel.sched_wakeup_granularity_ns=1000000
fs.file-max=2097152
net.core.netdev_max_backlog=10000
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_congestion_control=bbr
EOF
    sysctl --system 2>/dev/null | grep -E "swappiness|dirty" | head -4 || true

    # Audio v2
    mkdir -p /etc/pulse
    cat > /etc/pulse/daemon.conf << 'EOF'
default-sample-rate = 48000
default-fragment-size-msec = 2
default-fragments = 3
realtime-scheduling = yes
realtime-priority = 9
high-priority = yes
nice-level = -18
avoid-resampling = true
EOF
    log_ok "Tweaks v2 appliqués (latence audio réduite à 2ms)"
}

update_heroic() {
    section "Heroic Games Launcher"
    flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
    flatpak install -y flathub com.heroicgameslauncher.hgl 2>/dev/null \
        && log_ok "Heroic Games Launcher installé (Epic + GOG)" \
        || warn "Heroic : installation Flatpak échouée — connexion internet requise"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODE --check (silencieux, pour le timer systemd)
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$MODE" = "--check" ]; then
    COUNT=0
    NAMES=""
    for i in "${!UPDATE_IDS[@]}"; do
        if ! is_installed "${UPDATE_IDS[$i]}"; then
            COUNT=$((COUNT+1))
            NAMES="$NAMES\n• ${UPDATE_NAMES[$i]}"
        fi
    done
    if [ "$COUNT" -gt 0 ]; then
        notify-send "⛏ MineOS Update" \
            "$COUNT mise(s) à jour disponible(s) !\nOuvrez MineOS-Update depuis le bureau." \
            --icon=software-update-available --urgency=low 2>/dev/null || true
    fi
    exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════════
# MODE GUI (défaut) — Interface interactive dans le terminal
# ═══════════════════════════════════════════════════════════════════════════════
clear
echo ""
echo -e "${GRN}${BLD}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║          ⛏  MineOS Gaming — Mise à Jour              ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${RST}"
echo -e "  Version actuelle : ${CYN}${CURRENT_VERSION}${RST}"
echo ""

# Construire la liste des updates disponibles
AVAILABLE=()
for i in "${!UPDATE_IDS[@]}"; do
    if ! is_installed "${UPDATE_IDS[$i]}"; then
        AVAILABLE+=("$i")
    fi
done

if [ ${#AVAILABLE[@]} -eq 0 ]; then
    echo -e "  ${GRN}✅ MineOS Gaming est à jour ! Aucune mise à jour disponible.${RST}"
    echo ""
    # Mises à jour système apt quand même
    echo -e "  ${CYN}Vérification des mises à jour de sécurité Ubuntu...${RST}"
    sudo apt-get update -qq 2>/dev/null && sudo apt-get upgrade -y 2>/dev/null || true
    flatpak update -y 2>/dev/null || true
    echo -e "  ${GRN}✅ Système Ubuntu à jour.${RST}"
    echo ""
    read -p "  Appuyez sur Entrée pour quitter..." _
    exit 0
fi

echo -e "  ${YLW}${#AVAILABLE[@]} mise(s) à jour MineOS disponible(s) :${RST}"
echo ""

for i in "${AVAILABLE[@]}"; do
    echo -e "  ${GRN}[$i]${RST} ${UPDATE_NAMES[$i]}"
    echo -e "      ${RST}${UPDATE_DESCS[$i]}"
    echo ""
done

echo -e "  ${BLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo ""
echo -e "  ${CYN}Options :${RST}"
echo "   [A] Tout installer (recommandé)"
echo "   [N] Choisir quelles mises à jour installer"
echo "   [S] Uniquement les mises à jour système Ubuntu"
echo "   [Q] Quitter"
echo ""
read -rp "  Votre choix : " CHOICE
CHOICE="${CHOICE^^}"  # uppercase

case "$CHOICE" in
    A)
        TO_INSTALL=("${AVAILABLE[@]}")
        ;;
    N)
        echo ""
        echo -e "  ${CYN}Entrez les numéros séparés par des espaces (ex: 0 2 4) :${RST}"
        read -rp "  > " -a NUMS
        TO_INSTALL=()
        for n in "${NUMS[@]}"; do
            [[ "${UPDATE_IDS[$n]+_}" ]] && TO_INSTALL+=("$n")
        done
        ;;
    S)
        echo ""
        echo -e "  ${CYN}Mise à jour système Ubuntu + Flatpak...${RST}"
        sudo apt-get update && sudo apt-get upgrade -y
        flatpak update -y 2>/dev/null || true
        echo -e "  ${GRN}✅ Système à jour${RST}"
        read -p "  Appuyez sur Entrée..." _
        exit 0
        ;;
    Q|"")
        echo ""; echo "  Annulé."; exit 0
        ;;
    *)
        echo "  Choix invalide."; exit 1
        ;;
esac

if [ ${#TO_INSTALL[@]} -eq 0 ]; then
    echo "  Aucune mise à jour sélectionnée."
    exit 0
fi

# Vérifier si root nécessaire
NEED_ROOT=false
for i in "${TO_INSTALL[@]}"; do
    [ "${UPDATE_ROOT[$i]}" = "true" ] && NEED_ROOT=true && break
done

if [ "$NEED_ROOT" = "true" ] && [ "$EUID" -ne 0 ]; then
    echo ""
    echo -e "  ${YLW}Certaines mises à jour nécessitent les droits administrateur.${RST}"
    exec sudo bash "$0" "--force-ids" "${TO_INSTALL[@]}"
fi

# ── Appliquer les updates ────────────────────────────────────────────────────
echo ""
echo -e "  ${CYN}Début de l'installation...${RST}"
echo ""
FAILED=()
SUCCESS=()

for i in "${TO_INSTALL[@]}"; do
    echo -e "  ${MAG}▶ Installation : ${UPDATE_NAMES[$i]}${RST}"
    CMD="${UPDATE_CMDS[$i]}"
    if $CMD 2>&1 | tee -a "$LOG_FILE"; then
        mark_installed "${UPDATE_IDS[$i]}"
        SUCCESS+=("${UPDATE_NAMES[$i]}")
        echo -e "  ${GRN}✅ ${UPDATE_NAMES[$i]} — OK${RST}"
    else
        FAILED+=("${UPDATE_NAMES[$i]}")
        echo -e "  ${RED}❌ ${UPDATE_NAMES[$i]} — Échec${RST}"
    fi
    echo ""
done

# ── Mise à jour système apt ──────────────────────────────────────────────────
echo -e "  ${CYN}Mise à jour sécurité Ubuntu...${RST}"
apt-get update -qq && apt-get upgrade -y -q 2>/dev/null || true
flatpak update -y 2>/dev/null | tail -3 || true

# ── Rapport final ─────────────────────────────────────────────────────────────
echo ""
echo -e "${GRN}${BLD}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║             ✅  Mise à jour terminée !                ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${RST}"

if [ ${#SUCCESS[@]} -gt 0 ]; then
    echo -e "  ${GRN}Installé avec succès :${RST}"
    for s in "${SUCCESS[@]}"; do echo "    ✅ $s"; done
fi
if [ ${#FAILED[@]} -gt 0 ]; then
    echo ""
    echo -e "  ${RED}Échecs (non bloquants) :${RST}"
    for f in "${FAILED[@]}"; do echo "    ❌ $f"; done
fi

echo ""
echo -e "  ${CYN}Log complet : $LOG_FILE${RST}"
echo ""
read -p "  Appuyez sur Entrée pour quitter..." _

# Notification desktop
notify-send "⛏ MineOS Update" \
    "${#SUCCESS[@]} mise(s) à jour installée(s) avec succès !" \
    --icon=software-update-available 2>/dev/null || true
