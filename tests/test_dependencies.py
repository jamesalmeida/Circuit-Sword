"""Installer dependency policy tested with fake package tools, never real apt."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DependencyTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.directory_path = Path(self.directory.name)
        self.log = self.directory_path / 'calls'
        self.ready = self.directory_path / 'ready'
        scripts = {
            'dpkg-query': '''#!/bin/bash
printf '%s\\n' "dpkg-query $*" >> "$CALL_LOG"
if [[ "$*" == *"$MISSING_PACKAGE"* && ! -f "$READY" ]]; then exit 1; fi
if [[ "$*" == *'${Version}'* ]]; then
  printf '%s' "$SERIAL_VERSION"
else
  printf '%s' 'install ok installed'
fi
''',
            'dpkg': '''#!/bin/bash
[[ "$2" != 2.* ]]
''',
            'apt-get': '''#!/bin/bash
printf '%s\\n' "apt-get $*" >> "$CALL_LOG"
if [[ "$APT_FAIL" == 1 ]]; then exit 42; fi
if [[ "$1" == install ]]; then touch "$READY"; fi
''',
        }
        for name, script in scripts.items():
            path = self.directory_path / name
            path.write_text(script)
            path.chmod(0o755)
        self.environment = dict(os.environ, PATH=str(self.directory_path) + os.pathsep + os.environ['PATH'],
                                CALL_LOG=str(self.log), READY=str(self.ready),
                                MISSING_PACKAGE='not-a-package', SERIAL_VERSION='3.5-1', APT_FAIL='0')

    def run_helper(self, target, **environment):
        self.environment.update(environment)
        return subprocess.run(['bash', str(ROOT / 'settings/install-python3-deps.sh'), target],
                              env=self.environment, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, universal_newlines=True)

    def test_complete_image_checks_target_database_without_apt(self):
        target = str(self.directory_path / 'target image')
        result = self.run_helper(target)
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.log.read_text()
        self.assertIn('--admindir=' + target + '/var/lib/dpkg', calls)
        self.assertNotIn('apt-get', calls)

    def test_missing_target_package_does_not_install_on_host(self):
        result = self.run_helper(str(self.directory_path / 'target'), MISSING_PACKAGE='python3-serial')
        self.assertEqual(result.returncode, 1)
        self.assertIn('inside the target OS', result.stderr)
        self.assertNotIn('apt-get', self.log.read_text())

    def test_python2_era_serial_version_rejected(self):
        result = self.run_helper(str(self.directory_path / 'target'), SERIAL_VERSION='2.6-1')
        self.assertEqual(result.returncode, 1)
        self.assertNotIn('apt-get', self.log.read_text())

    def test_live_missing_dependencies_installed_and_rechecked(self):
        result = self.run_helper('/', MISSING_PACKAGE='python3-serial')
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.log.read_text()
        self.assertIn('apt-get update\napt-get install -y python3 python3-serial python3-rpi.gpio', calls)
        self.assertTrue(self.ready.exists())
        self.assertTrue(calls.endswith('--showformat=${Version} python3-serial\n'))

    def test_live_existing_dependencies_skip_apt(self):
        self.assertEqual(self.run_helper('/').returncode, 0)
        self.assertNotIn('apt-get', self.log.read_text())

    def test_apt_update_failure_stops_installation(self):
        result = self.run_helper('/', MISSING_PACKAGE='python3', APT_FAIL='1')
        self.assertEqual(result.returncode, 42)
        self.assertNotIn('apt-get install', self.log.read_text())
        self.assertFalse(self.ready.exists())


if __name__ == '__main__':
    unittest.main()
