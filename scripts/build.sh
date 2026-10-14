#!/bin/bash
# ============================================================
#  MineOS — Script de build ISO principal
#  Utilise live-build (Debian officiel)
# ============================================================
set -euo pipefail

VERSION="${1:-1.0.0}"
BUILD_DIR="$(pwd)/build"
LB_DIR="$(pwd)/lb-workspace"

echo "============================================"
echo "  ⛏ MineOS ISO Builder v${VERSION}"
echo "============================================"

# ─── Nettoyage ───────────────────────────────────────────
rm -rf "$LB_DIR" "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$LB_DIR"
cd "$LB_DIR"

# ─── Configuration live-build ────────────────────────────
echo "[1/6] Configuration live-build..."
lb config \
  --architectures amd64 \
  --distribution bookworm \
  --debian-installer none \
  --binary-images iso-hybrid \
  --memtest none \
  --bootloaders "grub-efi,syslinux" \
  --uefi-secure-boot disable \
  --apt-recommends false \
  --archive-areas "main contrib non-free non-free-firmware" \
  --mirror-bootstrap "http://deb.debian.org/debian" \
  --mirror-binary "http://deb.debian.org/debian" \
  --mirror-binary-security "http://security.debian.org/debian-security" \
  --hostname "mineos" \
  --username "user" \
  --iso-application "MineOS" \
  --iso-publisher "MineOS Project" \
  --iso-volume "MineOS-${VERSION}" \
  --bootappend-live "boot=live components quiet splash hostname=mineos username=user"

# ─── Paquets ─────────────────────────────────────────────
echo "[2/6] Configuration des paquets..."
mkdir -p config/package-lists

cat > config/package-lists/mineos.list.chroot << 'PKGEOF'
# ── Système de base ──
systemd
systemd-sysv
udev
dbus
policykit-1
sudo
wget
curl
ca-certificates
gnupg
apt-transport-https
software-properties-common
locales
tzdata
keyboard-configuration

# ── Réseau ──
network-manager
network-manager-gnome
wireless-tools
wpasupplicant
rfkill

# ── Bureau (Openbox) ──
openbox
obconf
lxappearance
lxsession
lightdm
lightdm-gtk-greeter
lightdm-gtk-greeter-settings
tint2
nitrogen
picom
rofi
dunst
xorg
xserver-xorg
xinit
x11-xserver-utils
x11-utils
xterm
xdg-utils
xdg-user-dirs

# ── Gestionnaire de fichiers ──
thunar
thunar-archive-plugin
thunar-volman
gvfs
gvfs-backends
udisks2

# ── Applications ──
mousepad
tilix
geany
vlc
gimp
file-roller

# ── Polices & icônes ──
fonts-noto
fonts-noto-color-emoji
fonts-liberation
papirus-icon-theme

# ── Audio ──
pulseaudio
pavucontrol
alsa-utils

# ── Utilitaires ──
zip
unzip
p7zip-full
htop
neofetch
bash-completion
nano
vim

# ── Wine (compatibilité .exe) ──
wine
wine64
winetricks
playonlinux
PKGEOF

# ─── Hooks : install Google Chrome ───────────────────────
echo "[3/6] Configuration des hooks..."
mkdir -p config/hooks/live

cat > config/hooks/live/0100-install-chrome.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> Installation de Google Chrome..."

# Ajouter la clé GPG Google
wget -qO- https://dl.google.com/linux/linux_signing_key.pub \
  | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg

# Ajouter le repo Chrome
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] \
  https://dl.google.com/linux/chrome/deb/ stable main" \
  > /etc/apt/sources.list.d/google-chrome.list

apt-get update -qq
apt-get install -y google-chrome-stable

echo ">>> Chrome installé: $(google-chrome --version)"
HOOKEOF

cat > config/hooks/live/0200-wine-setup.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> Configuration Wine..."

# Activer l'architecture 32-bit pour Wine
dpkg --add-architecture i386
apt-get update -qq
apt-get install -y --no-install-recommends \
  wine32 \
  libwine:i386 \
  fonts-wine

# Créer un script d'aide pour lancer les .exe
cat > /usr/local/bin/run-exe << 'EXEOF'
#!/bin/bash
# MineOS EXE Launcher — Lance un .exe via Wine
if [ -z "$1" ]; then
  echo "Usage: run-exe <fichier.exe> [args...]"
  exit 1
