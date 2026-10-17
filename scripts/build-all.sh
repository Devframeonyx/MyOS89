#!/bin/bash
# ============================================================
#  MineOS Gaming Edition — Build Ubuntu 22.04 (Jammy)
#  XFCE + Opera GX + Store apps + Personnalisation
# ============================================================
set -uo pipefail
# Pas de -e : lb_chroot_hacks peut retourner des warnings non-fatals (chmod symlinks)
# Ces erreurs sont gérées manuellement dans l'étape lb build (voir étape 7).

VERSION="${1:-1.0.0}"
BUILD_DIR="/opt/mineos-build"
OUT_DIR="/opt/mineos-output"

echo "============================================"
echo "  MineOS Gaming v${VERSION} [Ubuntu Jammy]"
echo "============================================"

rm -rf "$BUILD_DIR" "$OUT_DIR"
mkdir -p "$BUILD_DIR" "$OUT_DIR"
cd "$BUILD_DIR"

# ─────────────────────────────────────────────
# ÉTAPE 0 : Config live-build pour Ubuntu
# ─────────────────────────────────────────────
echo "[0/9] Configuration mirrors Ubuntu..."
mkdir -p /etc/live
cat > /etc/live/build.conf << 'EOF'
LB_MIRROR_BOOTSTRAP="http://archive.ubuntu.com/ubuntu"
LB_MIRROR_BINARY="http://archive.ubuntu.com/ubuntu"
LB_MIRROR_BINARY_SECURITY="http://security.ubuntu.com/ubuntu"
LB_MIRROR_CHROOT="http://archive.ubuntu.com/ubuntu"
LB_MIRROR_CHROOT_SECURITY="http://security.ubuntu.com/ubuntu"
LB_PARENT_DISTRIBUTION="jammy"
LB_PARENT_MIRROR_BOOTSTRAP="http://archive.ubuntu.com/ubuntu"
LB_PARENT_MIRROR_CHROOT="http://archive.ubuntu.com/ubuntu"
LB_PARENT_MIRROR_CHROOT_SECURITY="http://security.ubuntu.com/ubuntu"
LB_PARENT_MIRROR_BINARY="http://archive.ubuntu.com/ubuntu"
LB_PARENT_MIRROR_BINARY_SECURITY="http://security.ubuntu.com/ubuntu"
EOF

export LB_PARENT_DISTRIBUTION=jammy
export LB_PARENT_MIRROR_BOOTSTRAP="http://archive.ubuntu.com/ubuntu"
export LB_PARENT_MIRROR_CHROOT="http://archive.ubuntu.com/ubuntu"
export LB_PARENT_MIRROR_CHROOT_SECURITY="http://security.ubuntu.com/ubuntu"
export LB_PARENT_MIRROR_BINARY="http://archive.ubuntu.com/ubuntu"
export LB_PARENT_MIRROR_BINARY_SECURITY="http://security.ubuntu.com/ubuntu"

# ─────────────────────────────────────────────
# ÉTAPE 1 : lb config
# ─────────────────────────────────────────────
echo "[1/9] lb config (Ubuntu Jammy)..."
lb config \
  --architectures amd64 \
  --distribution jammy \
  --debian-installer none \
  --binary-images iso-hybrid \
  --memtest none \
  --apt-recommends false \
  --archive-areas "main restricted universe multiverse" \
  --mirror-bootstrap "http://archive.ubuntu.com/ubuntu" \
  --mirror-chroot "http://archive.ubuntu.com/ubuntu" \
  --mirror-chroot-security "http://security.ubuntu.com/ubuntu" \
  --mirror-binary "http://archive.ubuntu.com/ubuntu" \
  --mirror-binary-security "http://security.ubuntu.com/ubuntu" \
  --iso-application "MineOS Gaming" \
  --iso-publisher "MineOS Project" \
  --iso-volume "MineOS-${VERSION}" \
  --bootappend-live "boot=live components quiet splash hostname=mineos username=user"

echo "[1b/9] Sources Ubuntu + keyring..."

# Sources Ubuntu (main restricted universe multiverse + security + updates)
mkdir -p config/archives
cat > config/archives/ubuntu.list.chroot << 'EOF'
deb http://archive.ubuntu.com/ubuntu jammy main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu jammy-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu jammy-security main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu jammy-backports main restricted universe multiverse
EOF

# Préférences : s'assurer qu'on utilise bien Ubuntu
cat > config/archives/ubuntu.pref.chroot << 'EOF'
Package: *
Pin: release o=Ubuntu
Pin-Priority: 990
EOF

echo "Sources Ubuntu OK"

# ─────────────────────────────────────────────
# ÉTAPE 2 : Hostname
# ─────────────────────────────────────────────
echo "[2/9] Hostname..."
mkdir -p config/includes.chroot/etc
echo "mineos" > config/includes.chroot/etc/hostname
cat > config/includes.chroot/etc/hosts << 'EOF'
127.0.0.1   localhost
127.0.1.1   mineos
::1         localhost ip6-localhost ip6-loopback
EOF

# ─────────────────────────────────────────────
# ÉTAPE 3 : Paquets
# ─────────────────────────────────────────────
echo "[3/9] Paquets..."
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
ubuntu-keyring
linux-image-generic
linux-headers-generic
EOF
# IMPORTANT : linux-image-generic doit être dans la liste de paquets (pas un hook).
# initramfs-tools et casper s'installent pendant lb_chroot_live-packages et
# déclenchent le trigger update-initramfs. Sans kernel installé à ce moment,
# /boot/initrd.img et /boot/initrd.img.old sont des symlinks cassés.
# lb_chroot_hacks tente ensuite un chmod dessus → exit 123.
# Avec linux-image-generic ici, le trigger trouve un kernel et génère l'initramfs
# AVANT que lb_chroot_hacks ne tourne. Le hook Liquorix (0250) remplace ensuite
# ce kernel par la version gaming.

