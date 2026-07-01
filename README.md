# UserBlade-Installer

A full KDE‑based desktop environment for BlackArch, focused on usability, GUI accessibility, theming, audio quality, and powerful tooling.

UserBlade transforms a minimal BlackArch install into a polished, modern desktop with:

    KDE Plasma

    PipeWire + JACK

    Flatpak + Flathub

    Qt theming

    AUR support

    A curated application suite

    Automatic KDE layout (right dock + top bar)

    GUI control center + updater

    Welcome/tutorial on first login

## Installation

Download and run the installer:
bash



> wget https://raw.githubusercontent.com/UnknownSkittle/UserBlade-Installer/refs/heads/main/userblade.sh

> chmod +x userblade.sh

> sudo ./userblade.sh

    Note:  
    The installer must be run as root, but it configures your non‑root user automatically.

## What the Installer Does
### Desktop Environment

    Installs KDE Plasma core

    Installs Plasma workspace + wallpapers

    Installs System Monitor

    Installs Konsole, Dolphin, System Settings

    Enables SDDM

    Installs xdg-desktop-portal-kde

    Creates standard user directories (Documents, Downloads, etc.)

### Audio Stack

    PipeWire

    ALSA → PipeWire

    PulseAudio → PipeWire

    JACK → PipeWire

    WirePlumber

    EasyEffects

    Helvum

    pavucontrol‑qt

### Theming

    Kvantum + Arc Dark

    Arc KDE

    Papirus icons

    qt5ct + qt6ct

### Development Tools

    Java (OpenJDK)

    Python + pip

    Node.js + npm

    Git

### Applications

    Steam (with multilib auto‑enable)

    OBS Studio

    Krita

    Firefox

    VLC

    GIMP

    qBittorrent

    Thunderbird

    CPU‑X

    GHex

### AUR Applications

##### (Installed only if yay builds successfully)

    OnlyOffice

    Bottles

    Discord

    Whatsie

    VSCode

    OpenTabletDriver

### UserBlade Features

    UserBlade Control Center

    UserBlade Updater

    UserBlade Welcome tutorial

    Shell‑agnostic alias file

    UserBlade KDE layout template

    Automatic layout application using plasma-apply-layout

##Automatic KDE Layout Application

UserBlade includes a layout template:
Code

> ~/.local/share/plasma/layout-templates/userblade.layout.lay

The installer automatically applies it using:
bash

plasma-apply-layout ~/.local/share/plasma/layout-templates/userblade.layout.lay

This sets:

    Right‑side dock

    Top bar

    AppMenu

    System tray

    UserBlade wallpaper

If you ever want to reapply it manually:
bash

> plasma-apply-layout ~/.local/share/plasma/layout-templates/userblade.layout.lay

Terminal Aliases

UserBlade creates:
Code

> ~/.userblade_aliases

Add this line to your shell config (~/.bashrc, ~/.zshrc, etc.):
bash

> source ~/.userblade_aliases

Aliases:

    > ub-update — update system + AUR + Flatpak

    > ub-search — search packages

    > ub-install — install packages

Control Center & Updater

Open UserBlade Control Center from the application menu.

It provides GUI access to:

    Arch packages

    AUR packages

    Flatpak apps

    Updates

    BlackArch tools

The UserBlade Updater is a simplified launcher for GUI updates.
Welcome Screen

On first login, you’ll see the UserBlade Welcome window.

It includes:

    Quick tips

    Links to tools

    A “Don’t show again” button

Disable manually:
bash

> touch ~/.config/userblade-welcome-disabled

Troubleshooting
Steam fails to launch

Ensure multilib is enabled:
ini

[multilib]
> Include = /etc/pacman.d/mirrorlist

Then:
bash

> sudo pacman -Syu

Qt apps look inconsistent

Open:
Code

qt5ct
qt6ct

Select Arc Dark.
Audio issues

Use:

    pavucontrol‑qt for routing

    EasyEffects for filters

    Helvum for advanced PipeWire graph control

AUR packages fail to build

Ensure toolchain:
bash

sudo pacman -S base-devel

Fix yay ownership:
bash

> sudo chown -R $USER:$USER ~/yay

Uninstalling UserBlade

UserBlade is modular. You can remove components individually:

    Remove apps via pacman or bauh

    Remove layout template

    Remove welcome script

    Remove alias file

There is no full uninstall script yet.
Credits

UserBlade is built on:

    BlackArch

    KDE Plasma

    PipeWire

    Flatpak

    Arch Linux ecosystem