fi
wine "$@"
EXEOF
chmod +x /usr/local/bin/run-exe

# Association fichier .exe -> Wine
mkdir -p /usr/share/applications
cat > /usr/share/applications/wine-exe.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Wine EXE Launcher
Exec=wine %f
MimeType=application/x-ms-dos-executable;application/x-msi;application/x-ms-shortcut;
Icon=wine
Type=Application
NoDisplay=true
DESKTOPEOF

# Mettre à jour la base mime
update-mime-database /usr/share/mime 2>/dev/null || true
update-desktop-database 2>/dev/null || true

echo ">>> Wine configuré"
HOOKEOF

cat > config/hooks/live/0300-mineos-theme.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> Installation du thème MineOS..."

# ── Thème GTK MineOS Dark ──
mkdir -p /usr/share/themes/MineOS-Dark/{gtk-2.0,gtk-3.0,gtk-4.0}

# GTK 3 - couleurs Minecraft dark
cat > /usr/share/themes/MineOS-Dark/gtk-3.0/gtk.css << 'CSSEOF'
@define-color bg_color #1a1a2e;
@define-color fg_color #e2e8f0;
@define-color base_color #16213e;
@define-color text_color #e2e8f0;
@define-color selected_bg_color #4ade80;
@define-color selected_fg_color #0d1117;
@define-color tooltip_bg_color #0f3460;
@define-color tooltip_fg_color #e2e8f0;

* {
  -gtk-icon-style: regular;
}

window, .background {
  background-color: @bg_color;
  color: @fg_color;
}

headerbar, .titlebar {
  background: #0d2137;
  border-bottom: 1px solid #2d4a6e;
  color: @fg_color;
}

button {
  background: rgba(74,222,128,0.1);
  border: 1px solid #2d4a6e;
  border-radius: 4px;
  color: @fg_color;
}

button:hover {
  background: rgba(74,222,128,0.2);
  border-color: #4ade80;
}

entry {
  background: rgba(0,0,0,0.4);
  border: 1px solid #2d4a6e;
  border-radius: 4px;
  color: #22d3ee;
}

treeview, .view {
  background: @base_color;
  color: @fg_color;
}

treeview:selected {
  background: rgba(74,222,128,0.15);
  color: #4ade80;
}

scrollbar slider {
  background: #2d4a6e;
  border-radius: 3px;
  min-width: 6px;
  min-height: 6px;
}
CSSEOF

# GTK 2
cat > /usr/share/themes/MineOS-Dark/gtk-2.0/gtkrc << 'GTK2EOF'
gtk-color-scheme = "bg_color:#1a1a2e\nfg_color:#e2e8f0\nbase_color:#16213e\ntext_color:#e2e8f0\nselected_bg_color:#4ade80\nselected_fg_color:#0d1117"
style "default" {
  bg[NORMAL] = @bg_color
  fg[NORMAL] = @fg_color
  base[NORMAL] = @base_color
  text[NORMAL] = @text_color
  bg[SELECTED] = @selected_bg_color
  fg[SELECTED] = @selected_fg_color
}
class "*" style "default"
GTK2EOF

echo ">>> Thème MineOS-Dark installé"
HOOKEOF

cat > config/hooks/live/0400-openbox-config.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> Configuration Openbox..."

# Créer la config Openbox par défaut pour l'utilisateur live
mkdir -p /etc/skel/.config/openbox

# autostart : lancer les composants au démarrage
cat > /etc/skel/.config/openbox/autostart << 'AUTOEOF'
# MineOS Autostart

# Fond d'écran
nitrogen --restore &

# Compositeur (transparence, ombres)
picom --config ~/.config/picom.conf &

# Barre des tâches
tint2 &

# Gestionnaire de réseau
nm-applet &

# Notifications
dunst &

# PulseAudio
pulseaudio --start &

# Initialiser les dossiers utilisateur
xdg-user-dirs-update &
AUTOEOF

