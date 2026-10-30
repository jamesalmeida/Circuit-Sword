# Circuit Sword Software
Power management and safe shutdown software for the Circuit Sword.

This fork preserves the verified DMG-CM3 usability fixes and tracks work toward a
supported OS. See [legacy handheld fixes](docs/legacy-handheld-fixes.md) for the
patches, tested versions, installation and rollback instructions. The
[Python 3 port](docs/python3-compatibility.md) passes development tests and awaits
spare-card hardware validation. A modern OS image is not yet available.

## Display

This fork was built and tested on a Circuit Sword fitted with the upgraded
640×480 LCD. It has not been tested on the original 320×240 display. If you
have the original display, you will probably need to change the display
settings before it works. This should only be a config change: replace the
640×480 DPI block in [`bookworm/config.txt`](bookworm/config.txt)
(`framebuffer_width`, `framebuffer_height`, `dpi_output_format` and
`hdmi_timings`) with the 320×240 values in
[`settings/config.txt`](settings/config.txt). The 180° panel flip in
[`bookworm/lcd-flip.py`](bookworm/lcd-flip.py) and the `LCD` setting in
[`kite-arduino/CS_FIRMWARE/config.h`](kite-arduino/CS_FIRMWARE/config.h) also
target the 640×480 panel.

## [Download](https://github.com/kiteretro/Circuit-Sword/releases)
