# Findings — PEP 817 wheel variants for ITKPythonPackage

A thesis-ready summary of what this experiment learned. Companion to
[`format-comparison.md`](format-comparison.md), which carries the raw
side-by-side artifact.

## Hypothesis evaluated

Two empirical questions, from the original plan:

1. *Can the variants-enabled fork of `scikit-build-core` produce a
   PEP-817-shaped wheel from a real CMake-driven Python project?*
2. *Is ITK's existing wheel format compatible with PEP 817 once a
   `variant.json` sidecar and label suffix are applied?*

## Result

Both questions answer **yes**, on the strength of two end-to-end
demonstrations and one cross-check:

- **Phase 1** (`pixi run build-pilot`): the
  `henryiii/scikit-build-core@henryiii/feat/variants` fork builds the
  `pilot/` pybind11 project twice — once as a TBB-on variant
  (`label=tbbon`, property `itk::threading::tbb`) and once as the
  null-variant fallback. Both wheels carry the PEP 817 label suffix,
  both contain a parsable `variant.json` in `.dist-info/`, and the
  fork's emitter automatically pulls `variantlib` in as a build dep
  when variants are active.

- **Phase 2** (`pixi run repack-itk`; `pixi run validate-itk`): the
  custom `mock/make_variant_wheel.py` takes an ordinary wheel and
  rewrites it into a PEP-817-shaped variant wheel with byte-equal
  payloads but a new `variant.json` sidecar and a fully recomputed
  `RECORD`. The validator confirms every entry's hash + size matches.

- **Cross-check**: the same validator passes both pipelines' output —
  fork-built wheels and post-process-mocked wheels both clear the
  same external check. That means the mock isn't producing a
  validator-dependent shape, and the validator isn't too lax.

Therefore: **ITK's existing wheel artifacts are format-compatible with
PEP 817**, and a wheel-variant pipeline could be plugged into the
existing `BuildWheelsSupport/` flow without touching the C++ side.

## What worked out-of-the-box

- The fork's `--config-setting` surface (`experimental=true`,
  `variant=ns::feat::value`, `variant-label=...`, `null-variant=true`)
  matched the source code reading from PR #1284 with no surprises.
- `variantlib`'s `VariantsJson` constructor accepts a parsed
  `variant.json` payload and validates it without complaint, which is
  what `validate_variant_wheel.py` relies on.
- The PEP 817 schema URL is **embedded inside `variant.json` itself**
  (currently `https://variants-schema.wheelnext.dev/v0.0.3.json`), so a
  stable wheel survives spec churn — installers can fetch the schema
  pinned at build time rather than the latest.
- `pip` rejects a variant-tagged wheel today, as desired, so the format
  is safe to ship to PyPI now and have older installers ignore.

## What did not work

