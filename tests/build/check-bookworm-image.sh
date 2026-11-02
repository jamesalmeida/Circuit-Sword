#!/bin/bash
# Checks a built Bookworm image (.img or .img.xz) without booting it: the
# files, services, driver and ownership that bookworm/image-setup.sh should
# have produced. Needs root, the tools in build/README.md, and qemu-arm
# registered with binfmt_misc (some checks run the image's programs).
#
# Usage: sudo tests/build/check-bookworm-image.sh <image.img[.xz]>

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=build/image-lib.sh
. "$REPO/build/image-lib.sh"

SRC=${1:?image.img or image.img.xz}
PASS=0
FAIL=0
ok() { echo "PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
check() { local name=$1; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/cs-check.XXXXXX")
trap 'image_cleanup; rm -rf "$WORK"' EXIT
IMG="$WORK/image.img"
case "$SRC" in
  *.xz) xz -dc "$SRC" > "$IMG" ;;
  *) cp --sparse=always "$SRC" "$IMG" ;;
esac

image_find_partitions "$IMG"
image_mount_partitions "$IMG"
R=$ROOT_MNT
B=$BOOT_MNT
in_image() {
  chroot "$R" /usr/bin/env -i HOME=/root LANG=C.UTF-8 \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin "$@"
}

KERNEL=$(basename "$(ls -d "$R"/lib/modules/*-rpi-v7)")
CS=$R/home/pi/Circuit-Sword

echo "== Boot partition"
check "config.txt is bookworm/config.txt" cmp "$B/config.txt" "$CS/bookworm/config.txt"
check "original config.txt is kept" test -s "$B/config_ORIGINAL.txt"
check "cmdline.txt still has Raspberry Pi OS first-boot resize" grep -q "init=/usr/lib/raspberrypi-sys-mods/firstboot" "$B/cmdline.txt"

echo "== Wi-Fi"
check "r8723bs module is installed for $KERNEL" test -f "$R/lib/modules/$KERNEL/updates/dkms/r8723bs.ko.xz"
check "modules.dep lists r8723bs" grep -q "updates/dkms/r8723bs.ko" "$R/lib/modules/$KERNEL/modules.dep"
check "driver power saving is off" grep -q "rtw_power_mgnt=0" "$R/etc/modprobe.d/r8723bs-cs.conf"
check "NetworkManager power saving is off" grep -q "wifi.powersave = 2" "$R/etc/NetworkManager/conf.d/90-circuit-sword-wifi.conf"
check "RTL8723BS firmware is present" test -f "$R/lib/firmware/rtlwifi/rtl8723bs_nic.bin"
check "kernel package is held" bash -c "chroot '$R' apt-mark showhold | grep -qx linux-image-rpi-v7"
check "no DKMS signing key is shipped" test ! -e "$R/var/lib/dkms/mok.key"

echo "== HUD, panel flip, shutdown"
check "HUD binary is built" test -x "$CS/cs-hud/src/cs-hud"
check "HUD finds all its libraries" bash -c "! chroot '$R' ldd /home/pi/Circuit-Sword/cs-hud/src/cs-hud | grep -q 'not found'"
check "HUD service is enabled" test -L "$R/etc/systemd/system/multi-user.target.wants/cs-hud.service"
check "panel flip service is enabled" test -L "$R/etc/systemd/system/sysinit.target.wants/cs-lcd-flip.service"
check "panel flip can import pyserial" in_image python3 -c "import serial"
# RPi.GPIO refuses to import anywhere but a real Pi, so only locate it
check "tester can find RPi.GPIO" in_image python3 -c "import importlib.util, sys; sys.exit(importlib.util.find_spec('RPi.GPIO') is None)"
check "safe-shutdown script is executable" test -x "$R/opt/cs_shutdown.sh"
check "amixer and PipeWire are installed" test -x "$R/usr/bin/amixer" -a -x "$R/usr/bin/pipewire"

echo "== System"
check "boots to the console" bash -c "readlink '$R/etc/systemd/system/default.target' | grep -q multi-user.target"
check "journal is persistent" grep -q "Storage=persistent" "$R/etc/systemd/journald.conf.d/99-circuit-sword.conf"
check "checkout is owned by pi" bash -c "[ \"\$(stat -c %u:%g '$CS' '$CS/cs-hud/src/cs-hud' | sort -u)\" == 1000:1000 ]"
check "build stamp is present" grep -q "^source_commit: " "$R/etc/circuit-sword-build"
check "no chroot service blocker is left" test ! -e "$R/usr/sbin/policy-rc.d"
check "resolv.conf is the base image's" test ! -e "$R/etc/resolv.conf.cs-build"
check "apt lists are cleaned" bash -c "[ -z \"\$(ls -A '$R/var/lib/apt/lists' | grep -v -e '^lock$' -e '^partial$' -e '^auxfiles$')\" ]"

echo "root filesystem: $(df -h --output=used,avail "$R" | tail -1)"
echo
echo "$PASS passed, $FAIL failed"
((FAIL == 0))
