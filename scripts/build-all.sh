#!/bin/bash
# ============================================================
#  MineOS Gaming Edition — Build complet
#  Tourne entièrement en root (appelé via sudo depuis CI)
# ============================================================
set -euo pipefail

VERSION="${1:-1.0.0}"
BUILD_DIR="/opt/mineos-build"
OUT_DIR="/opt/mineos-output"

echo "============================================"
echo "  MineOS Gaming v${VERSION}"
echo "============================================"

# Nettoyer et créer les dossiers de travail
rm -rf "$BUILD_DIR" "$OUT_DIR"
mkdir -p "$BUILD_DIR" "$OUT_DIR"
cd "$BUILD_DIR"

# ─────────────────────────────────────────────
# ÉTAPE 0 : Forcer Debian (évite ubuntu mirror)
# ─────────────────────────────────────────────
echo ""
echo "[0/8] Override mirror Debian (fix Ubuntu runner)..."

# live-build lit /etc/live/build.conf en priorité — on force tout ici
mkdir -p /etc/live
cat > /etc/live/build.conf << 'EOF'
LB_MIRROR_BOOTSTRAP="http://deb.debian.org/debian"
LB_MIRROR_BINARY="http://deb.debian.org/debian"
LB_MIRROR_BINARY_SECURITY="http://security.debian.org/debian-security"
LB_MIRROR_CHROOT="http://deb.debian.org/debian"
LB_MIRROR_CHROOT_SECURITY="http://security.debian.org/debian-security"
LB_MIRROR_CHROOT_UPDATES="http://deb.debian.org/debian"
EOF

echo "Mirror config forcé : $(cat /etc/live/build.conf)"

# ─────────────────────────────────────────────
# ÉTAPE 1 : lb config
# ─────────────────────────────────────────────
echo ""
echo "[1/8] lb config..."
lb config \
  --architectures amd64 \
  --distribution bookworm \
  --debian-installer none \
  --binary-images iso-hybrid \
  --memtest none \
  --apt-recommends false \
  --archive-areas "main contrib non-free non-free-firmware" \
  --mirror-bootstrap "http://deb.debian.org/debian" \
  --mirror-chroot "http://deb.debian.org/debian" \
  --mirror-chroot-security "http://security.debian.org/debian-security" \
  --mirror-chroot-updates "http://deb.debian.org/debian" \
  --mirror-binary "http://deb.debian.org/debian" \
  --mirror-binary-security "http://security.debian.org/debian-security" \
  --iso-application "MineOS Gaming" \
  --iso-publisher "MineOS Project" \
  --iso-volume "MineOS-${VERSION}" \
  --bootappend-live "boot=live components quiet splash hostname=mineos username=user"

echo "lb config OK"

# ─────────────────────────────────────────────
# ÉTAPE 2 : Hostname (maintenant on est root = pas de permission denied)
# ─────────────────────────────────────────────
echo ""
echo "[2/8] Hostname & hosts..."
mkdir -p config/includes.chroot/etc
echo "mineos" > config/includes.chroot/etc/hostname
cat > config/includes.chroot/etc/hosts << 'EOF'
127.0.0.1   localhost
127.0.1.1   mineos
::1         localhost ip6-localhost ip6-loopback
EOF

# ─────────────────────────────────────────────
# ÉTAPE 3 : Listes de paquets
# ─────────────────────────────────────────────
echo ""
echo "[3/8] Paquets..."
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
lutris
EOF

# ─────────────────────────────────────────────
# ÉTAPE 4 : Hooks
# ─────────────────────────────────────────────
echo ""
echo "[4/8] Hooks..."
mkdir -p config/hooks/live

# ── Locale FR ──────────────────────────────────────────────
cat > config/hooks/live/0050-locale.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
sed -i 's/# fr_FR.UTF-8/fr_FR.UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=fr_FR.UTF-8 LC_ALL=fr_FR.UTF-8
HOOKEOF

# ── Google Chrome ───────────────────────────────────────────
cat > config/hooks/live/0100-chrome.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> Chrome..."
wget -qO /tmp/chrome.deb \
  "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
apt-get install -y /tmp/chrome.deb || apt-get install -f -y
rm -f /tmp/chrome.deb
echo ">>> Chrome OK"
HOOKEOF