# Paquets boot EFI + BIOS (nécessaires pour iso-hybrid bootable sur vrai PC)
cat > config/package-lists/00-boot.list.chroot << 'EOF'
grub-efi-amd64
grub-efi-amd64-bin
grub-pc-bin
shim-signed
mtools
syslinux
syslinux-common
isolinux
efibootmgr
EOF

cat > config/package-lists/01-xfce.list.chroot << 'EOF'
xfce4
xfce4-goodies
xfce4-panel
xfce4-session
xfce4-settings
xfce4-terminal
xfce4-whiskermenu-plugin
xfce4-notifyd
xfce4-screenshooter
xfce4-taskmanager
xfce4-power-manager
xfce4-clipman-plugin
xfce4-pulseaudio-plugin
thunar
thunar-archive-plugin
thunar-volman
gvfs
gvfs-backends
udisks2
lightdm
lightdm-gtk-greeter
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
gtk2-engines-murrine
gtk2-engines-pixbuf
EOF

cat > config/package-lists/02-apps.list.chroot << 'EOF'
mousepad
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
nitrogen
picom
rofi
dunst
python3-pil
imagemagick
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

cat > config/package-lists/05-flatpak.list.chroot << 'EOF'
flatpak
gnome-software-plugin-flatpak
EOF

# ─────────────────────────────────────────────
# ÉTAPE 4 : Hooks
# ─────────────────────────────────────────────
echo "[4/9] Hooks..."
mkdir -p config/hooks/live

# ── Locale FR ──────────────────────────────────────────────
cat > config/hooks/live/0050-locale.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
sed -i 's/# fr_FR.UTF-8/fr_FR.UTF-8/' /etc/locale.gen 2>/dev/null || true
locale-gen fr_FR.UTF-8
update-locale LANG=fr_FR.UTF-8 LC_ALL=fr_FR.UTF-8
HOOKEOF

# ── Opera GX ───────────────────────────────────────────────
cat > config/hooks/live/0100-opera.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> Opera GX..."
wget -qO /tmp/opera.gpg "https://deb.opera.com/archive.key"
gpg --dearmor -o /usr/share/keyrings/opera.gpg /tmp/opera.gpg
rm -f /tmp/opera.gpg

echo "deb [signed-by=/usr/share/keyrings/opera.gpg] https://deb.opera.com/opera-stable/ stable non-free" \
  > /etc/apt/sources.list.d/opera.list

apt-get update -qq
apt-get install -y opera-stable 2>/dev/null || echo "Opera skip"
ln -sf /usr/bin/opera /usr/local/bin/opera-gx 2>/dev/null || true
echo ">>> Opera OK"
HOOKEOF

# ── Wine 32bit + DXVK + Bottles ───────────────────────────
cat > config/hooks/live/0200-wine.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> Wine + DXVK + Bottles..."
dpkg --add-architecture i386
apt-get update -qq
apt-get install -y wine32 libwine:i386 fonts-wine \
  libvulkan1:i386 libgl1-mesa-dri:i386 2>/dev/null || true

DXVK_VER="2.3.1"
wget -qO /tmp/dxvk.tar.gz \
  "https://github.com/doitsujin/dxvk/releases/download/v${DXVK_VER}/dxvk-${DXVK_VER}.tar.gz" \
  || { echo "DXVK skip"; exit 0; }
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
echo "DXVK active"
EOF
chmod +x /usr/local/bin/wine-dxvk-setup

cat > /usr/local/bin/install-bottles << 'EOF'
#!/bin/bash
echo ">>> Installation de Bottles..."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub com.usebottles.bottles
echo ">>> Bottles installé !"
EOF
chmod +x /usr/local/bin/install-bottles

cat > /usr/share/applications/wine-exe.desktop << 'EOF'
[Desktop Entry]
Name=Wine EXE Launcher
Exec=mineos-exe %f
MimeType=application/x-ms-dos-executable;application/x-msi;application/x-ms-shortcut;
Icon=wine
Type=Application
NoDisplay=true
EOF
update-desktop-database 2>/dev/null || true

mkdir -p /usr/share/mime/packages
cat > /usr/share/mime/packages/wine.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-ms-dos-executable">
    <comment>Executable Windows</comment>
    <glob pattern="*.exe"/>
    <glob pattern="*.EXE"/>
  </mime-type>
</mime-info>
EOF
update-mime-database /usr/share/mime 2>/dev/null || true
echo ">>> Wine OK"
HOOKEOF

# ── Kernel Liquorix ─────────────────────────────────────────
cat > config/hooks/live/0250-kernel.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> Kernel Liquorix (Ubuntu)..."
wget -qO /tmp/liq.gpg "https://liquorix.net/liquorix-keyring.gpg" \
  || { echo "Liquorix GPG echec"; exit 0; }
install -D -m 644 /tmp/liq.gpg /usr/share/keyrings/liquorix-keyring.gpg
. /etc/os-release
echo "deb [signed-by=/usr/share/keyrings/liquorix-keyring.gpg] https://liquorix.net/debian ${VERSION_CODENAME} main" \
  > /etc/apt/sources.list.d/liquorix.list
apt-get update -qq
apt-get install -y linux-image-liquorix-amd64 linux-headers-liquorix-amd64 \
  || echo "Liquorix indispo, kernel Ubuntu conserve"
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
HOOKEOF

# ── GPU universel ────────────────────────────────────────────
cat > config/hooks/live/0500-gpu.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> Drivers GPU (Ubuntu)..."
GPU_INFO=$(lspci 2>/dev/null | grep -iE "VGA|3D|Display" || true)
HAS_NVIDIA=$(echo "$GPU_INFO" | grep -ic "nvidia" || true)
HAS_AMD=$(echo "$GPU_INFO"   | grep -icE "amd|radeon|ati" || true)
echo "GPU: $GPU_INFO"

if [ "$HAS_NVIDIA" -gt 0 ]; then
  # Ubuntu : PPA ubuntu-drivers
  apt-get install -y ubuntu-drivers-common 2>/dev/null || true
  ubuntu-drivers install 2>/dev/null || \
    apt-get install -y nvidia-driver-535 nvidia-settings libvulkan1 vulkan-tools 2>/dev/null || true
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
EndSection
EOF
  cat >> /etc/environment << 'EOF'
