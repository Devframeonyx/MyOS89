#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
#  MineOS v13 — Configuration complète dans le chroot
#  Appelé par build.sh après l'installation des paquets
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail
CHROOT="$1"
VERSION="$2"

log() { echo -e "\n  \033[1;36m[config]\033[0m $*"; }

# Helper : écrire un fichier dans le chroot
write_chroot() {
    local path="$CHROOT/$1"
    mkdir -p "$(dirname "$path")"
    cat > "$path"
}

# ─── Hostname ──────────────────────────────────────────────────────────────
log "Hostname + réseau"
echo "mineos" | write_chroot etc/hostname
write_chroot etc/hosts << 'EOF'
127.0.0.1   localhost
127.0.1.1   mineos
::1         localhost ip6-localhost ip6-loopback
EOF

# ─── Sysctl gaming ─────────────────────────────────────────────────────────
log "Tweaks sysctl gaming"
write_chroot etc/sysctl.d/99-mineos-gaming.conf << 'EOF'
# MineOS Gaming — optimisations performances
vm.swappiness=10
vm.dirty_ratio=15
vm.dirty_background_ratio=5
kernel.sched_autogroup_enabled=1
fs.file-max=2097152
# Réseau gaming
net.core.netdev_max_backlog=5000
net.core.rmem_max=26214400
net.core.wmem_max=26214400
net.ipv4.tcp_fastopen=3
EOF

write_chroot etc/security/limits.d/99-mineos.conf << 'EOF'
# MineOS Gaming — limites système
*    soft nofile  1048576
*    hard nofile  1048576
*    soft memlock unlimited
*    hard memlock unlimited
@audio soft rtprio 99
@audio hard rtprio 99
EOF

# ─── PulseAudio low-latency ────────────────────────────────────────────────
log "PulseAudio low-latency"
write_chroot etc/pulse/daemon.conf << 'EOF'
default-sample-rate = 48000
default-fragment-size-msec = 5
default-fragments = 2
realtime-scheduling = yes
realtime-priority = 9
high-priority = yes
nice-level = -15
EOF

# ─── GPU — drivers + détection runtime ────────────────────────────────────
log "GPU : configs modprobe"
write_chroot etc/modprobe.d/amdgpu.conf << 'EOF'
options amdgpu si_support=1
options amdgpu cik_support=1
options amdgpu dpm=1
options amdgpu dc=1
options amdgpu ppfeaturemask=0xffffffff
EOF

write_chroot etc/modprobe.d/i915-gaming.conf << 'EOF'
options i915 enable_guc=3
options i915 enable_fbc=1
options i915 enable_psr=1
options i915 fastboot=1
EOF

write_chroot etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
# NVIDIA open-source Nouveau désactivé → driver propriétaire au 1er boot
blacklist nouveau
options nouveau modeset=0
EOF

# Script détection GPU (s'exécute au démarrage sur le vrai matériel)
write_chroot usr/local/bin/mineos-gpu-detect << 'EOF'
#!/bin/bash
# Détection GPU — s'exécute sur le vrai hardware, lspci fonctionne ici
GPU_INFO=$(lspci 2>/dev/null | grep -iE "VGA|3D|Display" || true)
HAS_NVIDIA=$(echo "$GPU_INFO" | grep -ic "nvidia" || echo 0)
HAS_AMD=$(echo "$GPU_INFO"   | grep -icE "amd|radeon|ati" || echo 0)

ENV_FILE=/etc/environment
# Supprimer les anciennes valeurs GPU si relancé
sed -i '/^VK_ICD_FILENAMES\|^__GL_\|^RADV_\|^AMD_VULKAN\|^MESA_LOADER\|^mesa_glthread\|^vblank_mode/d' "$ENV_FILE" 2>/dev/null || true

if [ "$HAS_NVIDIA" -gt 0 ]; then
    echo "VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json"     >> "$ENV_FILE"
    echo "__GL_THREADED_OPTIMIZATIONS=1"                                 >> "$ENV_FILE"
    echo "__GL_MaxFramesAllowed=1"                                       >> "$ENV_FILE"
    # Installer driver NVIDIA propre si absent
    if ! dpkg -l 2>/dev/null | grep -q "nvidia-driver"; then
        ubuntu-drivers install 2>/dev/null \
            || apt-get install -y nvidia-driver-535 nvidia-settings 2>/dev/null || true
    fi
    mkdir -p /etc/X11/xorg.conf.d
    cat > /etc/X11/xorg.conf.d/20-nvidia.conf << 'XEOF'
Section "Device"
  Identifier "NVIDIA Card"
  Driver     "nvidia"
  Option     "NoLogo"         "1"
  Option     "TripleBuffer"   "1"
  Option     "AllowIndirectGLXProtocol" "off"
EndSection
XEOF
    systemctl set-default graphical.target 2>/dev/null || true
    notify-send "⛏ MineOS" "GPU NVIDIA détecté — driver activé !" --icon=video-display 2>/dev/null || true

