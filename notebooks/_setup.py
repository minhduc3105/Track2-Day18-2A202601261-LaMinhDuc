"""Path bootstrap for the lightweight notebooks.

Resolves `scripts/lakehouse.py` from the repo root regardless of where
Jupyter / Python was launched from. Used by all NB*/lite notebooks:

    import _setup  # noqa: F401  -- adds scripts/ to sys.path
    from lakehouse import path, reset

Why: the prior pattern `sys.path.insert(0, "../scripts")` is *cwd-relative*
and silently breaks if the notebook is run from the repo root or a CI
runner. When imported, `__file__` identifies this file.  When this helper is
run directly as a notebook, `__file__` does not exist, so we also resolve the
repo from common Jupyter working directories.
"""
from __future__ import annotations

import sys
from pathlib import Path

_DOCKER = Path("/workspace/scripts")
_HERE = Path(__file__).resolve().parent if "__file__" in globals() else Path.cwd()
_CANDIDATES = (_HERE / "scripts", _HERE.parent / "scripts")
_LOCAL = next((candidate for candidate in _CANDIDATES if candidate.exists()), None)
_TARGET = _DOCKER if _DOCKER.exists() else _LOCAL

if _TARGET is None:
    raise RuntimeError(
        "Could not find scripts/. Start Jupyter from the repository root "
        "or its notebooks/ directory."
    )
sys.path.insert(0, str(_TARGET))
