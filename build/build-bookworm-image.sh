#!/bin/bash
# Builds a Circuit Sword DMG-CM3 base image from Raspberry Pi OS Lite Bookworm
# (32-bit): the pinned base image from bookworm-inputs.sh, set up in an
# emulated ARM chroot by bookworm/image-setup.sh from one commit of this
# repository. RetroPie is installed afterwards on the device. See
# build/README.md.
#
# Needs Linux, root, network, and qemu-arm registered with binfmt_misc
# (Debian: qemu-user-static; Arch: qemu-user-static qemu-user-static-binfmt).

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: sudo ./build-bookworm-image.sh [options] YES

  --ref REF          Commit, branch or tag of this repository to install (default: HEAD)
  --out-dir DIR      Where to write the image, checksum, manifest and package list (default: .)
  --cache-dir DIR    Where to keep the downloaded base image (default: ./cache)
  --no-compress      Write a raw .img instead of .img.xz
USAGE
  exit 1
}

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd -- "$SCRIPT_DIR/.." && pwd)
# shellcheck source=build/image-lib.sh
. "$SCRIPT_DIR/image-lib.sh"
# shellcheck source=build/bookworm-inputs.sh
. "$SCRIPT_DIR/bookworm-inputs.sh"

REF="HEAD"
OUT_DIR="."
CACHE_DIR="./cache"
COMPRESS=1
CS_REPO_URL=${CS_REPO_URL:-https://github.com/jamesalmeida/Circuit-Sword}

ARGS=()
while (($#)); do
  case "$1" in
    --ref) REF=${2:?}; shift 2 ;;
    --out-dir) OUT_DIR=${2:?}; shift 2 ;;
    --cache-dir) CACHE_DIR=${2:?}; shift 2 ;;
    --no-compress) COMPRESS=0; shift ;;
    -h|--help) usage ;;
    -*) echo "Unknown option [$1]"; usage ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
