"""An existing importable venv must not bypass the native-loader version guard."""
import runpy
import unittest
from importlib.metadata import PackageNotFoundError
from pathlib import Path
from unittest.mock import patch

CHECK = Path(__file__).resolve().parents[1] / 'scripts/check_mlx_vlm.py'
PINS = {'mlx': '0.32.3', 'mlx-vlm': '0.7.8', 'mlx-lm': '0.32.0', 'transformers': '5.19.0'}

class NativeMLXVersions(unittest.TestCase):
    def test_tested_versions_pass(self):
        with patch('importlib.metadata.version', side_effect=PINS.__getitem__):
            runpy.run_path(str(CHECK))

    def test_old_importable_environment_is_rejected(self):
        for package, stale in [('mlx-vlm', '0.6.3'), ('mlx-lm', '0.31.2')]:
            with self.subTest(package=package):
                old = dict(PINS, **{package: stale})
                with patch('importlib.metadata.version', side_effect=old.__getitem__):
                    with self.assertRaisesRegex(SystemExit, 'Run ./setup.sh'):
                        runpy.run_path(str(CHECK))

    def test_missing_dependency_is_rejected(self):
        with patch('importlib.metadata.version', side_effect=PackageNotFoundError):
            with self.assertRaisesRegex(SystemExit, 'missing'):
                runpy.run_path(str(CHECK))

if __name__ == '__main__':
    unittest.main()
