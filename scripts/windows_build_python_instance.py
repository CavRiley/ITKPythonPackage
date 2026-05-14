import re
import zipfile
from pathlib import Path

from build_python_instance_base import BuildPythonInstanceBase


class WindowsBuildPythonInstance(BuildPythonInstanceBase):
    """Windows-specific wheel builder.

    Handles Windows path conventions, pixi-based Python environment
    discovery, and ``delvewheel`` for wheel repair.

    Three regimes for ``post_build_fixup`` parallel to the macOS class:

    * **Conda cache, pre-bundled** (recipe ran ``delvewheel repair`` in
      place inside the conda env): the wheel already ships an
      ``itk/.libs/`` (or ``itk/itk.libs/`` / ``itk/itk_libs/``) sibling
      next to the ``.pyd`` files, with their import tables pointing at
      the bundle.  Re-running ``delvewheel`` would either duplicate the
      payload or fail — those wheels are skipped here.
    * **Conda cache, not pre-bundled**: ``.pyd`` files reference bare
      DLL names like ``ITKCommon-5.4.dll``.  ``delvewheel repair`` is
      run with ``--add-path <conda_prefix>/Library/bin`` so the DLLs
      get bundled into the wheel.
    * **From-source (legacy tarball cache)**: ``delvewheel`` is run with
      the in-build oneTBB ``bin/`` directory (the previous behavior).

    Wheels with no ``.pyd`` files at all (the meta wheel, or any empty
    per-group wheel) are skipped — ``delvewheel`` requires at least one
    native binary to process.
    """

    def prepare_build_env(self) -> None:
        """Set up the Windows build environment, TBB paths, and venv info."""
        # #############################################
        # ### Setup build tools
        self.package_env_config["USE_TBB"] = "ON"
        self.package_env_config["TBB_DIR"] = str(
            self.build_dir_root / "build" / "oneTBB-prefix" / "lib" / "cmake" / "TBB"
        )
        # The interpreter is provided; ensure basic tools are available
        self.venv_paths()
        self.update_venv_itk_build_configurations()

        target_arch = self.package_env_config["ARCH"]
        itk_binary_build_name: Path = (
            self.build_dir_root
            / "build"
            / f"ITK-{self.platform_env}-{self.get_pixi_environment_name()}_{target_arch}"
        )

        self.cmake_itk_source_build_configurations.set(
            "ITK_BINARY_DIR:PATH", str(itk_binary_build_name)
        )

        # Keep values consistent with prior quoting behavior
        # self.cmake_compiler_configurations.set("CMAKE_CXX_FLAGS:STRING", "-O3 -DNDEBUG")
        # self.cmake_compiler_configurations.set("CMAKE_C_FLAGS:STRING", "-O3 -DNDEBUG")

    def post_build_fixup(self) -> None:
        """Repair wheels with ``delvewheel``, with conda-cache branches.

        See the class docstring for the three regimes.  All wheels are
        scanned individually; empty meta wheels and wheels that already
        carry a recipe-bundled ``.libs/`` directory are skipped before
        ``delvewheel`` runs.
        """
        conda_itk_dir = getattr(self, "_conda_itk_dir", None)
        if conda_itk_dir is not None:
            # Conda cache: assemble lib paths from any caller-provided
            # extra lib paths plus the conda env's Library/bin/ where
            # DLLs live (mirror to <prefix>/lib/python*/site-packages/itk
            # is also possible but Library/bin is the canonical Windows
            # conda layout).
            search_lib_paths = (
                [
                    s
                    for s in str(self.windows_extra_lib_paths[0]).rstrip(";").split(";")
                    if s
                ]
                if self.windows_extra_lib_paths
                else []
            )
            conda_prefix = conda_itk_dir.parents[2]  # lib/cmake/ITK-x.y -> prefix
            search_lib_paths.append(str(conda_prefix / "Library" / "bin"))
            search_lib_paths_str: str = ";".join(map(str, search_lib_paths))
            for wheel in sorted((self.build_dir_root / "dist").glob("itk_*.whl")):
                if not self._wheel_has_pyd(wheel):
                    print(f"Skipping fixup of {wheel.name}: no .pyd files inside")
                    continue
                if self._wheel_has_predelocated_libs(wheel):
                    print(
                        f"Skipping delvewheel of {wheel.name}: wheel already "
                        "contains a recipe-bundled .libs/ directory"
                    )
                    continue
                self.fixup_wheel(str(wheel), lib_paths=search_lib_paths_str)
        else:
            # From-source path: append the oneTBB-prefix\\bin directory for
            # fixing wheels built with local oneTBB
            search_lib_paths = (
                [s for s in str(self.windows_extra_lib_paths[0]).rstrip(";") if s]
                if self.windows_extra_lib_paths
                else []
            )
            search_lib_paths.append(str(self.build_dir_root / "oneTBB-prefix" / "bin"))
            search_lib_paths_str = ";".join(map(str, search_lib_paths))
            self.fixup_wheels(search_lib_paths_str)

    @staticmethod
    def _wheel_has_pyd(wheel_path: Path) -> bool:
        """Return True if the wheel contains at least one ``.pyd`` file.

        Used to skip post-build fixup on empty meta wheels —
        ``delvewheel`` requires at least one native binary to process.
        """
        with zipfile.ZipFile(wheel_path) as zf:
            return any(name.endswith(".pyd") for name in zf.namelist())

    @staticmethod
    def _wheel_has_predelocated_libs(wheel_path: Path) -> bool:
        """Return True if the wheel ships a recipe-bundled ``.libs/`` dir.

        Modern ``libitk-wrapping`` conda recipes may pre-bundle DLLs by
        running ``delvewheel repair`` in-place inside the conda env.
        The resulting bundle directory is then forwarded into each
        wheel by the cmake_install.cmake shim.  Re-running
        ``delvewheel`` on such a wheel either duplicates the payload or
        fails outright because the import tables already point at the
        bundle.

        Recognises every shape we've seen in the wild:
        ``itk/.libs/``, ``itk/itk.libs/``, ``itk/itk_libs/``.
        """
        prefixes = ("itk/.libs/", "itk/itk.libs/", "itk/itk_libs/")
        with zipfile.ZipFile(wheel_path) as zf:
            return any(name.startswith(prefixes) for name in zf.namelist())

    def fixup_wheel(
        self, filepath, lib_paths: str = "", remote_module_wheel: bool = False
    ) -> None:
        """Repair a wheel using ``delvewheel`` with the given library paths.

        Parameters
        ----------
        filepath : str
            Path to the ``.whl`` file to repair.
        lib_paths : str, optional
            Semicolon-delimited directories to add to ``delvewheel --add-path``.
        remote_module_wheel : bool, optional
            Unused on Windows (kept for interface compatibility).
        """
        # Windows fixup_wheel
        lib_paths = lib_paths.strip()
        lib_paths = lib_paths + ";" if lib_paths else ""
        print(f"Library paths for fixup: {lib_paths}")

        delve_wheel = "delvewheel.exe"
        cmd = [
            str(delve_wheel),
            "repair",
            "--no-mangle-all",
            "--add-path",
            lib_paths.strip(";"),
            "--ignore-in-wheel",
            "-w",
            str(self.build_dir_root / "dist"),
            str(filepath),
        ]
        self.echo_check_call(cmd)

    def build_tarball(self):
        """Create an archive of the ITK Python package build tree (Windows).

        Mirrors scripts/windows-build-tarball.ps1 behavior:
        - Remove contents of IPP/dist
        - Use 7-Zip, when present, to archive the full IPP tree into
          ITKPythonBuilds-windows.zip at the parent directory of IPP (e.g., C:\P)
        - Fallback to Python's zip archive creation if 7-Zip is unavailable
        """

        # out_zip = self.build_dir_root / "build" / "ITKPythonBuilds-windows.zip"
        out_zip = self.build_dir_root / "ITKPythonBuilds-windows.zip"

        # 1) Clean IPP/dist contents (do not remove the directory itself)
        dist_dir = self.build_dir_root / "dist"
        if dist_dir.exists():
            for p in dist_dir.glob("*"):
                try:
                    if p.is_dir():
                        # shutil.rmtree alternative without importing here
                        for sub in p.rglob("*"):
                            # best-effort clean
                            try:
                                if sub.is_file() or sub.is_symlink():
                                    sub.unlink(missing_ok=True)
                            except Exception:
                                pass
                        try:
                            p.rmdir()
                        except Exception:
                            pass
                    else:
                        p.unlink(missing_ok=True)
                except Exception:
                    # best-effort cleanup; ignore errors to continue packaging
                    pass

        # 2) Try to use 7-Zip if available
        seven_zip_candidates = [
            Path(r"C:\\7-Zip\\7z.exe"),
            Path(r"C:\\Program Files\\7-Zip\\7z.exe"),
            Path(r"C:\\Program Files (x86)\\7-Zip\\7z.exe"),
        ]

        seven_zip = None
        for cand in seven_zip_candidates:
            if cand.exists():
                seven_zip = cand
                break

        if seven_zip is None:
            # Try PATH lookup using where/which behavior from shutil
            import shutil as _shutil

            found = _shutil.which("7z.exe") or _shutil.which("7z")
            if found:
                seven_zip = Path(found)

        if seven_zip is not None:
            cmd = [
                str(seven_zip),
                "a",
                "-t7z",
                "-r",
                str(out_zip),
                str(self.build_dir_root / "ITK"),
                str(self.build_dir_root / "build"),
                str(self.ipp_dir),
                "-xr!*.o",
                "-xr!*.obj",  # Windows equivalent of .o
                "-xr!wheelbuilds",  # Do not include the wheelbuild support directory
                "-xr!__pycache__",  # Do not include __pycache__
                "-xr!install_manifest_*.txt",  # Do not include install manifest files
                "-xr!.git",  # Exclude git directory
                "-xr!.idea",  # Exclude IDE directory
                "-xr!.pixi",  # Exclude pixi environment
                "-xr!castxml_inputs",
                "-xr!Wrapping\Modules",
                "-xr!*.pdb",  # Exclude debug symbols
            ]
            return_status: int = self.echo_check_call(cmd)
            if return_status == 0:
                return

        # 3) Fallback: create a .zip using Python's shutil
        # This will create a zip archive named ITKPythonBuilds-windows.zip
        import shutil as _shutil

        if out_zip.exists():
            try:
                out_zip.unlink()
            except Exception:
                pass
        # make_archive requires base name without extension
        base_name = str(out_zip.with_suffix("").with_suffix(""))
        # shutil.make_archive will append .zip
        _shutil.make_archive(
            base_name,
            "zip",
            root_dir=str(self.build_dir_root),
            base_dir=str(self.build_dir_root.name),
        )

    def venv_paths(self) -> None:
        """Populate ``venv_info_dict`` from the pixi-managed Python environment on Windows."""

        def get_python_version(platform_env: str) -> None | tuple[int, int]:
            pattern = re.compile(r"py3(?P<minor>\d+)")
            m = pattern.search(platform_env)
            if not m:
                return None
            return 3, int(m.group("minor"))

        # Get the python executable path
        python_exe = Path(self.package_env_config["PYTHON_EXECUTABLE"])

        # For the pixi environment structure:
        # python.exe is at: <env>/python.exe
        # Headers are at: <env>/include/
        # Libraries are at: <env>/libs/
        env_root = python_exe.parent  # C:/BDR/IPP/.pixi/envs/windows-py311

        venv_bin_path = env_root  # Where python.exe is
        venv_base_dir = env_root

        # Python development files are directly under env root
        python_include_dir = env_root / "include"

        python_major, python_minor = get_python_version(self.platform_env)
        # Version-specific library (e.g., python311.lib) - required for
        # CMake's FindPython3 to extract version info for Development.Module
        xy_lib_ver = f"{python_major}{python_minor}"
        python_library = env_root / "libs" / f"python{xy_lib_ver}.lib"

        # Stable ABI library (python3.lib) - for Development.SABIModule
        if python_minor >= 11:
            python_sabi_library = env_root / "libs" / f"python{python_major}.lib"
        else:
            python_sabi_library = python_library

        self.venv_info_dict = {
            "python_include_dir": python_include_dir,  # .../windows-py311/include
            "python_library": python_library,  # .../windows-py311/libs/python311.lib
            "python_sabi_library": python_sabi_library,  # .../windows-py311/libs/python3.lib
            "venv_bin_path": venv_bin_path,  # .../windows-py311
            "venv_base_dir": venv_base_dir,  # .../windows-py311
            "python_root_dir": env_root,  # .../windows-py311
        }

    def discover_python_venvs(
        self, platform_os_name: str, platform_architecture: str
    ) -> list[str]:
        """Return default Windows Python environment names.

        Parameters
        ----------
        platform_os_name : str
            Operating system identifier (unused, kept for interface).
        platform_architecture : str
            Architecture suffix appended to each environment name.

        Returns
        -------
        list[str]
            Environment names like ``['39-x64', '310-x64', '311-x64']``.
        """
        default_platform_envs = [
            f"310-{platform_architecture}",
            f"311-{platform_architecture}",
        ]
        return default_platform_envs
