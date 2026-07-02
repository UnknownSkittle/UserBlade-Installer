#!/bin/bash
# ============================================================
# UserBlade Unified Installer (Arc-Dark Plasma • Hard Fallback)
# ============================================================

set -e

LOG="/var/log/userblade-installer.log"
exec > >(tee -a "$LOG") 2>&1

log() { echo "[UserBlade] $*"; }

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

# ------------------------------------------------------------
# OS Branding
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# System update + base tools
# ------------------------------------------------------------
log "Updating system..."
pacman -Syu --noconfirm

log "Installing base tools..."
pacman -S --noconfirm wget curl git base-devel pciutils xdg-user-dirs || log "Base tools: some packages failed, continuing."

sudo -u "$USER" xdg-user-dirs-update || log "xdg-user-dirs-update failed, continuing."

# ------------------------------------------------------------
# Enable multilib
# ------------------------------------------------------------
if ! grep -q "^

\[multilib\]

" /etc/pacman.conf; then
  cat <<EOF >> /etc/pacman.conf

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
fi

pacman -Syu --noconfirm

# ------------------------------------------------------------
# Install yay (AUR helper)
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# Helper: safe pacman install
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# Install neofetch-git (AUR)
# ------------------------------------------------------------
log "Installing neofetch-git..."
safe_yay neofetch-git

# ------------------------------------------------------------
# KDE Plasma + SDDM
# ------------------------------------------------------------
log "Installing KDE Plasma + SDDM..."
safe_pacman plasma-desktop plasma-workspace plasma-systemmonitor \
  konsole dolphin systemsettings sddm sddm-kcm xdg-desktop-portal-kde

# ------------------------------------------------------------
# Apps (no Steam)
# ------------------------------------------------------------
log "Installing apps..."
safe_pacman ghex gimp vlc firefox qbittorrent thunderbird cpu-x

safe_yay bauh bottles discord whatsie visual-studio-code-bin onlyoffice-bin opentabletdriver

# ------------------------------------------------------------
# Audio stack (PipeWire + jack2 kept, pipewire-jack safety)
# ------------------------------------------------------------
log "Checking for pipewire-jack conflicts..."
if pacman -Q pipewire-jack >/dev/null 2>&1; then
    log "Removing pipewire-jack to prevent JACK conflicts..."
    pacman -Rns --noconfirm pipewire-jack || log "Failed to remove pipewire-jack, continuing."
fi

log "Installing PipeWire audio stack (jack2 retained)..."
safe_pacman pipewire pipewire-alsa pipewire-pulse wireplumber \
    pavucontrol-qt easyeffects helvum

# ------------------------------------------------------------
# GPU auto-detect (force overwrite for all drivers)
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# Remove other DEs (safe clean)
# ------------------------------------------------------------
log "Removing other DEs..."
pacman -Rns --noconfirm xfce4 xfce4-goodies gnome gnome-shell lxqt lxqt-session \
  lxde lxde-common cinnamon mate mate-extra budgie-desktop deepin \
  pantheon-session enlightenment i3-wm openbox 2>/dev/null || log "Some DEs not present, continuing."

systemctl disable lightdm gdm lxdm mdm slim 2>/dev/null || log "Some display managers not enabled, continuing."
pacman -Rns --noconfirm lightdm gdm lxdm mdm slim 2>/dev/null || log "Some display managers not present, continuing."

# ------------------------------------------------------------
# Wallpaper + icon
# ------------------------------------------------------------
log "Downloading wallpaper + icon..."
sudo -u "$USER" mkdir -p "$USER_HOME/Pictures" "$USER_HOME/Icons"

if ! sudo -u "$USER" wget -O "$USER_HOME/Pictures/userblade_wallpaper.jpg" "https://iili.io/C7P8pCg.jpg"; then
  log "Failed to download wallpaper, using placeholder."
  touch "$USER_HOME/Pictures/userblade_wallpaper.jpg"
fi

if ! sudo -u "$USER" wget -O "$USER_HOME/Icons/userblade_icon.png" "https://iili.io/C7ikyhX.png"; then
  log "Failed to download icon, using placeholder."
  touch "$USER_HOME/Icons/userblade_icon.png"
