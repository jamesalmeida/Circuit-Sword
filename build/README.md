# Image builders

- [Bookworm base image](#bookworm-base-image): `build-bookworm-image.sh`, the
  current target.
- [Legacy RetroPie](#legacy-retropie): `build-image.sh` and `upgrade-kernel.sh`,
  for Stretch/Buster-era RetroPie images.

## Bookworm base image

`build-bookworm-image.sh` builds the DMG-CM3 base system recorded in
[the Bookworm bring-up notes](../docs/bookworm-bringup.md) from the pinned
Raspberry Pi OS Lite (Legacy, 32-bit) image in
[`bookworm-inputs.sh`](bookworm-inputs.sh). It runs
[`bookworm/image-setup.sh`](../bookworm/image-setup.sh) inside the image in an
emulated ARM chroot:

- `config.txt` from `bookworm/config.txt` (fkms, 640×480 DPI LCD, SDIO Wi-Fi,
  safe-shutdown GPIO); the original is kept as `config_ORIGINAL.txt`.
- RTL8723BS Wi-Fi driver built with DKMS for the image's `rpi-v7` kernel, with
  driver and NetworkManager power saving off. Kernel, headers and firmware
  packages are held.
- The HUD with its private DispmanX userland, the panel 180° flip service,
  `/opt/cs_shutdown.sh`, console boot and persistent logs.
- `python3-serial`, ALSA utilities and PipeWire for the HUD's volume control.

RetroPie is not included; install it on the device afterwards as in the
bring-up notes.

### Build host

Linux, root, network, about 10 GB free, and `qemu-arm` registered with
binfmt_misc (Debian/Ubuntu: `qemu-user-static`; Arch: `qemu-user-static
qemu-user-static-binfmt`). In a container, use `--privileged` and create the
`/dev/loopN` nodes first.

```
sudo build/build-bookworm-image.sh --out-dir out YES
```

Options: `--ref REF` (commit to install, default `HEAD`), `--out-dir DIR`,
`--cache-dir DIR` (downloaded base image, default `./cache`), `--no-compress`.

Outputs, named `circuit-sword-CS_BOOKWORM_CM3_<UTC date-time>_g<commit>`:
`.img.xz` and its `.sha256`, a `.manifest` (base image URL and checksum,
commit, kernel, Wi-Fi driver status, held packages, partition offsets, image
checksums), a `.packages` list of every installed package version, and the
`.log` of the setup run. The manifest is also written into the image as
`/etc/circuit-sword-build`.

### Checking an image

```
sudo tests/build/check-bookworm-image.sh out/circuit-sword-<build>.img.xz
```

Mounts a copy and checks, without booting: `config.txt`, the Wi-Fi module
for the image's kernel and its power-saving settings, held kernel packages, the
HUD binary and its libraries, the enabled HUD and panel-flip services, Python
modules, console boot, ownership and leftovers from the build. Only the
handheld can show that the LCD, Wi-Fi, HUD and safe shutdown actually work.

### First boot

Write the image with Raspberry Pi Imager ("Use custom"), and in its OS
customisation set the user name to **`pi`**: the services and checkout live
in `/home/pi`, and a different name renames that home directory. Also set
Wi-Fi (with country) and SSH. The first seconds of boot are upside down until
the panel flip runs.

## Legacy RetroPie

`build-image.sh` turns a legacy RetroPie image into a Circuit Sword image.
It supports only images that mount the boot partition at `/boot` (RetroPie
4.x, Raspbian Stretch/Buster). Bookworm and later mount it at `/boot/firmware`
and are refused, because `install.sh` would write a `config.txt` that the
firmware never reads. For Bookworm, use the
[Bookworm base image](#bookworm-base-image) builder.

### Build host

Linux, run as root, with `util-linux` (`sfdisk`, `blkid`, `losetup`),
`dosfstools`, `e2fsprogs`, `git`, `dpkg`, `unzip`, `rsync` and network access
(`install.sh` fetches the Pixel theme). On Debian or Ubuntu:

```
sudo apt-get install fdisk dosfstools e2fsprogs git dpkg unzip rsync
```

In a container, use `--privileged` and create the `/dev/loopN` nodes first:
loop devices that the host creates later do not appear inside the container.

### Base image

The image must contain one FAT boot partition and one ext4 root partition
anywhere on the disk; offsets are read from the partition table. Both
filesystems are checked (read-only) before and after the build.

The base must already have `python3`, `python3-serial` (3.0 or newer) and
`python3-rpi.gpio` installed. The installer never runs the build host's apt
against the image. Stock RetroPie 4.8 lacks `python3-serial`, so it is refused
until that package is installed in it (on a Pi, or in an emulated chroot).

### Build

```
cd Circuit-Sword/build

# Optional: replace the kernel (zip layout from build-kernel.txt)
sudo ./upgrade-kernel.sh YES <base_image>.img pi_4.14.14-v7+.zip

sudo ./build-image.sh --base-sha256 <sha256 of the base> YES <base_image>_pi_4.14.14-v7+.img
```

`build-image.sh` options:

| Option | Effect |
| --- | --- |
| `--ref REF` | Install this commit, branch or tag of the checkout (default `HEAD`) |
| `--base-sha256 HEX` | Refuse a base image with a different SHA-256 |
| `--out-dir DIR` | Where to write the outputs (default: current directory) |
| `--user NAME` | Runtime user in the image (default `pi`; `install.sh` and the services expect `/home/pi`) |
| `--no-legacy-boot-firmware` | Skip Kite's 2019 CM3+ boot firmware (`settings/pi_plus_20190130.zip`) |

The image installs **committed** files only. Uncommitted changes print a warning
and are left out. The commit is cloned into `/home/pi/Circuit-Sword` as a
`master` branch that tracks this fork, so `update.sh` can pull later.

### Outputs

For each build, with a new build ID `CSO_CM3_<UTC date-time>_g<commit>`:

- `<base>_<build id>.img`: the image (the base image is not changed).
- `<base>_<build id>.img.sha256`: its checksum, for `sha256sum -c`.
- `<base>_<build id>.img.manifest`: build ID, source repository and commit,
  base image and its SHA-256, boot firmware and its SHA-256, boot directory,
  user, partition offsets, build host, and the image's SHA-256. Inputs recorded
  by `upgrade-kernel.sh` (kernel zip and its SHA-256) appear as `base.*` lines.

The manifest, minus the final image checksum, is also written into the image
as `/etc/circuit-sword-build`, so a card shows which build it is running.

A failed build deletes its partial outputs and detaches every loop device it
attached.

### Tests

```
sudo tests/build/test-image-build.sh
```

Runs against small generated images. Set `CS_TEST_RETROPIE_IMG` to a stock
`retropie-buster-4.8-rpi2_3_zero2w.img` for the end-to-end builds, and
`CS_TEST_BOOKWORM_IMG` to a stock Raspberry Pi OS Lite Bookworm image to check
that it is refused. These tests do not boot the result; a built image must
still be checked on a spare card.
