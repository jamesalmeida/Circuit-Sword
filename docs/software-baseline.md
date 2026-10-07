# Software baseline and update path

Read-only inventory of the original DMG-CM3 on 2026-10-06:

| Component | Installed version |
| --- | --- |
| OS | Raspbian GNU/Linux 9 (Stretch) |
| Kernel | `4.14.30-v7+` |
| Circuit Sword | v1.3.3, `bde930e` |
| RetroPie-Setup | `fb02fd76`, 2020-06-14 |
| EmulationStation | v2.7.5rp, built 2018-02-27 |
| RetroArch | v1.8.8, `9552f87`, built 2020-06-09, 32-bit GCC 6.3.0 |

Installed emulator directories include `gpsp`, `mame4all`, `mupen64plus`, `pifba`,
`reicast`, `retroarch` and `snes9x`. Libretro cores include multiple SNES9x
generations, MAME 2000/2003, FBNeo, Flycast, PCSX-ReARMed, PPSSPP, mGBA,
Gambatte, Genesis Plus GX, PicoDrive and other console/computer cores.

None of the inspected emulator/core directories contains `.rp-distinfo` build
metadata. Their exact installed revisions are unknown; do not infer them from
the RetroPie-Setup checkout date or an old year in a core's name. No emulator,
OS package, kernel or firmware was updated during this inventory.

## Recommended sequence

1. Restore the existing shrunk backup to a spare 64 GB or larger card and verify
   that it boots. Keep the original working card available. Reapply the committed
   usability patches after restoring; the SD image predates those changes.
2. Implement [Python 3 compatibility (#1)](https://github.com/jamesalmeida/Circuit-Sword/issues/1)
   in this fork. This can begin on the development Mac before a spare card is ready.
3. Establish the display, HUD, controls, audio, Wi-Fi and safe shutdown on a
   supported OS on the spare card. [Display/HUD compatibility (#2)](https://github.com/jamesalmeida/Circuit-Sword/issues/2)
   is a known blocker; a stock modern image is not yet a validated Circuit Sword
   replacement. Select the OS/RetroPie combination during this validation.
4. Install and test emulator updates individually on that supported baseline,
   checking performance, controls, save compatibility and representative games.
5. Automate the proven configuration in the
   [image builder (#3)](https://github.com/jamesalmeida/Circuit-Sword/issues/3), with
   pinned inputs and a distinct version/build identifier for each device image.

Raspberry Pi recommends a fresh image on new boot media for major OS upgrades:
[official OS upgrade guidance](https://www.raspberrypi.com/documentation/computers/os.html#upgrade-to-a-new-major-version).
This supports testing the migration on a spare card instead of upgrading the
working Stretch installation in place.

RetroPie supports updates to individual packages through Manage Packages:
[official update documentation](https://github.com/RetroPie/RetroPie-Docs/blob/master/docs/Updating-RetroPie.md).
Current package availability and compatibility with this old OS still need to be
established before installing anything. Preserve the local joy2key patch when
updating software that supplies those files.

Older arcade cores can require less processing power, and ROM-set versions must
match the chosen arcade emulator. Test replacements rather than assuming all old
cores should be removed:
[official arcade documentation](https://github.com/RetroPie/RetroPie-Docs/blob/master/docs/Arcade.md).
