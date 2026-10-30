# shellcheck shell=bash
# Shared helpers for the image build scripts. Source this file; do not run it.
#
# Partitions are found from the image's partition table and identified by
# probing their filesystems, never by fixed byte offsets. Every loop device,
# mount and temporary directory is recorded and released by image_cleanup, which
# callers run from an EXIT trap so a failed build leaves nothing attached.
#
# Needs util-linux (sfdisk, blkid, losetup), dosfstools and e2fsprogs.
#
# Functions return results in the global variables their comments name.
# shellcheck disable=SC2034

CS_MOUNTS=()
CS_LOOPS=()
CS_TMPDIRS=()

die() {
  echo "ERROR: $*" >&2
  exit 1
}

image_require_tools() {
  local tool
  for tool in sfdisk blkid losetup mount umount fsck.vfat e2fsck "$@"; do
    command -v "$tool" >/dev/null || die "Required tool [$tool] not found"
  done
}

# Sets BOOT_OFFSET, BOOT_SIZE, ROOT_OFFSET and ROOT_SIZE (bytes) for the image's
# only FAT and only ext4 partition. Anything else is ambiguous and refused.
image_find_partitions() {
  local img=$1 dump sector start size offset bytes fstype image_bytes
  local -a vfat=() ext4=() other=()

  dump=$(sfdisk --dump "$img" 2>/dev/null) || die "No readable partition table in [$img]"
  sector=$(sed -nE 's/^sector-size: *([0-9]+)$/\1/p' <<<"$dump")
  sector=${sector:-512}
  image_bytes=$(stat -c %s "$img")

  while read -r start size; do
    [[ -n "$start" ]] || continue
    offset=$((start * sector))
    bytes=$((size * sector))
    ((bytes > 0)) || continue
    ((offset + bytes <= image_bytes)) ||
      die "Partition at byte $offset (size $bytes) extends past the end of [$img]; is the image truncated?"
    fstype=$(blkid --probe --offset "$offset" --size "$bytes" -o value -s TYPE "$img" 2>/dev/null) || fstype=""
    case "$fstype" in
      vfat) vfat+=("$offset $bytes") ;;
      ext4) ext4+=("$offset $bytes") ;;
      *) other+=("${fstype:-unknown}@$offset") ;;
    esac
  done < <(sed -nE 's/.*start= *([0-9]+), *size= *([0-9]+).*/\1 \2/p' <<<"$dump")

  ((${#vfat[@]} == 1 && ${#ext4[@]} == 1)) ||
    die "Expected one FAT boot and one ext4 root partition in [$img]; found ${#vfat[@]} FAT, ${#ext4[@]} ext4, other: ${other[*]:-none}"

  read -r BOOT_OFFSET BOOT_SIZE <<<"${vfat[0]}"
  read -r ROOT_OFFSET ROOT_SIZE <<<"${ext4[0]}"
}

# Attaches IMG's byte range to a loop device and checks its filesystem without
# repairing it. Sets IMAGE_LOOP. Pass "ro" as MODE for a read-only device.
image_attach_checked() {
  local img=$1 offset=$2 size=$3 fstype=$4 mode=${5:-rw} status=0 report
  local -a ro=()
  [[ "$mode" == ro ]] && ro=(--read-only)

  IMAGE_LOOP=$(losetup --find --show "${ro[@]}" --offset "$offset" --sizelimit "$size" "$img") ||
    die "Could not attach [$img] at byte $offset to a loop device"
  CS_LOOPS+=("$IMAGE_LOOP")

  case "$fstype" in
    vfat) report=$(fsck.vfat -n "$IMAGE_LOOP" 2>&1) || status=$? ;;
    ext4) report=$(e2fsck -fn "$IMAGE_LOOP" 2>&1) || status=$? ;;
    *) die "Unsupported filesystem [$fstype]" ;;
  esac
  ((status == 0)) || printf '%s\n' "$report" >&2
  ((status == 0)) || die "$fstype filesystem at byte $offset of [$img] failed its check (exit $status); repair or replace the image"
}

