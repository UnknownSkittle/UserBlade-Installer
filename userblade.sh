#!/bin/bash

# --------------------------------
# BASIC SAFETY + LOGGING
# --------------------------------
LOG_FILE="/var/log/userblade-installer.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "[UserBlade] Installer started at $(date)"

# --------------------------------
# ROOT + USER DETECTION
# --------------------------------
if [ "$(id -u)" -ne 0 ]; then
  echo "[UserBlade][ERROR] Run this script with sudo: sudo ./userblade.sh"
  exit 1
fi

if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
  USER="$SUDO_USER"
else
  USER=$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd)
fi

if [ -z "$USER" ]; then
  echo "[UserBlade][ERROR] Could not detect a non-root user. Create one first."
  exit 1
fi

USER_HOME=$(eval echo "~$USER")
echo "[UserBlade] Target user: $USER ($USER_HOME)"

# --------------------------------
# DISK SPACE INFO
# --------------------------------
FREE_KB=$(df --output=avail / | tail -n1)
FREE_GB=$((FREE_KB / 1024 / 1024))
echo "[UserBlade] Free space: ${FREE_GB}GB (recommended: >= 20GB)"
sleep 2

# --------------------------------
# SYSTEM UPDATE + CORE TOOLS
# --------------------------------
echo "[UserBlade] Updating system and installing core tools..."
pacman -Syu --noconfirm || echo "[UserBlade][WARN] pacman -Syu failed, continuing..."
pacman -S --noconfirm wget curl pciutils xdg-user-dirs || echo "[UserBlade][WARN] Core tools install failed, continuing..."
sudo -u "$USER" xdg-user-dirs-update || echo "[UserBlade][WARN] xdg-user-dirs-update failed, continuing..."

# --------------------------------
# KDE PLASMA CORE
# --------------------------------
echo "[UserBlade] Installing KDE Plasma core..."
pacman -S --noconfirm \
  plasma-desktop \
  plasma-workspace \
  plasma-workspace-wallpapers \
  plasma-systemmonitor \
  konsole \
  dolphin \
  systemsettings \
  sddm sddm-kcm \
  xdg-desktop-portal-kde || echo "[UserBlade][WARN] KDE core install failed, continuing..."

# --------------------------------
# FLATPAK + GVFS
# --------------------------------
echo "[UserBlade] Installing Flatpak + GVFS..."
pacman -S --noconfirm flatpak gvfs gvfs-mtp gvfs-gphoto2 gvfs-afc gvfs-smb || echo "[UserBlade][WARN] Flatpak/GVFS install failed, continuing..."
sudo -u "$USER" flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || echo "[UserBlade][WARN] Flathub add failed, continuing..."

# --------------------------------
# WALLPAPER + ICON
# --------------------------------
echo "[UserBlade] Downloading wallpaper and icon..."
mkdir -p "$USER_HOME/Pictures" "$USER_HOME/Icons"
sudo -u "$USER" wget -O "$USER_HOME/Pictures/userblade_wallpaper.jpg" "https://iili.io/C7P8pCg.jpg" || echo "[UserBlade][WARN] Wallpaper download failed."
sudo -u "$USER" wget -O "$USER_HOME/Icons/userblade_icon.png" "https://iili.io/C7ikyhX.png" || echo "[UserBlade][WARN] Icon download failed."

echo "UserBlade (Arch/BlackArch-based)" > /etc/issue
echo "UserBlade" > /etc/userblade-name

# --------------------------------
# MULTILIB FOR STEAM
# --------------------------------
echo "[UserBlade] Ensuring multilib is enabled..."
if ! grep -E '^

\[multilib\]

' /etc/pacman.conf >/dev/null 2>&1; then
  cat <<'EOF' >> /etc/pacman.conf

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
  pacman -Syu --noconfirm || echo "[UserBlade][WARN] pacman -Syu after multilib failed, continuing..."
fi

# --------------------------------
# YAY (AUR HELPER)
# --------------------------------
echo "[UserBlade] Installing yay (AUR helper)..."
pacman -S --noconfirm base-devel git || echo "[UserBlade][WARN] base-devel/git install failed, continuing..."

YAY_DIR="$USER_HOME/yay"
if [ -d "$YAY_DIR" ]; then
  OWNER=$(stat -c "%U" "$YAY_DIR")
  if [ "$OWNER" != "$USER" ]; then
    chown -R "$USER":"$USER" "$YAY_DIR"
  fi