__GL_THREADED_OPTIMIZATIONS=1
__GL_MaxFramesAllowed=1
EOF
  update-initramfs -u 2>/dev/null || true

elif [ "$HAS_AMD" -gt 0 ]; then
  apt-get update -qq
  # Ubuntu Jammy : firmware-amd-graphics n'existe pas → linux-firmware
  apt-get install -y linux-firmware libgl1-mesa-dri \
    mesa-vulkan-drivers mesa-va-drivers mesa-vdpau-drivers \
    libvulkan1 vulkan-tools 2>/dev/null || true
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

else
  apt-get update -qq
  # Ubuntu Jammy : intel-media-va-driver est dans non-free → intel-media-va-driver-non-free
  apt-get install -y linux-firmware intel-media-va-driver \
    libva-drm2 libva-x11-2 libgl1-mesa-dri \
    mesa-vulkan-drivers libvulkan1 vulkan-tools 2>/dev/null || true
  cat > /etc/modprobe.d/i915-gaming.conf << 'EOF'
options i915 enable_guc=3
options i915 enable_fbc=1
options i915 enable_psr=1
options i915 fastboot=1
EOF
  cat >> /etc/environment << 'EOF'
MESA_LOADER_DRIVER_OVERRIDE=iris
mesa_glthread=true
vblank_mode=0
EOF
fi

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

cat > /usr/local/bin/mineos-gpu-info << 'EOF'
#!/bin/bash
echo "=== MineOS GPU Info ==="
lspci | grep -iE "VGA|3D|Display"
glxinfo 2>/dev/null | grep -E "renderer|version" | head -4 || true
vulkaninfo 2>/dev/null | grep deviceName | head -2 || true
EOF
chmod +x /usr/local/bin/mineos-gpu-info
HOOKEOF

# ── Tweaks système ──────────────────────────────────────────
cat > config/hooks/live/0550-tweaks.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
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
default-fragment-size-msec = 5
default-fragments = 2
realtime-scheduling = yes
realtime-priority = 9
high-priority = yes
nice-level = -15
EOF
HOOKEOF

# ── Flatpak + Flathub ───────────────────────────────────────
cat > config/hooks/live/0560-flatpak.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> Flatpak + Flathub..."
apt-get install -y flatpak 2>/dev/null || true
cat > /usr/local/bin/mineos-flatpak-setup << 'EOF'
#!/bin/bash
flatpak remote-add --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
EOF
chmod +x /usr/local/bin/mineos-flatpak-setup

cat > /etc/xdg/autostart/mineos-flatpak.desktop << 'EOF'
[Desktop Entry]
Name=MineOS Flatpak Setup
Exec=/usr/local/bin/mineos-flatpak-setup
Type=Application
X-GNOME-Autostart-enabled=true
EOF
echo ">>> Flatpak OK"
HOOKEOF

# ── MineOS Store ─────────────────────────────────────────
cat > config/hooks/live/0570-store.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> MineOS Store..."

mkdir -p /usr/local/bin /usr/share/applications /usr/share/mineos

cat > /usr/local/bin/mineos-store << 'STOREEOF'
#!/bin/bash
APPS_LINUX=(
  "Discord|flatpak install -y flathub com.discordapp.Discord|com.discordapp.Discord"
  "Spotify|flatpak install -y flathub com.spotify.Client|com.spotify.Client"
  "OBS Studio|flatpak install -y flathub com.obsproject.Studio|com.obsproject.Studio"
  "VLC|sudo apt-get install -y vlc|vlc"
  "GIMP|sudo apt-get install -y gimp|gimp"
  "LibreOffice|sudo apt-get install -y libreoffice|libreoffice"
  "VSCode|flatpak install -y flathub com.visualstudio.code|com.visualstudio.code"
  "Kdenlive|flatpak install -y flathub org.kde.kdenlive|org.kde.kdenlive"
  "Blender|flatpak install -y flathub org.blender.Blender|org.blender.Blender"
  "Inkscape|sudo apt-get install -y inkscape|inkscape"
)

APPS_WINDOWS=(
  "7-Zip|https://www.7-zip.org/a/7z2301-x64.exe"
  "WinRAR|https://www.win-rar.com/fileadmin/winrar-versions/winrar/winrar-x64-701.exe"
  "Notepad++|https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.6.2/npp.8.6.2.Installer.x64.exe"
)

show_menu() {
  CHOICE=$(zenity --list \
    --title="⛏ MineOS Store" \
    --text="Choisissez une catégorie :" \
    --column="Catégorie" \
    "🐧 Applications Linux" \
    "🪟 Applications Windows (.exe via Wine)" \
    "🎮 Jeux (Steam / Lutris)" \
    --width=400 --height=280 2>/dev/null)
  case "$CHOICE" in
    "🐧 Applications Linux") show_linux ;;
    "🪟 Applications Windows (.exe via Wine)") show_windows ;;
    "🎮 Jeux (Steam / Lutris)") show_games ;;
    *) exit 0 ;;
  esac
}

show_linux() {
  ITEMS=""
  for app in "${APPS_LINUX[@]}"; do
    NAME=$(echo "$app" | cut -d'|' -f1)
    ITEMS="$ITEMS FALSE $NAME"
  done
  SELECTED=$(zenity --list --checklist \
    --title="🐧 Apps Linux" --text="Sélectionnez les apps à installer :" \
    --column="✓" --column="Application" $ITEMS \
    --width=500 --height=500 --separator="|" 2>/dev/null)
  [ -z "$SELECTED" ] && show_menu && return
  /usr/local/bin/mineos-flatpak-setup 2>/dev/null
  IFS='|' read -ra CHOSEN <<< "$SELECTED"
  for name in "${CHOSEN[@]}"; do
    for app in "${APPS_LINUX[@]}"; do
      APP_NAME=$(echo "$app" | cut -d'|' -f1)
      APP_CMD=$(echo "$app" | cut -d'|' -f2)
      if [ "$APP_NAME" = "$name" ]; then
        (echo "0"; echo "# Installation de $APP_NAME..."; eval "$APP_CMD" 2>/dev/null; echo "100"; echo "# $APP_NAME installé !") \
          | zenity --progress --title="Installation" --text="Installation de $APP_NAME..." --auto-close --width=400 2>/dev/null
      fi
    done
  done
  zenity --info --title="MineOS Store" --text="Installation terminée !" 2>/dev/null
  show_menu
}

