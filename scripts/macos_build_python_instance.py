import os
import stat
import subprocess
import tempfile
import zipfile
from pathlib import Path

from build_python_instance_base import BuildPythonInstanceBase


class MacOSBuildPythonInstance(BuildPythonInstanceBase):
    """macOS-specific wheel builder.

    Handles macOS deployment target and architecture settings, and uses
    ``delocate`` for wheel repair.  When the conda cache is in use (any
    arch), every wheel is delocated and rpaths are pre-patched so that
    delocate can resolve the ``@rpath/`` deps from inside its temp dir.
    """

    def prepare_build_env(self) -> None:
        """Set up the macOS build environment, deployment target, and architecture."""
        # #############################################
        # ### Setup build tools
        self.package_env_config["USE_TBB"] = "OFF"
        self.package_env_config["TBB_DIR"] = "NOT_FOUND"

        # The interpreter is provided; ensure basic tools are available
        self.venv_paths()
        self.update_venv_itk_build_configurations()
        macosx_target = self.package_env_config.get("MACOSX_DEPLOYMENT_TARGET", "")
        if macosx_target:
            self.cmake_compiler_configurations.set(
                "CMAKE_OSX_DEPLOYMENT_TARGET:STRING", macosx_target
            )

        target_arch = self.package_env_config["ARCH"]

        self.cmake_compiler_configurations.set(
            "CMAKE_OSX_ARCHITECTURES:STRING", target_arch
        )

        # build will be here if downloaded
        binaries_path = Path(
            self.build_dir_root
            / "build"
            / f"ITK-{self.platform_env}-{self.platform_env}_{target_arch}"
        )

        if Path(binaries_path).exists():
            itk_binary_build_name = binaries_path
        else:
            itk_binary_build_name: Path = (
                self.build_dir_root
                / "build"
                / f"ITK-{self.platform_env}-{self.get_pixi_environment_name()}_{target_arch}"
            )

        self.cmake_itk_source_build_configurations.set(
            "ITK_BINARY_DIR:PATH", itk_binary_build_name.as_posix()
        )

        # Keep values consistent with prior quoting behavior
        # self.cmake_compiler_configurations.set("CMAKE_CXX_FLAGS:STRING", "-O3 -DNDEBUG")
        # self.cmake_compiler_configurations.set("CMAKE_C_FLAGS:STRING", "-O3 -DNDEBUG")

    def post_build_fixup(self) -> None:
        """Run ``delocate`` on wheels to bundle shared libraries.

        Three regimes:

        * **Conda cache, pre-delocated** (current ``libitk-wrapping``
          recipe): the .so files in the conda env already carry
          ``@loader_path/.dylibs/…`` install names, and a sibling
          ``itk/.dylibs/`` directory is forwarded into the wheel by the
          cmake_install.cmake shim.  Running ``delocate`` again is a
          no-op at best and a hard error at worst (it tries to resolve
          paths that already exist inside the wheel as if they were
          external).  Detected by ``itk/.dylibs/`` being present in the
          wheel — those wheels are skipped here.
        * **Conda cache, not pre-delocated** (older recipes): wheel has
          ``.so`` files with ``@loader_path/../../../`` rpaths and no
          ``.dylibs/``.  ``fixup_wheel`` runs the rpath pre-patch and
          then delocates per-wheel.
        * **From-source x86_64**: only ``itk_core`` needs fixup (TBB
          bundling via the base-class ``fixup_wheels``).  arm64
          from-source skips delocate entirely.

        Wheels with no ``.so`` files at all (the meta wheel, or any
        empty per-group wheel) are skipped — ``delocate`` rejects them.
        """
        conda_itk_dir = getattr(self, "_conda_itk_dir", None)
        if conda_itk_dir is not None:
            for wheel in sorted((self.build_dir_root / "dist").glob("itk_*.whl")):
                if not self._wheel_has_so(wheel):
                    print(f"Skipping fixup of {wheel.name}: no .so files inside")
                    continue
                if self._wheel_has_predelocated_dylibs(wheel):
                    print(
                        f"Skipping delocate of {wheel.name}: wheel already "
                        "contains itk/.dylibs/ from the conda recipe"
                    )
                    continue
                self.fixup_wheel(str(wheel))
        elif self.package_env_config["ARCH"] == "x86_64":
            self.fixup_wheels()

    @staticmethod
    def _wheel_has_so(wheel_path: Path) -> bool:
        """Return True if the wheel contains at least one ``.so`` file.

        Used to skip post-build fixup on empty meta wheels — ``delocate``
        rejects wheels with no native binaries to bundle.
        """
        with zipfile.ZipFile(wheel_path) as zf:
            return any(name.endswith(".so") for name in zf.namelist())

    @staticmethod
    def _wheel_has_predelocated_dylibs(wheel_path: Path) -> bool:
        """Return True if the wheel already ships an ``itk/.dylibs/`` dir.

        Modern ``libitk-wrapping`` conda recipes pre-delocate the .so
        files inside the conda env, shipping a sibling ``itk/.dylibs/``
        with the bundled dylibs.  The cmake_install.cmake shim forwards
        that directory into the wheel.  Running ``delocate`` again on
        such a wheel fails because the install names already point at
        wheel-internal paths.
        """
        with zipfile.ZipFile(wheel_path) as zf:
            return any(name.startswith("itk/.dylibs/") for name in zf.namelist())

    def build_tarball(self):
        """Create a zstd-compressed tarball of the ITK build tree."""
        self.create_posix_tarball()

    def discover_python_venvs(
        self, platform_os_name: str, platform_architechure: str
    ) -> list[str]:
        """Discover available Python environments under the project ``venvs/`` dir.

        Parameters
        ----------
        platform_os_name : str
            Operating system identifier (unused, kept for interface).
        platform_architechure : str
            Architecture identifier (unused, kept for interface).

        Returns
        -------
        list[str]
            Sorted list of discovered environment names.
        """
        names = []

        # Discover virtualenvs under project 'venvs' folder
        def _discover_ipp_venvs() -> list[str]:
            venvs_dir = self.build_dir_root / "venvs"
            if not venvs_dir.exists():
                return []
            names.extend([p.name for p in venvs_dir.iterdir() if p.is_dir()])
            # Sort for stable order
            return sorted(names)

        default_platform_envs = _discover_ipp_venvs()

        return default_platform_envs

    def _patch_wheel_rpaths(
        self, wheel_path: str, old_rpath: str, new_rpath: str
    ) -> None:
        """Replace one LC_RPATH entry in every ``.so`` inside a wheel (in-place).

        Conda-cache ``.so`` files ship with ``@loader_path/../../../`` as their
        rpath (resolves to ``$CONDA_PREFIX/lib`` from site-packages).  delocate
        resolves ``@rpath/`` deps by walking the binary's own LC_RPATH entries
        from inside its temp extraction directory, where that relative traversal
        leads nowhere.  Replacing the rpath with the absolute conda ``lib/``
        path before running delocate lets it find, copy, and relink every dep.
        delocate's ``--sanitize-rpaths`` (on by default) then strips the
        absolute path so nothing conda-specific remains in the finished wheel.

        Parameters
        ----------
        wheel_path : str
            Path to the ``.whl`` file to patch in place.
        old_rpath : str
            Existing LC_RPATH entry to replace (e.g.
            ``"@loader_path/../../../"``).
        new_rpath : str
            New LC_RPATH entry (e.g. the absolute ``$CONDA_PREFIX/lib`` path).
        """
        wheel = Path(wheel_path)
        with tempfile.TemporaryDirectory() as tmp:
            extract = Path(tmp) / "wheel"
            with zipfile.ZipFile(wheel) as zf:
                zf.extractall(extract)
                attr_map = {info.filename: info.external_attr for info in zf.infolist()}

            patched = 0
            for so in extract.rglob("*.so"):
                so.chmod(so.stat().st_mode | stat.S_IWRITE)
                r = subprocess.run(
                    ["install_name_tool", "-rpath", old_rpath, new_rpath, str(so)],
                    capture_output=True,
                    text=True,
                )
                if r.returncode == 0:
                    patched += 1
                    # arm64 requires re-signing after any install_name_tool change
                    subprocess.run(
                        ["codesign", "--force", "--sign", "-", str(so)],
                        capture_output=True,
                        text=True,
                    )

            if patched == 0:
                return

            print(
                f"Pre-patched rpath in {patched} .so files: "
                f"{old_rpath!r} -> {new_rpath!r}"
            )
            wheel.unlink()
            with zipfile.ZipFile(wheel, "w", zipfile.ZIP_DEFLATED) as zf:
                for f in sorted(extract.rglob("*")):
                    if not f.is_file():
                        continue
                    arcname = str(f.relative_to(extract))
                    info = zipfile.ZipInfo(arcname)
                    info.external_attr = attr_map.get(arcname, 0)
                    with open(f, "rb") as fh:
                        zf.writestr(info, fh.read())

    def fixup_wheel(
        self, filepath, lib_paths: str = "", remote_module_wheel: bool = False
    ) -> None:
        """Repair a wheel using ``delocate``, bundling shared libraries.

        For conda-cache builds the ``.so`` files ship with
        ``@loader_path/../../../`` as their LC_RPATH.  ``_patch_wheel_rpaths``
        replaces that with the absolute conda ``lib/`` path so delocate can
        resolve every ``@rpath/`` dependency from within its temp dir, bundle
        the dylibs, and rewrite rpaths to ``@loader_path/.dylibs/``.

        Parameters
        ----------
        filepath : str
            Path to the ``.whl`` file.
        lib_paths : str, optional
            Colon-separated absolute library search paths used for rpath
            pre-patching.  When empty and a conda ITK dir is detected, the
            conda prefix ``lib/`` is used automatically.
        remote_module_wheel : bool, optional
            Unused on macOS (kept for interface compatibility).
        """
        self.remove_apple_double_files()

        # Auto-detect conda lib path when not explicitly provided.
        if not lib_paths:
            conda_itk_dir = getattr(self, "_conda_itk_dir", None)
            if conda_itk_dir is not None:
                lib_paths = str(conda_itk_dir.parents[2] / "lib")

        if lib_paths:
            # Pre-patch: swap the conda-env-relative rpath for an absolute path
            # so delocate can resolve @rpath/ deps from its temp extraction dir.
            for lp in lib_paths.split(os.pathsep):
                self._patch_wheel_rpaths(filepath, "@loader_path/../../../", lp)

        # Skip delocate on arm64 *from-source* (the legacy tarball arm64 case
        # didn't bundle anything and arm64 dylibs lack a conda counterpart to
        # bundle).  When conda is in use we want delocate on every arch.
        if (
            self.package_env_config["ARCH"] != "arm64"
            or getattr(self, "_conda_itk_dir", None) is not None
        ):
            venv_bin_path = self.venv_info_dict.get("venv_bin_path", None)
            if venv_bin_path:
                delocate_listdeps = f"{venv_bin_path}/delocate-listdeps"
                delocate_wheel = f"{venv_bin_path}/delocate-wheel"
                self.echo_check_call([str(delocate_listdeps), str(filepath)])
                self.echo_check_call([str(delocate_wheel), str(filepath)])
            else:
                print(
                    "=" * 20
                    + "WARNING: Could not find venv binary to delocate wheel"
                    + "=" * 20
                )

    def remove_apple_double_files(self):
        """Remove AppleDouble ``._*`` files using ``dot_clean`` if available."""
        try:
            # Optional: clean AppleDouble files if tool is available
            self.echo_check_call(
                ["dot_clean", str(self.package_env_config["IPP_SOURCE_DIR"])]
            )
        except Exception:
            # dot_clean may not be available; continue without it
            pass