((${#ARGS[@]} == 1)) && [[ ${ARGS[0]} == YES ]] || usage

image_require_tools git sha256sum curl xz chroot

# sudo runs git as root on a checkout owned by someone else; trust this one.
repo_git() { git -c safe.directory="$REPO" -c safe.directory="$REPO/.git" -C "$REPO" "$@"; }
COMMIT=$(repo_git rev-parse --verify "$REF^{commit}") || die "Unknown ref [$REF]"
SHORT=${COMMIT:0:7}
if [[ "$REF" == HEAD && -n "$(repo_git status --porcelain --untracked-files=no)" ]]; then
  echo "WARNING: uncommitted changes in [$REPO] are NOT included; the image installs commit $SHORT" >&2
fi

mkdir -p "$OUT_DIR" "$CACHE_DIR"
BASE_XZ="$CACHE_DIR/$(basename "$BASE_URL")"
if [[ ! -f "$BASE_XZ" ]]; then
  echo "[i] Downloading $BASE_URL"
  curl -fL --retry 3 -o "$BASE_XZ.part" "$BASE_URL"
  mv "$BASE_XZ.part" "$BASE_XZ"
fi
echo "[i] Checking base image checksum.."
[[ "$(sha256sum "$BASE_XZ" | cut -d' ' -f1)" == "$BASE_SHA256" ]] ||
  die "[$BASE_XZ] does not match the pinned SHA-256 $BASE_SHA256; delete it to download again"

BUILD="CS_BOOKWORM_CM3_$(date -u +"%Y%m%d-%H%M%S")_g$SHORT"
NAME="$OUT_DIR/circuit-sword-$BUILD"
IMG="$NAME.img"
MANIFEST="$NAME.manifest"
PACKAGES="$NAME.packages"
LOG="$NAME.log"
FINAL=$IMG
((COMPRESS)) && FINAL="$IMG.xz"

SUCCESS=0
on_exit() {
  image_cleanup || true
  if ((SUCCESS == 0)); then
    rm -f "$IMG" "$IMG.xz" "$FINAL.sha256" "$MANIFEST" "$PACKAGES"
    echo "FAILED: no image was produced; setup log kept at [$LOG]" >&2
  fi
}
trap on_exit EXIT

echo "[i] Unpacking base image.."
xz -dc "$BASE_XZ" > "$IMG"

image_find_partitions "$IMG"
image_grow_root "$IMG" "$GROW_ROOT_BYTES"
echo "[i] Boot partition at byte $BOOT_OFFSET ($BOOT_SIZE bytes), root at byte $ROOT_OFFSET ($ROOT_SIZE bytes)"
image_mount_partitions "$IMG"

BOOT_DIR=$(image_boot_dir "$ROOT_MNT")
[[ "$BOOT_DIR" == /boot/firmware ]] ||
  die "Expected a Bookworm image with its boot partition at /boot/firmware, not [$BOOT_DIR]"
image_require_user "$ROOT_MNT" pi
[[ "$IMAGE_UID:$IMAGE_HOME" == "1000:/home/pi" ]] ||
  die "Expected pi (uid 1000, /home/pi) in the base image; found uid $IMAGE_UID, home $IMAGE_HOME"

# The CM3 boots kernel7.img: the rpi-v7 flavour
kernels=()
for dir in "$ROOT_MNT"/lib/modules/*-rpi-v7; do
  [[ -d "$dir" ]] && kernels+=("$(basename "$dir")")
done
((${#kernels[@]} == 1)) || die "Expected one rpi-v7 kernel in the image; found: ${kernels[*]:-none}"
KERNEL=${kernels[0]}
echo "[i] Image kernel: $KERNEL"

# The image's 32-bit ARM programs must run here (binfmt_misc is not visible
# inside containers, so try one rather than looking for the registration)
chroot "$ROOT_MNT" /bin/true 2>/dev/null ||
  die "Cannot run the image's ARM programs; register qemu-arm with binfmt_misc (qemu-user-static, and on Arch qemu-user-static-binfmt)"

image_clone_repo "$REPO" "$COMMIT" "$ROOT_MNT/home/pi/Circuit-Sword" "$CS_REPO_URL"

# Chroot plumbing: boot partition where the OS expects it, kernel filesystems,
# and the build host's DNS while apt runs
image_bind "$BOOT_MNT" "$ROOT_MNT/boot/firmware"
for fs in /dev /dev/pts /proc /sys; do
  image_bind "$fs" "$ROOT_MNT$fs"
done
mv "$ROOT_MNT/etc/resolv.conf" "$ROOT_MNT/etc/resolv.conf.cs-build"
cp /etc/resolv.conf "$ROOT_MNT/etc/resolv.conf"

# Runs a command in the image with a clean environment (none of the build
# host's, such as a TMPDIR that does not exist in the image)
in_image() {
  chroot "$ROOT_MNT" /usr/bin/env -i HOME=/root TERM=dumb LANG=C.UTF-8 \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin "$@"
}

echo "[i] Setting up the image (log: $LOG).."
in_image bash /home/pi/Circuit-Sword/bookworm/image-setup.sh "$KERNEL" > "$LOG" 2>&1 ||
  { tail -30 "$LOG" >&2; die "image-setup.sh failed"; }

DKMS=$(in_image dkms status rtl8723bs-cs)
grep -q "$KERNEL.*installed" <<<"$DKMS" || die "RTL8723BS module is not installed for $KERNEL: $DKMS"
in_image dpkg-query -W -f '${Package}\t${Version}\t${Architecture}\n' > "$PACKAGES"
HELD=$(in_image apt-mark showhold | tr '\n' ' ')

mv "$ROOT_MNT/etc/resolv.conf.cs-build" "$ROOT_MNT/etc/resolv.conf"

{
  echo "build_id: $BUILD"
  echo "built_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "source_repository: $CS_REPO_URL"
  echo "source_commit: $COMMIT"
  echo "base_image: $BASE_URL"
  echo "base_image_sha256: $BASE_SHA256"
  echo "kernel: $KERNEL"
  echo "rtl8723bs: $DKMS"
  echo "held_packages: $HELD"
  echo "packages: $(basename "$PACKAGES") ($(wc -l < "$PACKAGES") packages)"
  echo "boot_dir: $BOOT_DIR"
  echo "runtime_user: pi"
  echo "boot_partition: offset=$BOOT_OFFSET size=$BOOT_SIZE"
  echo "root_partition: offset=$ROOT_OFFSET size=$ROOT_SIZE"
  echo "build_host: $(uname -srm)"
} > "$MANIFEST"
cp "$MANIFEST" "$ROOT_MNT/etc/circuit-sword-build"

# Unmount, then confirm both filesystems are still clean
image_cleanup
image_verify_filesystems "$IMG"

echo "image_sha256: $(sha256sum "$IMG" | cut -d' ' -f1)" >> "$MANIFEST"
if ((COMPRESS)); then
  echo "[i] Compressing.."
  xz -T0 -6 "$IMG"
  echo "image_xz_sha256: $(sha256sum "$FINAL" | cut -d' ' -f1)" >> "$MANIFEST"
fi
(cd "$(dirname "$FINAL")" && sha256sum "$(basename "$FINAL")") > "$FINAL.sha256"

SUCCESS=1
echo "SUCCESS: Image [$FINAL] has been built!"
echo "Manifest: [$MANIFEST]"
