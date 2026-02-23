# ITK Python Package

This project configures pyproject.toml files and manages environmental
variables needed to build ITK Python binary wheels on MacOS, Linux, and Windows platforms.
Scripts are available for both [ITK infrastructure](https://github.com/insightSoftwareConsortium/ITK) and 
ITK external module Python packages.

The Insight Toolkit (ITK) is an open-source, cross-platform system that provides developers
with an extensive suite of software tools for image analysis.
More information is available on the [ITK website](https://itk.org/)
or at the [ITK GitHub homepage](https://github.com/insightSoftwareConsortium/ITK).

## Table of Contents

- [Using ITK Python Packages](#using-itk-python-packages)
- [Building with ITKPythonPackage](#building-with-itkpythonpackage)
- [Frequently Asked Questions](#frequently-asked-questions)
- [Additional Information](#additional-information)

## Using ITK Python Packages (pre-built, or locally built)

ITKPythonPackage scripts can be used to produce [Python](https://www.python.org/) packages
for ITK and ITK external modules. The resulting packages can be
hosted on the [Python Package Index (PyPI)](https://pypi.org/)
for easy distribution.

### Installation of pre-built packages

To install baseline ITK Python packages:

```sh
> pip install itk
```

To install ITK external module packages:

```sh
> pip install itk-<module_name>
```

### Using ITK in Python scripts

```python
    import itk
    import sys

    input_filename = sys.argv[1]
    output_filename = sys.argv[2]

    image = itk.imread(input_filename)

    median = itk.median_image_filter(image, radius=2)

    itk.imwrite(median, output_filename)
```

### Other Resources for Using ITK in Python

See also the [ITK Python Quick Start
Guide](https://itkpythonpackage.readthedocs.io/en/master/Quick_start_guide.html).
There are also many [downloadable examples on the ITK examples website](https://examples.itk.org/search.html?q=Python).

For more information on ITK's Python wrapping, [an introduction is
provided in the ITK Software
Guide](https://itk.org/ITKSoftwareGuide/html/Book1/ITKSoftwareGuide-Book1ch3.html#x32-420003.7).

## Building with ITKPythonPackage

ITK reusable workflows are available to build and package Python wheels as
part of Continuous Integration (CI) via Github Actions runners.
Those workflows can handle the overhead of fetching, configuring, and
running ITKPythonPackage build scripts for most ITK external modules.
See [ITKRemoteModuleBuildTestPackageAction](https://github.com/InsightSoftwareConsortium/ITKRemoteModuleBuildTestPackageAction)
for more information.

> [!NOTE]
> When using`ITKRemoteModuleBuildTestPackageAction` in your remote module, you can specify the `itk-python-package-org` and `itk-python-package-tag` to build with.

For special cases where ITK reusable workflows are not a good fit,
ITKPythonPackage scripts can be directly used to build Python wheels
to target Windows, Linux, and MacOS platforms. See
[ITKPythonPackage ReadTheDocs](https://itkpythonpackage.readthedocs.io/en/latest/Build_ITK_Module_Python_packages.html)
documentation for more information on building wheels by hand.

## Building ITK Wheels Locally

This guide covers building ITK Python wheels locally using the `build_wheels.py` script.

### Prerequisites

**All Platforms:**
- Python 3.9 or later
- Git
- Docker for manylinux builds

### Quick Start

1. **Clone the repository:**
   ```bash
   git clone https://github.com/InsightSoftwareConsortium/ITKPythonPackage.git
   cd ITKPythonPackage
   ```

2. **Install Pixi** (if not already installed):
   ```bash
   curl -fsSL https://pixi.sh/install.sh | bash
   ```

3. **Build wheels:**
   ```bash
   pixi run python3 scripts/build_wheels.py \
     --platform-env <platform>-<py-version>
   ```

### Platform Environments

Available `--platform-env` options:

| Platform | Python Versions |
|----------|----------------|
| `linux` | py39, py310, py311 |
| `manylinux228` | py39, py310, py311 |
| `macosx` | py39, py310, py311 |
| `windows` | py39, py310, py311 |

**Example:** `--platform-env macosx-py311`

### Basic Usage

#### Build ITK Proper Wheels

Build ITK core library wheels without remote modules:

> [!IMPORTANT]
> It is recommended to build against ITK version tag `v6.0b01`, especially if building with dockcross.

```bash
# macOS example
pixi run python3 scripts/build_wheels.py \
  --platform-env macosx-py310 \
  --no-build-itk-tarball-cache
```

```bash
# Linux example
pixi run python3 scripts/build_wheels.py \
  --platform-env linux-py311 \
  --no-build-itk-tarball-cache
```

> [!IMPORTANT]
> When `--module-source-dir` is not provided, only ITK proper wheels are built. Remote module build steps are skipped.

#### Build ITK Remote Module Wheels

Build wheels for an ITK remote module:

```bash
pixi run python3 scripts/build_wheels.py \
  --platform-env macosx-py311 \
  --module-source-dir /path/to/ITKRemoteModule \
  --itk-git-tag v6.0a01 \
  --no-build-itk-tarball-cache
```

### Building and Using ITK Build Caches (Tarballs)

ITK build caches allow you to reuse pre-built ITK binaries across builds, significantly speeding up remote module development. This section covers creating caches locally and using them correctly.

#### Creating Local Build Caches

To build ITK once and create a reusable tarball cache:

```bash
bash scripts/make_tarballs.sh
```

> [!NOTE]
> This script warns you when you are building against the conventions used for GitHub Actions

**What this does:**
- Builds tarballs for python 3.9, 3.10, and 3.11 unless otherwise specified
- Creates a compressed tarball containing:
  - Pre-compiled ITK binaries (`.o`, `.a`, `.so` files)
  - ITK source code
  - CMake configuration files
- Places the tarball in parent of the `<build-dir-root>` specified by the `--build-dir-root` option

**Tarball naming:** `ITKPythonBuilds-<platform>.tar.zst`

Example: `ITKPythonBuilds-macosx-arm64.tar.zst`

#### Understanding Build Cache Paths

> [!IMPORTANT]
> Build caches contain **absolute paths** within the CMake cache files. When reusing caches, paths must match exactly or the cache must be regenerated.

**Standard build root paths that should be used in GitHub Action build caches:**

| Platform | Root Build Path                                   |
|----------|---------------------------------------------------|
| **manylinux** (docker) | `/work/ITKPythonPackage-build`                    |
| **macOS** | `/Users/svc-dashboard/D/P/ITKPythonPackage-build` |
| **Windows** | `TBD`                                             |

> [!WARNING]
> If you extract a build cache to different paths than it was built with, CMake will fail with path mismatch errors.


### Common Options


| Option | Description | Example                 |
|--------|-------------|-------------------------|
| `--platform-env` | Target platform and Python version | `macosx-py310`          |
| `--module-source-dir` | Path to remote module to build | `/path/to/module`       |
| `--module-dependencies-root-dir` | Root directory for module dependencies | `./dependencies`        |
| `--itk-module-deps` | Remote module dependencies | `Mod1@tag:Mod2@tag`     |
| `--build-dir-root` | Build directory location | `/tmp/itk-build`        |
| `--itk-source-dir` | Path to ITK source (reuse existing clone) | `/path/to/ITK`          |
| `--itk-git-tag` | ITK version/branch/commit to use | `0ffcaed`, `main`, `v6.0b01` |
| `--itk-package-version` | PEP440 version string for wheels | `v6.0b01`               |
| `--manylinux-version` | Manylinux standard version | `_2_28`             |
| `--cleanup` | Leave temporary build files after completion | (flag)                  |
| `--build-itk-tarball-cache` | Generate uploadable tarball cache | (flag)                  |
| `--no-build-itk-tarball-cache` | Skip tarball generation (default) | (flag)                  |

> [!NOTE]
> For the total list of options, run `pixi run python3 scripts/build_wheels.py --help`

## Advanced Examples

### Build with Dependencies

```bash
pixi run python3 scripts/build_wheels.py \
  --platform-env manylinux228-py310 \
  --module-source-dir ./ITKMyModule \
  --module-dependencies-root-dir ./dependencies \
  --itk-module-deps "ITKSplitComponents@v1.2.1:ITKTextureFeatures@v3.0.0" \
  --itk-package-version v6.0a01 \
  --no-build-itk-tarball-cache
```

### Custom Build Directory (Linux)

```bash
pixi run python3 scripts/build_wheels.py \
  --platform-env linux-py311 \
  --build-dir-root /tmp/itk-build \
  --itk-git-tag v5.4.0 \
  --no-build-itk-tarball-cache
```

> [!NOTE]
> Windows builds are also supported using `windows-py3X` platform environments.

## Output Location

Built wheels are placed in:
- **ITK proper**: `<build-dir-root>/dist/`
- **Remote modules**: `<module-source-dir>/dist/`

## Testing Your Wheels

Install and test locally:

```bash
pip install /path/to/your/wheel.whl

# Run a specific module operation
```

## Frequently Asked Questions

### What target platforms and architectures are supported?

ITKPythonPackage currently supports building wheels for the following platforms and architectures:
- Windows 10 x86_64 platforms
- Windows 11 x86_64 platforms
- MacOS 15.0+ x86_64 and arm64 platforms
- Linux glibc 2.17+ (E.g. Ubuntu 18.04+) x86_64 platforms
- Linux glibc 2.28+ (E.g. Ubuntu 20.04+) aarch64 (ARMv8) platforms

### What should I do if my target platform/architecture does not appear on the list above?

Please open an issue in the [ITKPythonPackage issue tracker](https://github.com/InsightSoftwareConsortium/ITKPythonPackage/issues)
for discussion, and consider contributing either time or funding to support
development. The ITK open source ecosystem is driven through contributions from its community members.

### What is an ITK external module?

The Insight Toolkit consists of several baseline module groups for image analysis
including filtering, I/O, registration, segmentation, and more. Community members
can extend ITK by developing an ITK "external" module which stands alone in a separate
repository and its independently built and tested. An ITK external module which
meets community standards for documentation and maintenance may be included in the
ITK build process as an ITK "remote" module to make it easier to retrieve and build.

Visit [ITKModuleTemplate](https://github.com/insightSoftwareConsortium/ITKmoduletemplate)
to get started creating a new ITK external module.

### How can I make my ITK C++ filters available in Python?

ITK uses SWIG to wrap C++ filters for use in Python.
See [Chapter 9 in the ITK Software Guide](https://itk.org/ITKSoftwareGuide/html/Book1/ITKSoftwareGuide-Book1ch9.html)
or visit [ITKModuleTemplate](https://github.com/insightSoftwareConsortium/ITKmoduletemplate)
to get started on writing `.wrap` files.

After you've added wrappings for your external module C++ filters
you may build and distribute Python packages automatically with
[ITKRemoteModuleBuildTestPackageAction](https://github.com/InsightSoftwareConsortium/ITKRemoteModuleBuildTestPackageAction)
or manually with ITKPythonPackage scripts.

### What makes building ITK external module wheels different from building ITK wheels?

In order to build an ITK external module you must have first built ITK for the same target platform.
However, building ITK modules and wrapping them for Python can take a very long time!
To avoid having to rebuild ITK before building every individual external module,
artifacts from the ITK build process (headers, source files, wrapper outputs, and more) are
packaged and cached as [ITKPythonBuilds](https://github.com/insightSoftwareConsortium/ITKpythonbuilds)
releases.

In order to build Python wheels for an ITK external module, ITKPythonPackage scripts
first fetch the appropriate ITK Python build artifacts along with other necessary
tools. Then, the module can be built, packaged, and distributed on [PyPI](https://pypi.org/).

### My external module has a complicated build process. Is it supported by ITKPythonPackage?

Start by consulting the [ITKPythonPackage ReadTheDocs](https://itkpythonpackage.readthedocs.io/en/master/Build_ITK_Module_Python_packages.html)
documentation and the [ITKPythonPackage issue tracker](https://github.com/InsightSoftwareConsortium/ITKPythonPackage/issues)
for discussion related to your specific issue.

If you aren't able to find an answer for your specific case, please start a discussion the
[ITK Discourse forum](https://discourse.itk.org/) for help.

## Additional Information

-   Free software: Apache Software license
-   Documentation: <http://itkpythonpackage.readthedocs.org>
-   Source code: <https://github.com/InsightSoftwareConsortium/ITKPythonPackage>
