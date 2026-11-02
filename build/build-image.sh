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

# Builds a Circuit Sword image from a legacy RetroPie base image (/boot layout).
# The Circuit Sword files come from one commit of this repository, cloned into
# the image; the result is written next to a SHA-256 checksum and a manifest of
# every build input. See build/README.md.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: sudo ./build-image.sh [options] YES <image.img>

  --ref REF                Commit, branch or tag of this repository to install (default: HEAD)
  --base-sha256 HEX        Refuse to build unless the base image has this SHA-256
  --out-dir DIR            Where to write the image, checksum and manifest (default: .)
  --user NAME              Runtime user in the image (default: pi)
  --no-legacy-boot-firmware
                           Do not copy Kite's 2019 CM3+ boot firmware
                           (settings/pi_plus_20190130.zip) onto the boot partition
USAGE
  exit 1
}

if [ "$EUID" -ne 0 ]
  then echo "Please run as root (sudo)"
  exit 1
fi

#####################################################################
# Vars

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd -- "$SCRIPT_DIR/.." && pwd)
# shellcheck source=build/image-lib.sh
. "$SCRIPT_DIR/image-lib.sh"

REF="HEAD"
BASE_SHA256=""
OUT_DIR="."
RUNTIME_USER="pi"
LEGACY_BOOT_ZIP="settings/pi_plus_20190130.zip"
CS_REPO_URL=${CS_REPO_URL:-https://github.com/jamesalmeida/Circuit-Sword}
GITHUBPROJECT="Circuit-Sword"

ARGS=()
while (($#)); do
  case "$1" in
    --ref) REF=${2:?}; shift 2 ;;
    --base-sha256) BASE_SHA256=${2:?}; shift 2 ;;
    --out-dir) OUT_DIR=${2:?}; shift 2 ;;
    --user) RUNTIME_USER=${2:?}; shift 2 ;;
    --no-legacy-boot-firmware) LEGACY_BOOT_ZIP=""; shift ;;
    -h|--help) usage ;;
    -*) echo "Unknown option [$1]"; usage ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

