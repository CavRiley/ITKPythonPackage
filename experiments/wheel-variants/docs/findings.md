# Findings — PEP 817 wheel variants for ITKPythonPackage

Companion to [`format-comparison.md`](format-comparison.md).

## Question and result

*Can the variants-enabled fork of `scikit-build-core` produce a
PEP-817-shaped wheel from the ITK wheel build, and can a real upstream
provider plugin (`wheelnext/provider-variant-x86-64`) be wired into the
ITK pyproject.toml without disturbing stock builds?*

**Yes** on both. The ITK wheel build emits an `x86_64v3`-labelled wheel
when `ITKPYTHONPACKAGE_WHEEL_VARIANT='x86_64::level::v3'` is set; a
null-variant fallback covers variant-unaware clients. The provider
plugin appears in `[variant.providers.x86_64]` of the rendered
pyproject.toml when (and only when) variants are active — stock builds
render byte-identical pyproject.toml output. The earlier ad-hoc
`itk::threading::tbb` axis demonstrated the format shape; the
provider-backed `x86_64::level::v3` axis demonstrates resolution-time
metadata as well.

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

## Hook points in the ITK wheel build

| File | Site | Role |
|---|---|---|
| `pixi.toml` | `[feature.variant-build]` block | Pulls scikit-build-core fork, variantlib, and `provider-variant-x86-64` via git pypi-deps |
| `scripts/pyproject.toml.in` | line 4 + trailing placeholder | Templated `[build-system].requires` and `[variant.providers.x86_64]` block, gated by `@PYPROJECT_BUILD_SYSTEM_REQUIRES@` and `@PYPROJECT_VARIANT_BLOCK@` |
| `scripts/pyproject_configure.py` | `_build_variant_pyproject_strings()` | Reads `WHEEL_VARIANTS` / `WHEEL_NULL_VARIANT` from `package_env_config` and renders the two placeholders; uses the existing engine's `remove_line_if_empty` + `newline_if_set` so stock builds emit byte-identical output |
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

- **x86_64 microarchitecture level** (`x86_64::level::v{1,2,3,4}`) — the
  current experiment. Backed by the upstream
  `wheelnext/provider-variant-x86-64` plugin. Maps to `-march=` flags
  via the provider; could let CI ship one wheel per microarch tier
  rather than always targeting the lowest-common-denominator baseline.
- **TBB on/off** (`itk :: threading :: tbb`) — earlier ad-hoc axis,
  retired from the demo when the upstream provider became available.
  Could return as a real provider if a project-local plugin is written;
  `USE_TBB` is hard-coded per platform today (Linux=ON, macOS=OFF,
  Windows=ON), and variants would let CI exercise the OFF case on Linux.
- **Conda-cache vs tarball-cache** (`ITKPYTHONPACKAGE_CACHE_SOURCE`) —
  natural fit for a `cache-source` namespace if both flavours ever ship.
- **Manylinux ABI tier** — already encoded in the platform tag, doesn't
  need variants.
- **Future GPU support** — direct fit for the canonical PEP 817
  `gpu::vendor::cudaXX` example, and a wheelnext provider analogous to
  `provider-variant-x86-64` would be the right model.

## Adding a real provider plugin

The previous phases left `variant.json` with empty `providers` and
`default-priorities.namespace` because the `itk` namespace had no
plugin to register. Wiring `wheelnext/provider-variant-x86-64` populates
both fields and makes the wheel install-time-resolvable.

**Stanza emitted into pyproject.toml when variants are active** (see
[`format-comparison.md`](format-comparison.md) § 7 for the full file):

```toml
[build-system]
requires = ["scikit-build-core", "provider-variant-x86-64"]

[variant.default-priorities]
namespace = ["x86_64"]

[variant.providers.x86_64]
requires = ["provider-variant-x86-64"]
plugin-api = "provider_variant_x86_64"
```

**Build CLI emitted by `_variant_config_settings()`:**

```
--config-setting=experimental=true
--config-setting=variant-label=x86_64v3
--config-setting=variant=x86_64::level::v3
```

**Host query** (the install-time question, run on the build host today):

```
$ pixi run -e variant-macosx-py311 \
    variantlib plugins get-configs -s -n x86_64
# (empty on macOS arm64 — the provider correctly reports that no
#  x86_64 microarch level applies to this CPU)
```

This *is* a passing result — it proves the plugin is loaded and
reachable via the `variant_plugins` entry-point group, and that the
install-time check is wired up; the host simply isn't an x86_64
machine. A second verification pass on Linux x86_64 (where the
provider returns `v1..v3` or higher) would close the loop on the
resolution side.

**Why this matters for ITK specifically.** Most ITK variant axes
(USE_TBB, GPU backends, manylinux ABI tier) are project-local and don't
have an upstream provider. Demonstrating the wiring against a stable
upstream plugin first means future ITK-internal axes can follow the
same template (write a provider, declare it in
`[variant.providers.<ns>]`, ship it as a build requirement) instead of
re-litigating the integration shape per axis.

## Phase log

- **Phase 1 (`b1ab68e`).** Sandbox scaffold: `experiments/wheel-variants/{pilot,docs}/` and a standalone pixi env pinning the henryiii fork.
- **Phase 2 (`bf30620`).** Format mock + post-process repacker (`mock/`) for taking an existing ITK wheel and reshaping it into PEP 817 form.
- **Phase 3 (`a80adb8`).** Native-build wiring: variant CLI flags + `_variant_config_settings()` spliced into the ITK wheel build.
- **Phase 4 (`65dd9cf`, `e743fe6`, `06ef6f2`).** Mock removal + 3-segment env-name fix + docs refresh.
- **Phase 5 (this phase).** Pilot removal; provider plugin wired through templating; docs refresh again.