fi

if ! command -v yay >/dev/null 2>&1; then
  cd "$USER_HOME"
  if [ ! -d yay ]; then
    sudo -u "$USER" git clone https://aur.archlinux.org/yay.git || echo "[UserBlade][WARN] yay clone failed."
  fi
  cd yay 2>/dev/null || cd "$USER_HOME"
  sudo -u "$USER" makepkg -si --noconfirm || echo "[UserBlade][WARN] yay build/install failed."
  cd "$USER_HOME"
fi

# --------------------------------
# THEMING + QT CONTROL
# --------------------------------
echo "[UserBlade] Installing theming (Kvantum, Arc, Papirus, qt5ct/qt6ct)..."
sudo -u "$USER" yay -S --noconfirm kvantum-theme-arc arc-kde papirus-icon-theme qt5ct qt6ct || echo "[UserBlade][WARN] theming AUR packages failed."

echo "[UserBlade] Configuring Kvantum..."
mkdir -p "$USER_HOME/.config/Kvantum"
cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.config/Kvantum/kvantum.kvconfig" >/dev/null
[General]
theme=Arc-Dark
EOF

# --------------------------------
# DRIVERS
# --------------------------------
echo "[UserBlade] Installing firmware and GPU drivers..."
pacman -S --noconfirm linux-firmware mesa || echo "[UserBlade][WARN] firmware/mesa install failed."

GPU_INFO=$(lspci | grep -i 'vga\|3d\|display' || true)
echo "[UserBlade] GPU detected: $GPU_INFO"

if echo "$GPU_INFO" | grep -qi amd; then
  pacman -S --noconfirm xf86-video-amdgpu || echo "[UserBlade][WARN] AMD driver install failed."
elif echo "$GPU_INFO" | grep -qi intel; then
  pacman -S --noconfirm xf86-video-intel || echo "[UserBlade][WARN] Intel driver install failed."
elif echo "$GPU_INFO" | grep -qi nvidia; then
  echo "[UserBlade][INFO] NVIDIA detected. Install proprietary drivers manually:"
  echo "  sudo pacman -S nvidia nvidia-utils"
fi

# --------------------------------
# DEV TOOLS
# --------------------------------
echo "[UserBlade] Installing development tools..."
pacman -S --noconfirm jdk-openjdk python python-pip nodejs npm git || echo "[UserBlade][WARN] dev tools install failed."

# --------------------------------
# APPLICATION SUITE
# --------------------------------
echo "[UserBlade] Installing application suite..."
pacman -S --noconfirm steam obs-studio krita firefox vlc gimp qbittorrent thunderbird cpu-x ghex || echo "[UserBlade][WARN] core apps install failed."

sudo -u "$USER" yay -S --noconfirm \
  onlyoffice-bin \
  bottles \
  discord \
  whatsie \
  visual-studio-code-bin \
  opentabletdriver || echo "[UserBlade][WARN] AUR apps install failed."

# --------------------------------
# AUDIO STACK
# --------------------------------
echo "[UserBlade] Installing PipeWire audio stack..."
pacman -S --noconfirm \
  pipewire \
  pipewire-alsa \
  pipewire-pulse \
  pipewire-jack \
  wireplumber \
  pavucontrol-qt \
  easyeffects \
  helvum || echo "[UserBlade][WARN] audio stack install failed."

# --------------------------------
# ACCESSIBILITY
# --------------------------------
echo "[UserBlade] Installing accessibility tools..."
pacman -S --noconfirm kaccess kmag kmousetool || echo "[UserBlade][WARN] accessibility tools install failed."

# --------------------------------
# KDE LAYOUT TEMPLATE
# --------------------------------
echo "[UserBlade] Creating KDE layout template..."
LAYOUT_DIR="$USER_HOME/.local/share/plasma/layout-templates"
mkdir -p "$LAYOUT_DIR"

LAYOUT_FILE="$LAYOUT_DIR/userblade.layout.lay"
cat <<EOF | sudo -u "$USER" tee "$LAYOUT_FILE" >/dev/null
[Desktop]
LayoutJS=org.kde.plasma.desktop-layout.js

[Containments][1]
plugin=org.kde.plasma.desktop
location=0
formfactor=0
wallpaperplugin=org.kde.image