show_windows() {
  ITEMS=""
  for app in "${APPS_WINDOWS[@]}"; do
    NAME=$(echo "$app" | cut -d'|' -f1)
    ITEMS="$ITEMS FALSE $NAME"
  done
  SELECTED=$(zenity --list --checklist \
    --title="🪟 Apps Windows" --text="Sélectionnez les apps Windows :" \
    --column="✓" --column="Application" $ITEMS \
    --width=500 --height=400 --separator="|" 2>/dev/null)
  [ -z "$SELECTED" ] && show_menu && return
  IFS='|' read -ra CHOSEN <<< "$SELECTED"
  for name in "${CHOSEN[@]}"; do
    for app in "${APPS_WINDOWS[@]}"; do
      APP_NAME=$(echo "$app" | cut -d'|' -f1)
      APP_URL=$(echo "$app" | cut -d'|' -f2)
      if [ "$APP_NAME" = "$name" ]; then
        TMPFILE="/tmp/$(basename $APP_URL)"
        (echo "10"; echo "# Téléchargement..."; wget -qO "$TMPFILE" "$APP_URL" 2>/dev/null; \
         echo "70"; echo "# Lancement..."; WINEFSYNC=1 wine "$TMPFILE" 2>/dev/null &; \
         echo "100"; echo "# Lancé !") \
          | zenity --progress --title="Installation Windows" --text="$APP_NAME..." --auto-close --width=400 2>/dev/null
      fi
    done
  done
  show_menu
}

show_games() {
  CHOICE=$(zenity --list --title="🎮 Jeux" --text="Ouvrir via :" \
    --column="Launcher" "Steam" "Lutris" "PlayOnLinux" \
    --width=300 --height=250 2>/dev/null)
  case "$CHOICE" in
    Steam) gamemoderun steam & ;;
    Lutris) lutris & ;;
    PlayOnLinux) playonlinux & ;;
  esac
}

show_menu
STOREEOF
chmod +x /usr/local/bin/mineos-store

cat > /usr/share/applications/mineos-store.desktop << 'EOF'
[Desktop Entry]
Name=MineOS Store
Comment=Installer des applications Linux et Windows
Exec=mineos-store
Icon=system-software-install
Terminal=false
Type=Application
Categories=System;
EOF
echo ">>> MineOS Store OK"
HOOKEOF

# ── XFCE thème + bureau ─────────────────────────────────────
cat > config/hooks/live/0600-xfce-desktop.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
echo ">>> XFCE bureau MineOS (Ubuntu)..."

mkdir -p /etc/skel/{Bureau,Documents,Images,Musique,Telecharges,Jeux}
mkdir -p /etc/skel/.config/xfce4/{xfconf/xfce-perchannel-xml,panel}
mkdir -p /usr/share/themes/MineOS-Dark/{gtk-3.0,gtk-2.0,xfwm4}
mkdir -p /usr/share/mineos/wallpapers

cat > /usr/share/themes/MineOS-Dark/gtk-3.0/gtk.css << 'EOF'
@define-color bg_color #1a1a2e;
@define-color fg_color #e2e8f0;
@define-color base_color #16213e;
@define-color selected_bg_color #4ade80;
@define-color selected_fg_color #0d1117;
@define-color border_color #2d4a6e;
@define-color accent_color #4ade80;

