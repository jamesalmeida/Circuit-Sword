#!/bin/bash
# Turns a Raspberry Pi OS Lite Bookworm (armhf) root filesystem into the
# Circuit Sword DMG-CM3 base system: LCD, RTL8723BS Wi-Fi, HUD, panel flip and
# safe shutdown. RetroPie is installed afterwards on the device.
#
# Runs as root inside the image (a chroot from build/build-bookworm-image.sh)
# with this repository at /home/pi/Circuit-Sword and the boot partition at
# /boot/firmware. Each step is the one recorded in docs/bookworm-bringup.md.
#
# Usage: image-setup.sh <kernel>   e.g. 6.12.109+rpt-rpi-v7
set -euo pipefail

KERNEL=${1:?kernel version of the image, e.g. 6.12.109+rpt-rpi-v7}
REPO=/home/pi/Circuit-Sword
export KERNEL CS_IMAGE_BUILD=1 DEBIAN_FRONTEND=noninteractive

# Nothing may start services inside the chroot
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod 755 /usr/sbin/policy-rc.d
trap 'rm -f /usr/sbin/policy-rc.d' EXIT

# The checkout belongs to pi; the HUD is compiled as pi inside it
chown -R 1000:1000 "$REPO"

apt-get update
# python3-serial: lcd-flip.py, cs-configure.py, cs-tester. PipeWire: the HUD's
# volume control drives pi's PipeWire session (bookworm/cs-hud.service).
apt-get install -y --no-install-recommends \
  python3-serial alsa-utils firmware-realtek \
  pipewire pipewire-alsa wireplumber

# Wi-Fi driver, built with DKMS for the image's kernel; driver power saving off
bash "$REPO/bookworm/install-rtl8723bs-dkms.sh"
install -m 644 "$REPO/bookworm/r8723bs-cs.conf" /etc/modprobe.d/r8723bs-cs.conf
install -d /etc/NetworkManager/conf.d
printf '[connection]\n# 2 = disabled; power saving stalls RTL8723BS downloads\nwifi.powersave = 2\n' \
  > /etc/NetworkManager/conf.d/90-circuit-sword-wifi.conf

# Display: fkms + 640x480 DPI LCD, then the panel's own 180 degree flip
cp /boot/firmware/config.txt /boot/firmware/config_ORIGINAL.txt
cp "$REPO/bookworm/config.txt" /boot/firmware/config.txt
install -m 644 "$REPO/bookworm/cs-lcd-flip.service" /etc/systemd/system/cs-lcd-flip.service
systemctl enable cs-lcd-flip.service

# HUD (battery, volume, brightness, Mode overlay) and safe shutdown
bash "$REPO/bookworm/install-cs-hud.sh"
install -m 755 "$REPO/settings/cs_shutdown.sh" /opt/cs_shutdown.sh

# Console only (the desktop left the LCD blank); keep logs across reboots
systemctl set-default multi-user.target
install -d /etc/systemd/journald.conf.d
printf '[Journal]\nStorage=persistent\n' > /etc/systemd/journald.conf.d/99-circuit-sword.conf

# The DKMS Wi-Fi module is built for this kernel only. Hold the kernel so a
# routine upgrade cannot leave the handheld without Wi-Fi (see bring-up notes).
mapfile -t held < <(dpkg-query -W -f '${Package} ${Status}\n' 'linux-image-*' 'linux-headers-*' raspi-firmware |
  awk '$NF == "installed" { print $1 }')
apt-mark hold "${held[@]}"

# DKMS generated a module-signing key the Pi never checks; do not ship a
# private key in a shared image (DKMS makes a new one if it needs it)
rm -f /var/lib/dkms/mok.key /var/lib/dkms/mok.pub

chown -R 1000:1000 "$REPO"
apt-get clean
rm -rf /var/lib/apt/lists/*
