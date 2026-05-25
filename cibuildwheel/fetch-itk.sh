#!/usr/bin/env bash
# Resolve a pre-built ITK from ITKPythonBuilds and unpack it for a cibuildwheel
# remote-module build. Designed to be called from a module's [tool.cibuildwheel]
# before-all. Prints the suggested ITK_DIR (the cp311 build tree) as the LAST
# line of stdout.
#
# Inputs (environment):
#   ITK_PACKAGE_VERSION       Release tag, e.g. v6.0b02 (required).
#   ITKPYTHONBUILDS_TARBALL   Optional absolute path to a local .tar.zst; if set,
#                             skips the download (offline dev).
#   ITKPYTHONBUILDS_CACHE     Cache root (default: ~/.cache/itk-python-builds).
#   ITK_TARGET                Optional target platform, decoupled from the host so a
#                             macOS host can prepare a Linux tree (zstd on the host,
#                             tree consumed by a manylinux container via a mount).
#                             One of: macosx-arm64 | linux-aarch64.
#                             Default: auto-detect from uname.
#
# Supported targets (cp311): macOS arm64, manylinux_2_28 aarch64.
set -euo pipefail

: "${ITK_PACKAGE_VERSION:?set ITK_PACKAGE_VERSION (e.g. v6.0b02)}"
CACHE_ROOT="${ITKPYTHONBUILDS_CACHE:-$HOME/.cache/itk-python-builds}"

# --- target platform -> asset name + ITK build-tree subdir ----------------
target="${ITK_TARGET:-}"
if [ -z "$target" ]; then
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os/$arch" in
  Darwin/arm64) target="macosx-arm64" ;;
  Linux/aarch64) target="linux-aarch64" ;;
  *) echo "unsupported host $os/$arch; set ITK_TARGET explicitly" >&2 && exit 2 ;;
  esac
fi
case "$target" in
macosx-arm64)
  ASSET="ITKPythonBuilds-macosx-arm64.tar.zst"
  ITK_SUBDIR="ITKPythonPackage/ITK-3.11-macosx_arm64"
  ;;
linux-aarch64)
  ASSET="ITKPythonBuilds-linux-manylinux_2_28_aarch64.tar.zst"
  ITK_SUBDIR="ITKPythonPackage/ITK-cp311-cp311-manylinux_2_28_aarch64"
  ;;
*) echo "unknown ITK_TARGET=$target (want macosx-arm64 | linux-aarch64)" >&2 && exit 2 ;;
esac

TAG_DIR="$CACHE_ROOT/$ITK_PACKAGE_VERSION"
ITK_DIR="$TAG_DIR/$ITK_SUBDIR"

mkdir -p "$TAG_DIR"

# --- resolve the tarball: local override -> cache -> download -------------
if [ -n "${ITKPYTHONBUILDS_TARBALL:-}" ]; then
  TARBALL="$ITKPYTHONBUILDS_TARBALL"
  echo "Using local override tarball: $TARBALL" >&2
else
  TARBALL="$TAG_DIR/$ASSET"
  if [ ! -f "$TARBALL" ]; then
    URL="https://github.com/InsightSoftwareConsortium/ITKPythonBuilds/releases/download/$ITK_PACKAGE_VERSION/$ASSET"
    echo "Downloading $URL" >&2
    curl -L --fail -o "$TARBALL.partial" "$URL"
    mv "$TARBALL.partial" "$TARBALL"
  else
    echo "Using cached tarball: $TARBALL" >&2
  fi
fi

# --- unpack (idempotent; REQUIRES --long=31 for the 2GB window) -----------
# Marker is the per-target build tree itself, so macOS and Linux trees can
# coexist under one tag dir without one's unpack masking the other's.
if [ ! -f "$ITK_DIR/ITKConfig.cmake" ]; then
  echo "Unpacking $target into $TAG_DIR ..." >&2
  zstd -dc --long=31 "$TARBALL" | tar -xf - -C "$TAG_DIR"
else
  echo "Already unpacked: $ITK_DIR" >&2
fi

# --- verify + emit ITK_DIR ------------------------------------------------
if [ ! -f "$ITK_DIR/ITKConfig.cmake" ]; then
  echo "ERROR: ITKConfig.cmake not found at $ITK_DIR" >&2
  echo "Available build trees:" >&2
  ls -d "$TAG_DIR"/ITKPythonPackage/ITK-* 2>/dev/null >&2 || true
  exit 1
fi

# Last stdout line = the resolved ITK_DIR (consumed by callers/tests).
echo "$ITK_DIR"
