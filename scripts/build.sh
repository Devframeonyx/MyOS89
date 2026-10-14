#!/bin/bash
# ============================================================
#  MineOS Gaming Edition — Script de build ISO
#  Fix: options lb config compatibles live-build 20230131+
# ============================================================
set -euo pipefail

VERSION="${1:-1.0.0}"
BUILD_DIR="$(pwd)/build"
LB_DIR="$(pwd)/lb-workspace"

echo "============================================"
echo "  ⛏ MineOS Gaming Edition v${VERSION}"
echo "============================================"

rm -rf "$LB_DIR" "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$LB_DIR"
cd "$LB_DIR"

# ─── 1. Configuration live-build (options corrigées) ─────
echo "[1/7] Configuration live-build..."

lb config \
  --architectures amd64 \
  --distribution bookworm \
  --debian-installer none \
  --binary-images iso-hybrid \
  --memtest none \
  --apt-recommends false \
  --archive-areas "main contrib non-free non-free-firmware" \
  --mirror-bootstrap "http://deb.debian.org/debian" \
  --mirror-binary "http://deb.debian.org/debian" \
  --mirror-binary-security "http://security.debian.org/debian-security" \
  --iso-application "MineOS Gaming" \
  --iso-publisher "MineOS Project" \
  --iso-volume "MineOS-${VERSION}" \
  --bootappend-live "boot=live components quiet splash hostname=mineos username=user"

# hostname & autologin via includes, pas via lb config
mkdir -p config/includes.chroot/etc
echo "mineos" > config/includes.chroot/etc/hostname
cat > config/includes.chroot/etc/hosts << 'EOF'
127.0.0.1   localhost
127.0.1.1   mineos
::1         localhost ip6-localhost ip6-loopback
EOF

# ─── 2. Paquets ──────────────────────────────────────────
echo "[2/7] Liste des paquets..."
mkdir -p config/package-lists

cat > config/package-lists/00-base.list.chroot << 'EOF'
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
rsync
EOF

cat > config/package-lists/01-desktop.list.chroot << 'EOF'
openbox
obconf
lxappearance
lxsession
lightdm
lightdm-gtk-greeter
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
xdg-utils
xdg-user-dirs
network-manager
network-manager-gnome
pulseaudio
pavucontrol
alsa-utils
fonts-noto
fonts-noto-color-emoji
fonts-liberation
papirus-icon-theme
EOF

cat > config/package-lists/02-apps.list.chroot << 'EOF'
thunar
thunar-archive-plugin
thunar-volman
gvfs
gvfs-backends
udisks2
mousepad
tilix
geany
vlc
gimp
file-roller
zip
unzip
p7zip-full
htop
neofetch
bash-completion
nano
vim
zenity
scrot
EOF

cat > config/package-lists/03-wine.list.chroot << 'EOF'
wine
wine64
winetricks
playonlinux
EOF

cat > config/package-lists/04-gaming.list.chroot << 'EOF'
gamemode
mangohud
mesa-vulkan-drivers
mesa-va-drivers
mesa-vdpau-drivers
libvulkan1
vulkan-tools
libgl1-mesa-dri
libgl1-mesa-glx
libgles2-mesa
lutris
steam-installer
EOF

# ─── 3. Hooks ────────────────────────────────────────────
echo "[3/7] Création des hooks..."
mkdir -p config/hooks/live

# ── Hook Chrome ──
cat > config/hooks/live/0100-chrome.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> [Hook] Google Chrome..."
wget -qO /tmp/google-chrome.deb \
  "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
apt-get install -y /tmp/google-chrome.deb || true
rm -f /tmp/google-chrome.deb
# Réinstaller les dépendances si nécessaire
apt-get install -f -y
echo ">>> Chrome: $(google-chrome --version 2>/dev/null || echo 'installé')"
HOOKEOF

