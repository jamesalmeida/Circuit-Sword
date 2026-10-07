"""Exercise real pyserial against a fake controller on a local pseudo-terminal."""
import os
import select
import threading
import unittest
from unittest import mock

from test_python3 import configure

try:
    import serial
except ImportError:
    serial = None


@unittest.skipIf(serial is None or os.name != 'posix', 'requires pyserial and POSIX')
class SerialPTYTests(unittest.TestCase):
    def setUp(self):
        self.master, self.slave = os.openpty()
        self.addCleanup(os.close, self.master)
        self.addCleanup(os.close, self.slave)
        self.port = serial.Serial(os.ttyname(self.slave), 115200,
                                  timeout=0.2, write_timeout=0.2)
        self.addCleanup(self.port.close)
        patcher = mock.patch.object(configure, 'ser', self.port)
        patcher.start()
        self.addCleanup(patcher.stop)

    def controller(self, command, reply):
        received = []

        def exchange():
            if select.select([self.master], [], [], 2)[0]:
                received.append(os.read(self.master, len(command)))
                if reply:
                    os.write(self.master, reply)

        thread = threading.Thread(target=exchange)
        thread.start()
        return thread, received

    def test_binary_reply_and_acknowledgement(self):
        for command, reply, action, expected in (
                (b'c', b'\x3f\x01', configure.get_voltage, 319),
                (b'J', b'OK', configure.calibrate_joystick, None)):
            thread, received = self.controller(command, reply)
            try:
                self.assertEqual(action(), expected)
            finally:
                thread.join(3)
            self.assertFalse(thread.is_alive())
            self.assertEqual(received, [command])

    def test_partial_reply_times_out(self):
        thread, received = self.controller(b'c', b'\x3f')
        try:
            with self.assertRaises(TimeoutError):
                configure.get_voltage()
        finally:
            thread.join(3)
        self.assertFalse(thread.is_alive())
        self.assertEqual(received, [b'c'])


if __name__ == '__main__':
    unittest.main()