elif [ "$HAS_AMD" -gt 0 ]; then
    echo "VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json" >> "$ENV_FILE"
    echo "RADV_PERFTEST=aco,ngg"                                           >> "$ENV_FILE"
    echo "AMD_VULKAN_ICD=RADV"                                            >> "$ENV_FILE"
    echo "mesa_glthread=true"                                             >> "$ENV_FILE"
    notify-send "⛏ MineOS" "GPU AMD détecté — RADV activé !" --icon=video-display 2>/dev/null || true

else
    # Intel / autre
    echo "VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/intel_icd.x86_64.json" >> "$ENV_FILE"
    echo "MESA_LOADER_DRIVER_OVERRIDE=iris"                               >> "$ENV_FILE"
    echo "mesa_glthread=true"                                             >> "$ENV_FILE"
    echo "vblank_mode=0"                                                  >> "$ENV_FILE"
    notify-send "⛏ MineOS" "GPU Intel détecté" --icon=video-display 2>/dev/null || true
fi
EOF
chmod +x "$CHROOT/usr/local/bin/mineos-gpu-detect"

write_chroot etc/systemd/system/mineos-gpu-detect.service << 'EOF'
[Unit]
Description=MineOS GPU Detection & Driver Activation
Before=display-manager.service
After=network.target
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/usr/local/bin/mineos-gpu-detect
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

chroot "$CHROOT" systemctl enable mineos-gpu-detect.service 2>/dev/null || true

# ─── GameMode config ───────────────────────────────────────────────────────
log "GameMode"
write_chroot etc/gamemode.ini << 'EOF'
[general]
renice=10
ioprio=0
inhibit_screensaver=1
desiredgov=performance

[cpu]
park_cores=no
pin_cores=yes

[gpu]
apply_gpu_optimisations=accept-responsibility
gpu_device=0
nv_powermizer_mode=1

[filter]
whitelist=steam;lutris;wine;playonlinux;heroic;bottles
EOF

# ─── MangoHud config ───────────────────────────────────────────────────────
log "MangoHud"
mkdir -p "$CHROOT/etc/MangoHud"
write_chroot etc/MangoHud/MangoHud.conf << 'EOF'
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
position=top-left
font_size=18
background_alpha=0.5
toggle_hud=Shift_R+F12
toggle_fps_limit=Shift_L+F1
no_display=0
EOF

# ─── DXVK ──────────────────────────────────────────────────────────────────
log "DXVK"
chroot "$CHROOT" /bin/bash -c "
set -e
DXVK_VER='2.3.1'
wget -qO /tmp/dxvk.tar.gz \
    \"https://github.com/doitsujin/dxvk/releases/download/v\${DXVK_VER}/dxvk-\${DXVK_VER}.tar.gz\" \
    || { echo 'DXVK download skip'; exit 0; }
mkdir -p /tmp/dxvk-extract
tar -xzf /tmp/dxvk.tar.gz -C /tmp/dxvk-extract --strip-components=1
mkdir -p /usr/share/dxvk
cp -r /tmp/dxvk-extract/x32 /tmp/dxvk-extract/x64 /usr/share/dxvk/
rm -rf /tmp/dxvk.tar.gz /tmp/dxvk-extract
echo 'DXVK installé : /usr/share/dxvk/'
" || warn "DXVK non installé (GitHub inaccessible) — non bloquant"