fi

# ------------------------------------------------------------
# Arc-Dark Plasma Theme (GTK + KDE + Kvantum)
# ------------------------------------------------------------
log "Installing Arc-Dark Plasma theme..."

safe_yay arc-gtk-theme-git

# Fallback GTK theme if Arc fails
if ! grep -q "Arc-Dark" "$USER_HOME/.config/gtk-3.0/settings.ini" 2>/dev/null; then
  log "Arc-Dark GTK may not be present, trying Materia as fallback..."
  safe_pacman materia-gtk-theme
fi

safe_pacman papirus-icon-theme breeze

# Kvantum with fallbacks
log "Installing Kvantum..."
if ! safe_pacman kvantum; then
  log "kvantum package failed, trying kvantum-qt5..."
  safe_pacman kvantum-qt5 || {
    log "kvantum-qt5 failed, trying kvantum-qt6..."
    safe_pacman kvantum-qt6 || log "All Kvantum variants failed, skipping Kvantum."
  }
fi

mkdir -p "$USER_HOME/.config"

# KDE globals
cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.config/kdeglobals" >/dev/null
[General]
ColorScheme=Arc-Dark-Plasma
widgetStyle=kvantum

[Icons]
Theme=Papirus-Dark

[CursorTheme]
Name=Breeze_Snow
EOF

# GTK3
mkdir -p "$USER_HOME/.config/gtk-3.0"
cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.config/gtk-3.0/settings.ini" >/dev/null
[Settings]
gtk-theme-name=Arc-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Breeze_Snow
EOF

# GTK4
mkdir -p "$USER_HOME/.config/gtk-4.0"
cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.config/gtk-4.0/settings.ini" >/dev/null
[Settings]
gtk-theme-name=Arc-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Breeze_Snow
EOF

# Kvantum Arc-Dark Plasma
mkdir -p "$USER_HOME/.config/Kvantum"
cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.config/Kvantum/kvantum.kvconfig" >/dev/null
[General]
theme=Arc-Dark-Plasma
EOF

# ------------------------------------------------------------
# Plasma layout + wallpaper
# ------------------------------------------------------------
log "Creating Plasma layout template..."
LAYOUT_DIR="$USER_HOME/.local/share/plasma/layout-templates"
mkdir -p "$LAYOUT_DIR"

cat <<EOF | sudo -u "$USER" tee "$LAYOUT_DIR/userblade.layout.lay" >/dev/null
[Desktop]
LayoutJS=org.kde.plasma.desktop-layout.js

[Containments][1]
plugin=org.kde.plasma.desktop
location=0
wallpaperplugin=org.kde.image

[Containments][1][Wallpaper][org.kde.image][General]
Image=file://$HOME/Pictures/userblade_wallpaper.jpg

[Containments][2]
plugin=org.kde.plasma.panel
location=3

[Containments][3]
plugin=org.kde.plasma.panel
location=1

[Containments][3][Applets][1]
plugin=org.kde.plasma.appmenu

[Containments][3][Applets][2]
plugin=org.kde.plasma.systemtray
EOF

# ------------------------------------------------------------
# Autostart: force layout + wallpaper
# ------------------------------------------------------------
log "Creating layout + wallpaper autostart..."
mkdir -p "$USER_HOME/.local/bin" "$USER_HOME/.config/autostart"

cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.local/bin/userblade-apply-layout.sh" >/dev/null
#!/bin/bash
LAYOUT="\$HOME/.local/share/plasma/layout-templates/userblade.layout.lay"

if command -v plasma-apply-layout >/dev/null 2>&1; then
  plasma-apply-layout "\$LAYOUT"
fi

if command -v qdbus >/dev/null 2>&1; then
  qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
    var allDesktops = desktops();
    for (var i=0;i<allDesktops.length;i++) {
      d = allDesktops[i];
      d.wallpaperPlugin = 'org.kde.image';
      d.currentConfigGroup = Array('Wallpaper', 'org.kde.image', 'General');
      d.writeConfig('Image', 'file://$HOME/Pictures/userblade_wallpaper.jpg');
    }
  "