[Containments][1][Wallpaper][org.kde.image][General]
Image=file://$USER_HOME/Pictures/userblade_wallpaper.jpg

[Containments][2]
plugin=org.kde.plasma.panel
location=3
formfactor=2
[Containments][2][General]
length=100

[Containments][3]
plugin=org.kde.plasma.panel
location=1
formfactor=2

[Containments][3][Applets][1]
plugin=org.kde.plasma.appmenu

[Containments][3][Applets][2]
plugin=org.kde.plasma.systemtray
EOF

# --------------------------------
# AUTO-APPLY KDE LAYOUT
# --------------------------------
echo "[UserBlade] Setting up auto layout application..."
mkdir -p "$USER_HOME/.local/bin"

AUTO_LAYOUT_SCRIPT="$USER_HOME/.local/bin/userblade-apply-layout.sh"
cat <<EOF | sudo -u "$USER" tee "$AUTO_LAYOUT_SCRIPT" >/dev/null
#!/bin/bash
LAYOUT="\$HOME/.local/share/plasma/layout-templates/userblade.layout.lay"
if command -v plasma-apply-layout >/dev/null 2>&1; then
    plasma-apply-layout "\$LAYOUT"
fi
EOF
sudo -u "$USER" chmod +x "$AUTO_LAYOUT_SCRIPT"

mkdir -p "$USER_HOME/.config/autostart"
cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.config/autostart/userblade-apply-layout.desktop" >/dev/null
[Desktop Entry]
Type=Application
Exec=$HOME/.local/bin/userblade-apply-layout.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=UserBlade Layout
Comment=Apply UserBlade KDE layout on login
EOF

# --------------------------------
# FORCE KDE TAKEOVER (ANY DE)
# --------------------------------
echo "[UserBlade] Forcing KDE Plasma to replace any existing desktop environment..."

systemctl disable lightdm 2>/dev/null || echo "[UserBlade][INFO] lightdm not active."
systemctl disable gdm 2>/dev/null || echo "[UserBlade][INFO] gdm not active."
systemctl disable lxdm 2>/dev/null || echo "[UserBlade][INFO] lxdm not active."
systemctl disable sddm 2>/dev/null || echo "[UserBlade][INFO] sddm was not active."
systemctl disable mdm 2>/dev/null || echo "[UserBlade][INFO] mdm not active."
systemctl disable slim 2>/dev/null || echo "[UserBlade][INFO] slim not active."

systemctl stop lightdm 2>/dev/null || true
systemctl stop gdm 2>/dev/null || true
systemctl stop lxdm 2>/dev/null || true
systemctl stop mdm 2>/dev/null || true
systemctl stop slim 2>/dev/null || true

systemctl enable sddm || echo "[UserBlade][WARN] Failed to enable sddm."
systemctl start sddm || echo "[UserBlade][WARN] Failed to start sddm."

mkdir -p /usr/share/xsessions
cat <<'EOF' > /usr/share/xsessions/plasma.desktop
[Desktop Entry]
Type=XSession
Exec=startplasma-x11
TryExec=startplasma-x11
Name=Plasma
EOF

systemctl set-default graphical.target || echo "[UserBlade][WARN] Failed to set default target."

rm -f "$USER_HOME/.config/autostart/xfce*" 2>/dev/null || true
rm -f "$USER_HOME/.config/autostart/gnome*" 2>/dev/null || true
rm -f "$USER_HOME/.config/autostart/lxqt*" 2>/dev/null || true
rm -f "$USER_HOME/.config/autostart/openbox*" 2>/dev/null || true

rm -f "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml" 2>/dev/null || true
rm -f "$USER_HOME/.config/lxqt/session.conf" 2>/dev/null || true
rm -f "$USER_HOME/.config/gnome-session" 2>/dev/null || true

echo "[UserBlade] KDE Plasma takeover complete. It will start on next boot."

# --------------------------------
# USERBLADE VERSION + UPDATE SYSTEM
# --------------------------------
echo "[UserBlade] Setting up versioning and update system..."
echo "1.0.0" > /etc/userblade-version

UPDATE_SCRIPT="$USER_HOME/.local/bin/update.sh"
sudo -u "$USER" wget -O "$UPDATE_SCRIPT" "https://raw.githubusercontent.com/UnknownSkittle/UserBlade-Installer/main/update.sh" || echo "[UserBlade][WARN] Failed to download update.sh."
sudo -u "$USER" chmod +x "$UPDATE_SCRIPT" || echo "[UserBlade][WARN] Failed to chmod update.sh."

