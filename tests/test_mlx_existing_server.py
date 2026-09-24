"""A model-list response must not authorize an unknown Bonsai 2 runtime."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]

class ExistingServer(unittest.TestCase):
    def probe(self, family):
        return subprocess.run(
            ['sh', '-c', '. "$1"; reject_unverified_bonsai2_mlx_server 8081; echo REUSED',
             'test', str(ROOT / 'scripts/common.sh')],
            env={**os.environ, 'BONSAI_FAMILY': family, 'BONSAI_CTX': '4096'},
            capture_output=True, text=True,
        )

    def test_bonsai2_rejects_unknown_loader(self):
        result = self.probe('bonsai2')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('cannot be verified', result.stdout + result.stderr)
        self.assertNotIn('REUSED', result.stdout)

    def test_older_families_keep_reuse(self):
        for family in ('ternary', 'bonsai'):
            with self.subTest(family=family):
                result = self.probe(family)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('REUSED', result.stdout)

if __name__ == '__main__':
    unittest.main()
