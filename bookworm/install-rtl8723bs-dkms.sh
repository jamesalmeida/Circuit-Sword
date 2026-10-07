#!/bin/bash
# Build the RTL8723BS SDIO Wi-Fi driver for Raspberry Pi OS Bookworm (32-bit)
# and register it with DKMS so every new kernel gets a rebuilt module.
#
# Raspberry Pi kernels do not enable CONFIG_RTL8723BS (Kite's Stretch image
# used a custom kernel; see build/build-kernel.txt). The source is the staging
# driver from Raspberry Pi's own kernel tree, pinned to a commit.
#
# Needs network, so run it over Ethernet/USB tethering, or use the offline
# bring-up described in docs/bookworm-bringup.md.
set -eu

COMMIT=${RTL8723BS_COMMIT:-43c132e}   # raspberrypi/linux rpi-6.12.y, 2026-10-05
NAME=rtl8723bs-cs
VER="6.12.y.${COMMIT:0:7}"
SRC=/usr/src/$NAME-$VER

apt-get install -y --no-install-recommends dkms git linux-headers-rpi-v7

if [[ ! -f "$SRC/Makefile" ]]; then
  tmp=$(mktemp -d)
  git -C "$tmp" init -q
  git -C "$tmp" remote add origin https://github.com/raspberrypi/linux
  git -C "$tmp" sparse-checkout set drivers/staging/rtl8723bs
  git -C "$tmp" fetch -q --depth 1 --filter=blob:none origin "$COMMIT"
  git -C "$tmp" checkout -q FETCH_HEAD
  rm -rf "$SRC"
  cp -a "$tmp/drivers/staging/rtl8723bs" "$SRC"
  rm -rf "$tmp"
fi

cat > "$SRC/dkms.conf" <<CONF
PACKAGE_NAME="$NAME"
PACKAGE_VERSION="$VER"
BUILT_MODULE_NAME[0]="r8723bs"
DEST_MODULE_LOCATION[0]="/updates/dkms"
MAKE[0]="make -C \${kernel_source_dir} M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build CONFIG_RTL8723BS=m modules"
CLEAN="make -C \${kernel_source_dir} M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build clean"
AUTOINSTALL="yes"
CONF

dkms status "$NAME/$VER" | grep -q . || dkms add "$NAME/$VER"
dkms install --force "$NAME/$VER"
modprobe r8723bs
dkms status "$NAME"
