#!/bin/bash

#
# This file originates from Kite's Circuit Sword control board project.
# Author: Kite (Giles Burgess)
#
# THIS HEADER MUST REMAIN WITH THIS FILE AT ALL TIMES
#
# This firmware is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This firmware is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this repo. If not, see <http://www.gnu.org/licenses/>.
#

# Replaces the kernel and modules of a legacy RetroPie image (/boot layout)
# with a kernel zip from build/build-kernel.txt. Writes a manifest next to the
# new image; build-image.sh carries it into the final image's manifest.

# sudo ./upgrade-kernel.sh "YES" "retropie-4.3-rpi2_rpi3.img" "pi_4.14.14-v7+.zip"

set -euo pipefail

if [ "$EUID" -ne 0 ]
  then echo "Please run as root (sudo)"
  exit 1
fi

if [ $# != 3 ] || [ "$1" != YES ] ; then
  echo "Usage: ./<cmd> YES <image.img> <kernel.zip>"
  exit 1
fi

#####################################################################
# Vars

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=build/image-lib.sh
. "$SCRIPT_DIR/image-lib.sh"

IMG=$2
KERNELZIP=$3
KERNEL="kernel7"

#####################################################################
# LOGIC!
echo "BUILDING.."

image_require_tools unzip rsync sha256sum

[[ -f "$IMG" ]] || die "IMG [$IMG] doesn't exist"
[[ -f "$KERNELZIP" ]] || die "KERNELZIP [$KERNELZIP] doesn't exist"

OUTFILE="$(basename "$IMG" .img)_$(basename "$KERNELZIP" .zip).img"
MANIFEST="$OUTFILE.manifest"
[[ ! -e "$OUTFILE" ]] || die "OUTFILE [$OUTFILE] exists! Can't create new image"

SUCCESS=0
on_exit() {
  image_cleanup || true
  [[ -n "${UNZIPDIR:-}" ]] && rm -rf "$UNZIPDIR"
  if ((SUCCESS == 0)); then
    rm -f "$OUTFILE" "$MANIFEST"
    echo "FAILED: no image was produced" >&2
  fi
}
trap on_exit EXIT

# Unzip kernel.zip into a private directory, never the current one
UNZIPDIR=$(mktemp -d "${TMPDIR:-/tmp}/cs-kernel.XXXXXX")
unzip -q "$KERNELZIP" -d "$UNZIPDIR"
[[ -f "$UNZIPDIR/pi/$KERNEL.img" ]] || die "No [pi/$KERNEL.img] in $KERNELZIP"
[[ -d "$UNZIPDIR/modules/lib/modules" ]] || die "No [modules/lib/modules] in $KERNELZIP"

# Copy img to new + name
cp --sparse=always "$IMG" "$OUTFILE"

image_find_partitions "$OUTFILE"
image_mount_partitions "$OUTFILE"
BOOT_DIR=$(image_boot_dir "$ROOT_MNT")
[[ "$BOOT_DIR" == /boot ]] ||
  die "The image mounts its boot partition at [$BOOT_DIR]; this legacy kernel is only for /boot images"

# Install
cp "$UNZIPDIR/pi/$KERNEL.img" "$BOOT_MNT/$KERNEL.img"
cp "$UNZIPDIR"/pi/*.dtb "$BOOT_MNT"
cp "$UNZIPDIR"/pi/overlays/*.dtb* "$BOOT_MNT/overlays/"
cp "$UNZIPDIR/pi/overlays/README" "$BOOT_MNT/overlays/"

rm -rf "$ROOT_MNT"/lib/modules/*

# -K keeps directory symlinks such as merged-/usr's /lib -> usr/lib
rsync -aK "$UNZIPDIR/modules/" "$ROOT_MNT/"

{
  echo "base_image: $(basename "$IMG")"
  echo "base_image_sha256: $(sha256sum "$IMG" | cut -d' ' -f1)"
  echo "kernel_zip: $(basename "$KERNELZIP")"
  echo "kernel_zip_sha256: $(sha256sum "$KERNELZIP" | cut -d' ' -f1)"
  echo "kernel_modules: $(ls "$UNZIPDIR/modules/lib/modules" | tr '\n' ' ')"
} > "$MANIFEST"

# Unmount, then confirm both filesystems are still clean
image_cleanup
image_verify_filesystems "$OUTFILE"

# DONE
SUCCESS=1
echo "SUCCESS: Image [$OUTFILE] has had its kernel upgraded!"