# ── Wine 32bit + DXVK ──────────────────────────────────────
cat > config/hooks/live/0200-wine.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> Wine + DXVK..."
dpkg --add-architecture i386
apt-get update -qq
apt-get install -y wine32 libwine:i386 fonts-wine \
  libvulkan1:i386 libgl1-mesa-dri:i386 2>/dev/null || true

DXVK_VER="2.3.1"
wget -qO /tmp/dxvk.tar.gz \
  "https://github.com/doitsujin/dxvk/releases/download/v${DXVK_VER}/dxvk-${DXVK_VER}.tar.gz" \
  || { echo "DXVK download failed, skip"; exit 0; }
mkdir -p /tmp/dxvk
tar -xzf /tmp/dxvk.tar.gz -C /tmp/dxvk --strip-components=1
mkdir -p /usr/share/dxvk
cp -r /tmp/dxvk/x32 /tmp/dxvk/x64 /usr/share/dxvk/
rm -rf /tmp/dxvk*

cat > /usr/local/bin/wine-dxvk-setup << 'EOF'
#!/bin/bash
PREFIX="${WINEPREFIX:-$HOME/.wine}"
cp /usr/share/dxvk/x64/*.dll "$PREFIX/drive_c/windows/system32/" 2>/dev/null || true
cp /usr/share/dxvk/x32/*.dll "$PREFIX/drive_c/windows/syswow64/" 2>/dev/null || true
echo "DXVK active dans $PREFIX"
EOF
chmod +x /usr/local/bin/wine-dxvk-setup

cat > /usr/share/applications/wine-exe.desktop << 'EOF'
[Desktop Entry]
Name=Wine EXE Launcher
Exec=wine %f
MimeType=application/x-ms-dos-executable;application/x-msi;
Icon=wine
Type=Application
NoDisplay=true
EOF
update-desktop-database 2>/dev/null || true
echo ">>> Wine + DXVK OK"
HOOKEOF

# ── Kernel Liquorix ─────────────────────────────────────────
cat > config/hooks/live/0250-kernel.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> Kernel Liquorix..."
wget -qO /tmp/liq.gpg "https://liquorix.net/liquorix-keyring.gpg" \
  || { echo "Liquorix GPG echec, kernel Debian conserve"; exit 0; }
install -D -m 644 /tmp/liq.gpg /usr/share/keyrings/liquorix-keyring.gpg
. /etc/os-release
echo "deb [signed-by=/usr/share/keyrings/liquorix-keyring.gpg] https://liquorix.net/debian ${VERSION_CODENAME} main" \
  > /etc/apt/sources.list.d/liquorix.list
apt-get update -qq
apt-get install -y linux-image-liquorix-amd64 linux-headers-liquorix-amd64 \
  || echo "Liquorix indispo, kernel Debian conserve"
HOOKEOF

# ── Steam ───────────────────────────────────────────────────
cat > config/hooks/live/0300-steam.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> Steam..."
dpkg --add-architecture i386
apt-get update -qq
apt-get install -y steam-installer 2>/dev/null || {
  wget -qO /tmp/steam.deb \
    "https://cdn.cloudflare.steamstatic.com/client/installer/steam.deb"
  apt-get install -y /tmp/steam.deb || true
  apt-get install -f -y || true
  rm -f /tmp/steam.deb
}
echo ">>> Steam OK"
HOOKEOF

# ── GameMode + MangoHud ─────────────────────────────────────
cat > config/hooks/live/0400-gamemode.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> GameMode + MangoHud..."
apt-get install -y gamemode mangohud 2>/dev/null || true

cat > /etc/gamemode.ini << 'EOF'
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

[filter]
whitelist=steam;lutris;wine;playonlinux
EOF

mkdir -p /etc/MangoHud
cat > /etc/MangoHud/MangoHud.conf << 'EOF'
fps
frame_timing
cpu_load
gpu_load
ram
cpu_temp
gpu_temp
position=top-left
font_size=18
background_alpha=0.5
toggle_hud=Shift_R+F12
EOF
echo ">>> GameMode + MangoHud OK"
HOOKEOF

# ── GPU universel NVIDIA / AMD / Intel ──────────────────────
cat > config/hooks/live/0500-gpu.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> Drivers GPU universels..."

GPU_INFO=$(lspci 2>/dev/null | grep -iE "VGA|3D|Display" || true)
HAS_NVIDIA=$(echo "$GPU_INFO" | grep -ic "nvidia" || true)
HAS_AMD=$(echo "$GPU_INFO"   | grep -icE "amd|radeon|ati" || true)

echo "GPU detecte : $GPU_INFO"

# ── NVIDIA ──
if [ "$HAS_NVIDIA" -gt 0 ]; then
  echo ">>> NVIDIA drivers..."
  apt-get update -qq
  apt-get install -y nvidia-driver nvidia-settings libvulkan1 vulkan-tools 2>/dev/null || true

  cat > /etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

  mkdir -p /etc/X11/xorg.conf.d
  cat > /etc/X11/xorg.conf.d/20-nvidia.conf << 'EOF'
Section "Device"
  Identifier "NVIDIA Card"
  Driver "nvidia"
  Option "NoLogo" "1"
  Option "TripleBuffer" "1"
  Option "AllowIndirectGLXProtocol" "0"
EndSection
EOF

  cat >> /etc/environment << 'EOF'
__GL_THREADED_OPTIMIZATIONS=1
__GL_MaxFramesAllowed=1
EOF
  update-initramfs -u 2>/dev/null || true
  echo ">>> NVIDIA OK"

# ── AMD ──
elif [ "$HAS_AMD" -gt 0 ]; then
  echo ">>> AMD drivers..."
  apt-get update -qq
  apt-get install -y firmware-amd-graphics libgl1-mesa-dri \
    mesa-vulkan-drivers mesa-va-drivers mesa-vdpau-drivers \
    libvulkan1 vulkan-tools radeontop 2>/dev/null || true

  cat > /etc/modprobe.d/amdgpu.conf << 'EOF'
options amdgpu si_support=1
options amdgpu cik_support=1
options amdgpu dpm=1
options amdgpu dc=1
options amdgpu ppfeaturemask=0xffffffff
blacklist radeon
EOF

  cat >> /etc/environment << 'EOF'
RADV_PERFTEST=aco,ngg
AMD_VULKAN_ICD=RADV
mesa_glthread=true
EOF

  sed -i 's/\[gpu\]/[gpu]\namd_performance_level=high/' /etc/gamemode.ini 2>/dev/null || true
  echo ">>> AMD OK"

# ── INTEL (defaut) ──
else
  echo ">>> Intel drivers (defaut)..."
  apt-get update -qq
  apt-get install -y firmware-misc-nonfree intel-media-va-driver \
    libva-drm2 libva-x11-2 libgl1-mesa-dri \
    mesa-vulkan-drivers libvulkan1 vulkan-tools 2>/dev/null || true

  cat > /etc/modprobe.d/i915-gaming.conf << 'EOF'
options i915 enable_guc=3
options i915 enable_fbc=1
options i915 enable_psr=1
options i915 fastboot=1
options i915 nuclear_pageflip=1
EOF

  cat >> /etc/environment << 'EOF'
MESA_LOADER_DRIVER_OVERRIDE=iris
mesa_glthread=true
vblank_mode=0
EOF
  echo ">>> Intel OK"
fi

# ── Vulkan ICD auto-selector (lancé au login) ──
cat > /usr/local/bin/mineos-vulkan-setup << 'EOF'
#!/bin/bash
GPU=$(lspci 2>/dev/null | grep -iE "VGA|3D" | head -1)
if echo "$GPU" | grep -qi nvidia; then
  export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json
elif echo "$GPU" | grep -qiE "amd|radeon"; then
  export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json
else
  export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/intel_icd.x86_64.json
fi
EOF
chmod +x /usr/local/bin/mineos-vulkan-setup

# ── Script info GPU (commande 'gpu' dans terminal) ──
cat > /usr/local/bin/mineos-gpu-info << 'EOF'
#!/bin/bash
echo "=== MineOS GPU Info ==="
lspci | grep -iE "VGA|3D|Display"
echo ""
glxinfo 2>/dev/null | grep -E "renderer|version" | head -4 || echo "glxinfo non dispo"
echo ""
vulkaninfo 2>/dev/null | grep deviceName | head -2 || echo "vulkaninfo non dispo"
echo ""
cat /sys/class/drm/card0/device/mem_info_vram_total 2>/dev/null \
  | awk '{printf "VRAM: %.0f MB\n", $1/1048576}' || true
nvidia-smi --query-gpu=name,memory.total,temperature.gpu \
  --format=csv,noheader 2>/dev/null || true
EOF
chmod +x /usr/local/bin/mineos-gpu-info
echo ">>> GPU universel OK"
HOOKEOF

# ── Tweaks système ──────────────────────────────────────────
cat > config/hooks/live/0550-tweaks.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> Tweaks systeme..."

cat > /etc/sysctl.d/99-mineos-gaming.conf << 'EOF'
vm.swappiness=10
vm.dirty_ratio=15
vm.dirty_background_ratio=5
kernel.sched_autogroup_enabled=1
fs.file-max=2097152
EOF

cat >> /etc/security/limits.conf << 'EOF'
* soft nofile 1048576
* hard nofile 1048576
* soft memlock unlimited
* hard memlock unlimited
EOF

mkdir -p /etc/pulse
cat > /etc/pulse/daemon.conf << 'EOF'
default-sample-rate = 48000
alternate-sample-rate = 44100
default-fragment-size-msec = 5
default-fragments = 2
realtime-scheduling = yes
realtime-priority = 9
high-priority = yes
nice-level = -15
EOF
echo ">>> Tweaks OK"
HOOKEOF

# ── Bureau Openbox ──────────────────────────────────────────
cat > config/hooks/live/0600-desktop.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> Bureau MineOS..."

mkdir -p /etc/skel/.config/{openbox,tint2,picom,nitrogen}
mkdir -p /etc/skel/{Bureau,Documents,Images,Musique,Telecharges,Jeux}
mkdir -p /usr/share/themes/MineOS-Dark/{gtk-3.0,gtk-2.0}

# Thème GTK3
cat > /usr/share/themes/MineOS-Dark/gtk-3.0/gtk.css << 'EOF'
@define-color bg_color #1a1a2e;
@define-color fg_color #e2e8f0;
@define-color base_color #16213e;
@define-color selected_bg_color #4ade80;
@define-color selected_fg_color #0d1117;
window,.background{background-color:@bg_color;color:@fg_color}
headerbar,.titlebar{background:#0d2137;border-bottom:1px solid #2d4a6e}
button{background:rgba(74,222,128,.1);border:1px solid #2d4a6e;border-radius:4px;color:@fg_color}
button:hover{background:rgba(74,222,128,.2);border-color:#4ade80}
entry{background:rgba(0,0,0,.4);border:1px solid #2d4a6e;border-radius:4px;color:#22d3ee}
treeview,.view{background:@base_color;color:@fg_color}
treeview:selected{background:rgba(74,222,128,.15);color:#4ade80}
EOF

# GTK2
cat > /usr/share/themes/MineOS-Dark/gtk-2.0/gtkrc << 'EOF'
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
EOF

# Openbox autostart
cat > /etc/skel/.config/openbox/autostart << 'EOF'
nitrogen --restore &
picom --config ~/.config/picom/picom.conf &
tint2 &
nm-applet &
dunst &
pulseaudio --start &
xdg-user-dirs-update &
/usr/lib/gamemode/gamemoded 2>/dev/null &
source /usr/local/bin/mineos-vulkan-setup 2>/dev/null
EOF

# Menu clic droit
cat > /etc/skel/.config/openbox/menu.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu>
  <menu id="root-menu" label="MineOS">
    <item label="Chrome">
      <action name="Execute"><command>google-chrome-stable</command></action>
    </item>
    <menu id="gaming-menu" label="Gaming">
      <item label="Steam">
        <action name="Execute"><command>gamemoderun steam</command></action>
      </item>
      <item label="Lutris">
        <action name="Execute"><command>lutris</command></action>
      </item>
      <item label="PlayOnLinux">
        <action name="Execute"><command>playonlinux</command></action>
      </item>
      <item label="Lancer .exe (Wine)">
        <action name="Execute"><command>mineos-exe</command></action>
      </item>
      <item label="Winetricks">
        <action name="Execute"><command>winetricks --gui</command></action>
      </item>
    </menu>
    <item label="Fichiers">
      <action name="Execute"><command>thunar</command></action>
    </item>
    <item label="Terminal">
      <action name="Execute"><command>tilix</command></action>
    </item>
    <item label="Bloc-notes">
      <action name="Execute"><command>mousepad</command></action>
    </item>
    <item label="VLC">
      <action name="Execute"><command>vlc</command></action>
    </item>
    <item label="GPU Info">
      <action name="Execute"><command>tilix -e mineos-gpu-info</command></action>
    </item>
    <separator/>
    <item label="Apparence">
      <action name="Execute"><command>lxappearance</command></action>
    </item>
    <separator/>
    <item label="Eteindre">
      <action name="Execute"><command>systemctl poweroff</command></action>
    </item>
    <item label="Redemarrer">
      <action name="Execute"><command>systemctl reboot</command></action>
    </item>
  </menu>
</openbox_menu>
EOF

# Raccourcis clavier
cat > /etc/skel/.config/openbox/rc.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config>
  <theme>
    <name>MineOS-Dark</name>
    <font place="ActiveWindow">
      <name>Noto Sans</name><size>10</size><weight>Bold</weight>
    </font>
    <font place="InactiveWindow">
      <name>Noto Sans</name><size>10</size>
    </font>
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
    <keybind key="Super-g">
      <action name="Execute"><command>gamemoderun steam</command></action>
    </keybind>
    <keybind key="Super-l">
      <action name="Execute"><command>lutris</command></action>
    </keybind>
    <keybind key="Super-r">
      <action name="Execute"><command>rofi -show run</command></action>
    </keybind>
    <keybind key="A-F4"><action name="Close"/></keybind>
    <keybind key="Super-d"><action name="ToggleShowDesktop"/></keybind>
    <keybind key="A-Tab"><action name="NextWindow"/></keybind>
    <keybind key="Print">
      <action name="Execute">
        <command>scrot ~/Images/screenshot-%Y%m%d-%H%M%S.png</command>
      </action>
    </keybind>
  </keyboard>
  <mouse>
    <context name="Desktop">
      <mousebind button="Right" action="Press">
        <action name="ShowMenu"><menu>root-menu</menu></action>
      </mousebind>
    </context>
    <context name="Titlebar">
      <mousebind button="Left" action="Drag"><action name="Move"/></mousebind>
      <mousebind button="Left" action="DoubleClick">
        <action name="MaximizeWindow"/>
      </mousebind>
    </context>
  </mouse>
</openbox_config>
EOF

# Tint2 barre des taches
cat > /etc/skel/.config/tint2/tint2rc << 'EOF'
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
EOF

# Picom (transparence + ombres)
cat > /etc/skel/.config/picom/picom.conf << 'EOF'
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
EOF

# .bashrc
cat > /etc/skel/.bashrc << 'EOF'
export LANG=fr_FR.UTF-8
export WINEFSYNC=1
export mesa_glthread=true
PS1='\[\e[0;32m\]mining \[\e[1;36m\]\u\[\e[0;37m\]@\[\e[1;34m\]mineos\[\e[0;37m\]:\[\e[1;33m\]\w\[\e[0m\]\$ '
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias chrome='google-chrome-stable'
alias exe='gamemoderun wine'
alias exe-dxvk='DXVK_HUD=fps gamemoderun wine'
alias steam='gamemoderun steam'
alias gpu='mineos-gpu-info'
alias dxvk='wine-dxvk-setup'
[ -f /etc/bash_completion ] && . /etc/bash_completion
source /usr/local/bin/mineos-vulkan-setup 2>/dev/null
echo ""
echo "  MineOS Gaming Edition"
echo "  exe <fichier.exe>  |  gpu  |  Super+G=Steam  |  Shift+F12=MangoHud"
echo ""
EOF

# Raccourcis bureau
for APP in steam lutris chrome terminal; do
  case $APP in
    steam)    EXEC="gamemoderun steam"; ICON="steam";           NAME="Steam"     ;;
    lutris)   EXEC="lutris";            ICON="lutris";          NAME="Lutris"    ;;
    chrome)   EXEC="google-chrome-stable"; ICON="google-chrome"; NAME="Chrome"  ;;
    terminal) EXEC="tilix";             ICON="terminal";        NAME="Terminal"  ;;
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
from PIL import Image, ImageDraw
img = Image.new('RGB', (1920, 1080), '#1a1a2e')
d = ImageDraw.Draw(img)
for x in range(0, 1920, 32):
    d.line([(x,0),(x,1080)], fill='#1f2a3d')
for y in range(0, 1080, 32):
    d.line([(0,y),(1920,y)], fill='#1f2a3d')
img.save('/usr/share/mineos/wallpaper.png')
" 2>/dev/null || \
convert -size 1920x1080 gradient:'#1a1a2e-#0d2137' \
  /usr/share/mineos/wallpaper.png 2>/dev/null || true

mkdir -p /etc/skel/.config/nitrogen
cat > /etc/skel/.config/nitrogen/bg-saved.cfg << 'EOF'
[xin_-1]
file=/usr/share/mineos/wallpaper.png
mode=4
bgcolor=#1a1a2e
EOF

# Script lanceur EXE
cat > /usr/local/bin/mineos-exe << 'EOF'
#!/bin/bash
FILE="$1"
if [ -z "$FILE" ]; then
  FILE=$(zenity --file-selection \
    --file-filter="Executables | *.exe *.msi *.bat" \
    --title="MineOS - Choisir un .exe" 2>/dev/null)
  [ -z "$FILE" ] && exit 0
fi
[ ! -f "$FILE" ] && { zenity --error --text="Fichier introuvable : $FILE" 2>/dev/null; exit 1; }
notify-send "MineOS" "Lancement : $(basename "$FILE")" 2>/dev/null
WINEFSYNC=1 gamemoderun wine "$FILE"
EOF
chmod +x /usr/local/bin/mineos-exe
echo ">>> Bureau OK"
HOOKEOF

# ── LightDM autologin ───────────────────────────────────────
cat > config/hooks/live/0700-lightdm.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> LightDM..."
mkdir -p /etc/lightdm
cat > /etc/lightdm/lightdm.conf << 'EOF'
[Seat:*]
autologin-user=user
autologin-user-timeout=0
greeter-session=lightdm-gtk-greeter
user-session=openbox
EOF
cat > /etc/lightdm/lightdm-gtk-greeter.conf << 'EOF'
[greeter]
background=#1a1a2e
theme-name=MineOS-Dark
icon-theme-name=Papirus-Dark
font-name=Noto Sans 11
clock-format=%H:%M - %A %d %B
EOF
echo ">>> LightDM OK"
HOOKEOF

# Rendre tous les hooks exécutables
chmod +x config/hooks/live/*.hook.chroot

# ─────────────────────────────────────────────
# ÉTAPE 5 : Includes (fichiers copiés dans le rootfs)
# ─────────────────────────────────────────────
echo ""
echo "[5/8] Includes..."
mkdir -p config/includes.chroot/usr/local/bin

# Copie anticipée de mineos-exe (backup si hook échoue)
cat > config/includes.chroot/usr/local/bin/mineos-exe << 'EOF'
#!/bin/bash
FILE="$1"
if [ -z "$FILE" ]; then
  FILE=$(zenity --file-selection \
    --file-filter="Executables | *.exe *.msi *.bat" \
    --title="MineOS - Choisir un .exe" 2>/dev/null)
  [ -z "$FILE" ] && exit 0
fi
notify-send "MineOS" "Lancement : $(basename "$FILE")" 2>/dev/null
WINEFSYNC=1 gamemoderun wine "$FILE"
EOF
chmod +x config/includes.chroot/usr/local/bin/mineos-exe

# ─────────────────────────────────────────────
# ÉTAPE 6 : Compression
# ─────────────────────────────────────────────
echo ""
echo "[6/8] Compression xz..."
mkdir -p config/compression
echo "xz" > config/compression/filesystem

# ─────────────────────────────────────────────
# ÉTAPE 7 : lb build
# ─────────────────────────────────────────────
echo ""
echo "[7/8] lb build (20-30 min)..."
lb build 2>&1 | tee /tmp/lb-build.log

# ─────────────────────────────────────────────
# ÉTAPE 8 : Collecte ISO
# ─────────────────────────────────────────────
echo ""
echo "[8/8] Collecte ISO..."
ISO=$(find "$BUILD_DIR" -name "*.iso" 2>/dev/null | head -1)
if [ -z "$ISO" ]; then
  echo "ERREUR : ISO introuvable. Dernieres lignes du log :"
  tail -100 /tmp/lb-build.log
  exit 1
fi

cp "$ISO" "$OUT_DIR/MineOS-Gaming-${VERSION}-x86_64.iso"
sha256sum "$OUT_DIR/MineOS-Gaming-${VERSION}-x86_64.iso" > "$OUT_DIR/SHA256SUMS"

echo ""
echo "============================================"
echo "  ISO : $OUT_DIR/MineOS-Gaming-${VERSION}-x86_64.iso"
echo "  Taille : $(du -sh $OUT_DIR/MineOS-Gaming-${VERSION}-x86_64.iso | cut -f1)"
echo "  SHA256 : $(cut -d' ' -f1 $OUT_DIR/SHA256SUMS)"
echo "============================================"
