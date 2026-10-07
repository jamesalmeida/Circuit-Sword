#!/bin/bash
# Build Kite's HUD for Bookworm and install it as a service.
# Run on the handheld from a checkout at /home/pi/Circuit-Sword.
#
# The HUD needs the legacy DispmanX userland (libbcm_host). On Bookworm the
# libraspberrypi0 package conflicts with raspi-utils/raspberrypi-sys-mods
# (installing it makes apt remove ~19 core Pi packages, and RetroPie later
# removes it again). So unpack it privately under /opt/cs-hud/userland and
# link the HUD there with an RPATH (not RUNPATH, so libbcm_host's own
# dependencies resolve there too); apt never sees it.
set -eu
REPO=/home/pi/Circuit-Sword
U=/opt/cs-hud/userland
LIB=$U/usr/lib/arm-linux-gnueabihf

apt-get install -y --no-install-recommends libpng-dev
# wiringPi is no longer packaged for Bookworm; Kite's bundled 2.46 build works.
command -v gpio >/dev/null || dpkg -i "$REPO/settings/wiringpi_2.46_armhf.deb"

if [[ ! -e $LIB/libbcm_host.so.0 ]]; then
  tmp=$(mktemp -d)
  (cd "$tmp" && apt-get download libraspberrypi0 libraspberrypi-dev)
  mkdir -p "$U"
  for deb in "$tmp"/*.deb; do dpkg -x "$deb" "$U"; done
  rm -rf "$tmp"
fi

cd "$REPO/cs-hud/src"
make clean
sudo -u pi env \
  CFLAGS="-I$U/usr/include -I$U/usr/include/interface/vcos/pthreads -I$U/usr/include/interface/vmcs_host/linux" \
  LDFLAGS="-L$LIB -Wl,--disable-new-dtags,-rpath,$LIB" make -j4
install -m 644 "$REPO/bookworm/cs-hud.service" /etc/systemd/system/cs-hud.service
systemctl daemon-reload
systemctl enable cs-hud.service
systemctl restart cs-hud.service
systemctl --no-pager status cs-hud.service | head -5
