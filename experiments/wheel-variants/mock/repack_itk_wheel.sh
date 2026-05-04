#!/usr/bin/env bash
# Repack the first .whl found in mock/fixtures/ as a TBB-on PEP 817 variant
# wheel. Calls make_variant_wheel.py with the canonical settings used in this
# experiment (property=itk::threading::tbb, label=tbbon).
#
# Usage (from experiments/wheel-variants/):
#   pixi run -- bash mock/repack_itk_wheel.sh
#
# To repack a specific wheel or use a different label, call make_variant_wheel.py
# directly:
#   pixi run python mock/make_variant_wheel.py -i path/to/wheel.whl -p itk::threading::tbb -l tbbon

set -euo pipefail

MOCK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="${MOCK_DIR}/fixtures"

# Pick the first .whl that is NOT already a variant-tagged output.
shopt -s nullglob
candidates=()
for whl in "${FIXTURES_DIR}"/*.whl; do
  case "${whl}" in
  *-tbbon.whl | *-null.whl) ;; # already a variant, skip
  *) candidates+=("${whl}") ;;
  esac
done

if [[ ${#candidates[@]} -eq 0 ]]; then
  echo "error: no candidate wheel in ${FIXTURES_DIR} (drop a real itk-*.whl there)" >&2
  exit 1
fi

INPUT="${candidates[0]}"
echo "==> Repacking ${INPUT}"

python "${MOCK_DIR}/make_variant_wheel.py" \
  --input "${INPUT}" \
  --property itk::threading::tbb \
  --label tbbon

echo "==> Output:"
ls -la "${FIXTURES_DIR}"/*-tbbon.whl