if ((${#ARGS[@]} == 3)); then
  die "The [branch] argument was removed: the image now installs a commit of this checkout. Use --ref ${ARGS[2]}"
fi
((${#ARGS[@]} == 2)) && [[ ${ARGS[0]} == YES ]] || usage
IMG=${ARGS[1]}

#####################################################################
# LOGIC!
echo "BUILDING.."

image_require_tools git sha256sum dpkg dpkg-query

[[ -f "$IMG" ]] || die "IMG [$IMG] doesn't exist"
mkdir -p "$OUT_DIR"

# sudo runs git as root on a checkout owned by someone else; trust this one
# (its work tree, and its .git directory when cloned from below).
GIT_TRUST=(-c safe.directory="$REPO" -c safe.directory="$REPO/.git")
repo_git() { git "${GIT_TRUST[@]}" -C "$REPO" "$@"; }

COMMIT=$(repo_git rev-parse --verify "$REF^{commit}") || die "Unknown ref [$REF]"
SHORT=${COMMIT:0:7}
if [[ "$REF" == HEAD && -n "$(repo_git status --porcelain --untracked-files=no)" ]]; then
  echo "WARNING: uncommitted changes in [$REPO] are NOT included; the image installs commit $SHORT" >&2
fi

echo "[i] Checksumming base image.."
BASE_ACTUAL=$(sha256sum "$IMG" | cut -d' ' -f1)
if [[ -n "$BASE_SHA256" && "${BASE_SHA256,,}" != "$BASE_ACTUAL" ]]; then
  die "Base image SHA-256 is $BASE_ACTUAL, expected $BASE_SHA256"
fi

LEGACY_BOOT_SHA256="none"
if [[ -n "$LEGACY_BOOT_ZIP" ]]; then
  LEGACY_BOOT_SHA256=$(repo_git show "$COMMIT:$LEGACY_BOOT_ZIP" | sha256sum | cut -d' ' -f1)
fi

BUILD="CSO_CM3_$(date -u +"%Y%m%d-%H%M%S")_g$SHORT"
OUTFILE="$OUT_DIR/$(basename "$IMG" .img)_$BUILD.img"
MANIFEST="$OUTFILE.manifest"
[[ ! -e "$OUTFILE" ]] || die "OUTFILE [$OUTFILE] exists! Can't create new image"

SUCCESS=0
on_exit() {
  image_cleanup || true
  if ((SUCCESS == 0)); then
    rm -f "$OUTFILE" "$MANIFEST" "$OUTFILE.sha256"
    echo "FAILED: no image was produced" >&2
  fi
}
trap on_exit EXIT

# Copy img to new + name
cp --sparse=always "$IMG" "$OUTFILE"

image_find_partitions "$OUTFILE"
echo "[i] Boot partition at byte $BOOT_OFFSET ($BOOT_SIZE bytes), root at byte $ROOT_OFFSET ($ROOT_SIZE bytes)"
image_mount_partitions "$OUTFILE"

BOOT_DIR=$(image_boot_dir "$ROOT_MNT")
if [[ "$BOOT_DIR" != /boot ]]; then
  die "The image mounts its boot partition at [$BOOT_DIR]. This builder and install.sh only support legacy RetroPie images (/boot); for Bookworm see docs/bookworm-bringup.md"
fi
image_require_user "$ROOT_MNT" "$RUNTIME_USER"
[[ "$IMAGE_HOME" == "/home/pi" ]] ||
  die "install.sh and the services expect /home/pi; [$RUNTIME_USER] has home [$IMAGE_HOME]"

# Clone the pinned commit into the image; install.sh finds it and skips its own clone.
BINDIR="$ROOT_MNT$IMAGE_HOME/$GITHUBPROJECT"
image_clone_repo "$REPO" "$COMMIT" "$BINDIR" "$CS_REPO_URL"

# Install, using the installer from the pinned commit rather than this checkout
bash "$BINDIR/install.sh" YES master "$BOOT_MNT" "$ROOT_MNT"

# Patch for PLUS: Kite's CM3+ boot firmware (2019). Legacy images only.
if [[ -n "$LEGACY_BOOT_ZIP" ]]; then
  unzip -q -o -d "$BOOT_MNT" "$BINDIR/$LEGACY_BOOT_ZIP"
fi

# Record the inputs, in the manifest and inside the image
{
  echo "build_id: $BUILD"
  echo "built_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "source_repository: $CS_REPO_URL"
  echo "source_commit: $COMMIT"
  echo "base_image: $(basename "$IMG")"
  echo "base_image_sha256: $BASE_ACTUAL"
  echo "legacy_boot_firmware: ${LEGACY_BOOT_ZIP:-none}"
  echo "legacy_boot_firmware_sha256: $LEGACY_BOOT_SHA256"
  echo "boot_dir: $BOOT_DIR"
  echo "runtime_user: $RUNTIME_USER"
  echo "boot_partition: offset=$BOOT_OFFSET size=$BOOT_SIZE"
  echo "root_partition: offset=$ROOT_OFFSET size=$ROOT_SIZE"
  echo "build_host: $(uname -srm)"
  # Inputs of the base image itself, e.g. the kernel from upgrade-kernel.sh
  if [[ -f "$IMG.manifest" ]]; then
    sed 's/^/base./' "$IMG.manifest"
  fi
} > "$MANIFEST"
cp "$MANIFEST" "$ROOT_MNT/etc/circuit-sword-build"

# Unmount, then confirm both filesystems are still clean
image_cleanup
image_verify_filesystems "$OUTFILE"

OUT_SHA256=$(sha256sum "$OUTFILE" | cut -d' ' -f1)
echo "image_sha256: $OUT_SHA256" >> "$MANIFEST"
(cd "$(dirname "$OUTFILE")" && sha256sum "$(basename "$OUTFILE")") > "$OUTFILE.sha256"

# DONE
SUCCESS=1
echo "SUCCESS: Image [$OUTFILE] has been built!"
echo "Manifest: [$MANIFEST]"