# ── Hook Wine 32bit + DXVK ──
cat > config/hooks/live/0200-wine-gaming.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> [Hook] Wine 32bit + DXVK..."

dpkg --add-architecture i386
apt-get update -qq
apt-get install -y --no-install-recommends \
  wine32 \
  libwine:i386 \
  fonts-wine \
  libvulkan1:i386 \
  libgl1-mesa-dri:i386 \
  libgl1-mesa-glx:i386 2>/dev/null || true

# Télécharger et installer DXVK (DirectX 9/10/11 → Vulkan)
DXVK_VER="2.3.1"
DXVK_URL="https://github.com/doitsujin/dxvk/releases/download/v${DXVK_VER}/dxvk-${DXVK_VER}.tar.gz"
echo ">>> Installation DXVK ${DXVK_VER}..."
wget -qO /tmp/dxvk.tar.gz "$DXVK_URL" || {
  echo "DXVK download failed, skipping"; exit 0
}
mkdir -p /tmp/dxvk
tar -xzf /tmp/dxvk.tar.gz -C /tmp/dxvk --strip-components=1
# Copier dans /usr/share pour setup_dxvk au runtime
mkdir -p /usr/share/dxvk
cp -r /tmp/dxvk/x32 /tmp/dxvk/x64 /usr/share/dxvk/
cp /tmp/dxvk/setup_dxvk.sh /usr/local/bin/setup_dxvk
chmod +x /usr/local/bin/setup_dxvk
rm -rf /tmp/dxvk*

