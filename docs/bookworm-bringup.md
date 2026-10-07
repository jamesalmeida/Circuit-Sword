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

`cmdline.txt` gains `fbcon=rotate:2`. `display_rotate=2` and
`display_lcd_rotate=2` are **not applied** under fkms (`vcgencmd get_config`
reports no rotate value); the boot splash is upside down.

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

Bring-up logs are kept on the card in `/home/pi/cs-bringup/`.

## Spike checklist

| Step | Status |
| --- | --- |
| 1. Boot, Wi-Fi, SSH | Pass (Wi-Fi after DKMS driver) |
| 2. LCD output | Pass; **rotation open** |
| 3. HUD / safe shutdown | Not started (power switch currently cuts power) |
| 4. Python 3 tools | Not started |
| 5. RetroPie + one game | Not started |