# Menu Openbox
cat > /etc/skel/.config/openbox/menu.xml << 'MENUEOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu>
  <menu id="root-menu" label="⛏ MineOS">
    <item label="🌐 Google Chrome">
      <action name="Execute"><command>google-chrome-stable</command></action>
    </item>
    <item label="📁 Fichiers (Thunar)">
      <action name="Execute"><command>thunar</command></action>
    </item>
    <item label="📝 Bloc-notes">
      <action name="Execute"><command>mousepad</command></action>
    </item>
    <item label="💻 Terminal">
      <action name="Execute"><command>tilix</command></action>
    </item>
    <item label="🎵 VLC">
      <action name="Execute"><command>vlc</command></action>
    </item>
    <item label="🎨 GIMP">
      <action name="Execute"><command>gimp</command></action>
    </item>
    <separator/>
    <item label="⚡ Lancer un .exe (Wine)">
      <action name="Execute">
        <command>bash -c 'FILE=$(zenity --file-selection --file-filter="*.exe *.msi" --title="Choisir un .exe à lancer"); [ -n "$FILE" ] &amp;&amp; wine "$FILE"'</command>
      </action>
    </item>
    <item label="🍷 Winetricks">
      <action name="Execute"><command>winetricks --gui</command></action>
    </item>
    <item label="🎮 PlayOnLinux">
      <action name="Execute"><command>playonlinux</command></action>
    </item>
    <separator/>
    <item label="⚙️ Paramètres apparence">
      <action name="Execute"><command>lxappearance</command></action>
    </item>
    <item label="📊 Gestionnaire de tâches">
      <action name="Execute"><command>tilix -e htop</command></action>
    </item>
    <separator/>
    <item label="🔒 Verrouiller">
      <action name="Execute"><command>dm-tool lock</command></action>
    </item>
    <item label="⏻ Éteindre">
      <action name="Execute"><command>systemctl poweroff</command></action>
    </item>
    <item label="🔄 Redémarrer">
      <action name="Execute"><command>systemctl reboot</command></action>
    </item>
  </menu>
</openbox_menu>
MENUEOF

# rc.xml : raccourcis clavier
cat > /etc/skel/.config/openbox/rc.xml << 'RCEOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config>
  <theme>
    <name>MineOS-Dark</name>
    <titleLayout>NLIMC</titleLayout>
    <font place="ActiveWindow"><name>Noto Sans</name><size>10</size><weight>Bold</weight></font>
    <font place="InactiveWindow"><name>Noto Sans</name><size>10</size></font>
  </theme>
  <desktops><number>4</number><firstdesk>1</firstdesk></desktops>
  <keyboard>
    <keybind key="Super-Return">
      <action name="Execute"><command>tilix</command></action>
    </keybind>
    <keybind key="Super-e">
      <action name="Execute"><command>thunar</command></action>
    </keybind>
    <keybind key="Super-b">
      <action name="Execute"><command>google-chrome-stable</command></action>
    </keybind>
    <keybind key="Super-r">
      <action name="Execute"><command>rofi -show run</command></action>
    </keybind>
    <keybind key="A-F4">
      <action name="Close"/>
    </keybind>
    <keybind key="Super-d">
      <action name="ToggleShowDesktop"/>
    </keybind>
    <keybind key="A-Tab">
      <action name="NextWindow"/>
    </keybind>
    <keybind key="Print">
      <action name="Execute"><command>scrot ~/Bureau/screenshot-%Y%m%d-%H%M%S.png</command></action>
    </keybind>
  </keyboard>
  <mouse>
    <context name="Desktop">
      <mousebind button="Right" action="Press">
        <action name="ShowMenu"><menu>root-menu</menu></action>
      </mousebind>
    </context>
    <context name="Titlebar">
      <mousebind button="Left" action="Drag">
        <action name="Move"/>
      </mousebind>
      <mousebind button="Left" action="DoubleClick">
        <action name="MaximizeWindow"/>
      </mousebind>
      <mousebind button="Right" action="Press">
        <action name="ShowMenu"><menu>client-menu</menu></action>
      </mousebind>
    </context>
    <context name="Bottom">
      <mousebind button="Left" action="Drag">
        <action name="Resize"/>
      </mousebind>
    </context>
  </mouse>
</openbox_config>
RCEOF

echo ">>> Openbox configuré"
HOOKEOF

cat > config/hooks/live/0500-user-setup.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> Configuration utilisateur MineOS..."

# Créer les dossiers XDG
mkdir -p /etc/skel/{Bureau,Documents,Images,Musique,Téléchargements,Vidéos,.config/{tint2,picom,dunst,nitrogen}}

