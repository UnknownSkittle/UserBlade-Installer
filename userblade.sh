#!/bin/bash
# ============================================================
# UserBlade Unified Installer (Plasma 6.7.2 Fixed)
# ============================================================

set -e

LOG="/var/log/userblade-installer.log"
exec > >(tee -a "$LOG") 2>&1

log() { echo "[UserBlade] $*"; }

# Root + user detection
if [ "$(id -u)" -ne 0 ]; then
  log "Run as root: sudo bash userblade-installer.sh"
  exit 1
fi

if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
  USER="$SUDO_USER"
else
  USER=$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd)
fi

USER_HOME=$(eval echo "~$USER")
log "Target user: $USER ($USER_HOME)"

# Helpers
safe_pacman() {
  pacman -S --noconfirm "$@" || log "pacman: failed to install $*, continuing."
}

safe_yay() {
  if command -v yay >/dev/null 2>&1; then
    sudo -u "$USER" yay -S --noconfirm "$@" || log "yay: failed to install $*, continuing."
  else
    log "yay not available, skipping AUR package: $*"
  fi
}

# Image handling (direct URLs)
download_image() {
  local url="$1"
  local output="$2"
  local max_retries=3
  local retry=0
  
  while [ $retry -lt $max_retries ]; do
    if sudo -u "$USER" wget -q -O "$output" "$url" 2>/dev/null; then
      log "Downloaded: $output"
      return 0
    fi
    retry=$((retry + 1))
    log "Retry $retry/$max_retries for: $url"
    sleep 2
  done
  
  log "Failed to download $url, creating fallback"
  return 1
}

# Icon cache rebuild (fixes missing app icons)
rebuild_icon_cache() {
  log "Rebuilding icon caches..."
  sudo -u "$USER" gtk-update-icon-cache -f -t "$USER_HOME/.local/share/icons" 2>/dev/null || true
  sudo -u "$USER" gtk-update-icon-cache -f -t "/usr/share/icons/hicolor" 2>/dev/null || true
  if command -v update-mime-database >/dev/null 2>&1; then
    update-mime-database /usr/share/mime 2>/dev/null || true
  fi
}

# OS Branding
log "Applying OS branding..."

cat <<EOF >/etc/os-release
NAME="UserBlade"
PRETTY_NAME="UserBlade Linux"
ID=userblade
ID_LIKE=arch
EOF

cat <<EOF >/etc/lsb-release
DISTRIB_ID=UserBlade
DISTRIB_RELEASE=1.0
DISTRIB_DESCRIPTION="UserBlade Linux"
EOF

echo "UserBlade Linux" >/etc/issue

# System update + base tools
log "Updating system..."
pacman -Syu --noconfirm

log "Installing base tools..."
safe_pacman wget curl git base-devel pciutils xdg-user-dirs imagemagick

sudo -u "$USER" xdg-user-dirs-update || log "xdg-user-dirs-update failed, continuing."

# Install Plasma 6 tools
safe_pacman kdeconnect kconfig kconfigwidgets

# Enable multilib
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
  cat <<EOF >> /etc/pacman.conf

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
fi

pacman -Syu --noconfirm

# Install yay (AUR helper)
if ! command -v yay >/dev/null 2>&1; then
  log "Installing yay..."
  sudo -u "$USER" git clone https://aur.archlinux.org/yay.git "$USER_HOME/yay" || log "Failed to clone yay, continuing without AUR."
  if [ -d "$USER_HOME/yay" ]; then
    chown -R "$USER":"$USER" "$USER_HOME/yay"
    cd "$USER_HOME/yay"
    sudo -u "$USER" makepkg -si --noconfirm || log "Failed to build yay, continuing without AUR."
    cd "$USER_HOME"
  fi
fi

# neofetch-git (AUR)
log "Installing neofetch-git..."
safe_yay neofetch-git

# KDE Plasma 6 + SDDM
log "Installing KDE Plasma 6 + SDDM..."
safe_pacman plasma-desktop plasma-workspace plasma-systemmonitor plasma-pa \
  konsole dolphin systemsettings sddm sddm-kcm xdg-desktop-portal-kde \
  plasma-browser-integration kdeconnect

# Plasma 6 specific packages
safe_pacman kscreenlocker kglobalshortcuts kwin kdeclarative

