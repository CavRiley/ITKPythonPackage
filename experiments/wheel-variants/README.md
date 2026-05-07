# PEP 817 wheel variants experiment

Evaluating [PEP 817 — Python Wheel Distribution Format for Variants](https://peps.python.org/pep-0817/)
for ITKPythonPackage. The current variant axis is the upstream
`x86_64::level::v{1,2,3,4}` microarchitecture namespace, backed by
[`wheelnext/provider-variant-x86-64`](https://github.com/wheelnext/provider-variant-x86-64);
a `null-variant` fallback wheel is also produced for variant-unaware
clients. The earlier ad-hoc `itk::threading::tbb` axis was retired once
the upstream provider became available.

## Where the wiring lives

| Site | Role |
|---|---|
| `pixi.toml` `[feature.variant-build]` | Pulls the variants-enabled scikit-build-core fork, `variantlib`, and `provider-variant-x86-64` via git pypi-deps. Used only by `variant-*` envs. |
| `scripts/pyproject.toml.in` | Templated `[build-system].requires` and trailing `[variant.providers.x86_64]` block, gated by two new placeholders. Stock builds render byte-identical output. |
| `scripts/pyproject_configure.py` | `_build_variant_pyproject_strings()` populates the placeholders from `package_env_config["WHEEL_VARIANTS"]`. |
| `scripts/build_wheels.py` | CLI flags `--wheel-variant`, `--wheel-variant-label`, `--null-variant` (env-var equivalents `ITKPYTHONPACKAGE_*`). |
| `scripts/build_python_instance_base.py` `_variant_config_settings()` | Emits the `--config-setting=variant-*` list spliced into both `python -m build` invocations. |

## Toolchain pins

| Repo | Source |
|---|---|
| henryiii/scikit-build-core, branch `henryiii/feat/variants` | git URL (variants-enabled fork tracking PR 1284) |
| wheelnext/variantlib | git URL |
| wheelnext/provider-variant-x86-64 | git URL |

`wheelnext/scikit-build-core@main` is stale and its
`variant-hash-build-tag` branch encodes a different design (hash in PEP
427 build-tag slot rather than label suffix). The henryiii fork is the
right pin.

## Reproducing the demo

```sh
ITKPYTHONPACKAGE_WHEEL_VARIANT='x86_64::level::v3' \
ITKPYTHONPACKAGE_WHEEL_VARIANT_LABEL='x86_64v3' \
pixi run -e variant-macosx-py311 build-itk-wheels -- \
    --build-dir-root /path/to/scratch \
    --platform-env variant-macosx-py311

# The ITK wheels produced under dist/ carry the `-x86_64v3` label
# suffix and a populated [variant.providers.x86_64] block in variant.json.

# Null-variant fallback (no property declared)
pixi run -e variant-macosx-py311 build-itk-wheels -- --null-variant
```

> `pixi run TASK --flag` silently drops `--flag`. Use
> `pixi run TASK -- --flag` for any flag pixi doesn't recognize.

Available variant envs: `variant-{macosx,linux,manylinux228,windows}-py311`.
Stock envs (`manylinux228-py311`, `macosx-py311`, ...) are unaffected.

## Layout

```
experiments/wheel-variants/
├── README.md
└── docs/
    ├── format-comparison.md   # stock vs variant wheel; ad-hoc vs provider-backed variant.json
    └── findings.md            # gotchas, hook points, provider-plugin notes
```

The earlier `pilot/` pybind11 demonstrator and `mock/` post-process
repacker were both removed once the ITK wheel build itself could prove
the same point — see [`docs/findings.md`](docs/findings.md) for the
phase log.

## Status

Upstream PR tracked: scikit-build-core PR 1284. PEP 817 itself is in
draft. Verification on x86_64 hosts (where the provider can answer "yes,
this level is supported") is a future step; macOS arm64 covers the
format and plumbing exhaustively.
