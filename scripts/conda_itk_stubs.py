"""Generate the CMake plumbing required to consume a conda-supplied ITK.

A conda-supplied ITK (``libitk`` + ``libitk-wrapping`` + ``libitk-*-devel``)
provides nearly everything the wheel build needs.  Two pieces of glue still
have to be produced locally because they vary across conda packages:

* **stub-find-modules** — a ``CMAKE_MODULE_PATH`` directory containing a
  ``FindHDF5.cmake`` bridge from conda-forge's lowercase ``hdf5::*`` to
  ITK's expected ``HDF5::HDF5`` target, plus a copy of
  ``TopologicalSort.cmake``.  Recent ``libitk-wrapping-devel`` conda
  packages ship this at ``<prefix>/lib/cmake/stub-find-modules/`` — we
  prefer that when present and otherwise install our own.

* **cmake_install.cmake** — a per-component install shim that
  ``scikit-build-core`` invokes during ``cmake --install``.  It maps
  each ``<Module>PythonWheelRuntimeLibraries`` component to the
  pre-installed Python files in the conda prefix and copies them into
  the wheel's install tree.  No conda package ships this today (the
  ``libitk-wrapping-devel`` payload only contains CMake config), so it
  is always materialised by this module.

Both pieces are version-agnostic — the ``cmake_install.cmake`` shim
globs for ``_<Module>Python*.so`` and the bridge module never names a
specific ITK MAJOR.MINOR.

Keeping the CMake content in standalone ``.cmake`` / ``.cmake.in``
files (rather than as string literals inside the Python build driver)
gives editors syntax highlighting and lets the templates be diffed,
linted, and reviewed independently.
"""

from __future__ import annotations

import shutil
from pathlib import Path

# `BuildWheelsSupport/conda-itk-stubs/` ships with the repo and is the
# authoritative source of the CMake content this module installs.
_TEMPLATES_DIR = (
    Path(__file__).resolve().parent.parent / "BuildWheelsSupport" / "conda-itk-stubs"
)


def _install_stub_find_modules(
    conda_prefix: Path,
    itk_source_dir: Path,
    build_dir_root: Path,
) -> Path:
    """Return a directory suitable for ``CMAKE_MODULE_PATH``.

    Prefers the version that ships inside the conda env when present;
    otherwise installs the repo-shipped ``FindHDF5.cmake`` plus a copy
    of ``TopologicalSort.cmake`` from the ITK source tree (when
    available) into ``<build_dir_root>/build/conda-itk-stubs/``.
    """
    shipped = conda_prefix / "lib" / "cmake" / "stub-find-modules"
    if (shipped / "FindHDF5.cmake").is_file():
        print(f"Using shipped conda stub-find-modules at {shipped}")
        return shipped

    local_stub_dir = build_dir_root / "build" / "conda-itk-stubs"
    local_stub_dir.mkdir(parents=True, exist_ok=True)

    shutil.copyfile(
        _TEMPLATES_DIR / "FindHDF5.cmake",
        local_stub_dir / "FindHDF5.cmake",
    )
    src_topo = itk_source_dir / "CMake" / "TopologicalSort.cmake"
    if src_topo.is_file():
        shutil.copyfile(src_topo, local_stub_dir / "TopologicalSort.cmake")

    print(f"Installed fallback conda stub-find-modules at {local_stub_dir}")
    return local_stub_dir


def _install_cmake_install_shim(
    conda_prefix: Path,
    conda_itk_dir: Path,
) -> Path:
    """Write the per-component install shim into the conda ITK cmake dir.

    The shim is always regenerated.  Conda relocation does not rewrite
    the embedded ``_ipp_conda_prefix`` value on macOS, so the env in
    which the build runs is the authoritative source of truth.
    """
    template = (_TEMPLATES_DIR / "cmake_install.cmake.in").read_text()
    rendered = template.replace("@CONDA_PREFIX@", conda_prefix.as_posix())
    dest = conda_itk_dir / "cmake_install.cmake"
    dest.write_text(rendered)
    print(f"Wrote conda cmake_install.cmake shim at {dest}")
    return dest


def install_stubs(
    conda_prefix: Path,
    conda_itk_dir: Path,
    itk_source_dir: Path,
    build_dir_root: Path,
) -> Path:
    """Install both stub layers required to consume a conda-supplied ITK.

    Parameters
    ----------
    conda_prefix : Path
        Active conda or pixi prefix (e.g.
        ``.pixi/envs/macosx-conda-py312``).
    conda_itk_dir : Path
        ``<prefix>/lib/cmake/ITK-<ver>`` directory where the install
        shim must live so scikit-build-core can find it during
        ``cmake --install``.
    itk_source_dir : Path
        ITK source tree.  Used as a fallback source for
        ``TopologicalSort.cmake`` when the conda env doesn't ship its
        own stub-find-modules.
    build_dir_root : Path
        Build artifacts root, used when a local stub-find-modules
        directory must be created.

    Returns
    -------
    Path
        Directory suitable for the CMake ``CMAKE_MODULE_PATH`` cache var.
    """
    stub_module_path = _install_stub_find_modules(
        conda_prefix, itk_source_dir, build_dir_root
    )
    _install_cmake_install_shim(conda_prefix, conda_itk_dir)
    return stub_module_path
