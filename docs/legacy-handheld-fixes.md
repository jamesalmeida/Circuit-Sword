# Legacy DMG-CM3 usability fixes

These changes were applied to the original handheld on 2026-10-06. A confirms in
`raspi-config`, console text is larger, and EmulationStation's bottom help text
sits farther from the display edge. The device rebooted successfully and the
owner confirmed the improved readability.

The patches preserve changes to files supplied by RetroPie and the Pixel theme,
which are not otherwise tracked in this repository. The console-font default is
also updated in `settings/config-cs.txt`, which `install.sh` copies to the boot
partition. They do not constitute a modern OS image or a firmware update.

## Tested environment

| Component | Version |
| --- | --- |
| Handheld | Circuit Sword / Game Boy DMG-CM3, 640×480 LCD |
| OS | Raspbian 9 Stretch, kernel `4.14.30-v7+` |
| Circuit Sword on device | v1.3.3, `bde930e` |
| RetroPie-Setup | `fb02fd76` (2020-06-14) |
| EmulationStation | v2.7.5rp, built 2018-02-27 |
| Theme | Pixel v1.7 |

The full SD backup was made **before** these changes. Restoring that image restores
the original behavior; apply these patches afterward to recover the fixes.

A later [display-wide bottom-margin experiment](display-margin-investigation.md)
was rolled back because it caused flickering. The settings below remain the
current stable configuration; they do not reserve a global bottom margin.

## Changes and evidence

### A confirms in configuration menus

[Issue #5](https://github.com/jamesalmeida/Circuit-Sword/issues/5),
[`joy2key-enter.patch`](../patches/legacy-retropie/joy2key-enter.patch).

Physical A and B produce button IDs 0 and 1 in both Linux joystick events and SDL.
Their mappings were already correct. The problem was that `joy2key.py` sent LF
(`0x0a`) for Enter, whereas this version of `whiptail` expects CR (`0x0d`) in raw
terminal mode. B sent Space, which activated a focused dialog button.

Normalize LF to CR immediately before terminal injection in both copies:

- `/home/pi/RetroPie-Setup/scriptmodules/supplementary/runcommand/joy2key.py`
- `/opt/retropie/supplementary/runcommand/joy2key.py`

This happens after button mapping and the existing `menu_swap_ok_cancel_buttons`
logic. EmulationStation and RetroArch controller profiles were unchanged.

On-device inert-menu checks showed that CR confirms in both `whiptail` and
`dialog`, while LF confirms only in `dialog`. Both patched scripts compile under
the device's Python 3. The owner confirmed A opens the `raspi-config` About screen;
the patch was still present after reboot. Separate manual testing of every
RetroPie-Setup screen and game was not performed.

### Larger console text

[`console-font.patch`](../patches/legacy-retropie/console-font.patch) changes
`STARTUPEXEC` in `/boot/config-cs.txt` from the bundled `miniwi-8.psf.gz` font to
the installed `/usr/share/consolefonts/Lat15-TerminusBold16.psf.gz`.

The 4×8 font produced 160 columns × 60 rows. The replacement is 8×16, producing
80 columns × 30 rows at 640×480. This doubles each character's width and height
while retaining space for the configuration menus. The console reported 80×30
after reboot. No change to `/etc/default/console-setup` was needed because
Circuit Sword's startup font command overrides it.

### Bottom help text clears the display edge

[Issue #4](https://github.com/jamesalmeida/Circuit-Sword/issues/4),
[`pixel-help-position.patch`](../patches/legacy-retropie/pixel-help-position.patch).

In `/etc/emulationstation/themes/pixel/pixel.xml`, move the help row from
`0.012 0.960` to `0.012 0.925` in the system, basic and detailed views. At 480
pixels high, this raises it 16.8 pixels without changing its font size, the LCD
timings, or game rendering. Per-system theme files include this common file.

The original Pixel XML contains nonstandard comments accepted by
EmulationStation. Those comments are preserved. Element structure was checked
with comments excluded, and EmulationStation loaded after reboot.

## Apply to a restored legacy card

The original handheld already has these fixes. Use these steps on an unmodified
restore of the tested image, from a checkout of this fork on the target Pi.
Do not run the patch commands on the Mac. For other RetroPie/theme versions,
review the source differences first; the patches deliberately require matching
context. A RetroPie or theme update may replace the patched files.

First confirm the font is installed and dry-run **all** patches. The subshell
stops on any failure, including an already-applied patch. It backs up the four
affected files only after all dry runs succeed.

```sh
(
    set -eu
    repo_dir="$PWD"
    test -f /usr/share/consolefonts/Lat15-TerminusBold16.psf.gz
    for patch_file in "$repo_dir"/patches/legacy-retropie/*.patch; do
        sudo patch --dry-run --batch --forward --fuzz=0 -d / -p1 < "$patch_file"
    done

    backup_dir="/home/pi/circuit-sword-maintenance/usability-$(date +%Y%m%d-%H%M%S)"
    sudo mkdir -m 700 -p "$backup_dir"
    sudo tar -C / -czf "$backup_dir/original-files.tar.gz" \
        boot/config-cs.txt \
        etc/emulationstation/themes/pixel/pixel.xml \
        home/pi/RetroPie-Setup/scriptmodules/supplementary/runcommand/joy2key.py \
        opt/retropie/supplementary/runcommand/joy2key.py

    for patch_file in "$repo_dir"/patches/legacy-retropie/*.patch; do
        sudo patch --batch --forward --fuzz=0 -d / -p1 < "$patch_file"
    done
    printf 'Original files: %s/original-files.tar.gz\n' "$backup_dir"
)
```

Exit any running game or configuration menu, then reboot the handheld. Confirm:

1. EmulationStation's bottom legend is visible on the system carousel and game list.
2. `raspi-config` is readable and A opens **9 About raspi-config**.
3. A also confirms in RetroPie-Setup; navigation and game controls still behave
   as before.
4. `stty -F /dev/tty1 size` over SSH prints `30 80`.

## Roll back

For a new application using the commands above, restore the archive from the
printed backup directory, then reboot. Substitute its actual timestamp:

```sh
sudo tar -C / -xzf /home/pi/circuit-sword-maintenance/usability-TIMESTAMP/original-files.tar.gz
sudo reboot
```

The first application on the original handheld used individual file backups,
not a tar archive:

- `/home/pi/circuit-sword-maintenance/issue-5-20261006-142048/` contains the two
  original `joy2key.py` files, controller/settings snapshots, a SHA-256 manifest,
  and the exact Enter-character diff.
- `/home/pi/circuit-sword-maintenance/readability-20261006-143107/` contains the
  original boot config, Pixel theme, console-setup config, a SHA-256 manifest,
  and `console-font-before.psf` (the saved active font and Unicode mapping).

Each original file is stored below its backup directory with its original path
relative to `/`. Restore only the two `joy2key.py` files, `boot/config-cs.txt`, and
`etc/emulationstation/themes/pixel/pixel.xml` to undo these changes, then reboot.
The controller profiles and console-setup config were backed up but not changed.

## Remaining modernization work

The next work is [Python 3 compatibility (#1)](https://github.com/jamesalmeida/Circuit-Sword/issues/1),
then [display/HUD support (#2)](https://github.com/jamesalmeida/Circuit-Sword/issues/2),
then the [image builder (#3)](https://github.com/jamesalmeida/Circuit-Sword/issues/3).
Test modern OS images on a spare card after verifying it can boot a restored
backup. No modern OS migration has been applied to the working card.
