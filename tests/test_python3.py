"""Hardware-free regression tests; no test opens a real boot file or serial port."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import types
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]


def load_module(name, relative_path):
    spec = importlib.util.spec_from_file_location(name, str(ROOT / relative_path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


configure = load_module('cs_configure', 'cs-configure.py')
hdmi = load_module('reboot_to_hdmi', 'settings/reboot_to_hdmi.py')
tester = load_module('cs_tester', 'cs-tester/cs-tester.py')


class FakeSerial:
    """Each write must match the next transaction; reads deliver one byte."""
    def __init__(self, transactions):
        self.transactions = list(transactions)
        self.pending = b''
        self.writes = []
        self.closed = False

    def write(self, command):
        if not isinstance(command, bytes):
            raise TypeError('pyserial writes require bytes')
        if self.pending:
            raise AssertionError('Previous reply was not consumed')
        expected, reply = self.transactions.pop(0)
        if command != expected:
            raise AssertionError((expected, command))
        self.writes.append(command)
        self.pending = reply
        return len(command)

    def read(self, size=1):
        reply, self.pending = self.pending[:size], self.pending[size:]
        return reply

    def close(self):
        self.closed = True


class SerialTests(unittest.TestCase):
    def endpoint(self, transactions):
        endpoint = FakeSerial(transactions)
        patcher = mock.patch.object(configure, 'ser', endpoint)
        patcher.start()
        self.addCleanup(patcher.stop)
        return endpoint

    def test_one_byte_values_are_not_text_or_terminators(self):
        # '?' is ambiguous in a one-byte binary reply: retain the valid value 63.
        for value in (0, 63, 75, 79, 255):
            with self.subTest(value=value):
                self.endpoint([(b'e', bytes([value]))])
                self.assertEqual(configure.get_volume(), value)

    def test_little_endian_and_no_binary_terminator(self):
        for reply, expected in ((b'\x3f\x01', 319), (b'OK', 19279),
                                (b'\x00\x00', 0), (b'\xff\xff', 65535)):
            with self.subTest(reply=reply):
                self.endpoint([(b'c', reply)])
                self.assertEqual(configure.get_voltage(), expected)

    def test_status_and_joystick_bit_order(self):
        self.endpoint([(b's', b'\x55'), (b'j', b'\x2a')])
        status = configure.get_status()
        self.assertEqual([status[k] for k in ('s_mode', 's_wifi', 's_aud',
                         's_info', 's_avol', 's_dpad_joy', 's_dvol')],
                         list('1010101'))
        joystick = configure.get_joystick_config()
        self.assertEqual([joystick[k] for k in ('j_iscalib1', 'j_iscalib2',
                         'j_xinvert1', 'j_yinvert1', 'j_xinvert2', 'j_yinvert2')],
                         list('010101'))

    def test_two_byte_button_flags(self):
        self.endpoint([(b'B', b'\x10\x80')])
        buttons = configure.get_button_state()
        self.assertEqual({key for key, val in buttons.items() if val == '1'},
                         {'b_a', 'b_c2'})

    def test_adc_commands_and_backlight(self):
        self.endpoint([(b'u', b'\x01\x01'), (b'o', b'\x02\x02'),
                       (b'p', b'\x03\x03'), (b'y', b'\xff\x03'),
                       (b't', b'\x00\x02'), (b'q', b'\x64')])
        self.assertEqual(configure.get_joystick_adc(),
                         dict(joy1_x=257, joy1_y=514, joy2_x=771, joy2_y=1023))
        self.assertEqual(configure.get_avol_adc(), 512)
        self.assertEqual(configure.get_backlight(), 100)

    def test_all_mutations_require_and_consume_ok(self):
        endpoint = self.endpoint([(bytes([cmd]), b'OK') for cmd in b'dCz{}()[]J'])
        configure.toggle_dpad_joy()
        configure.toggle_avol()
        configure.toggle_dvol()
        configure.set_joystick_config(True, True, True, True, True, True)
        configure.calibrate_joystick()
        self.assertFalse(endpoint.transactions)
        self.assertEqual(endpoint.pending, b'')

    def test_unsupported_acknowledgement(self):
        endpoint = self.endpoint([(b'J', b'?')])
        with mock.patch.object(endpoint, 'read', wraps=endpoint.read) as read:
            with self.assertRaisesRegex(configure.SerialProtocolError, 'not supported'):
                configure.calibrate_joystick()
            self.assertEqual(read.call_count, 1)

    def test_malformed_acknowledgement_is_not_success(self):
        self.endpoint([(b'd', b'NO')])
        with self.assertRaisesRegex(configure.SerialProtocolError, 'expected OK'):
            configure.toggle_dpad_joy()

    def test_empty_and_partial_replies_timeout(self):
        for command, reply, length, ack in [('s', b'', 1, False),
                                           ('c', b'\x3f', 2, False),
                                           ('J', b'O', 2, True),
                                           ('J', b'', 2, True)]:
            with self.subTest(command=command, reply=reply):
                self.endpoint([(command.encode('ascii'), reply)])
                with self.assertRaises(TimeoutError):
                    configure.readSerial(command, length, ack)

    def test_write_failure_propagates(self):
        endpoint = self.endpoint([])
        with mock.patch.object(endpoint, 'write', side_effect=OSError('disconnected')):
            with self.assertRaises(OSError):
                configure.get_status()
        with mock.patch.object(endpoint, 'write', return_value=0):
            with self.assertRaisesRegex(configure.SerialProtocolError, 'Incomplete write'):
                configure.get_status()

    def test_cli_aborts_and_closes_after_protocol_failure(self):
        endpoint = FakeSerial([(b's', b'')])
        serial_module = types.SimpleNamespace(
            Serial=mock.Mock(return_value=endpoint), PARITY_NONE='N',
            STOPBITS_ONE=1, EIGHTBITS=8, SerialException=OSError)
        with mock.patch.dict(sys.modules, {'serial': serial_module}), \
                mock.patch.object(configure.subprocess, 'check_output', return_value='inactive'), \
                self.assertLogs(level='ERROR'):
            self.assertEqual(configure.main([]), 1)
        self.assertTrue(endpoint.closed)
        self.assertEqual(endpoint.writes, [b's'])
        self.assertIsNone(configure.ser)
        self.assertEqual(serial_module.Serial.call_args[1]['timeout'], 15)

    def test_running_hud_prevents_opening_serial(self):
        serial_module = types.SimpleNamespace(Serial=mock.Mock())
        with mock.patch.dict(sys.modules, {'serial': serial_module}), \
                mock.patch.object(configure.subprocess, 'check_output',
                                  return_value='Active: active (running)'), \
                self.assertLogs(level='ERROR'):
            self.assertEqual(configure.main([]), 1)
        serial_module.Serial.assert_not_called()


class HDMITests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / 'config.txt'
        self.original = (ROOT / 'settings/config.txt').read_text()
        self.path.write_text(self.original)
        self.quiet = contextlib.redirect_stdout(io.StringIO())
        self.quiet.__enter__()
        self.addCleanup(self.quiet.__exit__, None, None, None)

    def test_hdmi_then_boot_check_restores_exact_config(self):
        # Preserve custom display settings and disabled alternatives/comments.
        self.original = self.original.replace('overscan_left=0', 'overscan_left=2')
        self.path.write_text(self.original)
        switcher = hdmi.HDMI_Switcher(str(self.path))
        switcher.enable_hdmi()
        switcher.save_config_file()
        active = self.path.read_text()
        self.assertIn('# CS CONFIG STATE: REBOOTING_TO_HDMI\n', active)
        self.assertIn('\nhdmi_mode=4\n', active)
        self.assertIn('\n#hdmi_mode=16\n', active)
        self.assertIn('\n#dtoverlay=dpi18\n', active)
        restored = hdmi.HDMI_Switcher(str(self.path))
        restored.enable_check()
        restored.save_config_file()
        self.assertEqual(self.path.read_text(), self.original)

    def test_explicit_dpi_restores_config(self):
        switcher = hdmi.HDMI_Switcher(str(self.path))
        switcher.enable_hdmi()
        switcher.save_config_file()
        switcher = hdmi.HDMI_Switcher(str(self.path))
        switcher.enable_dpi()
        switcher.save_config_file()
        self.assertEqual(self.path.read_text(), self.original)

    def test_idle_check_does_not_write(self):
        switcher = hdmi.HDMI_Switcher(str(self.path))
        switcher.enable_check()
        with mock.patch('builtins.open', side_effect=AssertionError('must not write')):
            switcher.save_config_file()

    def test_missing_or_duplicate_markers_rejected(self):
        for broken in (self.original.replace('# CS END DPI SETTINGS', ''),
                       self.original + '\n# CS END HDMI SETTINGS\n'):
            self.path.write_text(broken)
            with self.assertRaises(AssertionError):
                hdmi.HDMI_Switcher(str(self.path))
            self.assertEqual(self.path.read_text(), broken)

    def test_unknown_state_check_rejected_without_writing(self):
        broken = self.original.replace('STATE: IDLE', 'STATE: UNKNOWN')
        self.path.write_text(broken)
        switcher = hdmi.HDMI_Switcher(str(self.path))
        with self.assertRaisesRegex(Exception, 'Unknown state'):
            switcher.enable_check()
        self.assertEqual(self.path.read_text(), broken)

    def test_cli_dryrun_never_saves_or_reboots(self):
        args = ['reboot_to_hdmi.py', '--config', str(self.path), '--hdmi',
                '--dryrun', '--reboot']
        with mock.patch.object(sys, 'argv', args), mock.patch('os.system') as system:
            runpy.run_path(str(ROOT / 'settings/reboot_to_hdmi.py'), run_name='__main__')
        system.assert_not_called()
        self.assertEqual(self.path.read_text(), self.original)


class TesterTests(unittest.TestCase):
    def test_lsusb_output_is_decoded_before_device_detection(self):
        # Exercise a real text-mode subprocess, with a fixture executable.
        actual_check_output = subprocess.check_output
        with tempfile.TemporaryDirectory() as directory:
            lsusb = Path(directory) / 'lsusb'
            lsusb.write_text('#!/bin/sh\nprintf "%s\\n" "Atmel Corp." '
                             '"C-Media Electronics" "Terminus Technology Inc"\n')
            lsusb.chmod(0o755)
            def fixture_command(command, **kwargs):
                self.assertEqual(command, ['/usr/bin/lsusb'])
                return actual_check_output([str(lsusb)], **kwargs)
            output = io.StringIO()
            with mock.patch.object(tester.subprocess, 'check_output', side_effect=fixture_command), \
                    mock.patch.object(tester.os.path, 'exists', return_value=True), \
                    contextlib.redirect_stdout(output):
                tester.testUSB()
            self.assertEqual(output.getvalue().count('[ OK ]'), 4)
            self.assertNotIn('[FAIL]', output.getvalue())

    def test_missing_usb_devices_report_failure(self):
        output = io.StringIO()
        with mock.patch.object(tester.subprocess, 'check_output', return_value=''), \
                mock.patch.object(tester.os.path, 'exists', return_value=False), \
                contextlib.redirect_stdout(output):
            tester.testUSB()
        self.assertEqual(output.getvalue().count('[FAIL]'), 4)

    def test_gpio_is_cleaned_up_on_interrupt(self):
        gpio = mock.Mock()
        rpi = types.ModuleType('RPi')
        rpi.GPIO = gpio
        with mock.patch.dict(sys.modules, {'RPi': rpi, 'RPi.GPIO': gpio}), \
                mock.patch.object(tester, 'testUSB', side_effect=KeyboardInterrupt), \
                contextlib.redirect_stdout(io.StringIO()):
            tester.main()
        gpio.setup.assert_called_once_with(37, gpio.IN)
        gpio.cleanup.assert_called_once_with()


if __name__ == '__main__':
    unittest.main()
