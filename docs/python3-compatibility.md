# Python 3 compatibility

Implementation for [issue #1](https://github.com/jamesalmeida/Circuit-Sword/issues/1).
The development tests pass. The port is installed on the **spare restored card**
(see [spare-card validation](#spare-card-validation)); the original working card
is unchanged.
This is one prerequisite for a supported OS image, not a validated OS upgrade.

## Changes

- Boot, HDMI, tester and Arduino-reset callers explicitly use Python 3.
- The HDMI helper uses Python 3 dictionary iteration. Its existing configuration
  format and one-time HDMI/DPI transition are preserved.
- The tester uses Python 3 printing and decoded USB command output. Importing
  the tester does not initialize GPIO or launch diagnostics; running it still
  does. GPIO is cleaned up on exit.
- `cs-configure.py` opens the controller only from its command-line entry point.
  Commands are ASCII bytes; binary replies remain bytes and decode little-endian.
  Two-byte button flags now decode instead of raising “Not implemented”.
- Toggle/calibration commands require `OK`; `?`, malformed acknowledgements,
  missing replies and incomplete replies fail the command. Communication errors
  stop the tool and close the port rather than continuing with uncertain data.
  The read timeout remains 15 seconds to accommodate joystick calibration.
- The icon converter decodes subprocess output as text. The standalone GPIO
  utilities also use Python 3 syntax/interpreters.

The wire protocol is unchanged. Firmware queries return fixed-size binary data,
not terminated strings. A data byte can be `?` (63), and two data bytes can spell
`OK`. A one-byte `?` response to a binary query cannot be distinguished from a
valid value of 63 with this protocol; only acknowledgement commands can reject
it unambiguously. No Arduino firmware was changed or flashed.

Protocol references: `processSerial()` in
[`CS_FIRMWARE.ino`](../kite-arduino/CS_FIRMWARE/CS_FIRMWARE.ino) and
`serialWrite2()` in [`FUNCTIONS.ino`](../kite-arduino/CS_FIRMWARE/FUNCTIONS.ino).
The [pySerial API](https://pyserial.readthedocs.io/en/latest/pyserial_api.html)
specifies byte writes/reads and empty or partial reads on timeout.

## Dependencies and installation scope

The installer now checks for `python3`, `python3-serial` (version 3.0 or later)
and `python3-rpi.gpio` before changing boot files. On a running Pi it installs
missing packages through apt. For an offline image it checks the target's dpkg
database and fails with instructions if packages are missing; it does not install
them on the build host. Prepare those dependencies inside the target OS first.
The old bundled Python 2 serial package is no longer used.

Use a full checkout: `install.sh` calls the adjacent
`settings/install-python3-deps.sh`. The legacy installer still makes unrelated
hardware/system changes and the image builder still has the blockers tracked in
[issue #3](https://github.com/jamesalmeida/Circuit-Sword/issues/3). Do not run the
whole installer on the working card merely to test this Python port.

## Development validation

From the repository root:

```sh
python3 -m venv /tmp/circuit-sword-python3-venv
/tmp/circuit-sword-python3-venv/bin/python -m pip install pyserial==3.5
/tmp/circuit-sword-python3-venv/bin/python -m unittest discover -s tests -v
```

Tests use temporary copies of the boot configuration, fake GPIO/package tools,
and fake serial endpoints. Two integration tests use real pySerial with a local
pseudo-terminal acting as the controller; these are skipped if pySerial or POSIX
is unavailable. No test reads or writes the real boot configuration, opens a
physical serial device, invokes apt, or reboots.

On 2026-10-06, all **29 tests passed without skips** with pySerial 3.5:

| Environment | Python |
| --- | --- |
| Development Mac | 3.13.2 |
| Linux ARM64, `python:3.13-slim-bookworm` container | 3.13.16 |
| Linux ARM64, `python:3.5-slim-buster` container | 3.5.10 |

Python 3.5 is tested only for compatibility with the old userspace; this does not
make that interpreter or OS supported. All repository Python files and the
inline firmware-reset helper compiled under Python 3. Changed shell scripts
passed `bash -n`. The shell flasher and GPIO prototypes were not run on hardware.

## Spare-card validation

On 2026-10-06 the port was installed on a 128 GB spare card restored from the
pre-fix backup (Raspbian 9 Stretch, Python 3.5.3, Circuit Sword `bde930e`), after
the [legacy usability patches](legacy-handheld-fixes.md) were reapplied.

### Dependencies

Stretch was removed from `raspbian.raspberrypi.org`, so `apt-get update` fails
with the stock sources. Install from the legacy archive with a temporary source
list, leaving `/etc/apt` unchanged:

```sh
printf 'deb http://legacy.raspbian.org/raspbian/ stretch main contrib non-free rpi\ndeb http://archive.raspberrypi.org/debian/ stretch main ui\n' > /tmp/stretch-legacy.list
OPTS="-o Dir::Etc::SourceList=/tmp/stretch-legacy.list -o Dir::Etc::SourceParts=-"
sudo apt-get $OPTS update
sudo apt-get $OPTS install -y --no-install-recommends python3-serial python3-rpi.gpio
```

This installed `python3-serial` 3.2.1-1 and `python3-rpi.gpio` 0.6.5~stretch-1.
The Python 2 packages remain installed.

### Installed files

All six repository files matched upstream `74398b1` byte-for-byte before
replacement. The ported versions were copied over:

- `/home/pi/Circuit-Sword/{cs-configure.py,cs-tester/cs-tester.py,flash-arduino.sh}`
- `/home/pi/Circuit-Sword/settings/{reboot_to_hdmi.py,reboot_to_hdmi.sh,autostart.sh}`
- installed caller copies `/opt/retropie/configs/all/autostart.sh` and
  `/home/pi/RetroPie/retropiemenu/reboot_to_hdmi.sh`

Originals of all eight are in
`/home/pi/circuit-sword-maintenance/python3-20261006-180025/original-files.tar.gz`.

### Results

| Check | Result |
| --- | --- |
| Python files compile under 3.5.3; shell callers pass `bash -n` | Pass |
| `reboot_to_hdmi.py --check` (boot path) | Pass: state IDLE, config unchanged |
| `cs-configure.py` with `cs-hud` stopped, read-only, quit with `X` | Pass: all queries answered; Wi-Fi 1, backlight 100%, volume 90%, digital rocker 1, joysticks disabled (no sticks on DMG) |
| `cs-hud` restarted afterward | Active |
| `cs-tester.py`, two cycles, stopped with SIGINT | Pass: Arduino, audio, hub, joystick OK; SHDN ON; LCD pattern shown; clean exit |
| HDMI switch and return to DPI | Pending |

No toggles or calibrations were sent, and the MCU was not flashed.

### Roll back

```sh
sudo tar -C / -xzf /home/pi/circuit-sword-maintenance/python3-20261006-180025/original-files.tar.gz
```

The added apt packages are harmless to the Python 2 scripts and can stay.

## Remaining device validation

Keep issue #1 open until these pass on the spare card:

- **HDMI:** run *Reboot to HDMI* from the RetroPie menu, confirm HDMI output,
  then confirm the next boot returns to the LCD with the 2-pixel side margins
  intact in `/boot/config.txt`.
- **Toggles (optional):** in `cs-configure.py`, flip one setting such as the
  digital volume rocker, confirm it changes, then flip it back.

Do not flash the MCU for this port. The original working card and its Python 2
scripts have not been changed.
