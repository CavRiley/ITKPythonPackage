########################################################################
# Pull build dependencies and build an ITK external module.
#
# This script must be run in an x64 Developer PowerShell.
# See https://learn.microsoft.com/en-us/visualstudio/ide/reference/command-prompt-powershell?view=vs-2022#developer-powershell
#
# -----------------------------------------------------------------------
# Positional parameters / named options:
#
# -python_version_minor  Python minor version (required).
#     For instance, for Python 3.11:
#     > windows-download-cache-and-build-module-wheels.ps1 -python_version_minor 11
#     or positionally:
#     > windows-download-cache-and-build-module-wheels.ps1 11
#
# -setup_options         pyproject.toml options forwarded to the build script.
#     For instance, to exclude a library during packaging:
#     > ... -setup_options "--exclude-libs nvcuda.dll"
#
# -cmake_options         CMake options passed to pyproject.toml for project configuration.
#     For instance:
#     > ... -cmake_options "-DRTK_USE_CUDA:BOOL=ON"
#
# -----------------------------------------------------------------------
# Environment variables used in this script:
#
# `$env:ITK_PACKAGE_VERSION`
#     Tag for the ITKPythonBuilds archive to download/use. Required.
#
# `$env:ITKPYTHONPACKAGE_TAG`
#     Tag for ITKPythonPackage build scripts to use.
#     If empty, the scripts bundled in the archive will be used.
#
# `$env:ITKPYTHONPACKAGE_ORG`
#     GitHub organization/user for ITKPythonPackage. Default: InsightSoftwareConsortium.
#     Ignored if ITKPYTHONPACKAGE_TAG is empty.
#
# `$env:ITK_MODULE_PREQ`
#     Colon-delimited list of ITK module dependencies.
#     Format: `<org>/<module>@<tag>:<org>/<module>@<tag>:...`
#     Example: `InsightSoftwareConsortium/ITKMeshToPolyData@v0.10.0`
#     Passed directly to build_wheels.py via --itk-module-deps; dependency
#     building is handled inside that script, not here.
#
# `$env:MODULE_SRC_DIRECTORY`
#     Path to the ITK external module source. Defaults to the directory
#     containing this script.
#
########################################################################
param (
  [int]$python_version_minor,
  [string]$setup_options = "",
  [string]$cmake_options = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Resolve module source directory
$MODULE_SRC_DIRECTORY = if ($env:MODULE_SRC_DIRECTORY) {
  $env:MODULE_SRC_DIRECTORY
} else {
  $PSScriptRoot
}
echo "MODULE_SRC_DIRECTORY: $MODULE_SRC_DIRECTORY"

# Validate required inputs
if (-not $python_version_minor) {
  Write-Error "ERROR: -python_version_minor is required. Example: -python_version_minor 11"
  exit 1
}
if (-not $env:ITK_PACKAGE_VERSION) {
  Write-Error "ERROR: `$env:ITK_PACKAGE_VERSION must be set before running this script."
  exit 1
}

$pythonArch = "64"
$pythonVersion = "3.$python_version_minor"
$ITK_PACKAGE_VERSION = $env:ITK_PACKAGE_VERSION

$ITKPYTHONPACKAGE_ORG = if ($env:ITKPYTHONPACKAGE_ORG) { $env:ITKPYTHONPACKAGE_ORG } else { "InsightSoftwareConsortium" }
$ITKPYTHONPACKAGE_TAG = $env:ITKPYTHONPACKAGE_TAG   # may be empty

$DASHBOARD_BUILD_DIRECTORY = "C:\P"

echo "Python version : $pythonVersion-x$pythonArch"
echo "ITK_PACKAGE_VERSION: $ITK_PACKAGE_VERSION"

# Install Python if not already present
$pythonExe = "C:\Python$pythonVersion-x$pythonArch\python.exe"
if (-not (Test-Path $pythonExe)) {
  echo "Installing Python $pythonVersion-x$pythonArch ..."
  iex ((new-object net.webclient).DownloadString('https://raw.githubusercontent.com/scikit-build/scikit-ci-addons/master/windows/install-python.ps1'))
} else {
  echo "Python already installed at $pythonExe"
}

# Download ITKPythonBuilds archive (skip if already present)
$zipName           = "ITKPythonBuilds-windows.zip"
$zipDownloadUrl    = "https://github.com/InsightSoftwareConsortium/ITKPythonBuilds/releases/download/$ITK_PACKAGE_VERSION/$zipName"
# Use a version-stamped local filename so different versions coexist
$localZipName      = "ITKPythonBuilds-windows_${ITK_PACKAGE_VERSION}.zip"

if (Test-Path $localZipName) {
  echo "Found cached archive: $localZipName -- skipping download."
} else {
  echo "Downloading $zipDownloadUrl ..."
  Invoke-WebRequest -Uri $zipDownloadUrl -OutFile $localZipName
}

# Unpack archive
if (Test-Path $DASHBOARD_BUILD_DIRECTORY) {
  echo "Removing existing build directory: $DASHBOARD_BUILD_DIRECTORY"
  Remove-Item -Recurse -Force $DASHBOARD_BUILD_DIRECTORY
}
echo "Extracting archive to $DASHBOARD_BUILD_DIRECTORY ..."
7z x $localZipName -o"$DASHBOARD_BUILD_DIRECTORY" -aoa -r

# Optional: update ITKPythonPackage build scripts from a specific tag
if ($ITKPYTHONPACKAGE_TAG) {
  echo "Updating build scripts to $ITKPYTHONPACKAGE_ORG/ITKPythonPackage@$ITKPYTHONPACKAGE_TAG"

  $ippTmpDir = "$DASHBOARD_BUILD_DIRECTORY\IPP-tmp"
  $ippCloneUrl = "https://github.com/$ITKPYTHONPACKAGE_ORG/ITKPythonPackage.git"

  if (-not (Test-Path "$ippTmpDir\.git")) {
    git clone $ippCloneUrl $ippTmpDir
  }

  pushd $ippTmpDir
    git checkout $ITKPYTHONPACKAGE_TAG
    git reset "origin/$ITKPYTHONPACKAGE_TAG" --hard
    git status
  popd

  # Overlay everything from the cloned repo into IPP
  Copy-Item -Recurse -Force "$ippTmpDir\*" "$DASHBOARD_BUILD_DIRECTORY\IPP\"
  Remove-Item -Recurse -Force $ippTmpDir
}

# Fetch other build-time tools
# Note: doxygen is provided by the pixi environment; no need to download it here.
if (-not (Test-Path "grep-win.zip")) {
  Invoke-WebRequest -Uri "https://data.kitware.com/api/v1/file/5bbf87ba8d777f06b91f27d6/download/grep-win.zip" -OutFile "grep-win.zip"
}
7z x grep-win.zip -o"$DASHBOARD_BUILD_DIRECTORY\grep" -aoa -r
$env:Path += ";$DASHBOARD_BUILD_DIRECTORY\grep"

# Assemble the build command
$buildScript  = "$DASHBOARD_BUILD_DIRECTORY\IPP\scripts\build_wheels.py"
$buildDirRoot = "$DASHBOARD_BUILD_DIRECTORY\IPP-build"
$itkSourceDir = "$buildDirRoot\ITK"
$moduleDepsDir = "$DASHBOARD_BUILD_DIRECTORY\MODULE_DEPENDENCIES"
$platformEnv  = "win-py3$python_version_minor"

$build_command  = "& `"$pythonExe`" `"$buildScript`""
$build_command += " --platform-env `"$platformEnv`""
$build_command += " --module-source-dir `"$MODULE_SRC_DIRECTORY`""
$build_command += " --module-dependencies-root-dir `"$moduleDepsDir`""
$build_command += " --itk-module-deps `"$env:ITK_MODULE_PREQ`""
$build_command += " --no-build-itk-tarball-cache"
$build_command += " --build-dir-root `"$buildDirRoot`""
$build_command += " --manylinux-version ``"
$build_command += " --itk-git-tag `"$ITK_PACKAGE_VERSION`""
$build_command += " --itk-source-dir `"$itkSourceDir`""
$build_command += " --itk-package-version `"$ITK_PACKAGE_VERSION`""
$build_command += " --itk-pythonpackage-org `"$ITKPYTHONPACKAGE_ORG`""
$build_command += " --itk-pythonpackage-tag `"$ITKPYTHONPACKAGE_TAG`""
$build_command += " --no-use-ccache"
$build_command += " --skip-itk-build"
$build_command += " --skip-itk-wheel-build"

if ($setup_options.Length -gt 0) {
  $build_command += " $setup_options"
}
if ($cmake_options.Length -gt 0) {
  $build_command += " -- $cmake_options"
}
echo "Build command: $build_command"

# ---------------------------------------------------------------------------
# Build the target module
# ---------------------------------------------------------------------------
echo "Building target module ..."
iex $build_command