# Checks and mounts one partition on a new temporary directory; sets IMAGE_MOUNT.
image_mount() {
  local img=$1 offset=$2 size=$3 fstype=$4
  image_attach_checked "$img" "$offset" "$size" "$fstype"
  IMAGE_MOUNT=$(mktemp -d "${TMPDIR:-/tmp}/cs-$fstype.XXXXXX")
  CS_TMPDIRS+=("$IMAGE_MOUNT")
  mount -t "$fstype" "$IMAGE_LOOP" "$IMAGE_MOUNT" || die "Could not mount $fstype partition of [$img]"
  CS_MOUNTS+=("$IMAGE_MOUNT")
}

# Mounts the root and boot partitions found by image_find_partitions.
# Sets ROOT_MNT and BOOT_MNT.
image_mount_partitions() {
  local img=$1
  image_mount "$img" "$ROOT_OFFSET" "$ROOT_SIZE" ext4
  ROOT_MNT=$IMAGE_MOUNT
  image_mount "$img" "$BOOT_OFFSET" "$BOOT_SIZE" vfat
  BOOT_MNT=$IMAGE_MOUNT
}

# Re-checks both filesystems of an unmounted image without changing it.
image_verify_filesystems() {
  local img=$1
  image_attach_checked "$img" "$BOOT_OFFSET" "$BOOT_SIZE" vfat ro
  image_attach_checked "$img" "$ROOT_OFFSET" "$ROOT_SIZE" ext4 ro
  image_cleanup
}

# Unmounts, detaches and removes everything recorded above, newest first.
# Returns nonzero if anything could not be released.
image_cleanup() {
  local i failed=0
  sync
  for ((i = ${#CS_MOUNTS[@]} - 1; i >= 0; i--)); do
    umount "${CS_MOUNTS[i]}" || { echo "WARNING: could not unmount [${CS_MOUNTS[i]}]" >&2; failed=1; }
  done
  for ((i = ${#CS_LOOPS[@]} - 1; i >= 0; i--)); do
    losetup -d "${CS_LOOPS[i]}" 2>/dev/null ||
      { echo "WARNING: could not detach [${CS_LOOPS[i]}]" >&2; failed=1; }
  done
  for ((i = ${#CS_TMPDIRS[@]} - 1; i >= 0; i--)); do
    rmdir "${CS_TMPDIRS[i]}" 2>/dev/null || { echo "WARNING: left [${CS_TMPDIRS[i]}] in place" >&2; failed=1; }
  done
  CS_MOUNTS=()
  CS_LOOPS=()
  CS_TMPDIRS=()
  return $failed
}

# Prints where the root filesystem's fstab mounts the FAT partition:
# /boot on Stretch/Buster-era images, /boot/firmware on Bookworm and later.
image_boot_dir() {
  local root=$1 dir
  [[ -f "$root/etc/fstab" ]] || die "Root filesystem has no /etc/fstab"
  dir=$(awk '$1 !~ /^#/ && $3 == "vfat" { print $2; exit }' "$root/etc/fstab")
  [[ -n "$dir" ]] || die "The image's /etc/fstab does not mount a FAT boot partition"
  printf '%s\n' "$dir"
}

# Checks that USER exists in the image with a home directory; sets IMAGE_UID,
# IMAGE_GID and IMAGE_HOME from the image's own /etc/passwd (not the build host's).
image_require_user() {
  local root=$1 user=$2 entry
  entry=$(awk -F: -v user="$user" '$1 == user { print $3 ":" $4 ":" $6; exit }' "$root/etc/passwd")
  [[ -n "$entry" ]] || die "User [$user] does not exist in the image"
  IFS=: read -r IMAGE_UID IMAGE_GID IMAGE_HOME <<<"$entry"
  [[ -d "$root$IMAGE_HOME" ]] || die "Home directory [$IMAGE_HOME] of [$user] is missing from the image"
}
