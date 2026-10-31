"""An existing importable venv must not bypass the native-loader version guard."""
import runpy
import unittest
from importlib.metadata import PackageNotFoundError
from pathlib import Path
from unittest.mock import patch

CHECK = Path(__file__).resolve().parents[1] / 'scripts/check_mlx_vlm.py'
PINS = {'mlx': '0.32.3', 'mlx-vlm': '0.7.8', 'mlx-lm': '0.32.0', 'transformers': '5.19.0'}
# certifi is a security floor (CA bundle freshness), not a pin: newer bundles must pass.
CERTIFI_FLOOR = '2026.10.23'


def run_check(versions):
    with patch('importlib.metadata.version', side_effect=versions.__getitem__):
        runpy.run_path(str(CHECK))


class NativeMLXVersions(unittest.TestCase):
    def test_tested_versions_pass(self):
        run_check(dict(PINS, certifi=CERTIFI_FLOOR))

    def test_newer_certifi_passes(self):
        run_check(dict(PINS, certifi='2027.1.1'))

    def test_old_importable_environment_is_rejected(self):
        for package, stale in [('mlx-vlm', '0.6.3'), ('mlx-lm', '0.31.2'), ('certifi', '2026.9.1')]:
            with self.subTest(package=package):
                versions = dict(PINS, certifi=CERTIFI_FLOOR)
                versions[package] = stale
                with self.assertRaisesRegex(SystemExit, 'Run ./setup.sh'):
                    run_check(versions)

    def test_missing_dependency_is_rejected(self):
        with patch('importlib.metadata.version', side_effect=PackageNotFoundError):
            with self.assertRaisesRegex(SystemExit, 'missing'):
                runpy.run_path(str(CHECK))

    def test_unsupported_requirement_is_reported(self):
        with patch('pathlib.Path.read_text', return_value='mlx~=0.32.3\n'), \
                patch('importlib.metadata.version', side_effect=PackageNotFoundError):
            with self.assertRaisesRegex(SystemExit, 'unsupported requirement'):
                runpy.run_path(str(CHECK))


if __name__ == '__main__':
    unittest.main()
