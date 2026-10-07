# OS upgrade plan

Decision record for moving the DMG-CM3 off Raspbian 9 Stretch. Written
2026-10-06; see the [software baseline](software-baseline.md) for the current
versions.

## Constraints

| Fact | Source |
| --- | --- |
| Board is a CM3 (revision `a220a0`), 1 GB RAM, 32-bit ARMv7 | `/proc/cpuinfo` on the handheld |
| LCD is driven by firmware DPI settings: `dtoverlay=dpi18`, `enable_dpi_lcd`, `dpi_output_format`, `hdmi_timings`, `display_rotate=2` | `/boot/config.txt` |
| HUD, `dpi-cloner` and `cs-tester/pngview` draw through DispmanX (`bcm_host`) | [issue #2](https://github.com/jamesalmeida/Circuit-Sword/issues/2) |
| HUD reads buttons through wiringPi | `cs-hud/src` includes `<wiringPi.h>` |
| Wi-Fi is RTL8723BS on SDIO (`r8723bs`, in the mainline staging kernel) | `lsmod` |
| Python 3 port installed and passing on the spare card | [python3-compatibility.md](python3-compatibility.md) |

## What RetroPie supports now

- The last official RetroPie **image** is 4.8 (March 2022, Buster-based).
- RetroPie-Setup itself is actively maintained (commits on 2026-10-05/06).
- It ships **prebuilt binaries** for 32-bit Raspberry Pi OS 10 (Buster) and
  11 (Bullseye), and for 32/64-bit OS 12 (Bookworm). Anything newer, including
  13 (Trixie), builds from source, which takes many hours on a CM3.
- On 32-bit Pi, RetroPie still builds DispmanX-capable packages when the
  **fake-KMS (`vc4-fkms-v3d`) driver** is active
  (`get_rpi_video()` in `scriptmodules/system.sh`).

## Options

| | A. Bookworm 32-bit + fkms | B. Buster + RetroPie 4.8 | C. Bookworm/Trixie full KMS |
| --- | --- | --- | --- |
| RetroPie binaries | Yes (current) | Yes | Bookworm yes; Trixie source only |
| OS security updates | Bookworm is the current "Legacy" release | EOL since 2024 | Yes |
| HUD (DispmanX) | Likely works under fkms; must be proven | Works | **Rewrite to DRM** required (#2) |
| LCD config | Firmware DPI likely still honored under fkms; must be proven | Unchanged | Rewrite as `vc4-kms-dpi-generic` overlay |
| Python | 3.11 | 3.7 | 3.11 / 3.13 |
| Effort / risk | Low–medium; one spike decides | Low; dead-end OS | High |

FKMS is deprecated but still present on Bookworm. Raspberry Pi's
[Bookworm migration guide](https://pip-assets.raspberrypi.com/categories/1261-transitioning/documents/RP-006519-WP-1-Transitioning%20from%20Bullseye%20to%20Bookworm.pdf)
recommends moving DispmanX apps to DRM, and `libraspberrypi-dev` is gone from
Trixie, so option A is a stepping stone, not the end state.

## Recommendation

**Spike option A first; fall back to B if it fails; plan C as the long-term
HUD work under #2.**

### Spike A: pass/fail checklist (spare card, no Circuit Sword installer)

1. Flash Raspberry Pi OS **Lite, 32-bit, Bookworm** (Legacy channel) with SSH
   and Wi-Fi preset in Raspberry Pi Imager. Wi-Fi needs the RTL8723BS firmware
   from `wifi-firmware/` if the stock image lacks it.
2. Append the DPI block from `settings/config.txt` to
   `/boot/firmware/config.txt` and set `dtoverlay=vc4-fkms-v3d`.
   **Pass:** console appears on the LCD, right way up, with 2 px side margins.
3. Check `libraspberrypi0`/`libraspberrypi-dev` provide `bcm_host`; install
   wiringPi (bundled `.deb` or the maintained WiringPi fork); build `cs-hud`.
   **Pass:** HUD overlay shows battery/volume over the console.
4. Install the Python 3 port and deps from apt.
   **Pass:** `cs-configure.py` readings and `cs-tester.py` all OK.
5. Install RetroPie-Setup (basic install, binaries) and one emulator.
   **Pass:** EmulationStation and one game run on the LCD with HUD and audio.

Any failure in steps 2–3 that cannot be fixed by configuration is a stop: record
it and fall back to option B.

## Card plan

The 128 GB spare card currently holds the validated Stretch restore with the
Python 3 port; its HDMI check is still pending. The spike erases whichever card
it uses. Keep the original working card untouched throughout.