* { outline: none; }
window, .background { background-color: @bg_color; color: @fg_color; }
headerbar, .titlebar {
  background: linear-gradient(to bottom, #0d2137, #0a1628);
  border-bottom: 1px solid @border_color;
  color: @fg_color;
  padding: 4px 8px;
}
button {
  background: rgba(74,222,128,0.08);
  border: 1px solid @border_color;
  border-radius: 6px;
  color: @fg_color;
  padding: 4px 10px;
  transition: all 0.15s;
}
button:hover { background: rgba(74,222,128,0.2); border-color: @accent_color; }
button:active { background: rgba(74,222,128,0.3); }
entry {
  background: rgba(0,0,0,0.4);
  border: 1px solid @border_color;
  border-radius: 6px;
  color: #22d3ee;
  padding: 4px 8px;
}
entry:focus { border-color: @accent_color; }
treeview, .view { background: @base_color; color: @fg_color; }
treeview:selected, row:selected { background: rgba(74,222,128,0.15); color: @accent_color; }
scrollbar slider { background: @border_color; border-radius: 3px; min-width: 6px; min-height: 6px; }
scrollbar slider:hover { background: @accent_color; }
menu { background: @bg_color; border: 1px solid @border_color; padding: 4px; }
menuitem { padding: 6px 12px; border-radius: 4px; }
menuitem:hover { background: rgba(74,222,128,0.15); color: @accent_color; }
notebook header { background: @base_color; border-bottom: 1px solid @border_color; }
notebook tab { padding: 6px 12px; }
notebook tab:checked { border-bottom: 2px solid @accent_color; color: @accent_color; }
tooltip { background: #0d2137; border: 1px solid @border_color; color: @fg_color; border-radius: 6px; }
EOF

cat > /usr/share/themes/MineOS-Dark/gtk-2.0/gtkrc << 'EOF'
gtk-color-scheme = "bg_color:#1a1a2e\nfg_color:#e2e8f0\nbase_color:#16213e\ntext_color:#e2e8f0\nselected_bg_color:#4ade80\nselected_fg_color:#0d1117"
style "default" {
  bg[NORMAL]      = @bg_color
  bg[ACTIVE]      = @base_color
  bg[PRELIGHT]    = @base_color
  bg[SELECTED]    = @selected_bg_color
  bg[INSENSITIVE] = @bg_color
  fg[NORMAL]      = @fg_color
  fg[ACTIVE]      = @fg_color
  fg[PRELIGHT]    = @fg_color
  fg[SELECTED]    = @selected_fg_color
  base[NORMAL]    = @base_color
  text[NORMAL]    = @text_color
  engine "murrine" {
    colorize_scrollbar = FALSE
    border_shades      = { 0.8, 0.8 }
    roundness          = 4
    gradient_shades    = { 1.1, 1.0, 1.0, 0.9 }
  }
}
class "*" style "default"
EOF

cat > /usr/share/themes/MineOS-Dark/xfwm4/themerc << 'EOF'
shadow_delta_height=0
shadow_delta_width=0
shadow_delta_x=0
shadow_delta_y=-3
shadow_opacity=50
button_layout=O|HMC
button_offset=2
button_spacing=2
full_width_title=true
maximized_offset=0
show_popup_shadow=true
show_frame_shadow=true
title_font=Noto Sans Bold 10
title_horizontal_offset=6
title_vertical_offset_active=3
title_vertical_offset_inactive=3
EOF

mkdir -p /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml

cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="MineOS-Dark"/>
    <property name="IconThemeName" type="string" value="Papirus-Dark"/>
    <property name="DoubleClickTime" type="int" value="400"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="Noto Sans 10"/>
    <property name="MonospaceFontName" type="string" value="Noto Sans Mono 10"/>
    <property name="CursorThemeName" type="string" value="Adwaita"/>
    <property name="DecorationLayout" type="string" value="menu:minimize,maximize,close"/>
  </property>
</channel>
EOF

cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="MineOS-Dark"/>
    <property name="title_font" type="string" value="Noto Sans Bold 10"/>
    <property name="button_layout" type="string" value="O|HMC"/>
    <property name="snap_to_border" type="bool" value="true"/>
    <property name="snap_to_windows" type="bool" value="true"/>
    <property name="wrap_workspaces" type="bool" value="false"/>
    <property name="use_compositing" type="bool" value="true"/>
    <property name="frame_opacity" type="int" value="100"/>
    <property name="inactive_opacity" type="int" value="90"/>
  </property>
</channel>
EOF

cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitorVirtual1" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="/usr/share/mineos/wallpapers/default.png"/>
          <property name="image-style" type="int" value="5"/>
          <property name="color-type" type="int" value="0"/>
          <property name="rgba1" type="array">
            <value type="double" value="0.101961"/>
            <value type="double" value="0.101961"/>
            <value type="double" value="0.180392"/>
            <value type="double" value="1.000000"/>
          </property>
        </property>
      </property>
    </property>
  </property>
  <property name="desktop-menu" type="empty">
    <property name="show" type="bool" value="true"/>
  </property>
  <property name="desktop-icons" type="empty">
    <property name="style" type="int" value="2"/>
    <property name="icon-size" type="uint" value="48"/>
    <property name="tooltip-size" type="double" value="128"/>
  </property>
</channel>
EOF

cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
  </property>
  <property name="panel-1" type="empty">
    <property name="position" type="string" value="p=8;x=0;y=0"/>
    <property name="length" type="uint" value="100"/>
    <property name="position-locked" type="bool" value="true"/>
    <property name="size" type="uint" value="38"/>
    <property name="background-style" type="uint" value="1"/>
    <property name="background-rgba" type="array">
      <value type="double" value="0.039216"/>
      <value type="double" value="0.039216"/>
      <value type="double" value="0.101961"/>
      <value type="double" value="0.950000"/>
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
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="whiskermenu"/>
    <property name="plugin-2" type="string" value="separator">
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-3" type="string" value="tasklist"/>
    <property name="plugin-4" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-5" type="string" value="systray"/>
    <property name="plugin-6" type="string" value="pulseaudio"/>
    <property name="plugin-7" type="string" value="power-manager-plugin"/>
    <property name="plugin-8" type="string" value="clock">
      <property name="digital-format" type="string" value="%H:%M  %d/%m/%Y"/>
    </property>
  </property>
</channel>
EOF

cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/whiskermenu.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="whiskermenu" version="1.0">
  <property name="button-title" type="string" value="⛏ MineOS"/>
  <property name="button-icon" type="string" value=""/>
  <property name="show-button-title" type="bool" value="true"/>
  <property name="show-button-icon" type="bool" value="false"/>
  <property name="profile-shape" type="int" value="1"/>
  <property name="show-recent" type="bool" value="true"/>
  <property name="position-categories-horizontal" type="bool" value="false"/>
  <property name="position-search-alternate" type="bool" value="false"/>
</channel>
EOF

mkdir -p /etc/skel/.config/autostart

cat > /etc/skel/.config/autostart/mineos-startup.desktop << 'EOF'
[Desktop Entry]
Name=MineOS Startup
Exec=/usr/local/bin/mineos-startup
Type=Application
X-GNOME-Autostart-enabled=true
EOF

cat > /usr/local/bin/mineos-startup << 'EOF'
#!/bin/bash
sleep 2
/usr/local/bin/mineos-flatpak-setup 2>/dev/null &
source /usr/local/bin/mineos-vulkan-setup 2>/dev/null
/usr/lib/gamemode/gamemoded 2>/dev/null &
notify-send "⛏ MineOS Gaming" \
  "Bienvenue !\nStore : menu ⛏ → MineOS Store\nexe <fichier.exe> dans le terminal" \
  --icon=system-run 2>/dev/null &
EOF
chmod +x /usr/local/bin/mineos-startup

for ITEM in store opera terminal files; do
  case $ITEM in
    store)    NAME="MineOS Store";  EXEC="mineos-store";        ICON="system-software-install" ;;
    opera)    NAME="Opera GX";      EXEC="opera";               ICON="opera"                   ;;
    terminal) NAME="Terminal";      EXEC="xfce4-terminal";      ICON="terminal"                ;;
    files)    NAME="Fichiers";      EXEC="thunar";              ICON="file-manager"            ;;
  esac
  cat > "/etc/skel/Bureau/${ITEM}.desktop" << DEOF
