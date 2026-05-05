# PEP 817 wheel variants experiment

Evaluating [PEP 817 — Python Wheel Distribution Format for Variants](https://peps.python.org/pep-0817/)
for ITKPythonPackage. Variant axis: TBB on/off, expressed as
`itk :: threading :: tbb` with label `tbbon` (plus a `null-variant` fallback
for variant-unaware clients).

There are two paths in this branch:

1. **Native build (production path)** — the real ITK build emits PEP-817-shaped
   wheels directly via the `variant-build` pixi feature in the root
   `pixi.toml` and the `--wheel-variant` / `--wheel-variant-label` /
   `--null-variant` flags on `scripts/build_wheels.py`. Opt-in only.
2. **Sandbox pilot (this directory)** — a tiny pybind11 demonstrator
   (`pilot/`) for ~30s iteration when the full ITK build (1–2h) is too slow.

## Toolchain

| Repo | Pin |
|---|---|
| henryiii/scikit-build-core, branch `henryiii/feat/variants` (variants-enabled fork tracking the upstream PR) | git URL |
| wheelnext/variantlib (`variant.json` synthesis + parsing) | git URL |

`wheelnext/scikit-build-core@main` is stale and its `variant-hash-build-tag`
branch encodes a different design (hash in PEP 427 build-tag slot rather
than label suffix). The henryiii fork is the right pin.

## Layout

```
experiments/wheel-variants/
├── README.md
├── pixi.toml             # sandbox env (separate from root)
├── pilot/                # pybind11 demonstrator
│   ├── pyproject.toml
│   ├── CMakeLists.txt
│   ├── src/itk_variant_demo/{__init__.py,_demo.cpp}
│   ├── build_pilot.sh    # python -m build x2 with variant config-settings
│   └── inspect_wheel.py  # dump dist-info/variant.json + RECORD entries
└── docs/
    ├── format-comparison.md
    └── findings.md
```

## Running — production path

```sh
# TBB-on variant. The `--` separator is required so pixi forwards the
# script's flags instead of trying to parse them as its own.
pixi run -e variant-macosx-py311 build-itk-wheels -- \
    --wheel-variant 'itk::threading::tbb' \
    --wheel-variant-label tbbon

# Null-variant fallback
pixi run -e variant-macosx-py311 build-itk-wheels -- --null-variant

# Or via env vars
ITKPYTHONPACKAGE_WHEEL_VARIANT='itk::threading::tbb' \
ITKPYTHONPACKAGE_WHEEL_VARIANT_LABEL=tbbon \
    pixi run -e variant-macosx-py311 build-itk-wheels
```

> **Pixi gotcha:** `pixi run TASK --flag` silently drops `--flag`. Use
> `pixi run TASK -- --flag` for any flag pixi doesn't recognize.

Available variant envs: `variant-{macosx,linux,manylinux228,windows}-py311`.
Default envs (`manylinux228-py311`, `macosx-py311`, ...) are untouched.

## Running — sandbox pilot

```sh
cd experiments/wheel-variants
pixi install
pixi run build-pilot      # ~30s, builds two variant-tagged pilot wheels
pixi run inspect-pilot    # dump dist-info/variant.json + RECORD entries
```

## Status

Plan: `~/.claude/plans/effervescent-sparking-hickey.md`.

Upstream PR tracked: scikit-build-core PR 1284.
