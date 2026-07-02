#!/bin/bash
# ============================================================
# UserBlade Unified Installer (Full Overwrite Version)
# ============================================================

LOG="/var/log/userblade-installer.log"
exec > >(tee -a "$LOG") 2>&1

USER="$SUDO_USER"
USER_HOME=$(eval echo "~$USER")

echo "[UserBlade] Starting unified installer..."

# ------------------------------------------------------------
# OS Branding
# ------------------------------------------------------------
echo "[UserBlade] Applying OS branding..."
cat <<EOF | sudo tee /etc/os-release >/dev/null
NAME="UserBlade"
PRETTY_NAME="UserBlade Linux"
ID=userblade
ID_LIKE=arch
EOF

cat <<EOF | sudo tee /etc/lsb-release >/dev/null
DISTRIB_ID=UserBlade
DISTRIB_RELEASE=1.0
DISTRIB_DESCRIPTION="UserBlade Linux"
EOF

echo "UserBlade Linux" | sudo tee /etc/issue >/dev/null

# ------------------------------------------------------------
# System Update + Tools
# ------------------------------------------------------------
pacman -Syu --noconfirm
pacman -S --noconfirm wget curl git base-devel pciutils xdg-user-dirs

sudo -u "$USER" xdg-user-dirs-update

# ------------------------------------------------------------
# Enable Multilib
# ------------------------------------------------------------
if ! grep -q "^

\[multilib\]

" /etc/pacman.conf; then
  echo "[UserBlade] Enabling multilib..."
  cat <<EOF >> /etc/pacman.conf

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
fi

pacman -Syu --noconfirm

# ------------------------------------------------------------
# Install KDE Plasma + SDDM
# ------------------------------------------------------------
echo "[UserBlade] Installing KDE Plasma..."
pacman -S --noconfirm plasma-desktop plasma-workspace plasma-systemmonitor \
  konsole dolphin systemsettings sddm sddm-kcm xdg-desktop-portal-kde

# ------------------------------------------------------------
# Install Apps
# ------------------------------------------------------------
echo "[UserBlade] Installing apps..."
pacman -S --noconfirm steam ghex gimp vlc firefox qbittorrent thunderbird cpu-x

sudo -u "$USER" yay -S --noconfirm \
  bauh \
  bottles \
  discord \
  whatsie \
  visual-studio-code-bin \
  onlyoffice-bin \
  opentabletdriver

# ------------------------------------------------------------
# Install Audio Stack
# ------------------------------------------------------------
pacman -S --noconfirm pipewire pipewire-alsa pipewire-pulse pipewire-jack \
  wireplumber pavucontrol-qt easyeffects helvum

# ------------------------------------------------------------
# GPU Auto-Detect
# ------------------------------------------------------------
GPU=$(lspci | grep -i 'vga\|3d\|display' | tr '[:upper:]' '[:lower:]')

if echo "$GPU" | grep -q "amd"; then
  pacman -S --noconfirm xf86-video-amdgpu
elif echo "$GPU" | grep -q "intel"; then
  pacman -S --noconfirm xf86-video-intel
elif echo "$GPU" | grep -q "nvidia"; then
  if pacman -S --noconfirm nvidia nvidia-utils; then
    echo "[UserBlade] NVIDIA proprietary installed."
  else
    pacman -S --noconfirm xf86-video-nouveau
  fi
else
  echo "[UserBlade] Unknown GPU, using Mesa."
fi

# ------------------------------------------------------------
# Remove Other DEs (Safe Clean)
# ------------------------------------------------------------
echo "[UserBlade] Removing other DEs..."
pacman -Rns --noconfirm xfce4 xfce4-goodies gnome gnome-shell lxqt lxqt-session \
  lxde lxde-common cinnamon mate mate-extra budgie-desktop deepin \
  pantheon-session enlightenment i3-wm openbox 2>/dev/null

systemctl disable lightdm gdm lxdm mdm slim 2>/dev/null
pacman -Rns --noconfirm lightdm gdm lxdm mdm slim 2>/dev/null

# ------------------------------------------------------------
# Wallpaper + Icon
# ------------------------------------------------------------
sudo -u "$USER" mkdir -p "$USER_HOME/Pictures" "$USER_HOME/Icons"

sudo -u "$USER" wget -O "$USER_HOME/Pictures/userblade_wallpaper.jpg" "https://iili.io/C7P8pCg.jpg"
sudo -u "$USER" wget -O "$USER_HOME/Icons/userblade_icon.png" "https://iili.io/C7ikyhX.png"

# ------------------------------------------------------------
# KDE Theme Injection (Full Overwrite)
# ------------------------------------------------------------
echo "[UserBlade] Applying theme..."

cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.config/kdeglobals" >/dev/null
[General]
ColorScheme=UserBlade
widgetStyle=Arc-Dark

[Icons]
Theme=Papirus-Dark

[CursorTheme]
Name=Breeze_Snow
EOF

mkdir -p "$USER_HOME/.config/gtk-3.0" "$USER_HOME/.config/gtk-4.0"

cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.config/gtk-3.0/settings.ini" >/dev/null
[Settings]
gtk-theme-name=Arc-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Breeze_Snow
EOF

cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.config/gtk-4.0/settings.ini" >/dev/null
[Settings]
gtk-theme-name=Arc-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Breeze_Snow
EOF

# ------------------------------------------------------------
# KDE Layout (Right Dock + Top Bar)
# ------------------------------------------------------------
echo "[UserBlade] Applying layout..."

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
Image=file://$USER_HOME/Pictures/userblade_wallpaper.jpg

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

sudo -u "$USER" plasma-apply-layout "$LAYOUT_DIR/userblade.layout.lay"

# ------------------------------------------------------------
# SDDM Theme
# ------------------------------------------------------------
mkdir -p /etc/sddm.conf.d
cat <<EOF | sudo tee /etc/sddm.conf.d/theme.conf >/dev/null
[Theme]
Current=breeze
EOF

# ------------------------------------------------------------
# Plasma Session File
# ------------------------------------------------------------
cat <<EOF | sudo tee /usr/share/xsessions/plasma.desktop >/dev/null
[Desktop Entry]
Type=XSession
Exec=startplasma-x11
TryExec=startplasma-x11
Name=Plasma
EOF

# ------------------------------------------------------------
# Enable SDDM + Graphical Target
# ------------------------------------------------------------
systemctl enable sddm
systemctl set-default graphical.target

# ------------------------------------------------------------
# Fix Ownership
# ------------------------------------------------------------
chown -R "$USER":"$USER" "$USER_HOME"

echo "[UserBlade] Installation complete!"
echo "[UserBlade] Reboot to enter full UserBlade KDE."
