#!/bin/bash
# ============================================================
# UserBlade Unified Installer (Full Overwrite, Re-runnable)
# ============================================================

set -e

LOG="/var/log/userblade-installer.log"
exec > >(tee -a "$LOG") 2>&1

if [ "$(id -u)" -ne 0 ]; then
  echo "[UserBlade] Run as root: sudo bash userblade-installer.sh"
  exit 1
fi

if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
  USER="$SUDO_USER"
else
  USER=$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd)
fi

USER_HOME=$(eval echo "~$USER")

echo "[UserBlade] Target user: $USER ($USER_HOME)"

# ------------------------------------------------------------
# OS Branding
# ------------------------------------------------------------
echo "[UserBlade] Applying OS branding..."

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
echo "[UserBlade] Updating system..."
pacman -Syu --noconfirm

echo "[UserBlade] Installing base tools..."
pacman -S --noconfirm wget curl git base-devel pciutils xdg-user-dirs

sudo -u "$USER" xdg-user-dirs-update

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
  sudo -u "$USER" git clone https://aur.archlinux.org/yay.git "$USER_HOME/yay"
  chown -R "$USER":"$USER" "$USER_HOME/yay"
  cd "$USER_HOME/yay"
  sudo -u "$USER" makepkg -si --noconfirm
  cd "$USER_HOME"
fi

# ------------------------------------------------------------
# Install neofetch-git (AUR)
# ------------------------------------------------------------
echo "[UserBlade] Installing neofetch-git..."
sudo -u "$USER" yay -S --noconfirm neofetch-git

# ------------------------------------------------------------
# KDE Plasma + SDDM
# ------------------------------------------------------------
echo "[UserBlade] Installing KDE Plasma + SDDM..."
pacman -S --noconfirm plasma-desktop plasma-workspace plasma-systemmonitor \
  konsole dolphin systemsettings sddm sddm-kcm xdg-desktop-portal-kde

# ------------------------------------------------------------
# Apps (no Steam, keep gaming libs)
# ------------------------------------------------------------
echo "[UserBlade] Installing apps..."
pacman -S --noconfirm ghex gimp vlc firefox qbittorrent thunderbird cpu-x

sudo -u "$USER" yay -S --noconfirm \
  bauh \
  bottles \
  discord \
  whatsie \
  visual-studio-code-bin \
  onlyoffice-bin \
  opentabletdriver

# ------------------------------------------------------------
# Audio stack (PipeWire, full jack2 purge)
# ------------------------------------------------------------
echo "[UserBlade] Installing PipeWire audio stack..."
pacman -S --noconfirm pipewire pipewire-alsa pipewire-pulse pipewire-jack \
  wireplumber pavucontrol-qt easyeffects helvum

echo "[UserBlade] Removing jack2 and related packages..."
pacman -Rns --noconfirm jack2 jack2-dbus jack2-tools jack2-libs 2>/dev/null || true

# ------------------------------------------------------------
# GPU auto-detect
# ------------------------------------------------------------
echo "[UserBlade] Detecting GPU..."
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
# Remove other DEs (safe clean)
# ------------------------------------------------------------
echo "[UserBlade] Removing other DEs..."
pacman -Rns --noconfirm xfce4 xfce4-goodies gnome gnome-shell lxqt lxqt-session \
  lxde lxde-common cinnamon mate mate-extra budgie-desktop deepin \
  pantheon-session enlightenment i3-wm openbox 2>/dev/null || true

systemctl disable lightdm gdm lxdm mdm slim 2>/dev/null || true
pacman -Rns --noconfirm lightdm gdm lxdm mdm slim 2>/dev/null || true

# ------------------------------------------------------------
# Wallpaper + icon (your PNG + wallpaper)
# ------------------------------------------------------------
echo "[UserBlade] Downloading wallpaper + icon..."
sudo -u "$USER" mkdir -p "$USER_HOME/Pictures" "$USER_HOME/Icons"

sudo -u "$USER" wget -O "$USER_HOME/Pictures/userblade_wallpaper.jpg" "https://iili.io/C7P8pCg.jpg"
sudo -u "$USER" wget -O "$USER_HOME/Icons/userblade_icon.png" "https://iili.io/C7ikyhX.png"

# ------------------------------------------------------------
# Theme: Arc Dark + Papirus + Breeze Snow
# ------------------------------------------------------------
echo "[UserBlade] Installing theme components..."
pacman -S --noconfirm arc-gtk-theme papirus-icon-theme breeze

echo "[UserBlade] Applying KDE + GTK theme..."
mkdir -p "$USER_HOME/.config"

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
# Plasma layout (right dock + top bar) + wallpaper
# ------------------------------------------------------------
echo "[UserBlade] Creating Plasma layout template..."
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
# Autostart: force layout + wallpaper on login
# ------------------------------------------------------------
echo "[UserBlade] Creating layout + wallpaper autostart..."
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
# KSplash (KDE startup) using Breeze
# ------------------------------------------------------------
echo "[UserBlade] Configuring KSplash..."
cat <<EOF | sudo -u "$USER" tee "$USER_HOME/.config/ksplashrc" >/dev/null
[KSplash]
Theme=org.kde.breeze
EOF

# ------------------------------------------------------------
# Plymouth (boot splash) with static logo (your PNG)
# ------------------------------------------------------------
echo "[UserBlade] Installing Plymouth..."
pacman -S --noconfirm plymouth plymouth-theme-spinner

echo "[UserBlade] Creating UserBlade Plymouth theme..."
PLY_DIR="/usr/share/plymouth/themes/userblade"
mkdir -p "$PLY_DIR"

cp -r /usr/share/plymouth/themes/spinner/* "$PLY_DIR"

cp "$USER_HOME/Icons/userblade_icon.png" "$PLY_DIR/userblade.png" || true

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

plymouth-set-default-theme userblade

echo "[UserBlade] Rebuilding initramfs for Plymouth..."
if command -v mkinitcpio >/dev/null 2>&1; then
  mkinitcpio -P
fi

# ------------------------------------------------------------
# Neofetch ASCII (BlackArch-style, purple, sword)
# ------------------------------------------------------------
echo "[UserBlade] Setting custom neofetch ASCII..."
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
echo "[UserBlade] Creating Plasma session file..."
cat <<'EOF' >/usr/share/xsessions/plasma.desktop
[Desktop Entry]
Type=XSession
Exec=startplasma-x11
TryExec=startplasma-x11
Name=Plasma
EOF

echo "[UserBlade] Enabling SDDM + graphical target..."
systemctl enable sddm
systemctl set-default graphical.target

# ------------------------------------------------------------
# Ownership fix
# ------------------------------------------------------------
echo "[UserBlade] Fixing ownership..."
chown -R "$USER":"$USER" "$USER_HOME"

echo "[UserBlade] Done."
echo "[UserBlade] Reboot, log into KDE, and the autostart will force layout + wallpaper."
echo "[UserBlade] Neofetch will show UserBlade + custom ASCII."
echo "[UserBlade] Plymouth will show your PNG icon during boot."