[Desktop Entry]
Name=${NAME}
Exec=${EXEC}
Icon=${ICON}
Type=Application
DEOF
  chmod +x "/etc/skel/Bureau/${ITEM}.desktop"
done

mkdir -p /usr/share/mineos/wallpapers
python3 << 'PYEOF'
try:
  from PIL import Image, ImageDraw
  img = Image.new('RGB', (1920, 1080), '#1a1a2e')
  d = ImageDraw.Draw(img)
  for x in range(0, 1920, 32):
      d.line([(x,0),(x,1080)], fill='#1f2a3d', width=1)
  for y in range(0, 1080, 32):
      d.line([(0,y),(1920,y)], fill='#1f2a3d', width=1)
  img.save('/usr/share/mineos/wallpapers/default.png')
  img2 = Image.new('RGB', (1920, 1080), '#0a1628')
  d2 = ImageDraw.Draw(img2)
  for x in range(0, 1920, 48):
      d2.line([(x,0),(x,1080)], fill='#0d2137', width=1)
  for y in range(0, 1080, 48):
      d2.line([(0,y),(1920,y)], fill='#0d2137', width=1)
  img2.save('/usr/share/mineos/wallpapers/blue.png')
  img3 = Image.new('RGB', (1920, 1080), '#1a0a2e')
  d3 = ImageDraw.Draw(img3)
  for x in range(0, 1920, 32):
      d3.line([(x,0),(x,1080)], fill='#2d1b69', width=1)
  for y in range(0, 1080, 32):
      d3.line([(0,y),(1920,y)], fill='#2d1b69', width=1)
  img3.save('/usr/share/mineos/wallpapers/purple.png')
  print("3 wallpapers créés")
except Exception as e:
  print(f"PIL error: {e}")
  import subprocess
  subprocess.run(['convert','-size','1920x1080','gradient:#1a1a2e-#0d2137',
    '/usr/share/mineos/wallpapers/default.png'], capture_output=True)
PYEOF

cat > /usr/local/bin/mineos-wallpaper << 'EOF'
#!/bin/bash
CHOICE=$(zenity --list \
  --title="🖼 Fond d'écran MineOS" \
  --text="Choisissez un fond d'écran :" \
  --column="Aperçu" --column="Nom" --column="Fichier" \
  "🟢" "MineOS Dark (défaut)" "/usr/share/mineos/wallpapers/default.png" \
  "🔵" "MineOS Blue" "/usr/share/mineos/wallpapers/blue.png" \
  "🟣" "MineOS Purple" "/usr/share/mineos/wallpapers/purple.png" \
  "📁" "Choisir un fichier..." "custom" \
  --width=480 --height=300 \
  --print-column=3 2>/dev/null)
[ -z "$CHOICE" ] && exit 0
if [ "$CHOICE" = "custom" ]; then
  CHOICE=$(zenity --file-selection \
    --title="Choisir une image" \
    --file-filter="Images | *.png *.jpg *.jpeg *.webp" 2>/dev/null)
  [ -z "$CHOICE" ] && exit 0
fi
xfconf-query -c xfce4-desktop \
  -p /backdrop/screen0/monitorVirtual1/workspace0/last-image \
  -s "$CHOICE" 2>/dev/null || xfdesktop --reload 2>/dev/null || true
notify-send "🖼 MineOS" "Fond d'écran changé !" 2>/dev/null
EOF
chmod +x /usr/local/bin/mineos-wallpaper

cat > /usr/share/applications/mineos-wallpaper.desktop << 'EOF'
[Desktop Entry]
Name=Changer le fond d'écran
Exec=mineos-wallpaper
Icon=preferences-desktop-wallpaper
Terminal=false
Type=Application
Categories=Settings;
EOF

cat > /etc/skel/.bashrc << 'EOF'
export LANG=fr_FR.UTF-8
export WINEFSYNC=1
export mesa_glthread=true
PS1='\[\e[0;32m\]mining \[\e[1;36m\]\u\[\e[0;37m\]@\[\e[1;34m\]mineos\[\e[0;37m\]:\[\e[1;33m\]\w\[\e[0m\]\$ '
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias chrome='opera'
alias exe='gamemoderun wine'
alias exe-dxvk='DXVK_HUD=fps gamemoderun wine'
alias steam='gamemoderun steam'
alias gpu='mineos-gpu-info'
alias store='mineos-store'
alias wallpaper='mineos-wallpaper'
[ -f /etc/bash_completion ] && . /etc/bash_completion
source /usr/local/bin/mineos-vulkan-setup 2>/dev/null
echo ""
echo "  ⛏ MineOS Gaming — store | exe <app.exe> | gpu | wallpaper"
echo ""
EOF

cat > /usr/local/bin/mineos-exe << 'EOF'
#!/bin/bash
FILE="$1"
if [ -z "$FILE" ]; then
  FILE=$(zenity --file-selection \
    --file-filter="Executables | *.exe *.msi *.bat" \
    --title="MineOS - Lancer un .exe" 2>/dev/null)
  [ -z "$FILE" ] && exit 0
fi
notify-send "⚡ MineOS" "Lancement : $(basename "$FILE")" 2>/dev/null
WINEFSYNC=1 gamemoderun wine "$FILE"
EOF
chmod +x /usr/local/bin/mineos-exe

echo ">>> Bureau XFCE OK"
HOOKEOF

# ── LightDM ──────────────────────────────────────────────────
cat > config/hooks/live/0700-lightdm.hook.chroot << 'HOOKEOF'
#!/bin/bash
set -e
mkdir -p /etc/lightdm
cat > /etc/lightdm/lightdm.conf << 'EOF'
[Seat:*]
autologin-user=user
autologin-user-timeout=0
greeter-session=lightdm-gtk-greeter
user-session=xfce
EOF
cat > /etc/lightdm/lightdm-gtk-greeter.conf << 'EOF'
[greeter]
background=#1a1a2e
theme-name=MineOS-Dark
icon-theme-name=Papirus-Dark
font-name=Noto Sans 11
clock-format=%H:%M — %A %d %B
indicators=~host;~spacer;~clock;~spacer;~session;~power
EOF
HOOKEOF

