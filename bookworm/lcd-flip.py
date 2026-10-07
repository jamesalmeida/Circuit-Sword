#!/usr/bin/env python3
"""Rotate the DMG-CM3 640x480 LCD 180 degrees in the panel itself.

The Circuit Sword MCU forwards 'L<hex>!' to the LCD controller over SPI.
Writing 0x09 to the panel's address-mode register (0x36) flips both scan
directions (bit 0) and keeps BGR order (bit 3), so every layer (console, DispmanX, KMS) is upright without any
software rotation. The register is volatile: the MCU re-initialises the
panel on power-up, so this runs at every boot.
"""
import sys
import time

import serial

PORT = "/dev/ttyACM0"
COMMAND = b"L3609!"

for attempt in range(10):
    try:
        with serial.Serial(PORT, 115200, timeout=2) as port:
            time.sleep(0.2)
            port.reset_input_buffer()
            port.write(COMMAND)
            reply = port.read(2)
        if reply == b"OK":
            print("LCD flipped 180 degrees")
            sys.exit(0)
        print("unexpected reply %r" % reply, file=sys.stderr)
    except (OSError, serial.SerialException) as err:
        print("attempt %d: %s" % (attempt + 1, err), file=sys.stderr)
    time.sleep(1)
sys.exit(1)
