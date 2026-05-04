# PEP 817 wheel variants experiment

Two experiment paths for evaluating
[PEP 817 — Python Wheel Distribution Format for Variants](https://peps.python.org/pep-0817/)
against ITKPythonPackage's wheels, on the
[`experiment/wheel-variants`](https://github.com/CavRiley/ITKPythonPackage/tree/experiment/wheel-variants)
branch on `cav`:

1. **Native build (production path, primary deliverable)** — the real ITK
   build emits PEP-817-shaped wheels directly when invoked through the new
   `variant-build` pixi feature in the **root** `pixi.toml` and the new
   `--wheel-variant` / `--wheel-variant-label` / `--null-variant` flags on
   `scripts/build_wheels.py`. Opt-in only; production envs are unaffected.
2. **Sandbox demonstrators (this directory)** — a `pilot/` pybind11 module
   for fast end-to-end iteration, plus a `mock/` post-process tool kept as a
   reference for the format-shape claims. Useful for thesis writeups and
   format validation; **not** the production path.

## Why

ITKPythonPackage today has several "variant-shaped" build axes that force
either separate package names (`itk-numerics`, `itk-meta`) or separate CI
matrices (TBB on/off per platform, conda-cache vs tarball-cache, manylinux
ABI tier, future GPU support). PEP 817 proposes a single distribution
publishing per-variant wheels, distinguished by a `variant.json` sidecar in
the dist-info plus a label suffix on the wheel filename.

The chosen variant axis for this experiment is **TBB on/off**, expressed as
the property `itk :: threading :: tbb` with label `tbbon` (vs a
`null-variant` fallback wheel for clients that do not understand variants).

## Toolchain

The reference implementation lives in the [wheelnext GitHub
organization](https://github.com/wheelnext):

| Repo | Used for | Pin |
|---|---|---|
| `henryiii/scikit-build-core` (`henryiii/feat/variants` branch) | Build backend with variant config-settings | git URL in `pixi.toml` |
| `wheelnext/variantlib` | `variant.json` synthesis and parsing | git URL in `pixi.toml` |
| `wheelnext/variant-repack` | Post-process a built wheel to add variant metadata | git URL in `pixi.toml` |
| `wheelnext/variants-schema` | Schema reference for `variant.json` | read-only reference |

`wheelnext/scikit-build-core@main` is stale (last variants-related work absent;
its `variant-hash-build-tag` branch encodes a *different* design — variant
hash in the PEP 427 build-tag slot — so it is not interchangeable with the
filename-label-suffix approach in PR #1284). The henryiii fork tracks the
PR head and is the right pin for this experiment.

## Layout

```
experiments/wheel-variants/
├── README.md                 # this file
├── pixi.toml                 # sandbox env; pulls scikit-build-core + variantlib + variant-repack from forks
├── .gitignore                # ignore .pixi/, build/, dist/
├── pilot/                    # Phase 1: end-to-end demonstrator
│   ├── pyproject.toml        # uses scikit_build_core.build backend
│   ├── CMakeLists.txt        # trivial pybind11 module
│   ├── src/itk_variant_demo/__init__.py
│   ├── src/itk_variant_demo/_demo.cpp
│   ├── build_pilot.sh        # runs python -m build twice with variant config-settings
│   └── inspect_wheel.py      # dumps dist-info/variant.json + RECORD entries
├── mock/                     # Phase 2: format-mock onto a real ITK wheel
│   ├── repack_itk_wheel.sh   # thin wrapper around variant-repack build
│   ├── validate_variant_wheel.py
│   └── fixtures/
│       └── README.md         # how to drop in a real itk-*.whl
└── docs/                     # Phase 3
    ├── format-comparison.md  # standard vs variant wheel, side-by-side
    └── findings.md           # thesis-ready summary
```

## Running — production path (real ITK build)

From the **repo root**, using the `variant-build` pixi feature added to the
root `pixi.toml`:

```sh
# TBB-on variant. The `--` separator is required so pixi forwards the
# script's flags instead of trying to parse them as its own.
pixi run -e variant-macosx-py311 build-itk-wheels -- \
    --wheel-variant 'itk::threading::tbb' \
    --wheel-variant-label tbbon

# Null-variant fallback (PEP 817 publishers should ship one alongside)
pixi run -e variant-macosx-py311 build-itk-wheels -- --null-variant

# Or via env vars (parity with ITK_PACKAGE_VERSION style — no `--` needed
# because no extra args are passed to the script):
ITKPYTHONPACKAGE_WHEEL_VARIANT='itk::threading::tbb' \
ITKPYTHONPACKAGE_WHEEL_VARIANT_LABEL=tbbon \
    pixi run -e variant-macosx-py311 build-itk-wheels
```

> **Pixi gotcha:** `pixi run TASK --some-flag` silently drops `--some-flag`
> when pixi can't determine whether it's a pixi flag or a task flag. Always
> use `pixi run TASK -- --some-flag` for any task that takes flags pixi
> doesn't know about.

Available variant envs in the root `pixi.toml`:
`variant-macosx-py311`, `variant-linux-py311`, `variant-manylinux228-py311`,
`variant-windows-py311`. Default production envs (`manylinux228-py311`,
`macosx-py311`, ...) are unaffected — they continue to use the stock
scikit-build-core pin and never see variant config-settings.

ITK builds are slow (1–2 hours) — the pilot below is the fast iteration loop.

## Running — sandbox demonstrators

```sh
cd experiments/wheel-variants
pixi install                         # local sandbox env (separate from root)
pixi run build-pilot                 # ~30s, builds two variant-tagged pilot wheels
pixi run inspect-pilot               # dump dist-info/variant.json + RECORD entries
pixi run validate-pilot              # cross-check format with our validator
```

The `mock/` directory contains the post-process repack tool used in earlier
phases. Retained as a reference; not the production path. See
[`docs/findings.md`](docs/findings.md) for the design pivot rationale.

## Status

Reference plan: `~/.claude/plans/effervescent-sparking-hickey.md`.

Upstream PR being tracked: [scikit-build/scikit-build-core#1284](https://github.com/scikit-build/scikit-build-core/pull/1284).