CHECKER="$USER_HOME/.local/bin/userblade-check-updates.sh"
cat <<EOF | sudo -u "$USER" tee "$CHECKER" >/dev/null
#!/bin/bash
LOCAL_VERSION=\$(cat /etc/userblade-version 2>/dev/null || echo "unknown")
REMOTE_VERSION=\$(curl -s https://raw.githubusercontent.com/UnknownSkittle/UserBlade-Installer/main/version.txt)
if [ -n "\$REMOTE_VERSION" ] && [ "\$LOCAL_VERSION" != "\$REMOTE_VERSION" ]; then
    notify-send "UserBlade Update Available" "New version: \$REMOTE_VERSION (installed: \$LOCAL_VERSION)"
fi
EOF
sudo -u "$USER" chmod +x "$CHECKER"

cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.config/autostart/userblade-update-check.desktop" >/dev/null
[Desktop Entry]
Type=Application
Exec=$HOME/.local/bin/userblade-check-updates.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=UserBlade Update Checker
Comment=Checks for new UserBlade versions
EOF

# --------------------------------
# CONTROL CENTER & UPDATER
# --------------------------------
echo "[UserBlade] Creating Control Center and Updater launchers..."
mkdir -p "$USER_HOME/.local/share/applications"

cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.local/share/applications/userblade-control-center.desktop" >/dev/null
[Desktop Entry]
Name=UserBlade Control Center
Comment=Manage updates, apps, and system tools
Exec=sh -c "bauh &"
Icon=$HOME/Icons/userblade_icon.png
Terminal=false
Type=Application
Categories=System;
EOF

cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.local/share/applications/userblade-updater.desktop" >/dev/null
[Desktop Entry]
Name=UserBlade Updater
Comment=Run UserBlade update script
Exec=$HOME/.local/bin/update.sh
Icon=system-software-update
Terminal=false
Type=Application
Categories=System;
EOF

# --------------------------------
# ALIASES
# --------------------------------
echo "[UserBlade] Creating terminal aliases..."
ALIAS_FILE="$USER_HOME/.userblade_aliases"
cat <<'EOF' | sudo -u "$USER" tee "$ALIAS_FILE" >/dev/null
alias ub-update='sudo pacman -Syu && yay -Syu && flatpak update'
alias ub-search='pacman -Ss'
alias ub-install='sudo pacman -S'
EOF

# --------------------------------
# WELCOME SCREEN
# --------------------------------
echo "[UserBlade] Setting up welcome screen..."
WELCOME_SCRIPT="$USER_HOME/.local/bin/userblade-welcome.sh"
cat <<'EOF' | sudo -u "$USER" tee "$WELCOME_SCRIPT" >/dev/null
#!/bin/bash
FLAG="$HOME/.config/userblade-welcome-disabled"
mkdir -p "$HOME/.config"

if [ -f "$FLAG" ]; then exit 0; fi

MSG="Welcome to UserBlade!

Your system is now configured with:
- KDE Plasma
- PipeWire audio stack
- Flatpak + Flathub
- UserBlade layout
- GUI control center + updater
- ub-* terminal aliases

You can disable this message permanently."

if command -v zenity >/dev/null 2>&1; then
  zenity --question --title="UserBlade Welcome" --text="$MSG" \
    --ok-label="Close" --cancel-label="Don't show again"
  if [ $? -ne 0 ]; then touch "$FLAG"; fi
else
  echo "$MSG"
fi
EOF
sudo -u "$USER" chmod +x "$WELCOME_SCRIPT"

cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.config/autostart/userblade-welcome.desktop" >/dev/null
[Desktop Entry]
Type=Application
Exec=$HOME/.local/bin/userblade-welcome.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=UserBlade Welcome
Comment=Show UserBlade tutorial on startup
EOF

# --------------------------------
# OWNERSHIP FIX
# --------------------------------
echo "[UserBlade] Fixing ownership for $USER_HOME..."
chown -R "$USER":"$USER" "$USER_HOME" || echo "[UserBlade][WARN] chown failed, continuing."

echo "[UserBlade] Installation complete."
echo "[UserBlade] Log saved to: $LOG_FILE"
echo "[UserBlade] Reboot to enter KDE Plasma (UserBlade)."
