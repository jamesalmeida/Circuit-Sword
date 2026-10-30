#!/bin/bash
# Tests for build/image-lib.sh and build/build-image.sh on disposable images.
#
# Needs root on Linux (loop devices) plus sfdisk, mkfs.vfat, mkfs.ext4, git,
# dpkg, unzip, zip and rsync. Never touches a real disk. Optional real base images:
#   CS_TEST_RETROPIE_IMG  stock retropie-buster-4.8-rpi2_3_zero2w.img (end-to-end build)
#   CS_TEST_BOOKWORM_IMG  stock Raspberry Pi OS Lite Bookworm armhf image (must be refused)
# The end-to-end build clones es-theme-pixel from GitHub, as install.sh does.
#
# Usage: sudo tests/build/test-image-build.sh

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/cs-image-test.XXXXXX")
PASS=0
FAIL=0
SKIP=0

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

ok() { echo "PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "SKIP: $1"; SKIP=$((SKIP + 1)); }
check() { local name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }

# in_lib SCRIPT ARGS...: runs SCRIPT in a new shell with build/image-lib.sh
# loaded and cleanup trapped, so its exit-on-error stays contained. ARGS are $1...
in_lib() {
  local script=$1
  shift
  bash -c ". \"$REPO/build/image-lib.sh\"; trap image_cleanup EXIT; $script" in_lib "$@"
}

no_loops_under() { ! losetup -a | grep -qF "$1"; }
no_temp_mounts() { ! grep -q " ${TMPDIR:-/tmp}/cs-" /proc/mounts; }

# make_image FILE BOOT_START BOOT_SECTORS ROOT_START ROOT_SECTORS FSTAB_BOOT_DIR [ROOT2_START]
# A FAT boot and ext4 root partition at the given sectors, with a minimal
# root filesystem: fstab, a pi user (uid 1000) and its home directory.
make_image() {
  local img=$1 bs=$2 bn=$3 rs=$4 rn=$5 bootdir=$6 r2=${7:-}
  local tree="$WORK/tree" end=$((rs + rn))
  [[ -n "$r2" ]] && end=$((r2 + rn))
  truncate -s $(((end + 2048) * 512)) "$img"
  {
    echo "label: dos"
    echo "start=$bs, size=$bn, type=c"
    echo "start=$rs, size=$rn, type=83"
    [[ -n "$r2" ]] && echo "start=$r2, size=$rn, type=83"
  } | sfdisk -q "$img"
  rm -rf "$tree"
  mkdir -p "$tree/etc" "$tree/home/pi"
  printf 'proc /proc proc defaults 0 0\nPARTUUID=1-01 %s vfat defaults 0 2\nPARTUUID=1-02 / ext4 defaults 0 1\n' \
    "$bootdir" > "$tree/etc/fstab"
  printf 'root:x:0:0:root:/root:/bin/bash\npi:x:1000:1000:,,,:/home/pi:/bin/bash\n' > "$tree/etc/passwd"
  local fat="$WORK/fat.part" ext="$WORK/ext.part"
  rm -f "$fat" "$ext"
  mkfs.vfat -C "$fat" $((bn / 2)) >/dev/null
  mkfs.ext4 -q -F -d "$tree" "$ext" $((rn / 2))k >/dev/null
  dd if="$fat" of="$img" bs=512 seek="$bs" conv=notrunc status=none
  dd if="$ext" of="$img" bs=512 seek="$rs" conv=notrunc status=none
  [[ -n "$r2" ]] && dd if="$ext" of="$img" bs=512 seek="$r2" conv=notrunc status=none
  rm -f "$fat" "$ext"
}

# run_build IMG OUTDIR [options...]: prints output, returns build-image's status.
run_build() {
  local img=$1 out=$2
  shift 2
  bash "$REPO/build/build-image.sh" "$@" --out-dir "$out" YES "$img" 2>&1
}

#####################################################################
echo "== Partition discovery"

IMG="$WORK/odd.img"
make_image "$IMG" 2048 65536 200000 131072 /boot
out=$(in_lib 'image_find_partitions "$1"; echo "$BOOT_OFFSET $BOOT_SIZE $ROOT_OFFSET $ROOT_SIZE"' "$IMG")
check "finds partitions at non-standard offsets" [ "$out" == "1048576 33554432 102400000 67108864" ]

out=$(in_lib 'image_find_partitions "$1"; image_mount_partitions "$1"; image_boot_dir "$ROOT_MNT"; image_require_user "$ROOT_MNT" pi; echo "$IMAGE_UID:$IMAGE_GID:$IMAGE_HOME"' "$IMG")
check "reads boot dir and user from the image" [ "$out" == $'/boot\n1000:1000:/home/pi' ]
check "releases loop devices after mounting" no_loops_under "$IMG"
check "removes temporary mount points" no_temp_mounts

out=$(in_lib 'image_find_partitions "$1"; image_mount_partitions "$1"; image_require_user "$ROOT_MNT" alice' "$IMG" 2>&1)
check "refuses a user missing from the image" grep -q "User \[alice\] does not exist" <<<"$out"

IMG2="$WORK/two-roots.img"
make_image "$IMG2" 2048 65536 100000 65536 /boot 200000
out=$(in_lib 'image_find_partitions "$1"' "$IMG2" 2>&1)
check "refuses an image with two ext4 partitions" grep -q "found 1 FAT, 2 ext4" <<<"$out"
rm -f "$IMG2"

IMG3="$WORK/truncated.img"
cp "$IMG" "$IMG3"
truncate -s $((150000 * 512)) "$IMG3"
out=$(in_lib 'image_find_partitions "$1"' "$IMG3" 2>&1)
check "refuses a truncated image" grep -q "extends past the end" <<<"$out"
rm -f "$IMG3"

#####################################################################
echo "== build-image.sh failures leave nothing behind"

OUT="$WORK/out"
mkdir -p "$OUT"

# A stand-in kernel zip with the layout build/build-kernel.txt produces
KZ="$WORK/kernel"
mkdir -p "$KZ/pi/overlays" "$KZ/modules/lib/modules/4.14.14-test-v7+/kernel"
echo test-kernel > "$KZ/pi/kernel7.img"
echo dtb > "$KZ/pi/bcm2710-rpi-cm3.dtb"
echo dtbo > "$KZ/pi/overlays/test.dtbo"
echo readme > "$KZ/pi/overlays/README"
echo dep > "$KZ/modules/lib/modules/4.14.14-test-v7+/modules.dep"
(cd "$KZ" && zip -qr ../pi_4.14.14-test.zip pi modules)

BW="$WORK/bookworm-layout.img"
make_image "$BW" 16384 65536 100000 131072 /boot/firmware
out=$(run_build "$BW" "$OUT")
status=$?
check "refuses a /boot/firmware image" [ $status -ne 0 ]
check "explains the /boot/firmware refusal" grep -q "mounts its boot partition at \[/boot/firmware\]" <<<"$out"
check "deletes the partial image after a failure" [ -z "$(ls -A "$OUT")" ]
check "detaches loop devices after a failure" no_loops_under "$OUT"
check "unmounts after a failure" no_temp_mounts

mkdir -p "$OUT/pi" && touch "$OUT/pi/keep"
out=$(cd "$OUT" && bash "$REPO/build/upgrade-kernel.sh" YES "$BW" "$WORK/pi_4.14.14-test.zip" 2>&1)
status=$?
check "upgrade-kernel.sh refuses a /boot/firmware image" [ $status -ne 0 ]
check "upgrade-kernel.sh explains the refusal" grep -q "only for /boot images" <<<"$out"
check "upgrade-kernel.sh leaves the current directory alone" [ "$(ls -A "$OUT")" == "pi" ] && [ -f "$OUT/pi/keep" ]
check "upgrade-kernel.sh unmounts after a failure" no_temp_mounts
rm -rf "$OUT/pi" "$BW"

CORRUPT="$WORK/corrupt.img"
cp "$IMG" "$CORRUPT"
# Zero the group descriptors (after the superblock), so the partition still
# probes as ext4 but fails e2fsck.
dd if=/dev/zero of="$CORRUPT" bs=1024 seek=$((102400000 / 1024 + 2)) count=6 conv=notrunc status=none
out=$(run_build "$CORRUPT" "$OUT")
status=$?
check "refuses an image whose root filesystem is damaged" [ $status -ne 0 ]
check "names the damaged filesystem" grep -q "ext4 filesystem at byte 102400000 .* failed its check" <<<"$out"
check "leaves no output after a damaged image" [ -z "$(ls -A "$OUT")" ]
check "unmounts after a damaged image" no_temp_mounts
rm -f "$CORRUPT"

out=$(run_build "$IMG" "$OUT" --base-sha256 0000000000000000000000000000000000000000000000000000000000000000)
status=$?
check "refuses a base image with the wrong checksum" [ $status -ne 0 ]
check "reports the checksum mismatch" grep -q "Base image SHA-256 is" <<<"$out"

out=$(bash "$REPO/build/build-image.sh" YES "$IMG" master 2>&1)
check "explains the removed branch argument" grep -q "Use --ref master" <<<"$out"

#####################################################################
echo "== Real base images"

if [[ -n "${CS_TEST_BOOKWORM_IMG:-}" ]]; then
  out=$(run_build "$CS_TEST_BOOKWORM_IMG" "$OUT")
  status=$?
  check "refuses stock Bookworm" [ $status -ne 0 ]
  check "stock Bookworm refusal names /boot/firmware" grep -q "\[/boot/firmware\]" <<<"$out"
  check "stock Bookworm leaves no output" [ -z "$(ls -A "$OUT")" ]
  check "stock Bookworm left nothing mounted" no_temp_mounts
else
  skip "stock Bookworm (set CS_TEST_BOOKWORM_IMG)"
fi

if [[ -n "${CS_TEST_RETROPIE_IMG:-}" ]]; then
  BASE_SUM=$(sha256sum "$CS_TEST_RETROPIE_IMG" | cut -d' ' -f1)
  out=$(run_build "$CS_TEST_RETROPIE_IMG" "$OUT")
  check "stock RetroPie 4.8 is refused for its missing python3-serial" grep -q "needs python3, python3-serial" <<<"$out"
  check "missing package leaves no output" [ -z "$(ls -A "$OUT")" ]

  # Stand-in for a base image prepared with python3-serial: add its dpkg
  # status entry to a copy. Only the builder is under test here.
  PREP="$WORK/retropie-prepared.img"
  cp --sparse=always "$CS_TEST_RETROPIE_IMG" "$PREP"
  in_lib 'image_find_partitions "$1"; image_mount_partitions "$1"
    printf "\nPackage: python3-serial\nStatus: install ok installed\nPriority: optional\nSection: python\nMaintainer: test\nArchitecture: all\nVersion: 3.4-4\nDescription: test fixture\n" >> "$ROOT_MNT/var/lib/dpkg/status"' "$PREP"
  PREP_SUM=$(sha256sum "$PREP" | cut -d' ' -f1)

  COMMIT=$(git -c safe.directory="$REPO" -C "$REPO" rev-parse HEAD)
  out=$(run_build "$PREP" "$OUT" --base-sha256 "$PREP_SUM")
  status=$?
  [[ $status -eq 0 ]] || echo "$out" | tail -20
  check "builds from a prepared RetroPie 4.8 image" [ $status -eq 0 ]
  BUILT=$(ls "$OUT"/*.img 2>/dev/null | head -1)
  [[ -n "$BUILT" ]] || BUILT="$OUT/missing.img"
  MANIFEST="$BUILT.manifest"
  check "names the image after the build and commit" grep -q "_CSO_CM3_[0-9]\{8\}-[0-9]\{6\}_g${COMMIT:0:7}\.img$" <<<"$BUILT"
  check "writes a checksum that verifies" bash -c 'cd "$(dirname "$0")" && sha256sum -c --quiet "$(basename "$0").sha256"' "$BUILT"
  check "manifest records the source commit" grep -q "^source_commit: $COMMIT$" "$MANIFEST"
  check "manifest records the base checksum" grep -q "^base_image_sha256: $PREP_SUM$" "$MANIFEST"
  check "manifest records the image checksum" grep -q "^image_sha256: $(cut -d' ' -f1 "$BUILT.sha256")$" "$MANIFEST"
  check "leaves the base image unchanged" [ "$(sha256sum "$PREP" | cut -d' ' -f1)" == "$PREP_SUM" ]
  check "leaves the original download unchanged" [ "$(sha256sum "$CS_TEST_RETROPIE_IMG" | cut -d' ' -f1)" == "$BASE_SUM" ]
  check "detaches loop devices after a build" no_loops_under "$OUT"
  check "unmounts after a build" no_temp_mounts

  inspect=$(in_lib 'image_find_partitions "$1"; image_mount_partitions "$1"
    cs="$ROOT_MNT/home/pi/Circuit-Sword"
    echo "commit=$(git -c safe.directory="*" -C "$cs" rev-parse HEAD)"
    echo "branch=$(git -c safe.directory="*" -C "$cs" rev-parse --abbrev-ref HEAD)"
    echo "origin=$(git -c safe.directory="*" -C "$cs" remote get-url origin)"
    echo "owner=$(stat -c %u:%g "$cs" "$cs/install.sh" | sort -u | tr "\n" " ")"
    echo "stamp=$(grep -c "^source_commit: " "$ROOT_MNT/etc/circuit-sword-build")"
    echo "hudlink=$(readlink "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/cs-hud.service")"
    cmp -s "$cs/settings/config.txt" "$BOOT_MNT/config.txt" && echo config=cs
    [ -f "$BOOT_MNT/config_ORIGINAL.txt" ] && echo original=kept
    echo "lib=$(readlink "$ROOT_MNT/lib")"
    echo "theme=$(git -c safe.directory="*" -C "$ROOT_MNT/etc/emulationstation/themes/pixel" rev-parse HEAD)"
    unzip -p "$cs/settings/pi_plus_20190130.zip" start.elf | cmp -s - "$BOOT_MNT/start.elf" && echo firmware=plus' "$BUILT")
  check "clones the exact commit into the image" grep -q "^commit=$COMMIT$" <<<"$inspect"
  check "checks out a master branch for update.sh" grep -q "^branch=master$" <<<"$inspect"
  check "points origin at the fork" grep -q "^origin=https://github.com/jamesalmeida/Circuit-Sword$" <<<"$inspect"
  check "owns the checkout by the image's pi uid" grep -q "^owner=1000:1000 $" <<<"$inspect"
  check "stamps the build into /etc/circuit-sword-build" grep -q "^stamp=1$" <<<"$inspect"
  check "links the HUD service inside the image" grep -q "^hudlink=/lib/systemd/system/cs-hud.service$" <<<"$inspect"
  check "installs the Circuit Sword config.txt" grep -q "^config=cs$" <<<"$inspect"
  check "keeps the original config.txt" grep -q "^original=kept$" <<<"$inspect"
  check "keeps merged-/usr /lib -> usr/lib intact" grep -q "^lib=usr/lib$" <<<"$inspect"
  check "installs the pinned Pixel theme commit" grep -q "^theme=50918176ba339ba7bb17b17f53cf94bc3d095d12$" <<<"$inspect"
  check "applies the legacy CM3+ boot firmware" grep -q "^firmware=plus$" <<<"$inspect"
  rm -f "$OUT"/*

  out=$(cd "$OUT" && bash "$REPO/build/upgrade-kernel.sh" YES "$PREP" "$WORK/pi_4.14.14-test.zip" 2>&1)
  status=$?
  [[ $status -eq 0 ]] || echo "$out" | tail -20
  KIMG="$OUT/retropie-prepared_pi_4.14.14-test.img"
  check "upgrade-kernel.sh builds from a prepared RetroPie 4.8 image" [ $status -eq 0 ]
  check "upgrade-kernel.sh records the kernel zip checksum" grep -q "^kernel_zip_sha256: $(sha256sum "$WORK/pi_4.14.14-test.zip" | cut -d' ' -f1)$" "$KIMG.manifest"
  inspect=$(in_lib 'image_find_partitions "$1"; image_mount_partitions "$1"
    echo "kernel=$(cat "$BOOT_MNT/kernel7.img")"
    echo "modules=$(ls "$ROOT_MNT/lib/modules" | tr "\n" " ")"
    echo "lib=$(readlink "$ROOT_MNT/lib")"' "$KIMG")
  check "installs the kernel" grep -q "^kernel=test-kernel$" <<<"$inspect"
  check "replaces the modules" grep -q "^modules=4.14.14-test-v7+ $" <<<"$inspect"
  check "keeps /lib -> usr/lib while copying modules" grep -q "^lib=usr/lib$" <<<"$inspect"
  out=$(run_build "$KIMG" "$OUT" --no-legacy-boot-firmware)
  status=$?
  BUILT=$(ls "$OUT"/*_CSO_CM3_*.img 2>/dev/null | head -1)
  check "builds without the legacy boot firmware" [ $status -eq 0 ]
  check "manifest records no legacy boot firmware" grep -q "^legacy_boot_firmware: none$" "$BUILT.manifest"
  check "manifest carries the kernel from the base image" grep -q "^base.kernel_zip: pi_4.14.14-test.zip$" "$BUILT.manifest"
  rm -f "$OUT"/* "$PREP"
else
  skip "RetroPie 4.8 end-to-end build (set CS_TEST_RETROPIE_IMG)"
fi


echo
echo "$PASS passed, $FAIL failed, $SKIP skipped"
((FAIL == 0))
