#!/bin/bash
# Build Kite's HUD against Bookworm's libraspberrypi-dev and install it as a service.
# Run on the handheld from a checkout at /home/pi/Circuit-Sword.
set -eu
REPO=/home/pi/Circuit-Sword
apt-get install -y --no-install-recommends libraspberrypi-dev libpng-dev
# wiringPi is no longer packaged for Bookworm; Kite's bundled 2.46 build works.
command -v gpio >/dev/null || dpkg -i "$REPO/settings/wiringpi_2.46_armhf.deb"
cd "$REPO/cs-hud/src"
make clean
sudo -u pi env CFLAGS="$(pkg-config --cflags bcm_host)" \
  LDFLAGS="$(pkg-config --libs-only-L bcm_host)" make -j4
install -m 644 "$REPO/bookworm/cs-hud.service" /etc/systemd/system/cs-hud.service
systemctl daemon-reload
systemctl enable --now cs-hud.service
systemctl --no-pager status cs-hud.service | head -5