# Apps (no Steam)
log "Installing apps..."
safe_pacman ghex gimp vlc firefox qbittorrent thunderbird cpu-x

safe_yay bauh bottles discord whatsie visual-studio-code-bin onlyoffice-bin opentabletdriver

# Ensure icon theme packages are installed
safe_pacman papirus-icon-theme breeze adwaita-icon-theme

# Audio stack (PipeWire + jack2 kept, pipewire-jack safety)
log "Checking for pipewire-jack conflicts..."
if pacman -Q pipewire-jack >/dev/null 2>&1; then
    log "Removing pipewire-jack to prevent JACK conflicts..."
    pacman -Rns --noconfirm pipewire-jack || log "Failed to remove pipewire-jack, continuing."
fi

log "Installing PipeWire audio stack..."
safe_pacman pipewire pipewire-alsa pipewire-pulse wireplumber \
    pavucontrol-qt easyeffects helvum

# Enable PipeWire user services
sudo -u "$USER" systemctl --user enable pipewire pipewire-pulse wireplumber 2>/dev/null || log "PipeWire user services may need manual enable."

# GPU auto-detect (force overwrite for all drivers)
log "Detecting GPU..."
GPU=$(lspci | grep -i 'vga\|3d\|display' | tr '[:upper:]' '[:lower:]' || echo "")

if echo "$GPU" | grep -q "amd"; then
    log "Installing AMD driver with overwrite..."
    pacman -S --overwrite '*' --noconfirm xf86-video-amdgpu || log "AMD driver failed, falling back to Mesa."
elif echo "$GPU" | grep -q "intel"; then
    log "Installing Intel driver with overwrite..."
    pacman -S --overwrite '*' --noconfirm xf86-video-intel || log "Intel driver failed, falling back to Mesa."
elif echo "$GPU" | grep -q "nvidia"; then
    log "Installing NVIDIA driver with overwrite..."
    pacman -S --overwrite '*' --noconfirm nvidia nvidia-utils || {
      log "NVIDIA proprietary failed, trying nouveau..."
      pacman -S --overwrite '*' --noconfirm xf86-video-nouveau || log "NVIDIA drivers failed, falling back to Mesa."
    }
else
    log "Unknown GPU, using Mesa."
fi

# Install vulkan support for better compatibility
safe_pacman vulkan-radeon vulkan-intel || log "Vulkan drivers not available for this GPU."

# Remove other DEs (safe clean)
log "Removing other DEs..."
pacman -Rns --noconfirm xfce4 xfce4-goodies gnome gnome-shell lxqt lxqt-session \
  lxde lxde-common cinnamon mate mate-extra budgie-desktop deepin \
  pantheon-session enlightenment i3-wm openbox 2>/dev/null || log "Some DEs not present, continuing."

systemctl disable lightdm gdm lxdm mdm slim 2>/dev/null || log "Some display managers not enabled, continuing."
pacman -Rns --noconfirm lightdm gdm lxdm mdm slim 2>/dev/null || log "Some display managers not present, continuing."

# Ensure xorg is installed for KDE
safe_pacman xorg-server xorg-xinit

# Wallpaper + icon (direct web links)
log "Setting up wallpaper + icon..."
sudo -u "$USER" mkdir -p "$USER_HOME/Pictures" "$USER_HOME/Icons"

# Direct image URLs
WALLPAPER_URL="https://iili.io/CY0S5dl.jpg"
ICON_URL="https://iili.io/C7ikyhX.png"

download_image "$WALLPAPER_URL" "$USER_HOME/Pictures/userblade_wallpaper.jpg"
download_image "$ICON_URL" "$USER_HOME/Icons/userblade_icon.png"

# Create cache directory
sudo -u "$USER" mkdir -p "$USER_HOME/.cache/userblade"

# Store URLs for future updates
echo "$WALLPAPER_URL" > "$USER_HOME/.cache/userblade/wallpaper.url"
echo "$ICON_URL" > "$USER_HOME/.cache/userblade/icon.url"

# Ensure ownership
chown -R "$USER":"$USER" "$USER_HOME/Pictures" "$USER_HOME/Icons" "$USER_HOME/.cache/userblade"

# Arc-Dark Plasma Theme (GTK + KDE + Kvantum + Plasma 6)
log "Installing Arc-Dark Plasma theme..."