# ── Fix initramfs + suppression symlinks .old (bug live-build Ubuntu) ───────
# Pourquoi ça plante :
#   1. Le kernel postinst crée /boot/initrd.img.old -> initrd.img-<old-kver>
#      mais dans un chroot frais il n'y a pas d'"ancien" kernel → symlink cassé.
#   2. update-initramfs est mis en "deferred" par dpkg et n'est jamais flushé.
#   3. lb_chroot_hacks tente chmod sur ces symlinks cassés → exit 123.
# Fix : flush des triggers dpkg + génération initramfs + suppression des .old.
cat > config/hooks/live/0800-initramfs.hook.chroot << 'HOOKEOF'
#!/bin/bash
# Pourquoi ce hook existe :
#   update-initramfs est "deferred" par dpkg et ne crée jamais les fichiers
#   initrd.img-<kver> dans un chroot live-build. Les symlinks /boot/initrd.img
#   et /boot/initrd.img.old restent cassés. lb_chroot_hacks tente un chmod
#   dessus et plante (exit 123).
#
# Fix : mkinitramfs DIRECTEMENT (contourne le système de triggers dpkg),
#       puis suppression des symlinks .old qui n'ont aucun sens dans un chroot frais.
#
# NOTE : lb_chroot_hacks est aussi patché sur le host (étape 6b du script parent)
#        pour que même si ce hook échoue, le chmod ne bloque pas le build.

export DEBIAN_FRONTEND=noninteractive

echo ">>> Modules disponibles :"
ls /lib/modules/ 2>/dev/null || echo "(aucun)"

for KVER in $(ls /lib/modules/ 2>/dev/null | sort); do
  OUT="/boot/initrd.img-${KVER}"
  if [ ! -f "$OUT" ]; then
    echo ">>> mkinitramfs $KVER -> $OUT"
    # Flush les triggers dpkg en attente avant mkinitramfs
    dpkg --configure -a 2>/dev/null || true
    if mkinitramfs -o "$OUT" "$KVER"; then
      echo ">>> mkinitramfs OK : $OUT"
    elif update-initramfs -c -k "$KVER"; then
      echo ">>> update-initramfs OK : $OUT"
    else
      echo "WARN: initramfs non généré pour $KVER — le patch lb_chroot_hacks (étape 6b) prendra le relais"
      continue
    fi
  else
    echo ">>> $OUT existe déjà"
  fi
  # Réparer le symlink principal s'il est cassé
  if [ -L /boot/initrd.img ] && [ ! -e /boot/initrd.img ]; then
    ln -sf "initrd.img-${KVER}" /boot/initrd.img
    echo ">>> /boot/initrd.img -> initrd.img-${KVER}"
  fi
done

# Supprimer les symlinks .old cassés (pas d'"ancien kernel" dans un chroot frais)
for f in /boot/initrd.img.old /boot/vmlinuz.old; do
  if [ -L "$f" ] && [ ! -e "$f" ]; then
    echo ">>> rm dangling $f"
    rm -f "$f"
  fi
done

echo ">>> Initramfs OK"
HOOKEOF

# ── GRUB EFI + BIOS (bootable sur vrai PC) ──────────────────
cat > config/hooks/live/0850-grub.hook.chroot << 'HOOKEOF'
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
echo ">>> Config GRUB EFI/BIOS..."

# Config GRUB principale
mkdir -p /boot/grub
cat > /etc/default/grub << 'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_TIMEOUT_STYLE=menu
GRUB_DISTRIBUTOR="MineOS Gaming"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash boot=live components hostname=mineos username=user"
GRUB_CMDLINE_LINUX=""
GRUB_TERMINAL_OUTPUT="gfxterm"
GRUB_GFXMODE="1920x1080,1280x720,auto"
GRUB_GFXPAYLOAD_LINUX="keep"
GRUB_DISABLE_OS_PROBER=true
EOF

# grub.cfg pour le live (sera aussi dans binary/boot/grub/ du squashfs)
cat > /boot/grub/grub.cfg << 'EOF'
set default=0
set timeout=5
set gfxmode=1920x1080,1280x720,auto
set gfxpayload=keep
insmod all_video
insmod gfxterm
insmod png
terminal_output gfxterm

menuentry "⛏ MineOS Gaming (Live)" --class ubuntu --class gnu-linux {
  linux  /live/vmlinuz boot=live components quiet splash hostname=mineos username=user
  initrd /live/initrd.img
}

menuentry "⛏ MineOS Gaming (failsafe)" --class ubuntu {
  linux  /live/vmlinuz boot=live components nomodeset hostname=mineos username=user
  initrd /live/initrd.img
}

menuentry "Démarrer depuis le disque dur" --class hdd {
  chainloader +1
}
EOF

echo ">>> GRUB OK"
HOOKEOF

