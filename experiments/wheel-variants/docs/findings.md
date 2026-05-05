# Findings — PEP 817 wheel variants for ITKPythonPackage

Companion to [`format-comparison.md`](format-comparison.md).

## Question and result

*Can the variants-enabled fork of `scikit-build-core` produce a PEP-817-shaped
wheel from a CMake-driven Python project, and can ITKPythonPackage's build
emit them natively?*

**Yes** on both. `pixi run build-pilot` produces a TBB-on variant wheel
(`label=tbbon`, property `itk::threading::tbb`) and a null-variant fallback,
each carrying the PEP 817 label suffix and a parsable `variant.json` in
`.dist-info/`. The same machinery is wired into the production build via the
`variant-build` pixi feature and the new opt-in flags on
`scripts/build_wheels.py`.

## Things that worked out-of-the-box

- The fork's `--config-setting` surface (`experimental=true`,
  `variant=ns::feat::value`, `variant-label=...`, `null-variant=true`).
- `variantlib`'s `VariantsJson` constructor for round-trip validation.
- The PEP 817 schema URL is embedded inside `variant.json` itself
  (`https://variants-schema.wheelnext.dev/v0.0.3.json`), so older or newer
  installers can fetch the right schema for any given wheel.
- `pip` rejects a variant-tagged wheel today as desired, so the format is
  safe to ship to PyPI now and have older installers ignore.

## Gotchas worth remembering

- **Build isolation must be off.** `python -m build`'s default isolated-venv
  mode resolves a vanilla `scikit-build-core` from PyPI and ignores the fork.
  Always run with `--no-isolation --skip-dependency-check`.
- **`null-variant` is mutually exclusive with `variant-label`.** The null
  label is implicit; passing both fails immediately.
- **Pixi feature merging is intersection,** so `feature.python-dev-pkgs`'s
  `scikit-build-core<0.12` pin would prevent the `0.12.3.dev` fork from
  resolving. The variant envs use a parallel `variant-python-dev-pkgs`
  feature that omits the pin.
- **Pixi drops unknown task flags.** `pixi run TASK --flag` silently swallows
  `--flag`; use `pixi run TASK -- --flag`.
- **`wheelnext/scikit-build-core@main` is stale.** Its
  `variant-hash-build-tag` branch encodes a *different* design (hash in PEP
  427 build-tag slot, not label suffix). The `henryiii/feat/variants` fork
  tracks the live PR and is the right pin.

## Production hook points

Native-build wiring (committed) and where future changes plug in:

| File | Lines | Role |
|---|---|---|
| `pixi.toml` | `[feature.variant-build]` block | Pulls scikit-build-core fork + variantlib via pypi-deps |
| `scripts/build_wheels.py` | `--wheel-variant`, `--wheel-variant-label`, `--null-variant` flags | CLI surface with env-var defaults and cross-flag validation |
| `scripts/build_python_instance_base.py` | `_variant_config_settings()` | Emits `--config-setting=variant-*` list, spliced into both `python -m build` invocations |
| `scripts/cmake_argument_builder.py` | future | If new `--config-setting=variant-*` shapes appear upstream, extend here |

## Risks

- **PR #1284 has not merged upstream;** API surface may shift.
- **PEP 817 schema URL** is currently `v0.0.3.json` and will move.
- **No PyPI-side variant resolution exists yet** — until pip/uv ship variant-aware
  install paths, only the producer side is exercised.
- **PEP 817 has no canonical JSON serialization** for `variant.json`, so byte-identical
  reproducibility across implementers is not guaranteed.

## Variant axes available in the project

- **TBB on/off** (`itk :: threading :: tbb`) — used by this experiment.
  `USE_TBB` is hard-coded per platform today (Linux=ON, macOS=OFF, Windows=ON);
  variants would let CI exercise the OFF case on Linux.
- **Conda-cache vs tarball-cache** (`ITKPYTHONPACKAGE_CACHE_SOURCE`) — natural
  fit for a `cache-source` namespace if both flavors ever ship.
- **Manylinux ABI tier** — already encoded in the platform tag, doesn't need variants.
- **Future GPU support** — direct fit for the canonical PEP 817 `gpu :: vendor :: cudaXX` example.