# Config tint2 (barre des tâches)
cat > /etc/skel/.config/tint2/tint2rc << 'T2EOF'
# MineOS Tint2 Config
panel_items = TSC
panel_size = 100% 36
panel_margin = 0 0
panel_padding = 4 4 4
panel_background_id = 1
wm_menu = 1
panel_dock = 0
panel_layer = bottom
panel_position = bottom center horizontal
font_shadow = 0
panel_shrink = 0

# Fond de la barre
rounded = 0
border_width = 0
background_color = #0a0a1a 100
border_color = #2d4a6e 100

# Taskbar
taskbar_mode = single_desktop
taskbar_padding = 2 3 2
taskbar_background_id = 0
taskbar_active_background_id = 2

# Boutons de tâches
task_icon = 1
task_text = 1
task_centered = 1
task_maximum_size = 150 30
task_padding = 6 3 6
task_font = Noto Sans 9
task_font_color = #e2e8f0 80
task_active_font_color = #4ade80 100
task_background_id = 3
task_active_background_id = 2

# Fond tâche active
rounded = 4
border_width = 1
background_color = #1a1a2e 100
border_color = #4ade80 40

# Fond tâche inactive
rounded = 4
border_width = 0
background_color = #0a0a1a 0
border_color = #2d4a6e 0

# Systray
systray_padding = 4 4 4
systray_background_id = 0
systray_sort = ascending

# Horloge
time1_format = %H:%M
time1_font = Noto Sans Bold 10
time2_format = %d/%m/%Y
time2_font = Noto Sans 8
clock_font_color = #e2e8f0 90
clock_padding = 8 0
clock_background_id = 0
T2EOF

# Config picom (compositeur)
cat > /etc/skel/.config/picom/picom.conf << 'PICOMEOF'
# MineOS Picom Config
backend = "glx";
vsync = true;
shadow = true;
shadow-radius = 12;
shadow-offset-x = -12;
shadow-offset-y = -12;
shadow-opacity = 0.5;
shadow-exclude = ["class_g = 'tint2'"];
fading = true;
fade-in-step = 0.05;
fade-out-step = 0.05;
fade-delta = 5;
opacity-rule = ["90:class_g = 'Tilix'"];
corner-radius = 8;
PICOMEOF

# Config nitrogen (fond d'écran)
cat > /etc/skel/.config/nitrogen/bg-saved.cfg << 'NITEOF'
[xin_-1]
file=/usr/share/mineos/wallpaper.png
mode=4
bgcolor=#1a1a2e
NITEOF

# Raccourcis bureau
cat > /etc/skel/Bureau/chrome.desktop << 'DEOF'
[Desktop Entry]
Name=Google Chrome
Exec=google-chrome-stable %U
Icon=google-chrome
Type=Application
Categories=Network;WebBrowser;
DEOF

cat > /etc/skel/Bureau/wine-launcher.desktop << 'DEOF'
[Desktop Entry]
Name=Lancer un .exe
Comment=Ouvrir un fichier Windows avec Wine
Exec=bash -c 'FILE=$(zenity --file-selection --file-filter="*.exe *.msi" --title="Choisir un .exe"); [ -n "$FILE" ] && wine "$FILE"'
Icon=wine
Type=Application
DEOF

cat > /etc/skel/Bureau/terminal.desktop << 'DEOF'
[Desktop Entry]
Name=Terminal
Exec=tilix
Icon=terminal
Type=Application
DEOF