write_chroot usr/local/bin/wine-dxvk-setup << 'EOF'
#!/bin/bash
PREFIX="${WINEPREFIX:-$HOME/.wine}"
mkdir -p "$PREFIX/drive_c/windows/system32" "$PREFIX/drive_c/windows/syswow64"
cp /usr/share/dxvk/x64/*.dll "$PREFIX/drive_c/windows/system32/" 2>/dev/null || true
cp /usr/share/dxvk/x32/*.dll "$PREFIX/drive_c/windows/syswow64/" 2>/dev/null || true
WINEFSYNC=1 wine winecfg -v win10 2>/dev/null || true
echo "DXVK configuré dans $PREFIX"
notify-send "⛏ Wine" "DXVK activé pour ce préfixe Wine !" 2>/dev/null || true
EOF
chmod +x "$CHROOT/usr/local/bin/wine-dxvk-setup"

# ─── Opera GX ──────────────────────────────────────────────────────────────
log "Opera GX (avec fallback Chromium)"
chroot "$CHROOT" /bin/bash -c "
set -e
export DEBIAN_FRONTEND=noninteractive
if wget -q --spider 'https://deb.opera.com/archive.key' 2>/dev/null; then
    wget -qO /tmp/opera.gpg 'https://deb.opera.com/archive.key'
    gpg --dearmor -o /usr/share/keyrings/opera.gpg /tmp/opera.gpg
    rm -f /tmp/opera.gpg
    echo 'deb [signed-by=/usr/share/keyrings/opera.gpg] https://deb.opera.com/opera-stable/ stable non-free' \
        > /etc/apt/sources.list.d/opera.list
    apt-get update -qq
    apt-get install -y opera-stable 2>/dev/null \
        && ln -sf /usr/bin/opera-stable /usr/local/bin/opera \
        && ln -sf /usr/bin/opera-stable /usr/local/bin/opera-gx \
        && echo 'Opera GX installé !' \
        || { echo 'Opera impossible — fallback Chromium';
             apt-get install -y chromium-browser 2>/dev/null || true;
             ln -sf /usr/bin/chromium-browser /usr/local/bin/opera || true;
             ln -sf /usr/bin/chromium-browser /usr/local/bin/opera-gx || true; }
else
    echo 'deb.opera.com inaccessible — fallback Chromium'
    apt-get install -y chromium-browser 2>/dev/null || true
    ln -sf /usr/bin/chromium-browser /usr/local/bin/opera || true
    ln -sf /usr/bin/chromium-browser /usr/local/bin/opera-gx || true
fi
" || warn "Opera/Chromium non installé — non bloquant"

# ─── Steam ──────────────────────────────────────────────────────────────────
log "Steam"
chroot "$CHROOT" /bin/bash -c "
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get install -y steam-installer 2>/dev/null || {
    wget -qO /tmp/steam.deb 'https://cdn.cloudflare.steamstatic.com/client/installer/steam.deb' \
        && apt-get install -y /tmp/steam.deb 2>/dev/null \
        && apt-get install -f -y 2>/dev/null \
        && rm -f /tmp/steam.deb \
        || echo 'Steam se téléchargera au 1er démarrage'
}
" || warn "Steam non installé — non bloquant"

# ─── Flatpak setup ─────────────────────────────────────────────────────────
log "Flatpak + Flathub (setup au démarrage)"
write_chroot usr/local/bin/mineos-flatpak-setup << 'EOF'
#!/bin/bash
flatpak remote-add --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
echo "Flathub configuré"
EOF
chmod +x "$CHROOT/usr/local/bin/mineos-flatpak-setup"

write_chroot etc/xdg/autostart/mineos-flatpak.desktop << 'EOF'
[Desktop Entry]
Name=MineOS Flatpak Setup
Exec=/usr/local/bin/mineos-flatpak-setup
Type=Application
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF

# ─── Mime .exe → Wine ──────────────────────────────────────────────────────
log "Mime types Wine (.exe)"
write_chroot usr/share/applications/wine-exe.desktop << 'EOF'
[Desktop Entry]
Name=Wine EXE Launcher
Exec=mineos-exe %f
MimeType=application/x-ms-dos-executable;application/x-msi;application/x-ms-shortcut;
Icon=wine
Type=Application
NoDisplay=true
EOF

mkdir -p "$CHROOT/usr/share/mime/packages"
write_chroot usr/share/mime/packages/mineos-wine.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-ms-dos-executable">
    <comment>Programme Windows</comment>
    <glob pattern="*.exe"/>
    <glob pattern="*.EXE"/>
  </mime-type>
  <mime-type type="application/x-msi">
    <comment>Installer Windows</comment>
    <glob pattern="*.msi"/>
  </mime-type>
</mime-info>
EOF

# ─── Script launcher .exe ──────────────────────────────────────────────────
log "Launcher .exe"
write_chroot usr/local/bin/mineos-exe << 'EOF'
#!/bin/bash
FILE="$1"
if [ -z "$FILE" ]; then
    FILE=$(zenity --file-selection \
        --file-filter="Programmes Windows | *.exe *.msi *.bat" \
        --title="MineOS — Lancer un .exe" 2>/dev/null)
    [ -z "$FILE" ] && exit 0
fi
notify-send "⚡ MineOS" "Lancement : $(basename "$FILE")" --icon=wine 2>/dev/null || true
WINEFSYNC=1 gamemoderun wine "$FILE"
EOF
chmod +x "$CHROOT/usr/local/bin/mineos-exe"

# ─── Thème XFCE MineOS Dark ────────────────────────────────────────────────
log "Thème XFCE MineOS Dark"
mkdir -p "$CHROOT/usr/share/themes/MineOS-Dark/"{gtk-3.0,gtk-2.0,xfwm4}

write_chroot usr/share/themes/MineOS-Dark/gtk-3.0/gtk.css << 'EOF'
@define-color bg_color        #1a1a2e;
@define-color fg_color        #e2e8f0;
@define-color base_color      #16213e;
@define-color selected_bg     #4ade80;
@define-color selected_fg     #0d1117;
@define-color border_color    #2d4a6e;
@define-color accent          #4ade80;
@define-color accent_dim      rgba(74,222,128,0.15);
@define-color header_bg       #0d2137;

* { outline: none; box-sizing: border-box; }

window, .background { background-color: @bg_color; color: @fg_color; }

headerbar, .titlebar {
    background: linear-gradient(to bottom, @header_bg, #0a1628);
    border-bottom: 1px solid @border_color;
    color: @fg_color;
    padding: 4px 8px;
    min-height: 38px;
}

button {
    background: rgba(74,222,128,0.07);
    border: 1px solid @border_color;
    border-radius: 6px;
    color: @fg_color;
    padding: 5px 12px;
    transition: all 0.15s ease;
}
button:hover  { background: @accent_dim; border-color: @accent; color: @accent; }
button:active { background: rgba(74,222,128,0.25); }
button.suggested-action { background: @accent; color: @selected_fg; border: none; }
button.destructive-action { background: rgba(255,70,70,0.15); border-color: rgba(255,70,70,0.5); }

entry {
    background: rgba(0,0,0,0.4);
    border: 1px solid @border_color;
    border-radius: 6px;
    color: #22d3ee;
    padding: 5px 10px;
    caret-color: @accent;
}
entry:focus { border-color: @accent; box-shadow: 0 0 0 2px rgba(74,222,128,0.15); }

treeview, .view     { background: @base_color; color: @fg_color; }
row:selected        { background: @accent_dim; color: @accent; }
treeview:selected   { background: @accent_dim; color: @accent; }

scrollbar { background: @base_color; }
scrollbar slider    { background: @border_color; border-radius: 4px; min-width: 6px; min-height: 6px; }
scrollbar slider:hover { background: @accent; }

menu { background: @bg_color; border: 1px solid @border_color; padding: 4px; border-radius: 8px; }
menuitem { padding: 6px 14px; border-radius: 4px; }
menuitem:hover { background: @accent_dim; color: @accent; }

notebook header { background: @base_color; border-bottom: 1px solid @border_color; }
notebook tab    { padding: 6px 14px; }
notebook tab:checked { border-bottom: 2px solid @accent; color: @accent; }

tooltip { background: @header_bg; border: 1px solid @border_color; color: @fg_color; border-radius: 6px; padding: 4px 8px; }

progressbar progress { background: linear-gradient(to right, #0d9488, @accent); border-radius: 3px; }
progressbar trough  { background: @base_color; border-radius: 3px; }

scale trough { background: @base_color; border-radius: 3px; min-height: 4px; }
scale highlight { background: @accent; border-radius: 3px; }
scale slider { background: @accent; border-radius: 50%; min-width: 16px; min-height: 16px; }

checkbutton check, radiobutton radio {
    background: @base_color;
    border: 1px solid @border_color;
    border-radius: 3px;
}
checkbutton check:checked, radiobutton radio:checked {
    background: @accent;
    border-color: @accent;
}
EOF

write_chroot usr/share/themes/MineOS-Dark/gtk-2.0/gtkrc << 'EOF'
gtk-color-scheme = "bg_color:#1a1a2e\nfg_color:#e2e8f0\nbase_color:#16213e\ntext_color:#e2e8f0\nselected_bg_color:#4ade80\nselected_fg_color:#0d1117"
style "default" {
    bg[NORMAL]      = @bg_color
    bg[ACTIVE]      = @base_color
    bg[PRELIGHT]    = "#0d2137"
    bg[SELECTED]    = @selected_bg_color
    bg[INSENSITIVE] = @bg_color
    fg[NORMAL]      = @fg_color
    fg[ACTIVE]      = @fg_color
    fg[PRELIGHT]    = @fg_color
    fg[SELECTED]    = @selected_fg_color
    base[NORMAL]    = @base_color
    base[ACTIVE]    = "#0d2137"
    text[NORMAL]    = @text_color
    text[SELECTED]  = @selected_fg_color
    engine "murrine" {
        colorize_scrollbar = FALSE
        border_shades      = { 0.8, 0.8 }
        roundness          = 6
        gradient_shades    = { 1.1, 1.0, 1.0, 0.9 }
    }
}
class "*" style "default"
EOF

write_chroot usr/share/themes/MineOS-Dark/xfwm4/themerc << 'EOF'
button_layout=O|HMC
button_offset=4
button_spacing=2
full_width_title=true
title_font=Noto Sans Bold 10
title_horizontal_offset=8
title_vertical_offset_active=4
title_vertical_offset_inactive=4
show_popup_shadow=true
show_frame_shadow=true
shadow_opacity=60
shadow_delta_y=-3
EOF

write_chroot usr/share/themes/MineOS-Dark/index.theme << 'EOF'
[Desktop Entry]
Type=X-GNOME-Metatheme
Name=MineOS Dark
Comment=Thème sombre gaming pour MineOS
Encoding=UTF-8

[X-GNOME-Metatheme]
GtkTheme=MineOS-Dark
MetacityTheme=MineOS-Dark
IconTheme=Papirus-Dark
CursorTheme=Adwaita
ButtonLayout=menu:minimize,maximize,close
EOF

# ─── Wallpapers ────────────────────────────────────────────────────────────
log "Wallpapers"
mkdir -p "$CHROOT/usr/share/mineos/wallpapers"
chroot "$CHROOT" python3 << 'PYEOF'
try:
    from PIL import Image, ImageDraw, ImageFilter
    import math

    def grid_wallpaper(w, h, bg, grid, name, accent=None):
        img = Image.new('RGB', (w, h), bg)
        d = ImageDraw.Draw(img)
        for x in range(0, w, 32):
            d.line([(x,0),(x,h)], fill=grid, width=1)
        for y in range(0, h, 32):
            d.line([(0,y),(w,y)], fill=grid, width=1)
        if accent:
            # Point lumineux central subtil
            cx, cy = w//2, h//2
            for r in range(300, 0, -10):
                alpha = int(30 * (1 - r/300))
                d.ellipse([cx-r, cy-r, cx+r, cy+r], outline=(*bytes.fromhex(accent.lstrip('#')), alpha))
        img.save(f'/usr/share/mineos/wallpapers/{name}.png')
        print(f'  {name}.png créé')

    grid_wallpaper(1920, 1080, '#1a1a2e', '#1f2a3d', 'default',  '4ade80')
    grid_wallpaper(1920, 1080, '#0a1628', '#0d2137', 'blue',      '22d3ee')
    grid_wallpaper(1920, 1080, '#1a0a2e', '#2d1b69', 'purple',    'a78bfa')
    grid_wallpaper(1920, 1080, '#0d1f0d', '#152a15', 'green',     '4ade80')
    grid_wallpaper(1920, 1080, '#1a0a0a', '#2d1515', 'red',       'f87171')
    print('5 wallpapers créés avec succès')
except Exception as e:
    print(f'PIL error: {e}')
    import subprocess
    for name, color in [('default','#1a1a2e'),('blue','#0a1628'),('purple','#1a0a2e'),('green','#0d1f0d'),('red','#1a0a0a')]:
        subprocess.run(['convert', '-size', '1920x1080', f'gradient:{color}-#0a0a0a',
            f'/usr/share/mineos/wallpapers/{name}.png'], capture_output=True)
    print('Wallpapers créés via ImageMagick')
PYEOF

# ─── Config XFCE skeleton ──────────────────────────────────────────────────
log "Config XFCE skeleton"
SKEL="$CHROOT/etc/skel"
mkdir -p "$SKEL"/{Bureau,Documents,Images,Musique,Téléchargements,Jeux}
mkdir -p "$SKEL/.config/xfce4/xfconf/xfce-perchannel-xml"
mkdir -p "$SKEL/.config/autostart"
mkdir -p "$SKEL/.local/share/applications"

write_chroot etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName"     type="string" value="MineOS-Dark"/>
    <property name="IconThemeName" type="string" value="Papirus-Dark"/>
    <property name="DoubleClickTime" type="int" value="400"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName"           type="string" value="Noto Sans 10"/>
    <property name="MonospaceFontName"  type="string" value="Noto Sans Mono 10"/>
    <property name="CursorThemeName"    type="string" value="Adwaita"/>
    <property name="DecorationLayout"   type="string" value="menu:minimize,maximize,close"/>
  </property>
</channel>
EOF

write_chroot etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme"               type="string" value="MineOS-Dark"/>
    <property name="title_font"          type="string" value="Noto Sans Bold 10"/>
    <property name="button_layout"       type="string" value="O|HMC"/>
    <property name="snap_to_border"      type="bool"   value="true"/>
    <property name="snap_to_windows"     type="bool"   value="true"/>
    <property name="wrap_workspaces"     type="bool"   value="false"/>
    <property name="use_compositing"     type="bool"   value="true"/>
    <property name="frame_opacity"       type="int"    value="100"/>
    <property name="inactive_opacity"    type="int"    value="92"/>
    <property name="vblank_mode"         type="string" value="xpresent"/>
  </property>
</channel>
EOF

write_chroot etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitorVirtual1" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image"   type="string" value="/usr/share/mineos/wallpapers/default.png"/>
          <property name="image-style"  type="int"    value="5"/>
          <property name="color-type"   type="int"    value="0"/>
          <property name="rgba1" type="array">
            <value type="double" value="0.101961"/>
            <value type="double" value="0.101961"/>
            <value type="double" value="0.180392"/>
            <value type="double" value="1.0"/>
          </property>
        </property>
      </property>
    </property>
  </property>
  <property name="desktop-icons" type="empty">
    <property name="style"        type="int"  value="2"/>
    <property name="icon-size"    type="uint" value="48"/>
    <property name="tooltip-size" type="double" value="128"/>
  </property>
</channel>
EOF

write_chroot etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml << 'EOF'
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
    <property name="size"             type="uint"   value="38"/>
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
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="whiskermenu"/>
    <property name="plugin-2" type="string" value="separator">
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-3" type="string" value="tasklist"/>
    <property name="plugin-4" type="string" value="separator">
      <property name="expand" type="bool"  value="true"/>
      <property name="style"  type="uint"  value="0"/>
    </property>
    <property name="plugin-5" type="string" value="systray"/>
    <property name="plugin-6" type="string" value="pulseaudio"/>
    <property name="plugin-7" type="string" value="network-manager-applet"/>
    <property name="plugin-8" type="string" value="power-manager-plugin"/>
    <property name="plugin-9" type="string" value="clock">
      <property name="digital-format" type="string" value="%H:%M  %d/%m/%Y"/>
    </property>
  </property>
</channel>
EOF

write_chroot etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/whiskermenu.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="whiskermenu" version="1.0">
  <property name="button-title"                   type="string" value="⛏ MineOS"/>
  <property name="show-button-title"              type="bool"   value="true"/>
  <property name="show-button-icon"               type="bool"   value="false"/>
  <property name="profile-shape"                  type="int"    value="1"/>
  <property name="show-recent"                    type="bool"   value="true"/>
  <property name="position-categories-horizontal" type="bool"   value="false"/>
</channel>
EOF

# Autostart
write_chroot etc/skel/.config/autostart/mineos-startup.desktop << 'EOF'
[Desktop Entry]
Name=MineOS Startup
Exec=/usr/local/bin/mineos-startup
Type=Application
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF

# ─── Script de démarrage ───────────────────────────────────────────────────
log "Script de démarrage MineOS"
write_chroot usr/local/bin/mineos-startup << 'EOF'
#!/bin/bash
sleep 2
/usr/local/bin/mineos-flatpak-setup 2>/dev/null &
/usr/local/bin/mineos-gpu-detect    2>/dev/null &
# Lancer GameMode daemon si pas déjà actif
pgrep gamemoded >/dev/null || /usr/lib/gamemode/gamemoded 2>/dev/null &
notify-send "⛏ MineOS Gaming" \
    "Bienvenue sur MineOS Gaming Edition !\nStore → menu ⛏ → MineOS Store\nLancer un .exe → double-clic ou 'exe fichier.exe'" \
    --icon=system-run --urgency=low 2>/dev/null &
EOF
chmod +x "$CHROOT/usr/local/bin/mineos-startup"

# ─── Raccourcis bureau ────────────────────────────────────────────────────
log "Raccourcis bureau"
declare -A DESKTOPS
DESKTOPS["store"]="[Desktop Entry]\nName=⛏ MineOS Store\nExec=mineos-store\nIcon=system-software-install\nType=Application\nTerminal=false"
DESKTOPS["opera"]="[Desktop Entry]\nName=Opera GX\nExec=opera-gx\nIcon=opera\nType=Application\nTerminal=false"
DESKTOPS["terminal"]="[Desktop Entry]\nName=Terminal\nExec=xfce4-terminal\nIcon=terminal\nType=Application\nTerminal=false"
DESKTOPS["steam"]="[Desktop Entry]\nName=Steam\nExec=gamemoderun steam\nIcon=steam\nType=Application\nTerminal=false"
DESKTOPS["lutris"]="[Desktop Entry]\nName=Lutris\nExec=lutris\nIcon=lutris\nType=Application\nTerminal=false"
DESKTOPS["files"]="[Desktop Entry]\nName=Fichiers\nExec=thunar\nIcon=file-manager\nType=Application\nTerminal=false"

for name in "${!DESKTOPS[@]}"; do
    printf "${DESKTOPS[$name]}" > "$SKEL/Bureau/${name}.desktop"
    chmod +x "$SKEL/Bureau/${name}.desktop"
done

# ─── MineOS Store ─────────────────────────────────────────────────────────
log "MineOS Store"
write_chroot usr/local/bin/mineos-store << 'STOREEOF'
#!/bin/bash
# ════════════════════════════════════
#  MineOS Store
# ════════════════════════════════════

APPS_LINUX=(
    "Discord|flatpak install -y flathub com.discordapp.Discord"
    "Spotify|flatpak install -y flathub com.spotify.Client"
    "OBS Studio|flatpak install -y flathub com.obsproject.Studio"
    "Heroic Games (Epic/GOG)|flatpak install -y flathub com.heroicgameslauncher.hgl"
    "Bottles (Wine GUI)|flatpak install -y flathub com.usebottles.bottles"
    "VSCode|flatpak install -y flathub com.visualstudio.code"
    "Kdenlive (Vidéo)|flatpak install -y flathub org.kde.kdenlive"
    "Blender (3D)|flatpak install -y flathub org.blender.Blender"
    "LibreOffice|sudo apt-get install -y libreoffice"
    "Inkscape|sudo apt-get install -y inkscape"
    "VLC|sudo apt-get install -y vlc"
    "GIMP|sudo apt-get install -y gimp"
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
        "🐧 Applications Linux (Flatpak / apt)" \
        "🪟 Applications Windows (.exe via Wine)" \
        "🎮 Jeux (Steam / Lutris / Heroic)" \
        "🔧 Outils MineOS" \
        --width=460 --height=300 2>/dev/null) || exit 0
    case "$CHOICE" in
        "🐧"*) show_linux   ;;
        "🪟"*) show_windows ;;
        "🎮"*) show_games   ;;
        "🔧"*) show_tools   ;;
        *)      exit 0       ;;
    esac
}

show_linux() {
    ITEMS=""
    for app in "${APPS_LINUX[@]}"; do
        NAME="${app%%|*}"
        ITEMS="$ITEMS FALSE $NAME"
    done
    SELECTED=$(zenity --list --checklist \
        --title="🐧 Apps Linux" \
        --text="Cochez les apps à installer :" \
        --column="✓" --column="Application" $ITEMS \
        --width=540 --height=540 --separator="|" 2>/dev/null) || { show_menu; return; }
    [ -z "$SELECTED" ] && { show_menu; return; }
    /usr/local/bin/mineos-flatpak-setup 2>/dev/null
    IFS='|' read -ra CHOSEN <<< "$SELECTED"
    for name in "${CHOSEN[@]}"; do
        for app in "${APPS_LINUX[@]}"; do
            APP_NAME="${app%%|*}"
            APP_CMD="${app##*|}"
            if [ "$APP_NAME" = "$name" ]; then
                (eval "$APP_CMD" 2>&1 | zenity --text-info \
                    --title="Installation de $APP_NAME" \
                    --width=600 --height=300 2>/dev/null) &
            fi
        done
    done
    wait
    zenity --info --title="MineOS Store" --text="✅ Installations terminées !" --width=300 2>/dev/null
    show_menu
}

show_windows() {
    ITEMS=""
    for app in "${APPS_WINDOWS[@]}"; do
        NAME="${app%%|*}"
        ITEMS="$ITEMS FALSE $NAME"
    done
    SELECTED=$(zenity --list --checklist \
        --title="🪟 Apps Windows" \
        --text="Cochez les apps Windows à installer :" \
        --column="✓" --column="Application" $ITEMS \
        --width=500 --height=400 --separator="|" 2>/dev/null) || { show_menu; return; }
    [ -z "$SELECTED" ] && { show_menu; return; }
    IFS='|' read -ra CHOSEN <<< "$SELECTED"
    for name in "${CHOSEN[@]}"; do
        for app in "${APPS_WINDOWS[@]}"; do
            APP_NAME="${app%%|*}"
            APP_URL="${app##*|}"
            if [ "$APP_NAME" = "$name" ]; then
                TMPFILE="/tmp/$(basename "$APP_URL")"
                (
                    echo "10"; echo "# Téléchargement de $APP_NAME..."
                    wget -qO "$TMPFILE" "$APP_URL" 2>/dev/null
                    echo "70"; echo "# Lancement de l'installeur..."
                    WINEFSYNC=1 gamemoderun wine "$TMPFILE" 2>/dev/null &
                    echo "100"; echo "# Installeur lancé !"
                ) | zenity --progress --title="Installation Windows" \
                    --text="$APP_NAME..." --auto-close --width=400 2>/dev/null
            fi
        done
    done
    show_menu
}

show_games() {
    CHOICE=$(zenity --list \
        --title="🎮 Jeux" \
        --text="Ouvrir le launcher :" \
        --column="Launcher" --column="Description" \
        "Steam"   "Bibliothèque Steam + proton" \
        "Lutris"  "Gestionnaire multi-sources" \
        "Heroic"  "Epic Games + GOG" \
        --width=420 --height=280 \
        --print-column=1 2>/dev/null) || { show_menu; return; }
    case "$CHOICE" in
        Steam)  gamemoderun steam    2>/dev/null & ;;
        Lutris) lutris               2>/dev/null & ;;
        Heroic) heroicgameslauncher  2>/dev/null || \
                flatpak run com.heroicgameslauncher.hgl 2>/dev/null & ;;
    esac
    show_menu
}

show_tools() {
    CHOICE=$(zenity --list \
        --title="🔧 Outils MineOS" \
        --text="Outil :" \
        --column="Outil" --column="Description" \
        "GPU Info"          "Infos carte graphique" \
        "DXVK Setup"        "Activer DXVK dans Wine" \
        "Fond d'écran"      "Changer le wallpaper" \
        "Mise à jour"       "Mettre à jour le système" \
        --width=460 --height=320 \
        --print-column=1 2>/dev/null) || { show_menu; return; }
    case "$CHOICE" in
        "GPU Info")     xfce4-terminal -e "bash -c 'mineos-gpu-info; read'" & ;;
        "DXVK Setup")   wine-dxvk-setup & ;;
        "Fond d'écran") mineos-wallpaper & ;;
        "Mise à jour")
            xfce4-terminal -e "bash -c 'sudo apt-get update && sudo apt-get upgrade -y; flatpak update -y; read'" &
            ;;
    esac
    show_menu
}

show_menu
STOREEOF
chmod +x "$CHROOT/usr/local/bin/mineos-store"

write_chroot usr/share/applications/mineos-store.desktop << 'EOF'
[Desktop Entry]
Name=⛏ MineOS Store
Comment=Installer des applications Linux et Windows
Exec=mineos-store
Icon=system-software-install
Terminal=false
Type=Application
Categories=System;
EOF

# ─── GPU Info + Wallpaper tools ────────────────────────────────────────────
write_chroot usr/local/bin/mineos-gpu-info << 'EOF'
#!/bin/bash
echo "═══════════════════════════════════"
echo "  ⛏ MineOS GPU Info"
echo "═══════════════════════════════════"
echo ""
echo "=== PCI GPU ===" 
lspci | grep -iE "VGA|3D|Display"
echo ""
echo "=== OpenGL ===" 
glxinfo 2>/dev/null | grep -E "renderer|version" | head -6 || echo "glxinfo non disponible"
echo ""
echo "=== Vulkan ===" 
vulkaninfo 2>/dev/null | grep deviceName | head -3 || echo "vulkan non disponible"
echo ""
echo "=== Variables GPU actives ===" 
grep -E "VK_ICD|GL_|RADV|MESA|mesa_glthread" /etc/environment 2>/dev/null || echo "(aucune)"
echo ""
read -p "Appuyez sur Entrée..."
EOF
chmod +x "$CHROOT/usr/local/bin/mineos-gpu-info"

write_chroot usr/local/bin/mineos-wallpaper << 'EOF'
#!/bin/bash
CHOICE=$(zenity --list \
    --title="🖼 Fond d'écran MineOS" \
    --text="Choisissez un fond d'écran :" \
    --column="Couleur" --column="Nom" --column="Fichier" \
    "🟢" "MineOS Dark (défaut)"  "/usr/share/mineos/wallpapers/default.png" \
    "🔵" "MineOS Blue"           "/usr/share/mineos/wallpapers/blue.png" \
    "🟣" "MineOS Purple"         "/usr/share/mineos/wallpapers/purple.png" \
    "🌿" "MineOS Green"          "/usr/share/mineos/wallpapers/green.png" \
    "🔴" "MineOS Red"            "/usr/share/mineos/wallpapers/red.png" \
    "📁" "Choisir un fichier..." "custom" \
    --width=500 --height=340 \
    --print-column=3 2>/dev/null) || exit 0

[ -z "$CHOICE" ] && exit 0
if [ "$CHOICE" = "custom" ]; then
    CHOICE=$(zenity --file-selection \
        --title="Choisir une image" \
        --file-filter="Images | *.png *.jpg *.jpeg *.webp" 2>/dev/null) || exit 0
fi
xfconf-query -c xfce4-desktop \
    -p /backdrop/screen0/monitorVirtual1/workspace0/last-image \
    -s "$CHOICE" 2>/dev/null \
    || xfdesktop --reload 2>/dev/null || true
notify-send "🖼 MineOS" "Fond d'écran changé !" --icon=image-x-generic 2>/dev/null
EOF
chmod +x "$CHROOT/usr/local/bin/mineos-wallpaper"

write_chroot usr/share/applications/mineos-wallpaper.desktop << 'EOF'
[Desktop Entry]
Name=Changer le fond d'écran
Exec=mineos-wallpaper
Icon=preferences-desktop-wallpaper
Terminal=false
Type=Application
Categories=Settings;
EOF

# ─── .bashrc ──────────────────────────────────────────────────────────────
log ".bashrc MineOS"
write_chroot etc/skel/.bashrc << 'EOF'
# MineOS Gaming Edition
export LANG=fr_FR.UTF-8
export WINEFSYNC=1
export mesa_glthread=true
export DXVK_CONFIG_FILE="$HOME/.config/dxvk.conf"

PS1='\[\e[0;32m\]⛏ \[\e[1;36m\]\u\[\e[0;37m\]@\[\e[1;34m\]mineos\[\e[0;37m\]:\[\e[1;33m\]\w\[\e[0m\]\$ '

alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias ..='cd ..'
alias ...='cd ../..'

# MineOS Gaming
alias exe='gamemoderun wine'
alias exe-dxvk='DXVK_HUD=fps gamemoderun wine'
alias steam='gamemoderun steam'
alias browser='opera-gx'
alias gpu='mineos-gpu-info'
alias store='mineos-store'
alias wallpaper='mineos-wallpaper'
alias update='sudo apt-get update && sudo apt-get upgrade -y && flatpak update -y'

[ -f /etc/bash_completion ] && . /etc/bash_completion

echo ""
echo "  ⛏  MineOS Gaming Edition — Bienvenue !"
echo "  store | exe <app.exe> | exe-dxvk <app.exe> | gpu | update"
echo ""
EOF

# ─── LightDM auto-login ────────────────────────────────────────────────────
log "LightDM auto-login"
mkdir -p "$CHROOT/etc/lightdm"
write_chroot etc/lightdm/lightdm.conf << 'EOF'
[Seat:*]
autologin-user=user
autologin-user-timeout=0
greeter-session=lightdm-gtk-greeter
user-session=xfce
EOF

write_chroot etc/lightdm/lightdm-gtk-greeter.conf << 'EOF'
[greeter]
background=#1a1a2e
theme-name=MineOS-Dark
icon-theme-name=Papirus-Dark
font-name=Noto Sans 11
clock-format=%H:%M — %A %d %B
indicators=~host;~spacer;~clock;~spacer;~session;~power
EOF

# ─── Casper (live session) ─────────────────────────────────────────────────
log "Casper live session"
write_chroot etc/casper.conf << 'EOF'
export USERNAME="user"
export USERFULLNAME="MineOS Gaming User"
export HOST="mineos"
export BUILD_SYSTEM="MineOS"
EOF

# ─── Mise à jour des bases de données ──────────────────────────────────────
log "Mise à jour BDD (mime, desktop, icons)"
chroot "$CHROOT" /bin/bash -c "
update-mime-database /usr/share/mime       2>/dev/null || true
update-desktop-database                    2>/dev/null || true
gtk-update-icon-cache /usr/share/icons/hicolor 2>/dev/null || true
" || true

log "Configuration terminée ✓"