chmod +x config/hooks/live/*.hook.chroot

# ─────────────────────────────────────────────
# ÉTAPE 5 : Includes
# ─────────────────────────────────────────────
echo "[5/9] Includes..."
mkdir -p config/includes.chroot/usr/local/bin
cat > config/includes.chroot/usr/local/bin/mineos-exe << 'EOF'
#!/bin/bash
FILE="$1"
if [ -z "$FILE" ]; then
  FILE=$(zenity --file-selection \
    --file-filter="Executables | *.exe *.msi *.bat" \
    --title="MineOS - Lancer un .exe" 2>/dev/null)
  [ -z "$FILE" ] && exit 0
fi
notify-send "MineOS" "Lancement : $(basename "$FILE")" 2>/dev/null
WINEFSYNC=1 gamemoderun wine "$FILE"
EOF
chmod +x config/includes.chroot/usr/local/bin/mineos-exe

# ─────────────────────────────────────────────
# ÉTAPE 6 : Compression
# ─────────────────────────────────────────────
echo "[6/9] Compression xz..."
mkdir -p config/compression
echo "xz" > config/compression/filesystem

# ─────────────────────────────────────────────
# ÉTAPE 6b : Patch lb_chroot_hacks sur le HOST
# ─────────────────────────────────────────────
# Pourquoi : live-build exécute lb_chroot_hacks DANS le répertoire de build,
# avec des chemins comme "chroot/boot/initrd.img". Si ce symlink est cassé
# (update-initramfs différé, pas de fichier initrd.img-<kver> cible), chmod
# retourne une erreur. Le hook 0800 tente de corriger ça depuis l'intérieur du
# chroot, mais peut échouer si l'environnement chroot est contraint à ce stade.
# Ce patch ajoute une garde [ -e ... ] avant chaque chmod dans lb_chroot_hacks,
# rendant le script tolérant aux symlinks cassés — sans jamais modifier le comportement
# sur des installations normales.
echo "[6b/9] Patch lb_chroot_hacks (host)..."

# Chercher lb_chroot_hacks dans les emplacements connus de live-build
# live-build 3.x nomme les scripts "lb_chroot_hacks", live-build 4.x+ "chroot_hacks"
LB_HACKS=""
for candidate in \
  /usr/lib/live/build/lb_chroot_hacks \
  /usr/lib/live/build/chroot_hacks \
  /usr/share/live/build/lb_chroot_hacks \
  /usr/share/live/build/chroot_hacks \
  $(which lb_chroot_hacks 2>/dev/null) \
  $(find /usr/lib /usr/share -name "lb_chroot_hacks" 2>/dev/null | head -1) \
  $(find /usr/lib /usr/share -name "chroot_hacks"    2>/dev/null | head -1)
do
  if [ -f "$candidate" ]; then
    LB_HACKS="$candidate"
    break
  fi
done

if [ -z "$LB_HACKS" ]; then
  echo "WARN : lb_chroot_hacks introuvable sur ce système — patch ignoré"
  echo "       (le hook 0800-initramfs doit suffire)"
else
  echo ">>> Fichier trouvé : $LB_HACKS"
  # Sauvegarder l'original (idempotent : ne pas écraser si déjà patché)
  if [ ! -f "${LB_HACKS}.orig" ]; then
    cp "$LB_HACKS" "${LB_HACKS}.orig"
    echo ">>> Backup : ${LB_HACKS}.orig"
  fi

  # Patch 1 : chmod sur initrd.img      (symlink principal)
  # Avant : chmod 600 chroot/boot/initrd.img
  # Après : [ -e chroot/boot/initrd.img ] && chmod 600 chroot/boot/initrd.img
  sed -i \
    's|^\(\s*\)chmod \([0-9]*\) \(chroot/boot/initrd\.img\)\s*$|\1[ -e \3 ] \&\& chmod \2 \3|' \
    "$LB_HACKS"

  # Patch 2 : chmod sur initrd.img.old  (symlink "ancien kernel", absent dans un chroot frais)
  sed -i \
    's|^\(\s*\)chmod \([0-9]*\) \(chroot/boot/initrd\.img\.old\)\s*$|\1[ -e \3 ] \&\& chmod \2 \3|' \
    "$LB_HACKS"

  # Patch 3 : chmod sur vmlinuz.old     (même problème, même fix)
  sed -i \
    's|^\(\s*\)chmod \([0-9]*\) \(chroot/boot/vmlinuz\.old\)\s*$|\1[ -e \3 ] \&\& chmod \2 \3|' \
    "$LB_HACKS"

  # Vérifier que le patch a modifié quelque chose (ou que le fichier était déjà patché)
  if diff -q "${LB_HACKS}.orig" "$LB_HACKS" > /dev/null 2>&1; then
    echo ">>> Aucune modification — soit déjà patché, soit les lignes n'ont pas le format attendu"
    echo ">>> Vérification manuelle :"
    grep -n "initrd.img\|vmlinuz.old" "$LB_HACKS" | head -10 || true
  else
    echo ">>> lb_chroot_hacks patché avec succès"
    echo ">>> Diff :"
    diff "${LB_HACKS}.orig" "$LB_HACKS" || true
  fi
fi

# ─────────────────────────────────────────────
# ÉTAPE 7 : lb build
# ─────────────────────────────────────────────
echo "[7/9] lb build (20-30 min)..."
# Le || true permet de continuer même si lb retourne un code d'erreur
# sur des warnings non-fatals (chmod dangling symlinks, etc.)
lb build 2>&1 | tee /tmp/lb-build.log || {
  EXIT_CODE=$?
  # Vérifier si l'ISO a quand même été créée malgré l'erreur
  ISO_CHECK=$(find "$BUILD_DIR" -name "*.iso" 2>/dev/null | head -1)
  if [ -n "$ISO_CHECK" ]; then
    echo ">>> lb build a retourné $EXIT_CODE mais l'ISO existe — on continue"
  else
    echo "ERREUR FATALE lb build (code $EXIT_CODE)"
    tail -50 /tmp/lb-build.log
    exit $EXIT_CODE
  fi
}

# ─────────────────────────────────────────────
# ÉTAPE 8 : Collecte ISO
# ─────────────────────────────────────────────
echo "[8/9] Collecte ISO..."
ISO=$(find "$BUILD_DIR" -name "*.iso" 2>/dev/null | head -1)
if [ -z "$ISO" ]; then
  echo "ERREUR : ISO introuvable."
  tail -100 /tmp/lb-build.log
  exit 1
fi

cp "$ISO" "$OUT_DIR/MineOS-Gaming-${VERSION}-x86_64.iso"
sha256sum "$OUT_DIR/MineOS-Gaming-${VERSION}-x86_64.iso" > "$OUT_DIR/SHA256SUMS"

echo "[9/9] Done !"
echo "ISO : $OUT_DIR/MineOS-Gaming-${VERSION}-x86_64.iso"
echo "Taille : $(du -sh $OUT_DIR/MineOS-Gaming-${VERSION}-x86_64.iso | cut -f1)"
