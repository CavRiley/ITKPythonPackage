#!/usr/bin/env bash
# Build the pilot demonstrator twice: once as a TBB-on variant, once as the
# null-variant fallback. The two wheels prove the variants-enabled fork
# (henryiii/scikit-build-core@henryiii/feat/variants) emits PEP-817-shaped
# filenames + a variant.json sidecar in dist-info.
#
# Usage (from experiments/wheel-variants/):
#   pixi run -- bash pilot/build_pilot.sh
#
# Outputs land in pilot/dist/.

set -euo pipefail

PILOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${PILOT_DIR}"

rm -rf dist build _skbuild
mkdir -p dist

echo "==> Variant A: TBB on (label=tbbon)"
python -m build --wheel . \
  --outdir dist \
  --no-isolation --skip-dependency-check \
  --config-setting=experimental=true \
  --config-setting=variant=itk::threading::tbb \
  --config-setting=variant-label=tbbon \
  --config-setting=cmake.define.ITK_VARIANT_DEMO_TBB=ON

echo "==> Variant B: null-variant fallback"
# Per the variants fork, null-variant is mutually exclusive with
# variant-label — the "null" label is applied automatically.
python -m build --wheel . \
  --outdir dist \
  --no-isolation --skip-dependency-check \
  --config-setting=experimental=true \
  --config-setting=null-variant=true \
  --config-setting=cmake.define.ITK_VARIANT_DEMO_TBB=OFF

echo "==> Built wheels:"
ls -la dist/