chmod +x /etc/skel/Bureau/*.desktop

# Fond d'écran MineOS (généré via Python + PIL)
mkdir -p /usr/share/mineos
python3 << 'PYEOF'
try:
    from PIL import Image, ImageDraw, ImageFont
    img = Image.new('RGB', (1920, 1080), color='#1a1a2e')
    draw = ImageDraw.Draw(img)
    # Grille Minecraft
    for x in range(0, 1920, 32):
        draw.line([(x, 0), (x, 1080)], fill='#1f2a3d', width=1)
    for y in range(0, 1080, 32):
        draw.line([(0, y), (1920, y)], fill='#1f2a3d', width=1)
    # Logo texte centre
    draw.text((960, 500), '⛏', fill='#4ade80', anchor='mm')
    img.save('/usr/share/mineos/wallpaper.png')
    print("Wallpaper PIL créé")
except:
    # Fallback : créer un PNG simple via convert
    import subprocess
    subprocess.run([
        'convert', '-size', '1920x1080',
        'gradient:#1a1a2e-#0d2137',
        '/usr/share/mineos/wallpaper.png'
    ], capture_output=True)
    print("Wallpaper convert créé")
PYEOF

echo ">>> Utilisateur configuré"
HOOKEOF

cat > config/hooks/live/0600-lightdm.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> Configuration LightDM..."

# Config LightDM
cat > /etc/lightdm/lightdm.conf << 'LDEOF'
[Seat:*]
autologin-user=user
autologin-user-timeout=0
greeter-session=lightdm-gtk-greeter
session-wrapper=/etc/X11/Xsession
LDEOF

# Config greeter (écran de connexion)
cat > /etc/lightdm/lightdm-gtk-greeter.conf << 'GREETEOF'
[greeter]
background=#1a1a2e
theme-name=MineOS-Dark
icon-theme-name=Papirus-Dark
font-name=Noto Sans 11
clock-format=%H:%M — %A %d %B
indicators=~host;~spacer;~clock;~spacer;~session;~a11y;~power
GREETEOF

echo ">>> LightDM configuré"
HOOKEOF

chmod +x config/hooks/live/*.hook.chroot

# ─── includes.chroot : fichiers supplémentaires ──────────
echo "[4/6] Copie des fichiers système..."
mkdir -p config/includes.chroot/etc/skel
mkdir -p config/includes.chroot/usr/local/bin

# Script de détection et lancement automatique .exe au double-clic
cat > config/includes.chroot/usr/local/bin/mineos-open << 'OPENEOF'
#!/bin/bash
# MineOS Smart File Opener
FILE="$1"
EXT="${FILE##*.}"
EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')

case "$EXT_LOWER" in
  exe|msi|bat|com)
    notify-send "⚡ MineOS" "Lancement via Wine : $(basename "$FILE")" 2>/dev/null
    wine "$FILE"
    ;;
  *)
    xdg-open "$FILE"
    ;;
esac
OPENEOF
chmod +x config/includes.chroot/usr/local/bin/mineos-open

# .bashrc avec prompt MineOS style
cat > config/includes.chroot/etc/skel/.bashrc << 'BASHRCEOF'
# MineOS .bashrc
export LANG=fr_FR.UTF-8
export LC_ALL=fr_FR.UTF-8

# Prompt style Minecraft
PS1='\[\e[0;32m\]⛏ \[\e[1;36m\]\u\[\e[0;37m\]@\[\e[1;34m\]mineos\[\e[0;37m\]:\[\e[1;33m\]\w\[\e[0m\]\$ '

# Aliases utiles
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias grep='grep --color=auto'
alias chrome='google-chrome-stable'
alias exe='wine'
alias update='sudo apt update && sudo apt upgrade -y'
alias neofetch='neofetch --ascii_distro MineOS 2>/dev/null || neofetch'

# Complétion bash
[ -f /etc/bash_completion ] && . /etc/bash_completion

echo ""
echo "  ⛏  Bienvenue sur MineOS 1.0 !"
echo "  Tapez 'chrome' pour ouvrir Chrome, 'exe <fichier.exe>' pour lancer un .exe"
echo ""
BASHRCEOF

# ─── Compression ─────────────────────────────────────────
echo "[5/6] Configuration de la compression..."
mkdir -p config/compression

# Utiliser xz pour un ISO plus compact
echo "xz" > config/compression/filesystem

# ─── Build ───────────────────────────────────────────────
echo "[6/6] Lancement du build (peut prendre 20-30 min)..."
sudo lb build 2>&1 | tee /tmp/mineos-build.log

# ─── Déplacer l'ISO ──────────────────────────────────────
if ls *.iso 1>/dev/null 2>&1; then
  mv *.iso "$BUILD_DIR/mineos.iso"
  echo "============================================"
  echo "  ✅ ISO créé : $BUILD_DIR/mineos.iso"
  echo "  Taille : $(du -sh $BUILD_DIR/mineos.iso | cut -f1)"
  echo "============================================"
else
  echo "❌ ERREUR : Aucun ISO trouvé après le build"
  echo "Dernières lignes du log :"
  tail -50 /tmp/mineos-build.log
  exit 1
fi