# Theme packages for Plasma 6
safe_yay arc-gtk-theme-git
safe_pacman papirus-icon-theme papirus-folders breeze-icons

log "Installing Kvantum for Plasma 6..."
safe_pacman kvantum

# Fallback if kvantum not available
if ! command -v kvantummanager >/dev/null 2>&1; then
  log "Kvantum not found, trying alternative..."
  safe_pacman kvantum-qt6 || log "Kvantum installation failed."
fi

# Install Breeze for fallback theme
safe_pacman breeze breeze-gtk

# Create Plasma 6 config structure
sudo -u "$USER" mkdir -p "$USER_HOME/.config"

# KDE Globals for Plasma 6
cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.config/kdeglobals" >/dev/null
[General]
ColorScheme=BreezeDark
WidgetStyle=breeze

[Icons]
Theme=Papirus-Dark

[CursorTheme]
Name=Breeze_Snow

[KDE]
ShowIconsInMenuItems=true
ShowDeleteCommand=false

[Tour]
ShowOnStart=false
EOF

# GTK3 configuration
sudo -u "$USER" mkdir -p "$USER_HOME/.config/gtk-3.0"
cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.config/gtk-3.0/settings.ini" >/dev/null
[Settings]
gtk-theme-name=Arc-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Breeze_Snow
gtk-application-prefer-dark-theme=1
gtk-font-name=Noto Sans 10
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintslight
EOF

# GTK4 configuration
sudo -u "$USER" mkdir -p "$USER_HOME/.config/gtk-4.0"
cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.config/gtk-4.0/settings.ini" >/dev/null
[Settings]
gtk-theme-name=Arc-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Breeze_Snow
gtk-application-prefer-dark-theme=1
EOF

# Kvantum configuration for Arc-Dark
sudo -u "$USER" mkdir -p "$USER_HOME/.config/Kvantum"
cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.config/Kvantum/kvantum.kvconfig" >/dev/null
[General]
theme=Arc-Dark
EOF

# Fix icon theme symlink for Papirus
sudo -u "$USER" ln -sf /usr/share/icons/Papirus-Dark "$USER_HOME/.local/share/icons/Papirus-Dark" 2>/dev/null || true

# Ensure ownership
chown -R "$USER":"$USER" "$USER_HOME/.config" "$USER_HOME/.local"

# Plasma 6 Panel Layout (Top bar + Right sidebar)
log "Creating Plasma 6 layout: Top panel + Right sidebar..."

LAYOUT_TEMPLATE_DIR="$USER_HOME/.local/share/plasma/layout-templates"
LAYOUT_DIR="$USER_HOME/.local/share/plasma/plasmashell/layouts"
sudo -u "$USER" mkdir -p "$LAYOUT_TEMPLATE_DIR" "$LAYOUT_DIR"

# Create a layout template that Plasma 6 can apply directly
cat <<'LAYOUT_EOF' | sudo -u "$USER" tee "$LAYOUT_TEMPLATE_DIR/userblade.layout.lay" >/dev/null
[Desktop]
LayoutJS=org.kde.plasma.desktop-layout.js

[Containments][1]
plugin=org.kde.plasma.desktop
location=0
wallpaperplugin=org.kde.image

[Containments][1][Wallpaper][org.kde.image][General]
Image=file://$USER_HOME/Pictures/userblade_wallpaper.jpg

[Containments][2]
plugin=org.kde.plasma.panel
location=1

[Containments][2][Applets][1]
plugin=org.kde.plasma.kickoff

[Containments][2][Applets][2]
plugin=org.kde.plasma.taskmanager

[Containments][2][Applets][3]
plugin=org.kde.plasma.systemtray

[Containments][2][Applets][4]
plugin=org.kde.plasma.digitalclock

[Containments][3]
plugin=org.kde.plasma.panel
location=3

[Containments][3][Applets][1]
plugin=org.kde.plasma.taskmanager

[Containments][3][Applets][2]
plugin=org.kde.plasma.systemtray
LAYOUT_EOF

# Keep the layout file pointing at the real wallpaper path
sudo -u "$USER" sed -i "s|^Image=.*$|Image=file://$USER_HOME/Pictures/userblade_wallpaper.jpg|" "$LAYOUT_TEMPLATE_DIR/userblade.layout.lay"

chown -R "$USER":"$USER" "$LAYOUT_TEMPLATE_DIR" "$LAYOUT_DIR"

