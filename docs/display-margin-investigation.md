# Bottom display margin investigation

[Issue #6](https://github.com/jamesalmeida/Circuit-Sword/issues/6) tracks terminal
text hidden by the DMG-CM3 glass bezel. The earlier Pixel theme adjustment fixes
the help labels, but does not reserve space for other software.

## Current state: stable configuration restored

On 2026-10-06, a display-wide margin test cleared the last terminal line but
caused whole-screen flickering. It was rolled back immediately. After the rollback,
the owner reported that the display looked perfect. SSH inspection confirmed:

- LCD framebuffer: 640×480; `framebuffer_height=480`.
- `overscan_bottom=0`, with the existing `overscan_scale=1` retained.
- Console font: 8×16 Terminus Bold; terminal dimensions 80 columns × 30 rows.
- Pixel help positions: `0.012 0.925` in system, basic and detailed views.

These are the settings preserved by commit `453c644` and the
[legacy handheld fixes](legacy-handheld-fixes.md). No display-wide bottom margin
is currently enabled. The terminal clipping issue remains open; the successful
rollback is not evidence that a global margin has been fixed.

## Rejected experiment

Only these settings were changed for the test:

| File / setting | Before | Test |
| --- | --- | --- |
| `/boot/config.txt`: `overscan_bottom` | `0` | `16` |
| `/boot/config.txt`: `framebuffer_height` | `480` | `464` |
| Pixel help positions, all three views | `0.012 0.925` | `0.012 0.960` |

The theme offset was removed during the test to avoid applying the same margin
twice. LCD timings, output format and `display_rotate=2` were unchanged.

After reboot, `fbset` reported 640×464, the terminal reported 80×29, and
`vcgencmd dispmanx_list` showed graphics layers placed in a 640×464 destination.
The owner confirmed the bottom line was visible but reported the entire screen
flickering. Do not deploy this combination as a fix.

Both changed files were restored from:

```text
/home/pi/circuit-sword-maintenance/issue-6-20261006-150859/
```

This directory contains `boot/config.txt`,
`etc/emulationstation/themes/pixel/pixel.xml`, and a SHA-256 manifest. A subsequent
reboot restored the stable values listed above.

## What remains unknown

The flicker's cause was not isolated. The experiment changed both overscan and
framebuffer height at once. The legacy graphics stack also runs the Circuit Sword
HUD and DPI cloner, but neither has been established as the cause. Any later
investigation should isolate one variable at a time and verify physical display
stability as well as the reported dimensions. No further experiment is active.

The [Raspberry Pi legacy display documentation](https://www.raspberrypi.com/documentation/computers/legacy_config_txt.html#generic-display-options)
describes the overscan, framebuffer and layer-scaling controls. This device's
observed flicker takes precedence over treating those options as a verified fix.