fi
EOF

sudo -u "$USER" chmod +x "$USER_HOME/.local/bin/userblade-apply-layout.sh"

cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.config/autostart/userblade-apply-layout.desktop" >/dev/null
[Desktop Entry]
Type=Application
Exec=$HOME/.local/bin/userblade-apply-layout.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=UserBlade Layout
Comment=Force apply UserBlade layout + wallpaper
EOF

# ------------------------------------------------------------
# KSplash
# ------------------------------------------------------------
log "Configuring KSplash..."
cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.config/ksplashrc" >/dev/null
[KSplash]
Theme=org.kde.breeze
EOF

# ------------------------------------------------------------
# Plymouth boot splash (with tribar fallback)
# ------------------------------------------------------------
log "Installing Plymouth..."
safe_pacman plymouth

if ! safe_pacman plymouth-theme-tribar; then
  log "plymouth-theme-tribar failed, trying plymouth-theme-bgrt..."
  safe_pacman plymouth-theme-bgrt || log "All Plymouth themes failed, continuing with base plymouth only."
fi

log "Creating UserBlade Plymouth theme..."
PLY_DIR="/usr/share/plymouth/themes/userblade"
mkdir -p "$PLY_DIR"

if [ -d /usr/share/plymouth/themes/tribar ]; then
  cp -r /usr/share/plymouth/themes/tribar/* "$PLY_DIR"
elif [ -d /usr/share/plymouth/themes/bgrt ]; then
  cp -r /usr/share/plymouth/themes/bgrt/* "$PLY_DIR"
fi

cp "$USER_HOME/Icons/userblade_icon.png" "$PLY_DIR/userblade.png" || log "Failed to copy icon to Plymouth theme, continuing."

cat <<EOF > "$PLY_DIR/userblade.plymouth"
[Plymouth Theme]
Name=UserBlade
Description=UserBlade static logo
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/userblade
ScriptFile=/usr/share/plymouth/themes/userblade/userblade.script
EOF

cat <<'EOF' > "$PLY_DIR/userblade.script"
wallpaper_image = Image("userblade.png");
wallpaper_sprite = Sprite(wallpaper_image);
wallpaper_sprite.SetZ(100);
wallpaper_sprite.SetPosition(Screen.Width/2 - wallpaper_image.GetWidth()/2,
                             Screen.Height/2 - wallpaper_image.GetHeight()/2);
EOF

if command-v plymouth-set-default-theme >/dev/null 2>&1; then
  plymouth-set-default-theme userblade || log "Failed to set Plymouth theme, continuing."
else
  log "plymouth-set-default-theme not found, skipping theme set."
fi

log "Rebuilding initramfs..."
if command -v mkinitcpio >/dev/null 2>&1; then
  mkinitcpio -P || log "mkinitcpio failed, continuing."
else
  log "mkinitcpio not found, skipping initramfs rebuild."
fi

# ------------------------------------------------------------
# Neofetch ASCII
# ------------------------------------------------------------
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
        PURPLE BLACKARCH + SWORD
EOF

cat <<EOF > "$NEO_DIR/config.conf"
ascii_distro="ascii"
ascii_file="$HOME/.config/neofetch/ascii"
color_blocks="on"
EOF

# ------------------------------------------------------------
# Plasma session + SDDM
# ------------------------------------------------------------
log "Creating Plasma session file..."
cat <<'EOF' >/usr/share/xsessions/plasma.desktop
[Desktop Entry]
Type=XSession
Exec=startplasma-x11
TryExec=startplasma-x11
Name=Plasma
EOF

log "Enabling SDDM + graphical target..."
systemctl enable sddm || log "Failed to enable sddm, continuing."
systemctl set-default graphical.target || log "Failed to set graphical.target, continuing."

# ------------------------------------------------------------
# Ownership fix
# ------------------------------------------------------------
log "Fixing ownership..."
chown -R "$USER":"$USER" "$USER_HOME" || log "Failed to fix ownership, continuing."

log "Done. Reboot into KDE to activate Arc-Dark Plasma + full UserBlade layout."