# KDE Plasma RC configuration for Plasma 6
cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.config/plasmarc" >/dev/null
[General]
sessions=plasmawayland

[PlasmaViewer]
PreviewPlugins=true
EOF

# Kwinrc for window manager
cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.config/kwinrc" >/dev/null
[General]
BorderlessMaximizedWindows=true
FocusPolicy=ClickToFocus

[Compositing]
Enabled=true
GLCore=true
Backend=glx

[DesktopSwitching]
VirtualDesktops=1
EOF

# Ensure proper permissions
chown -R "$USER":"$USER" "$USER_HOME/.config/kdeglobals" "$USER_HOME/.config/kwinrc" "$USER_HOME/.config/plasmarc"

# Autostart: Apply layout, wallpaper, and theme on login
log "Creating layout + wallpaper + theme autostart..."
sudo -u "$USER" mkdir -p "$USER_HOME/.local/bin" "$USER_HOME/.config/autostart"

# Main application script
cat <<'EOF' | sudo -u "$USER" tee "$USER_HOME/.local/bin/userblade-apply-layout.sh" >/dev/null
#!/bin/bash
set -e

export XDG_CURRENT_DESKTOP=KDE
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

HOME_DIR="$HOME"
WALLPAPER="$HOME_DIR/Pictures/userblade_wallpaper.jpg"
LAYOUT="$HOME_DIR/.local/share/plasma/layout-templates/userblade.layout.lay"
MARKER="$HOME_DIR/.local/share/userblade-layout-applied"

mkdir -p "$HOME_DIR/.local/share"

log() {
  echo "[UserBlade Layout] $*" | tee -a "$HOME_DIR/.local/share/userblade.log"
}

if [ -f "$MARKER" ]; then
  log "Already applied once; exiting."
  exit 0
fi

log "Starting layout application..."
sleep 5

# 1. Apply wallpaper with the supported Plasma 6 tool when present
if [ -f "$WALLPAPER" ]; then
  if command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
    log "Applying wallpaper with plasma-apply-wallpaperimage"
    plasma-apply-wallpaperimage "$WALLPAPER" 2>/dev/null || true
  fi

  if command -v qdbus-qt6 >/dev/null 2>&1; then
    QDBUS="qdbus-qt6"
  elif command -v qdbus >/dev/null 2>&1; then
    QDBUS="qdbus"
  else
    QDBUS=""
  fi

  if [ -n "$QDBUS" ]; then
    log "Applying wallpaper via DBus fallback"
    "$QDBUS" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
      var allDesktops = desktops();
      for (var i=0; i<allDesktops.length; i++) {
        d = allDesktops[i];
        d.wallpaperPlugin = 'org.kde.image';
        d.currentConfigGroup = Array('Wallpaper', 'org.kde.image', 'General');
        d.writeConfig('Image', 'file://$HOME_DIR/Pictures/userblade_wallpaper.jpg');
      }
    " 2>/dev/null || true
  fi
fi

# 2. Apply color/icon theme with Plasma 6 tools
if command -v kwriteconfig6 >/dev/null 2>&1; then
  log "Applying theme settings"
  kwriteconfig6 --file "$HOME_DIR/.config/kdeglobals" --group Icons --key Theme Papirus-Dark 2>/dev/null || true
  kwriteconfig6 --file "$HOME_DIR/.config/kdeglobals" --group General --key ColorScheme BreezeDark 2>/dev/null || true
fi

if command -v lookandfeeltool >/dev/null 2>&1; then
  log "Applying look-and-feel"
  lookandfeeltool -a org.kde.breezedark.desktop 2>/dev/null || true
fi

# 3. Apply the layout template if the tool exists
if command -v plasma-apply-layout >/dev/null 2>&1 && [ -f "$LAYOUT" ]; then
  log "Applying Plasma layout template"
  plasma-apply-layout "$LAYOUT" 2>/dev/null || true
fi

# 4. Rebuild icon cache and refresh GTK theme
log "Rebuilding icon caches"
gtk-update-icon-cache -f -t "$HOME_DIR/.local/share/icons" 2>/dev/null || true
gtk-update-icon-cache -f -t "/usr/share/icons/hicolor" 2>/dev/null || true
export GTK_THEME=Arc-Dark:dark

