"""Exercise MLX setup with fake tools; never download or install dependencies."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MLXSetupPaths(unittest.TestCase):
    def run_setup(self, family='bonsai2', existing=False, current=False,
                  metal=False, skip=False, vlm=True):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            tools = root / 'tools'
            tools.mkdir()
            log = root / 'calls'

            def executable(path, contents):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('#!/bin/sh\n' + contents)
                path.chmod(0o755)

            executable(tools / 'xcrun', 'echo xcrun >> "$CALLS"\n[ "$METAL_OK" = 1 ]\n')
            executable(tools / 'git', 'echo git >> "$CALLS"\n')
            executable(tools / 'uv', '''echo "uv $*" >> "$CALLS"
if [ "$1" = venv ]; then
    mkdir -p "$2/bin"
    cp "$FAKE_PY" "$2/bin/python"
fi
case "$*" in
    *requirements-mlx-vlm.txt*) touch "$TEST_ROOT/installed" ;;
esac
''')
            fake = root / 'fake-python'
            executable(fake, '''echo "python $*" >> "$CALLS"
case "$*" in
    *check_mlx_vlm.py*) [ "$CURRENT" = 1 ] || [ -f "$TEST_ROOT/installed" ] ;;
    *) exit 0 ;;
esac
''')
            executable(root / '.venv/bin/python', 'exit 1\n')
            if existing:
                executable(root / '.venv-vlm/bin/python', fake.read_text())
            source = (ROOT / 'setup.sh').read_text()
            start = source.index('if [ "$OS" = "Darwin" ] && ! bonsai_should_skip_mlx; then',
                                 source.index('#  8. MLX'))
            end = source.index('# ── Open WebUI:', start)
            script = '''set -e
info() { echo "$*"; }
warn() { echo "$*"; }
err() { echo "$*"; }
step() { echo "$*"; }
bonsai_should_skip_mlx() { [ "$SKIP_MLX" = 1 ]; }
''' + source[start:end]
            env = dict(os.environ, PATH=f'{tools}:/usr/bin:/bin', CALLS=str(log),
                       FAKE_PY=str(fake), TEST_ROOT=str(root), SCRIPT_DIR=str(root),
                       VENV_PY=str(root / '.venv/bin/python'), PYTHON_VERSION='3.11',
                       BONSAI_FAMILY=family, BONSAI_MLX_VLM=str(int(vlm)),
                       OS='Darwin', METAL_OK=str(int(metal)), CURRENT=str(int(current)),
                       SKIP_MLX=str(int(skip)))
            result = subprocess.run(['sh', '-c', script], cwd=root, env=env,
                                    capture_output=True, text=True)
            return result, log.read_text() if log.exists() else ''

    def test_bonsai2_fresh_install_without_metal(self):
        result, calls = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('requirements-mlx-vlm.txt', calls)
        self.assertIn('uv venv', calls)
        self.assertNotIn('xcrun', calls)
        self.assertNotIn('git', calls)
        self.assertNotIn('-e mlx/', calls)

    def test_bonsai2_updates_stale_environment_without_metal(self):
        result, calls = self.run_setup(existing=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('requirements-mlx-vlm.txt', calls)
        self.assertNotIn('uv venv', calls)
        self.assertNotIn('xcrun', calls)

    def test_current_environment_skips_install(self):
        result, calls = self.run_setup(existing=True, current=True)
        self.assertEqual(result.returncode, 0)
        self.assertNotIn('uv ', calls)

    def test_legacy_families_still_require_metal(self):
        for family in ['bonsai', 'ternary', 'all']:
            with self.subTest(family=family):
                result, calls = self.run_setup(family=family)
                self.assertEqual(result.returncode, 1)
                self.assertIn('legacy MLX fork build', result.stdout)
                self.assertIn('xcrun', calls)

    def test_all_installs_both_runtimes_with_metal(self):
        result, calls = self.run_setup(family='all', metal=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('-e mlx/', calls)
        self.assertIn('requirements-mlx-vlm.txt', calls)

    def test_skip_flags(self):
        for options in [{'skip': True}, {'vlm': False}]:
            with self.subTest(options=options):
                result, calls = self.run_setup(**options)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(calls, '')


if __name__ == '__main__':
    unittest.main()
