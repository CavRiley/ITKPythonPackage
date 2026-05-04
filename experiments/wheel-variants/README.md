# PEP 817 wheel variants experiment

A self-contained sandbox for evaluating
[PEP 817 — Python Wheel Distribution Format for Variants](https://peps.python.org/pep-0817/)
against ITKPythonPackage's wheels. Owned by the
[`experiment/wheel-variants`](https://github.com/CavRiley/ITKPythonPackage/tree/experiment/wheel-variants)
branch on `cav` (the user's fork). Nothing under this directory is touched
by the production build path; nothing outside this directory is touched by
this experiment.

## Why

ITKPythonPackage today has several "variant-shaped" build axes that force
either separate package names (`itk-numerics`, `itk-meta`) or separate CI
matrices (TBB on/off per platform, conda-cache vs tarball-cache, manylinux
ABI tier, future GPU support). PEP 817 proposes a single distribution
publishing per-variant wheels, distinguished by a `variant.json` sidecar in
the dist-info plus a label suffix on the wheel filename. This experiment
evaluates whether that format works for ITK in two ways:

1. **Pilot** (`pilot/`) — build a tiny pybind11-based demonstrator wheel via
   the variants-enabled fork of scikit-build-core, end-to-end. Proves the
   build backend can produce a PEP-817-shaped wheel.
2. **Mock** (`mock/`) — take a real ITK wheel from the production build and
   reshape it into PEP 817 form using `wheelnext/variant-repack`. Proves
   ITK's existing wheel artifacts are format-compatible.

The chosen variant axis is **TBB on/off**, expressed as the property
`itk :: threading :: tbb` with label `tbbon` (vs a `null-variant` fallback
wheel for clients that do not understand variants).

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

## Running

```sh
cd experiments/wheel-variants
pixi install                         # set up sandbox env (pulls forks)
pixi run -- bash pilot/build_pilot.sh
ls pilot/dist/                       # expect two variant-tagged wheels
pixi run python pilot/inspect_wheel.py pilot/dist/*.whl

# Phase 2 (after dropping a real ITK wheel into mock/fixtures/):
pixi run -- bash mock/repack_itk_wheel.sh
pixi run python mock/validate_variant_wheel.py mock/fixtures/*-tbbon.whl
```

## Status

Reference plan: `~/.claude/plans/effervescent-sparking-hickey.md`.

Upstream PR being tracked: [scikit-build/scikit-build-core#1284](https://github.com/scikit-build/scikit-build-core/pull/1284).