# 5. Reload Plasma shell
if command -v kquitapp6 >/dev/null 2>&1; then
  log "Reloading Plasma shell"
  kquitapp6 plasmashell 2>/dev/null || true
  sleep 2
  /usr/bin/plasmashell >/dev/null 2>&1 &
fi

touch "$MARKER"
log "Layout application complete"
EOF

sudo -u "$USER" chmod +x "$USER_HOME/.local/bin/userblade-apply-layout.sh"

# Desktop entry for autostart
cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.config/autostart/userblade-apply-layout.desktop" >/dev/null
[Desktop Entry]
Type=Application
Exec=$USER_HOME/.local/bin/userblade-apply-layout.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
X-KDE-autostart-phase=2
X-KDE-StartupNotify=false
Name=UserBlade Layout Initializer
Comment=Apply UserBlade layout, wallpaper, and theme
StartupNotify=false
Terminal=false
OnlyShowIn=KDE;
EOF

chown -R "$USER":"$USER" "$USER_HOME/.local/bin/userblade-apply-layout.sh" "$USER_HOME/.config/autostart"

# Fallback service so the style/layout hook runs reliably after login
sudo -u "$USER" mkdir -p "$USER_HOME/.config/systemd/user"
cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.config/systemd/user/userblade-apply-layout.service" >/dev/null
[Unit]
Description=UserBlade layout and theme application
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=$USER_HOME/.local/bin/userblade-apply-layout.sh

[Install]
WantedBy=default.target
EOF

sudo -u "$USER" systemctl --user daemon-reload 2>/dev/null || true
sudo -u "$USER" systemctl --user enable userblade-apply-layout.service 2>/dev/null || true

# Rebuild icon caches now
log "Rebuilding icon caches..."
rebuild_icon_cache

# Update database caches for GTK applications
update-desktop-database "$USER_HOME/.local/share/applications" 2>/dev/null || true

# KSplash (Login screen splash)
log "Configuring KSplash..."
cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.config/ksplashrc" >/dev/null
[KSplash]
Engine=KSplashQML
Theme=org.kde.breezedark.desktop
EOF

# Also set in global config
mkdir -p /etc/skel/.config
cat <<EOF | tee /etc/skel/.config/ksplashrc >/dev/null
[KSplash]
Engine=KSplashQML
Theme=org.kde.breezedark.desktop
EOF

# Plymouth boot splash
log "Installing Plymouth..."
safe_pacman plymouth

# Install theme
if ! safe_pacman plymouth-theme-tribar; then
  log "tribar theme unavailable, trying bgrt..."
  safe_pacman plymouth-theme-bgrt || log "Plymouth themes not available."
fi

log "Configuring Plymouth..."
PLY_DIR="/usr/share/plymouth/themes/userblade"
mkdir -p "$PLY_DIR"