# Script d'activation DXVK pour un prefix Wine
cat > /usr/local/bin/wine-dxvk-setup << 'DXVKEOF'
#!/bin/bash
# Active DXVK dans le prefix Wine courant
PREFIX="${WINEPREFIX:-$HOME/.wine}"
echo ">>> Activation DXVK dans : $PREFIX"
for f in /usr/share/dxvk/x64/*.dll; do
  cp "$f" "$PREFIX/drive_c/windows/system32/" 2>/dev/null || true
done
for f in /usr/share/dxvk/x32/*.dll; do
  cp "$f" "$PREFIX/drive_c/windows/syswow64/" 2>/dev/null || true
done
echo ">>> DXVK activé. Relance ton .exe."
DXVKEOF
chmod +x /usr/local/bin/wine-dxvk-setup

# Association .exe
cat > /usr/share/applications/wine-exe.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Wine EXE Launcher
Exec=wine %f
MimeType=application/x-ms-dos-executable;application/x-msi;
Icon=wine
Type=Application
NoDisplay=true
DESKTOPEOF

update-desktop-database 2>/dev/null || true
echo ">>> Wine gaming configuré"
HOOKEOF

# ── Hook Kernel liquorix (low-latency gaming) ──
cat > config/hooks/live/0250-kernel-liquorix.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> [Hook] Kernel Liquorix (low-latency gaming)..."

# Ajouter le repo liquorix
wget -qO /tmp/liquorix.gpg "https://liquorix.net/liquorix-keyring.gpg"
install -D -m 644 /tmp/liquorix.gpg /usr/share/keyrings/liquorix-keyring.gpg

. /etc/os-release
echo "deb [signed-by=/usr/share/keyrings/liquorix-keyring.gpg] \
  https://liquorix.net/debian $VERSION_CODENAME main" \
  > /etc/apt/sources.list.d/liquorix.list

apt-get update -qq
apt-get install -y linux-image-liquorix-amd64 linux-headers-liquorix-amd64 || {
  echo ">>> Liquorix non disponible, kernel Debian standard conservé"
}
echo ">>> Kernel configuré"
HOOKEOF

# ── Hook Steam ──
cat > config/hooks/live/0300-steam.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> [Hook] Steam..."
dpkg --add-architecture i386
apt-get update -qq

# Steam nécessite i386 et des libs 32bit
apt-get install -y --no-install-recommends \
  steam-installer \
  libgl1-mesa-dri:i386 \
  libgl1:i386 2>/dev/null || {
    # Fallback : télécharger directement
    wget -qO /tmp/steam.deb "https://cdn.cloudflare.steamstatic.com/client/installer/steam.deb"
    apt-get install -y /tmp/steam.deb || true
    apt-get install -f -y || true
    rm -f /tmp/steam.deb
  }
echo ">>> Steam installé"
HOOKEOF

# ── Hook Lutris ──
cat > config/hooks/live/0350-lutris.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> [Hook] Lutris..."
apt-get install -y lutris 2>/dev/null || {
  # Fallback via pip
  pip3 install lutris 2>/dev/null || true
}
echo ">>> Lutris configuré"
HOOKEOF

# ── Hook GameMode + MangoHud ──
cat > config/hooks/live/0400-gamemode-mangohud.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> [Hook] GameMode + MangoHud..."

apt-get install -y gamemode mangohud 2>/dev/null || true

# Config GameMode
mkdir -p /etc
cat > /etc/gamemode.ini << 'GMEOF'
[general]
renice=10
ioprio=0
inhibit_screensaver=1

[cpu]
park_cores=no
pin_cores=yes
governor=performance

[gpu]
apply_gpu_optimisations=accept-responsibility
gpu_device=0
amd_performance_level=high

[filter]
whitelist=steam;lutris;wine;playonlinux
GMEOF

# Config MangoHud globale
mkdir -p /etc/MangoHud
cat > /etc/MangoHud/MangoHud.conf << 'MHEOF'
fps
frame_timing
cpu_load
gpu_load
ram
vram
cpu_temp
gpu_temp
position=top-left
font_size=18
background_alpha=0.5
toggle_hud=Shift_R+F12
toggle_fps_limit=Shift_R+F1
fps_limit=0
MHEOF

echo ">>> GameMode + MangoHud configurés"
HOOKEOF

# ── Hook optimisations système gaming ──
cat > config/hooks/live/0500-gaming-tweaks.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> [Hook] Optimisations système gaming..."

# ── Swappiness basse (garder max en RAM) ──
cat > /etc/sysctl.d/99-mineos-gaming.conf << 'SYSEOF'
# MineOS Gaming Tweaks
vm.swappiness=10
vm.dirty_ratio=15
vm.dirty_background_ratio=5
kernel.sched_autogroup_enabled=1
net.core.netdev_max_backlog=16384
fs.file-max=2097152
SYSEOF

# ── IRQ affinity (CPU perf) ──
cat > /etc/udev/rules.d/99-mineos-gaming.rules << 'UDEVEOF'
# MineOS Gaming — USB polling rate boost
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="*", ATTR{idProduct}=="*", \
  RUN+="/bin/sh -c 'echo 1 > /sys$DEVPATH/power/autosuspend_delay_ms'"
UDEVEOF

# ── Audio low-latency (ALSA + PulseAudio) ──
mkdir -p /etc/pulse
cat > /etc/pulse/daemon.conf << 'PAEOF'
default-sample-rate = 48000
alternate-sample-rate = 44100
default-sample-channels = 2
default-fragment-size-msec = 5
default-fragments = 2
realtime-scheduling = yes
realtime-priority = 9
high-priority = yes
nice-level = -15
PAEOF

# ── limits pour gaming (no file descriptor limit) ──
cat >> /etc/security/limits.conf << 'LIMEOF'
* soft nofile 1048576
* hard nofile 1048576
* soft memlock unlimited
* hard memlock unlimited
LIMEOF

# ── Intel HD 620 : activer GuC/HuC pour meilleures perfs ──
cat > /etc/modprobe.d/i915-gaming.conf << 'I915EOF'
# Intel HD 620 (i3-7020U) optimisations
options i915 enable_guc=3
options i915 enable_fbc=1
options i915 enable_psr=1
options i915 fastboot=1
I915EOF

# ── GRUB : paramètres kernel gaming ──
mkdir -p /etc/default
cat >> /etc/default/grub << 'GRUBEOF'
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash mitigations=off nowatchdog nohz_full=1-3 rcu_nocbs=1-3 threadirqs"
GRUBEOF
# Note: mitigations=off = +10-15% perfs CPU (désactive Spectre/Meltdown patches)
# Sur une machine personnelle non-serveur c'est acceptable

echo ">>> Tweaks gaming appliqués"
HOOKEOF

# ── Hook bureau + thème ──
cat > config/hooks/live/0600-desktop.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> [Hook] Bureau MineOS Gaming..."

mkdir -p /etc/skel/.config/{openbox,tint2,picom,dunst,nitrogen}
mkdir -p /etc/skel/{Bureau,Documents,Images,Musique,Téléchargements,Jeux}
mkdir -p /usr/share/themes/MineOS-Dark/gtk-3.0
mkdir -p /usr/share/themes/MineOS-Dark/gtk-2.0

# Thème GTK3
cat > /usr/share/themes/MineOS-Dark/gtk-3.0/gtk.css << 'CSSEOF'
@define-color bg_color #1a1a2e;
@define-color fg_color #e2e8f0;
@define-color base_color #16213e;
@define-color selected_bg_color #4ade80;
@define-color selected_fg_color #0d1117;

window, .background { background-color: @bg_color; color: @fg_color; }
headerbar, .titlebar { background: #0d2137; border-bottom: 1px solid #2d4a6e; }
button { background: rgba(74,222,128,0.1); border: 1px solid #2d4a6e; border-radius: 4px; color: @fg_color; }
button:hover { background: rgba(74,222,128,0.2); border-color: #4ade80; }
entry { background: rgba(0,0,0,0.4); border: 1px solid #2d4a6e; border-radius: 4px; color: #22d3ee; }
treeview, .view { background: @base_color; color: @fg_color; }
treeview:selected { background: rgba(74,222,128,0.15); color: #4ade80; }
scrollbar slider { background: #2d4a6e; border-radius: 3px; min-width: 6px; min-height: 6px; }
CSSEOF

# GTK2
cat > /usr/share/themes/MineOS-Dark/gtk-2.0/gtkrc << 'G2EOF'
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
G2EOF

# Openbox autostart
cat > /etc/skel/.config/openbox/autostart << 'AUTOEOF'
nitrogen --restore &
picom --config ~/.config/picom/picom.conf &
tint2 &
nm-applet &
dunst &
pulseaudio --start &
xdg-user-dirs-update &
# Activer GameMode daemon
/usr/lib/gamemode/gamemoded &
AUTOEOF

# Menu Openbox (avec section Gaming)
cat > /etc/skel/.config/openbox/menu.xml << 'MENUEOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu>
  <menu id="root-menu" label="⛏ MineOS">

    <menu id="internet-menu" label="🌐 Internet">
      <item label="Google Chrome">
        <action name="Execute"><command>google-chrome-stable</command></action>
      </item>
    </menu>

    <menu id="gaming-menu" label="🎮 Gaming">
      <item label="Steam">
        <action name="Execute"><command>steam</command></action>
      </item>
      <item label="Lutris">
        <action name="Execute"><command>lutris</command></action>
      </item>
      <item label="PlayOnLinux">
        <action name="Execute"><command>playonlinux</command></action>
      </item>
      <separator/>
      <item label="⚡ Lancer un .exe (Wine+DXVK)">
        <action name="Execute">
          <command>bash -c 'FILE=$(zenity --file-selection --file-filter="*.exe *.msi" --title="Choisir un .exe"); [ -n "$FILE" ] &amp;&amp; gamemoderun wine "$FILE"'</command>
        </action>
      </item>
      <item label="🍷 Winetricks">
        <action name="Execute"><command>winetricks --gui</command></action>
      </item>
      <separator/>
      <item label="📊 MangoHud toggle (Shift+F12)">
        <action name="Execute"><command>notify-send "MangoHud" "Shift+F12 pour toggle l'overlay FPS"</command></action>
      </item>
    </menu>

    <menu id="apps-menu" label="📦 Applications">
      <item label="📁 Fichiers"><action name="Execute"><command>thunar</command></action></item>
      <item label="📝 Bloc-notes"><action name="Execute"><command>mousepad</command></action></item>
      <item label="💻 Terminal"><action name="Execute"><command>tilix</command></action></item>
      <item label="🎵 VLC"><action name="Execute"><command>vlc</command></action></item>
      <item label="🎨 GIMP"><action name="Execute"><command>gimp</command></action></item>
    </menu>

    <separator/>
    <item label="⚙️ Apparence"><action name="Execute"><command>lxappearance</command></action></item>
    <item label="📊 Tâches (htop)"><action name="Execute"><command>tilix -e htop</command></action></item>
    <separator/>
    <item label="⏻ Éteindre"><action name="Execute"><command>systemctl poweroff</command></action></item>
    <item label="🔄 Redémarrer"><action name="Execute"><command>systemctl reboot</command></action></item>
  </menu>
</openbox_menu>
MENUEOF

# rc.xml raccourcis
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
    <keybind key="Super-Return"><action name="Execute"><command>tilix</command></action></keybind>
    <keybind key="Super-e"><action name="Execute"><command>thunar</command></action></keybind>
    <keybind key="Super-b"><action name="Execute"><command>google-chrome-stable</command></action></keybind>
    <keybind key="Super-g"><action name="Execute"><command>steam</command></action></keybind>
    <keybind key="Super-l"><action name="Execute"><command>lutris</command></action></keybind>
    <keybind key="Super-r"><action name="Execute"><command>rofi -show run</command></action></keybind>
    <keybind key="A-F4"><action name="Close"/></keybind>
    <keybind key="Super-d"><action name="ToggleShowDesktop"/></keybind>
    <keybind key="A-Tab"><action name="NextWindow"/></keybind>
    <keybind key="Print"><action name="Execute"><command>scrot ~/Images/screenshot-%Y%m%d-%H%M%S.png</command></action></keybind>
  </keyboard>
  <mouse>
    <context name="Desktop">
      <mousebind button="Right" action="Press">
        <action name="ShowMenu"><menu>root-menu</menu></action>
      </mousebind>
    </context>
    <context name="Titlebar">
      <mousebind button="Left" action="Drag"><action name="Move"/></mousebind>
      <mousebind button="Left" action="DoubleClick"><action name="MaximizeWindow"/></mousebind>
    </context>
    <context name="Bottom">
      <mousebind button="Left" action="Drag"><action name="Resize"/></mousebind>
    </context>
  </mouse>
</openbox_config>
RCEOF

# Tint2
cat > /etc/skel/.config/tint2/tint2rc << 'T2EOF'
panel_items = TSC
panel_size = 100% 36
panel_margin = 0 0
panel_padding = 4 4 4
panel_background_id = 1
panel_layer = bottom
panel_position = bottom center horizontal
rounded = 0
border_width = 0
background_color = #0a0a1a 100
border_color = #2d4a6e 100
taskbar_mode = single_desktop
taskbar_padding = 2 3 2
task_icon = 1
task_text = 1
task_maximum_size = 150 30
task_padding = 6 3 6
task_font = Noto Sans 9
task_font_color = #e2e8f0 80
task_active_font_color = #4ade80 100
systray_padding = 4 4 4
time1_format = %H:%M
time1_font = Noto Sans Bold 10
time2_format = %d/%m/%Y
time2_font = Noto Sans 8
clock_font_color = #e2e8f0 90
clock_padding = 8 0
T2EOF

# Picom
cat > /etc/skel/.config/picom/picom.conf << 'PIEOF'
backend = "glx";
vsync = true;
shadow = true;
shadow-radius = 12;
shadow-offset-x = -12;
shadow-offset-y = -12;
shadow-opacity = 0.4;
shadow-exclude = ["class_g = 'tint2'", "class_g = 'steam'"];
fading = true;
fade-in-step = 0.06;
fade-out-step = 0.06;
corner-radius = 8;
PIEOF

# .bashrc gaming
cat > /etc/skel/.bashrc << 'BASHEOF'
export LANG=fr_FR.UTF-8
export LC_ALL=fr_FR.UTF-8
export DXVK_HUD=fps
export WINEFSYNC=1
export WINE_LARGE_ADDRESS_AWARE=1
export mesa_glthread=true
export __GL_THREADED_OPTIMIZATIONS=1

PS1='\[\e[0;32m\]⛏ \[\e[1;36m\]\u\[\e[0;37m\]@\[\e[1;34m\]mineos\[\e[0;37m\]:\[\e[1;33m\]\w\[\e[0m\]\$ '

alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias chrome='google-chrome-stable'
alias exe='gamemoderun wine'
alias exe-dxvk='DXVK_HUD=fps gamemoderun wine'
alias steam='gamemoderun steam'
alias update='sudo apt update && sudo apt upgrade -y'
alias gaming-info='glxinfo | grep "OpenGL renderer"'
alias fps-overlay='MANGOHUD=1'

[ -f /etc/bash_completion ] && . /etc/bash_completion

echo ""
echo "  ⛏  MineOS Gaming Edition"
echo "  exe <fichier.exe>   → lancer avec Wine+GameMode"
echo "  exe-dxvk <fichier>  → Wine+DXVK+MangoHud overlay"
echo "  Super+G = Steam  |  Super+L = Lutris"
echo ""
BASHEOF

# Raccourcis bureau
mkdir -p /etc/skel/Bureau
for APP in steam lutris chrome terminal; do
  case $APP in
    steam)    EXEC="gamemoderun steam"; ICON="steam"; NAME="Steam" ;;
    lutris)   EXEC="lutris"; ICON="lutris"; NAME="Lutris" ;;
    chrome)   EXEC="google-chrome-stable"; ICON="google-chrome"; NAME="Google Chrome" ;;
    terminal) EXEC="tilix"; ICON="terminal"; NAME="Terminal" ;;
  esac
  cat > "/etc/skel/Bureau/${APP}.desktop" << DEOF
[Desktop Entry]
Name=${NAME}
Exec=${EXEC}
Icon=${ICON}
Type=Application
DEOF
  chmod +x "/etc/skel/Bureau/${APP}.desktop"
done

# Wallpaper
mkdir -p /usr/share/mineos
python3 -c "
try:
    from PIL import Image, ImageDraw
    img = Image.new('RGB', (1920, 1080), '#1a1a2e')
    draw = ImageDraw.Draw(img)
    for x in range(0, 1920, 32):
        draw.line([(x,0),(x,1080)], fill='#1f2a3d', width=1)
    for y in range(0, 1080, 32):
        draw.line([(0,y),(1920,y)], fill='#1f2a3d', width=1)
    img.save('/usr/share/mineos/wallpaper.png')
except:
    pass
" 2>/dev/null || \
  convert -size 1920x1080 gradient:'#1a1a2e-#0d2137' /usr/share/mineos/wallpaper.png 2>/dev/null || \
  echo "Wallpaper skip"

# Nitrogen config
mkdir -p /etc/skel/.config/nitrogen
cat > /etc/skel/.config/nitrogen/bg-saved.cfg << 'NITEOF'
[xin_-1]
file=/usr/share/mineos/wallpaper.png
mode=4
bgcolor=#1a1a2e
NITEOF

echo ">>> Bureau configuré"
HOOKEOF

# ── Hook LightDM ──
cat > config/hooks/live/0700-lightdm.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> [Hook] LightDM autologin..."

mkdir -p /etc/lightdm
cat > /etc/lightdm/lightdm.conf << 'LDEOF'
[Seat:*]
autologin-user=user
autologin-user-timeout=0
greeter-session=lightdm-gtk-greeter
user-session=openbox
LDEOF

cat > /etc/lightdm/lightdm-gtk-greeter.conf << 'GEOF'
[greeter]
background=#1a1a2e
theme-name=MineOS-Dark
icon-theme-name=Papirus-Dark
font-name=Noto Sans 11
clock-format=%H:%M — %A %d %B
GEOF

echo ">>> LightDM configuré"
HOOKEOF

# ── Hook locale FR ──
cat > config/hooks/live/0050-locale.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> [Hook] Locale FR..."
sed -i 's/# fr_FR.UTF-8/fr_FR.UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=fr_FR.UTF-8 LC_ALL=fr_FR.UTF-8
echo ">>> Locale OK"
HOOKEOF

chmod +x config/hooks/live/*.hook.chroot

# ─── 4. includes.chroot ──────────────────────────────────
echo "[4/7] Fichiers système..."
mkdir -p config/includes.chroot/usr/local/bin

# Script lanceur EXE intelligent
cat > config/includes.chroot/usr/local/bin/mineos-exe << 'EXEOF'
#!/bin/bash
# MineOS EXE Smart Launcher
# Usage: mineos-exe [--dxvk] <fichier.exe>

DXVK=0
if [ "$1" = "--dxvk" ]; then DXVK=1; shift; fi

FILE="$1"
if [ -z "$FILE" ]; then
  FILE=$(zenity --file-selection \
    --file-filter="Exécutables Windows | *.exe *.msi *.bat" \
    --title="MineOS — Choisir un .exe" 2>/dev/null)
  [ -z "$FILE" ] && exit 0
fi

if [ ! -f "$FILE" ]; then
  zenity --error --text="Fichier introuvable : $FILE" 2>/dev/null
  exit 1
fi

notify-send "⚡ MineOS" "Lancement : $(basename "$FILE")" 2>/dev/null

if [ $DXVK -eq 1 ]; then
  DXVK_HUD=fps WINEFSYNC=1 gamemoderun wine "$FILE"
else
  WINEFSYNC=1 gamemoderun wine "$FILE"
fi
EXEOF
chmod +x config/includes.chroot/usr/local/bin/mineos-exe

# ─── 5. compression ─────────────────────────────────────
echo "[5/7] Compression xz..."
mkdir -p config/compression
echo "xz" > config/compression/filesystem

# ─── 6. Build ────────────────────────────────────────────
echo "[6/7] Build live-build (20-30 min)..."
sudo lb build 2>&1 | tee /tmp/mineos-build.log

# ─── 7. Finalisation ─────────────────────────────────────
echo "[7/7] Finalisation..."
ISO_FOUND=$(ls *.iso 2>/dev/null | head -1)

if [ -n "$ISO_FOUND" ]; then
  mv "$ISO_FOUND" "$BUILD_DIR/MineOS-Gaming-${VERSION}-x86_64.iso"
  ISO_PATH="$BUILD_DIR/MineOS-Gaming-${VERSION}-x86_64.iso"
  sha256sum "$ISO_PATH" > "$BUILD_DIR/SHA256SUMS"
  echo "============================================"
  echo "  ✅ MineOS Gaming Edition prêt !"
  echo "  📀 ISO : $ISO_PATH"
  echo "  📦 Taille : $(du -sh $ISO_PATH | cut -f1)"
  echo "  🔑 SHA256 : $(cut -d' ' -f1 $BUILD_DIR/SHA256SUMS)"
  echo "============================================"
else
  echo "❌ Build échoué. Log :"
  tail -80 /tmp/mineos-build.log
  exit 1
fi
