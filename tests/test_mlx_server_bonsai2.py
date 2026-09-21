import importlib.util
import tempfile
import threading
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "mlx_server_bonsai2.py"
SPEC = importlib.util.spec_from_file_location("mlx_server_bonsai2", MODULE_PATH)
mlx_server_bonsai2 = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mlx_server_bonsai2)

try:
    import mlx.core as mx

    HAS_MLX = True
except ImportError:
    HAS_MLX = False

# Per-thread default GPU streams arrived in mlx 0.32 (the version the Bonsai 2 pack pins).
# Earlier releases evaluate a lazy array from any thread, so the control test that
# reproduces the bug has nothing to reproduce there and is skipped.
MLX_HAS_THREAD_LOCAL_STREAMS = HAS_MLX and tuple(
    int(part) for part in mx.__version__.split(".")[:2]
) >= (0, 32)


class ReloadFlagTests(unittest.TestCase):
    def test_bare_reload_is_caught(self):
        self.assertEqual(mlx_server_bonsai2.reload_flag(["--reload"]), "--reload")

    def test_abbreviated_reload_is_caught(self):
        self.assertEqual(mlx_server_bonsai2.reload_flag(["--relo"]), "--relo")

    def test_reload_with_value_is_caught(self):
        self.assertEqual(
            mlx_server_bonsai2.reload_flag(["--reload=1"]), "--reload=1"
        )

    def test_unrelated_flags_pass(self):
        self.assertIsNone(mlx_server_bonsai2.reload_flag(["--port", "8082"]))

    def test_empty_passthrough_passes(self):
        self.assertIsNone(mlx_server_bonsai2.reload_flag([]))


class ResolveModelIdTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.pack = Path(self._tmp.name) / "pack"
        self.pack.mkdir()

    def test_nonexistent_name_aliases_to_pack(self):
        for requested in ("bonsai2", "gpt-4o", "", None):
            with self.subTest(requested=requested):
                self.assertEqual(
                    mlx_server_bonsai2.resolve_model_id(requested, self.pack),
                    str(self.pack),
                )

    def test_existing_directory_is_left_unchanged(self):
        other_dir = Path(self._tmp.name) / "some-other-model"
        other_dir.mkdir()
        self.assertEqual(
            mlx_server_bonsai2.resolve_model_id(str(other_dir), self.pack),
            str(other_dir),
        )

    def test_pack_path_itself_is_unchanged(self):
        self.assertEqual(
            mlx_server_bonsai2.resolve_model_id(str(self.pack), self.pack),
            str(self.pack),
        )


@unittest.skipUnless(HAS_MLX, "requires mlx.core")
class EvalArraysTests(unittest.TestCase):
    def test_nested_arrays_are_evaluated_and_readable_cross_thread(self):
        # mlx 0.32 exposes no public "is this array evaluated" predicate, so the
        # real test is the one below: read every array from a different thread
        # than the one that built it, which only works once it has been eval'd.
        lazy_a = mx.ones((2, 2)) + 1
        lazy_b = mx.ones((2, 2)) + 2
        lazy_c = mx.ones((2, 2)) + 3
        raw_inputs = {"a": lazy_a, "b": [lazy_b, {"c": lazy_c}], "d": "str"}

        result = mlx_server_bonsai2.eval_arrays(raw_inputs)
        self.assertIs(result, raw_inputs)

        outcome = {}

        def read_from_other_thread():
            try:
                outcome["values"] = [arr.tolist() for arr in (lazy_a, lazy_b, lazy_c)]
            except Exception as exc:  # noqa: BLE001 - capturing for the assertion below
                outcome["error"] = exc

        t = threading.Thread(target=read_from_other_thread)
        t.start()
        t.join()

        self.assertNotIn("error", outcome)
        self.assertEqual(
            outcome["values"],
            [
                [[2.0, 2.0], [2.0, 2.0]],
                [[3.0, 3.0], [3.0, 3.0]],
                [[4.0, 4.0], [4.0, 4.0]],
            ],
        )

    @unittest.skipUnless(MLX_HAS_THREAD_LOCAL_STREAMS, "cross-thread stream error needs mlx >= 0.32")
    def test_control_without_eval_arrays_cross_thread_read_raises(self):
        # Control: prove the test actually detects the bug it is meant to catch.
        # A lazy array built on this thread and read from a different thread, with
        # no eval_arrays() in between, must fail with mlx's cross-thread stream error.
        lazy = mx.ones((2, 2)) + 1
        outcome = {}

        def read_from_other_thread():
            try:
                lazy.tolist()
            except Exception as exc:  # noqa: BLE001 - capturing for the assertion below
                outcome["error"] = exc

        t = threading.Thread(target=read_from_other_thread)
        t.start()
        t.join()

        self.assertIn("error", outcome)
        self.assertIsInstance(outcome["error"], RuntimeError)
        self.assertRegex(str(outcome["error"]), "no Stream")

    def test_eval_arrays_makes_cross_thread_read_safe(self):
        lazy = mx.ones((2, 2)) + 1
        raw_inputs = {"a": lazy}
        mlx_server_bonsai2.eval_arrays(raw_inputs)

        outcome = {}

        def read_from_other_thread():
            try:
                outcome["value"] = lazy.tolist()
            except Exception as exc:  # noqa: BLE001 - capturing for the assertion below
                outcome["error"] = exc

        t = threading.Thread(target=read_from_other_thread)
        t.start()
        t.join()

        self.assertNotIn("error", outcome)
        self.assertEqual(outcome["value"], [[2.0, 2.0], [2.0, 2.0]])


if __name__ == "__main__":
    unittest.main()
