"""Check the tested native Bonsai 2 MLX dependency set without loading weights."""
from importlib.metadata import version, PackageNotFoundError
from pathlib import Path
import sys


def _version_key(value):
    """Numeric tuple for ordering dotted versions (certifi uses date tags like 2026.10.23).

    Non-numeric suffixes (rc1, dev, ...) are ignored: this checker only needs a floor
    comparison for date-based certificate bundles, where such suffixes do not appear.
    """
    key = []
    for part in value.split("."):
        digits = "".join(c for c in part if c.isdigit())
        key.append(int(digits) if digits else 0)
    return tuple(key)


for requirement in Path(__file__).with_name("requirements-mlx-vlm.txt").read_text().splitlines():
    if not requirement or requirement.startswith("#"):
        continue
    for specifier in ("==", ">="):
        if specifier in requirement:
            package, expected = requirement.split(specifier)
            break
    else:
        sys.exit(f"{requirement}: unsupported requirement, expected 'package==version' or 'package>=version'")
    try:
        actual = version(package)
    except PackageNotFoundError:
        actual = "missing"
    # Pinned packages must match exactly; floored ones (the certifi CA bundle) accept newer.
    satisfied = actual != "missing" and (
        actual == expected if specifier == "==" else _version_key(actual) >= _version_key(expected)
    )
    if not satisfied:
        sys.exit(f"{package}: expected {specifier}{expected}, found {actual}. Run ./setup.sh to update .venv-vlm.")
