# Python 3 compatibility

Implementation for [issue #1](https://github.com/jamesalmeida/Circuit-Sword/issues/1).
The development tests pass; the port has **not been installed on the handheld**.
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

## Remaining device validation

Keep issue #1 open until the CM3 spare card checks pass. Restore and boot the
backup first, and reapply the committed usability patches. Preserve originals
of any replaced files and record a distinct test build identifier before copying
the port onto that card.

Check the tester's USB/GPIO/display behavior and the configuration menu with
`cs-hud` stopped so only one program owns the serial port. Check readings first,
then verify intended toggles and restore their original values. Restart the HUD
after exiting. Test the HDMI transition and automatic return to DPI on that
card, retaining the custom display settings. Do not flash the MCU for this port.

Rollback is to restore the original scripts/callers or reimage the spare card.
The working card and its installed Python 2 scripts have not been changed.
