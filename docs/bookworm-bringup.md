# Bookworm bring-up (spike A)

Progress on the [OS upgrade plan](os-upgrade-plan.md) spike, 2026-10-06, on the
128 GB spare card. The original Stretch card is untouched.

## Image

Raspberry Pi Imager v2.0.11.1, *Raspberry Pi OS (Legacy, 32-bit)*, image
"Raspberry Pi reference 2026-10-06" (pi-gen stage4, i.e. the desktop edition;
Lite would be leaner). Raspbian 12 Bookworm, kernel `6.12.109+rpt-rpi-v7`.
Imager customisation: hostname `gameboy-cm3`, user `pi`, Wi-Fi, SSH key only.

ROMs, saves, BIOS and `/opt/retropie/configs` from the Stretch spare card were
copied to the Mac first (outside Git) and verified by file count and bytes.

## Boot partition changes

[`bookworm/config.txt`](../bookworm/config.txt) is the working
`/boot/firmware/config.txt`. Against the stock file:

- `dtoverlay=vc4-fkms-v3d` instead of `vc4-kms-v3d`; dropped
  `disable_fw_kms_setup` and `disable_overscan`; `dtparam=audio=off`.
- Appended the Circuit Sword block: SDIO Wi-Fi, `gpio-poweroff`, and the
  640×480 DPI settings from the Stretch card, including 2 px side margins.

`display_rotate=2` and `display_lcd_rotate=2` are **not applied** under fkms
(`vcgencmd get_config` reports no rotate value), so they are commented out. See
[Rotation](#rotation).

Default target set to `multi-user.target` (console; the desktop left the LCD
blank). Journald made persistent via
`/etc/systemd/journald.conf.d/99-circuit-sword.conf`.

## Wi-Fi: RTL8723BS needs an out-of-tree driver

The SDIO chip enumerates (`sdio:c07v024CdB723`) and `firmware-realtek` provides
`rtlwifi/rtl8723bs_nic.bin`, but **Raspberry Pi kernels never enable
`CONFIG_RTL8723BS`**: absent from `bcm2709_defconfig` on 4.14 through 6.12.
Kite's Stretch image used a custom kernel ([`build/build-kernel.txt`](../build/build-kernel.txt)).

Fix: build the staging driver from `raspberrypi/linux` `rpi-6.12.y` (`43c132e`,
2026-10-05; its post-6.12.109 driver commits are only security/bug fixes) and
register it with DKMS. Build time on the CM3: 1 min 46 s.

- Online: [`bookworm/install-rtl8723bs-dkms.sh`](../bookworm/install-rtl8723bs-dkms.sh).
- Offline (no network yet, as on first boot): resolve and download the 75
  packages for `linux-headers-6.12.109+rpt-rpi-v7 build-essential bc`
  (~105 MB) with [`bookworm/resolve-debs.py`](../bookworm/resolve-debs.py),
  place them and the driver tarball in `/boot/firmware/cs-wifi/`, and run
  [`bookworm/offline-wifi-build.sh`](../bookworm/offline-wifi-build.sh) once via
  `systemd.run=` on `cmdline.txt` (with `systemd.unit=kernel-command-line.target`
  and `systemd.run_success_action=reboot`). The script restores `cmdline.txt`.

Result: `wlan0` up at 192.168.184.136; `dkms status` reports
`rtl8723bs-cs/6.12.y.43c132e … installed`; `linux-headers-rpi-v7` is installed
so kernel upgrades pull matching headers and DKMS rebuilds the module.

The kernel, headers and `raspi-firmware` are held (`apt-mark hold`) at
6.12.109 so a routine upgrade cannot leave the handheld without Wi-Fi. To
update deliberately: `sudo apt-mark unhold` those packages, upgrade, confirm
`dkms status` shows the new kernel as installed *before* rebooting, then hold
again.

Bring-up logs are kept on the card in `/home/pi/cs-bringup/`.

## Rotation

The LCD is mounted upside down. Software options tried first:

- `fbcon=rotate:2` rotates only console text.
- `video=DSI-1:panel_orientation=upside_down` (fkms names the DPI connector
  `DSI-1`) makes DRM rotate the console plane in hardware; combined with
  `fbcon=rotate:2` the console was flipped twice. Neither affects DispmanX.

**Adopted: rotate in the panel.** The MCU firmware forwards `L<hex>!` serial
input to the LCD controller over SPI (`lcdSerial()` in
`kite-arduino/CS_FIRMWARE/LCD.ino`). On this 54-pin 640×480 panel, whose init
code Kite never published, writing `0x01` to register `0x36` flips both scan
directions. Observed on the device after a power cycle:

| Write | Result |
| --- | --- |
| `36 03` | one axis only (mirrored) |
| `36 01` | clean 180°, but red/blue swapped |
| `36 09` | clean 180°, correct colours (**adopted**) |

This implies the stock init leaves bit 1 (flip) and bit 3 (BGR) set; an 8-px
edge-band test pattern showed red and blue exchanged with `36 01`. White text
hides the swap, so check colours whenever this register changes. The register is volatile; the MCU
re-initialises the panel at power-up. [`bookworm/cs-lcd-flip.service`](../bookworm/cs-lcd-flip.service)
runs [`bookworm/lcd-flip.py`](../bookworm/lcd-flip.py) as soon as
`/dev/ttyACM0` appears (~11 s; flip done at ~14 s), so console, HUD and all
later graphics are upright with no software rotation. The first seconds of
boot remain upside down. No MCU firmware was flashed.

To undo: `sudo systemctl disable cs-lcd-flip` and power-cycle.

## HUD

The legacy `libraspberrypi0`/`-dev` packages still exist for Bookworm 32-bit,
but **must not be installed system-wide**: they conflict with `raspi-utils`, so
apt silently removed ~19 packages including `raspberrypi-sys-mods`,
`raspberrypi-net-mods`, `raspi-config` and `rpd-plym-splash`; RetroPie's
install later removed `libraspberrypi0` again, breaking the HUD and with it the
safe-shutdown power switch. [`bookworm/install-cs-hud.sh`](../bookworm/install-cs-hud.sh)
now unpacks both debs privately into `/opt/cs-hud/userland` and links the HUD
with an RPATH (`--disable-new-dtags`, so `libvchiq_arm`/`libvcos` resolve there
too). The removed Pi system packages were reinstalled.

Kite's bundled `wiringpi_2.46_armhf.deb` installs (wiringPi is no longer
packaged). The HUD source builds unmodified and runs under fkms: UART, Mode
overlay and status icons work.