# Copy base theme
if [ -d /usr/share/plymouth/themes/tribar ]; then
  cp -r /usr/share/plymouth/themes/tribar/* "$PLY_DIR/" 2>/dev/null || true
elif [ -d /usr/share/plymouth/themes/bgrt ]; then
  cp -r /usr/share/plymouth/themes/bgrt/* "$PLY_DIR/" 2>/dev/null || true
else
  log "No Plymouth theme found, creating minimal theme..."
  mkdir -p "$PLY_DIR"
fi

# Copy icon if available
if [ -f "$USER_HOME/Icons/userblade_icon.png" ]; then
  cp "$USER_HOME/Icons/userblade_icon.png" "$PLY_DIR/userblade.png"
fi

# Create Plymouth theme config
cat <<EOF > "$PLY_DIR/userblade.plymouth"
[Plymouth Theme]
Name=UserBlade
Description=UserBlade boot theme
ModuleName=script

[script]
ImageDir=$PLY_DIR
ScriptFile=$PLY_DIR/userblade.script
EOF

# Simple Plymouth script
cat <<'EOF' > "$PLY_DIR/userblade.script"
wallpaper_image = Image("userblade.png");
wallpaper_sprite = Sprite(wallpaper_image);
wallpaper_sprite.SetZ(100);
wallpaper_sprite.SetPosition(Screen.Width/2 - wallpaper_image.GetWidth()/2,
                             Screen.Height/2 - wallpaper_image.GetHeight()/2);
EOF

# Set Plymouth theme
if command -v plymouth-set-default-theme >/dev/null 2>&1; then
  plymouth-set-default-theme userblade || log "Failed to set Plymouth theme."
fi

# Rebuild initramfs
log "Rebuilding initramfs..."
if command -v mkinitcpio >/dev/null 2>&1; then
  mkinitcpio -P || log "mkinitcpio failed, continuing."
fi

# Neofetch ASCII + Config
log "Setting custom neofetch ASCII..."
NEO_DIR="$USER_HOME/.config/neofetch"
mkdir -p "$NEO_DIR"

cat <<'EOF' > "$NEO_DIR/ascii"
                 /\
                /  \
               / /\ \
              / /  \ \
     /\      / /    \ \
    /  \    / /  /\  \ \
   / /\ \  / /  /  \  \ \
  / /  \ \/ /  / /\ \  \ \
 / /    \  /  / /  \ \  \ \
/_/      \/__/ /    \_\  \ \
\ \      /  \_\      / /  / /
 \ \    / /\  \     / /  / /
  \ \  / /  \  \   / /  / /
   \ \/ /    \  \_/ /  / /
    \  /      \____/  / /
     \/        USERBLADE
         ARCH LINUX
EOF

cat <<EOF > "$NEO_DIR/config.conf"
print_info() {
    info title
    info underline
    info "OS" distro
    info "Host" model
    info "Kernel" kernel
    info "Uptime" uptime
    info "Packages" packages
    info "Shell" shell
    info "DE" de
    info "WM" wm
    info "Terminal" term
    info "CPU" cpu
    info "GPU" gpu
    info "Memory" memory
}

distro_shorthand="on"
kernel_shorthand="on"
uptime_shorthand="on"
memory_shorthand="on"
color_blocks="on"
block_range=(0 15)
bold="on"
image_backend="auto"
ascii_distro="ascii"
EOF

chown -R "$USER":"$USER" "$NEO_DIR"

# SDDM Configuration (Login screen)
log "Configuring SDDM..."
mkdir -p /etc/sddm.conf.d

cat <<EOF | tee /etc/sddm.conf.d/userblade.conf >/dev/null
[General]
Session=plasmawayland
Locale=en_US
Theme=breeze
Cursor=breeze_cursors
Font=Noto Sans,10,-1,5,50,0,0,0,0,0
NumLock=on
EOF

# Fallback SDDM config
if [ ! -f /etc/sddm.conf ]; then
  cat <<EOF | tee /etc/sddm.conf >/dev/null
[General]
Session=plasmawayland
Locale=en_US
Theme=breeze
Cursor=breeze_cursors
Font=Noto Sans,10,-1,5,50,0,0,0,0,0
NumLock=on
EOF
fi

# Install Breeze SDDM theme
safe_pacman sddm-theme-breeze || safe_pacman breeze

# Ensure correct SDDM user
mkdir -p /var/lib/sddm
chown -R sddm:sddm /var/lib/sddm 2>/dev/null || true

# Enable services
log "Enabling display manager + graphical target..."
systemctl enable sddm || log "Failed to enable sddm, continuing."
systemctl set-default graphical.target || log "Failed to set graphical.target, continuing."

# Enable any pending user services
systemctl --user enable --now dbus 2>/dev/null || log "User dbus may not be ready."

# Final cleanup + ownership fix
log "Fixing ownership..."
chown -R "$USER":"$USER" "$USER_HOME" || log "Failed to fix ownership, continuing."

# Clear package manager cache
pacman -Scc --noconfirm 2>/dev/null || true

# Ensure permissions for autostart
chmod 755 "$USER_HOME/.config/autostart"
chmod 644 "$USER_HOME/.config/autostart"/*.desktop

# Final icon cache rebuild
log "Final icon cache rebuild..."
rebuild_icon_cache

log "================================================================"
log "UserBlade installation complete!"
log "================================================================"
log "Reboot the system to start fresh KDE Plasma 6.7.2 experience"
log "The following will be applied on first login:"
log "  - Top panel with clock, apps, system tray"
log "  - Right sidebar with taskbar"
log "  - Arc-Dark theme with Papirus icons"
log "  - Custom wallpaper"
log "  - Optimized audio with PipeWire"
log "  - All app icons properly cached"
log "================================================================"
log "System log: $LOG"
log "User log: $USER_HOME/.local/share/userblade.log"
