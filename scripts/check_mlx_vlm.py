"""Check the tested native Bonsai 2 MLX dependency set without loading weights."""
from importlib.metadata import version, PackageNotFoundError
from pathlib import Path
import sys

for requirement in Path(__file__).with_name("requirements-mlx-vlm.txt").read_text().splitlines():
    if not requirement or requirement.startswith("#"):
        continue
    package, expected = requirement.split("==")
    try:
        actual = version(package)
    except PackageNotFoundError:
        actual = "missing"
    if actual != expected:
        sys.exit(f"{package}: expected {expected}, found {actual}. Run ./setup.sh to update .venv-vlm.")