Before the panel flip, the HUD's layers appeared upside down. The opt-in
`CS_HUD_ROTATE=180` environment variable adds `DISPMANX_ROTATE_180` to each
element; it is **not set** now that the panel rotates, but remains for panels
that cannot. The firmware rotates elements about
the display, so destination rectangles must **not** be mirrored as well
(tested: mirroring put the status bar at the bottom). Install with
[`bookworm/install-cs-hud.sh`](../bookworm/install-cs-hud.sh).

## RetroPie

RetroPie-Setup `15b002c` (2026-10-06), `basic_install` with Bookworm rpi3/kms
binaries. Two pitfalls:

- fkms makes RetroPie add the `dispmanx` platform flag, which makes
  EmulationStation depend on `omxplayer` (absent on Bookworm). Run with
  `__has_dispmanx=0`; RetroPie's packages use KMS anyway, and the HUD's
  DispmanX use is independent.
- Under a systemd unit whose stderr is the journal, RetroPie's download helper
  cannot open `/dev/stderr`, so every `.asc` signature "fails" and binary
  packages are silently skipped. Run it under `script -qfec` for a pty.

`autostart enable` needs `raspi-config` (for console autologin). EmulationStation's
volume control must be `AudioDevice=Master` for the USB card (default `HDMI`
gives "failed to find mixer elements"). Pixel theme help rows moved from
`0.960/0.962` to `0.925`. An edge-band pattern shows the bottom bezel hides
~9–10 px; swapping the vertical porches (13↔32) made no difference and was
reverted.

## Spike checklist

| Step | Status |
| --- | --- |
| 1. Boot, Wi-Fi, SSH | Pass (Wi-Fi after DKMS driver) |
| 2. LCD output | Pass; panel-level 180° flip from ~14 s into boot |
| 3. HUD / safe shutdown | Pass: upright, icons top-right, Mode overlay, safe shutdown on power switch, autostart |
| 4. Python 3 tools | Pass (config tool, tester USB/GPIO); tester `pngview` needs rebuild |
| 5. RetroPie + one game | ES running, input configured (incl. L1/L2/R1/R2); game test pending ROM copy |