- **`wheelnext/variant-repack@master`** is currently unusable. Its
  `commands/build.py` imports `VARIANT_LABEL_LENGTH` from
  `variantlib.constants`, but no tagged release of `variantlib` —
  including the latest `v0.0.3` that ships on `main` — defines that
  symbol. The CLI fails on import. The plan's documented fallback
  (`mock/make_variant_wheel.py`, ~150 lines of zip + RECORD logic
  that drives `variantlib`'s working APIs directly) was the
  workaround.
- **`wheelnext/scikit-build-core@main`** is **stale** (last variants
  work absent; default branch matches the upstream `scikit-build-core`
  from mid-2025). Its `variant-hash-build-tag` branch encodes a
  *different* design (variant hash in the PEP 427 build-tag slot)
  rather than the filename-suffix approach in PR #1284. The plan
  correctly fell back to the `henryiii` fork — there is currently no
  wheelnext-blessed branch that tracks the PR.
- **Build isolation must be off.** `python -m build`'s default
  isolated-venv mode resolves a vanilla `scikit-build-core` from PyPI
  and ignores the fork in pixi's env, producing
  `Unrecognized options in config-settings: variant variant-label`.
  Always run with `--no-isolation --skip-dependency-check` (which is
  also what production `scripts/build_python_instance_base.py` does
  for ITK's actual wheel build, line ~1240).
- **`null-variant` is mutually exclusive with `variant-label`.** The
  fork enforces this (the null label is implicit). A first-pass driver
  that passes both fails immediately. Worth flagging when designing
  the production-side hook: callers should treat `null-variant` as a
  separate code path.

## Format-stability concerns worth flagging

The two pipelines (fork-built null wheel; mock-built tbbon wheel)
both produce valid `variant.json` payloads, but their
**byte-level serializations differ**: the fork uses 4-space JSON indent;
the mock uses 2-space. The two payloads parse identically through
`variantlib`. PEP 817 (as published) does not yet specify a canonical
serialization, so this is a real ecosystem gap that has implications:

- **Reproducibility** across implementations is not guaranteed.
- **Content-addressable distribution** (sha256-keyed wheel caches like
  pip's) will treat the two `variant.json`s as different files even
  when they describe the same variant.
- **Multi-implementer agreement** on a canonical form (probably
  `json.dumps(payload, indent=2, sort_keys=True)` or similar) would
  resolve this. It belongs in the next PEP 817 revision.

ITKPythonPackage should document the JSON form it produces in any
production rollout, not rely on cross-implementation byte-equality.

## Where this would plug into the production build path

Reference call sites (read-only inspection — not edited in this
experiment, per the plan's pass criterion #4):

| Hook point | File | Lines | What changes when variants ship |
|---|---|---|---|
| ITK wheel build invocation | `scripts/build_python_instance_base.py` | ~1240–1276 | Append three to four extra `--config-setting=` flags: `experimental=true`, `variant-label=<label>` (or `null-variant=true`), and one or more `variant=ns::feat::value` |
| Remote module wheel build invocation | `scripts/build_python_instance_base.py` | ~1149–1200 | Same as above |
| CMake-arg → config-setting translation | `scripts/cmake_argument_builder.py` | ~94–104 | Add a parallel `getPythonBuildVariantsArguments()` method that emits `--config-setting=variant-*` |
| Per-platform fixup (delocate / delvewheel / auditwheel) | `scripts/{linux,macos,windows}_build_python_instance.py` | varies | Wheel-tag retag logic must learn the new label slot — currently retags assume `cp3xx-cp3xx-<plat>`, will need `cp3xx-cp3xx-<plat>-<label>` |
| Build-system requires | `scripts/pyproject.toml.in` | line 4 | Add `variantlib` to `requires` when variants are active (the fork already auto-injects this on top of what's declared, but the explicit form is cleaner) |
| pixi `scikit-build-core` pin | `pixi.toml` | line 42 | Either bump to `0.12.x` once the variants PR merges, or use a git source on the fork during the trial period |

The variant axis chosen for this experiment (TBB on/off as
`itk :: threading :: tbb`) has a real shape in the production build:
`USE_TBB` is hard-coded per platform today (Linux=ON, macOS=OFF,
Windows=ON, see the platform subclasses' `prepare_build_env()`). A real
production rollout would let CI actually exercise the OFF case on Linux,
which currently has no testing path.

Other variant axes the project has but doesn't currently expose:

- **Conda-cache vs tarball-cache** (`ITKPYTHONPACKAGE_CACHE_SOURCE`) —
  produces different binary deps, but resolved purely at build time.
  A natural fit for `itk :: cache-source :: {conda, tarball}` if the
  project ever wants to publish both.
- **Manylinux ABI tier** (`_2_28` vs `_2_34`) — currently encoded in
  the platform tag, so it does not need variants. Listing it in
  `findings.md` only to rule it out.
- **Future GPU support** — the variant of choice for this thesis if
  ITK ever ships a CUDA-accelerated wheel. PEP 817's motivating
  example (`gpu :: vendor :: cuda12` etc.) maps directly.

## Risks for a production rollout

1. **PR #1284 has not merged upstream.** API surface (config-setting
   names, `variant.json` schema) may shift. The experiment was small on
   purpose so a re-iteration after upstream changes is cheap.
2. **PEP 817 itself is still evolving.** The `v0.0.3` schema URL in
   `variant.json` will (eventually) become `v0.1.0`, `v1.0.0`, etc.
3. **No PyPI-side variant resolution exists yet.** Until pip/uv ship
   variant-aware install paths, the only consumers of variant-labeled
   wheels are operators who manually rename the file or hand the URL
   to a custom installer. This experiment validates the **producer**
   side; the **consumer** side is not yet operational anywhere.
4. **`variant-repack`'s broken state means the wheelnext toolchain is
   not yet a reliable post-process step** for projects that don't want
   to depend on `scikit-build-core`'s build-time emitter. Anyone wanting
   to add variants to existing CI artifacts (e.g. taking artifacts from
   `ITKPythonBuilds` releases and labeling them) will need to write
   their own repack — like this experiment did — until the wheelnext
   stack stabilizes.

## Pivot to native-build (production path) — 2026-05-04

The original conclusion below recommended *not* wiring variants into
production yet, treating the experiment as reference-only. The user
chose to move forward with a native-build integration anyway, on the
strength of the format-compatibility result. The production-path wiring
is now committed to this branch and works end-to-end via:

```sh
pixi run -e variant-macosx-py311 build-itk-wheels \
    --wheel-variant 'itk::threading::tbb' --wheel-variant-label tbbon
```

(or the `ITKPYTHONPACKAGE_WHEEL_VARIANT[_LABEL]` /
`ITKPYTHONPACKAGE_NULL_VARIANT` env vars).

### What the production wiring adds

- **`pixi.toml`:** new `[feature.variant-build]` (scikit-build-core fork
  + variantlib via pypi-deps) and `[feature.variant-python-dev-pkgs]`
  (mirror of `python-dev-pkgs` minus the conda `scikit-build-core` pin
  — pixi feature merging is intersection so the upper bound `<0.12.0`
  would otherwise prevent the `0.12.3.dev` fork from resolving). Four
  new environments: `variant-{macosx,linux,manylinux228,windows}-py311`.
- **`scripts/build_wheels.py`:** three new CLI flags
  (`--wheel-variant`, repeatable; `--wheel-variant-label`;
  `--null-variant`). Cross-flag validation + env-var defaults.
- **`scripts/build_python_instance_base.py`:** a small
  `_variant_config_settings` helper on `BuildPythonInstanceBase` that
  emits the right `--config-setting=variant-*` list (or `[]` for the
  production-default case). Spliced into both `python -m build`
  invocations (`build_external_module_wheel` and
  `build_itk_python_wheels`) just before `echo_check_call`.

### Properties preserved by the production wiring

- **Opt-in only.** Default-off via the flags/env vars. Production envs
  (`manylinux228-py311`, `macosx-py311`, `windows-py311`) continue to
  emit identical non-variant wheels.
- **No post-processing.** Wheels emerge with the label suffix and
  `variant.json` sidecar directly from `python -m build`, not via
  repack. ITK's binary `.so`/`.dylib`/`.pyd` payloads are byte-identical
  to a non-variant build of the same source.
- **Validation up front.** Property regex (`namespace::feature::value`,
  lowercase + `_`/`.`) and label regex (`[0-9a-z._]{1,16}`) are both
  enforced before the build backend sees them, so a typo fails fast
  with a clean error rather than mid-build.

### What does NOT change

The mock/repack path in `mock/` is retained as a format-validation
reference but is no longer the production approach. The `wheelnext/variant-repack@master`
breakage (importing `VARIANT_LABEL_LENGTH` from `variantlib.constants`
where no tagged release exposes it) is documented but not blocking
since the production path doesn't depend on it.

---

## Original recommendation (pre-pivot)

For ITKPythonPackage's production build:

- **Do not** wire variants into the production pipeline yet. PR #1284
  is a draft, the wheelnext post-process tooling is broken end-to-end,
  and there is no installer-side resolution to consume the output.
- **Do** keep this sandbox in tree on `experiment/wheel-variants` as a
  reference implementation. When the PEP 817 ecosystem stabilizes
  (pip ships variant-aware resolution; `variant-repack` and
  `variantlib` agree on a tagged release), the production hook points
  in `build_python_instance_base.py` and `cmake_argument_builder.py`
  are pre-mapped above and the changes are mechanical.
- **Track upstream:** [PR #1284](https://github.com/scikit-build/scikit-build-core/pull/1284),
  [PEP 817 status on python.org](https://peps.python.org/pep-0817/),
  and the wheelnext org's progress on a
  variant-aware pip fork.

## Repository

Branch: `experiment/wheel-variants` on `cav` (CavRiley/ITKPythonPackage).

Plan file: `~/.claude/plans/effervescent-sparking-hickey.md`.
