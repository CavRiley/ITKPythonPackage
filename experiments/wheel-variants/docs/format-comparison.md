# Format comparison — stock wheel vs PEP 817 variant wheel

This figure pairs a stock wheel with the variant-tagged wheel emitted by
the variants-enabled scikit-build-core fork. Both were built from the
trivial `pilot/` pybind11 module on macOS arm64 / CPython 3.12. The "stock"
column is the `null-variant` fallback wheel — the fork's PEP-817-shaped
"no properties" output — which serves as a clean baseline since nothing
changes except the variant identity. A real ITK wheel would behave the
same way (the binary `.so`/`.dylib`/`.pyd` payloads are not touched).

## 1. Filename

```
stock:  itk_variant_demo-0.0.1-cp312-cp312-macosx_15_0_arm64.whl
variant: itk_variant_demo-0.0.1-cp312-cp312-macosx_15_0_arm64-tbbon.whl
                                                              ^^^^^^
                                                              variant label
```

PEP 817 reserves a new label slot at the end of the filename. The label
must match `[0-9a-z._]{1,16}`. Old installers parse it as part of the
platform tag and refuse the wheel as not-applicable, which is exactly the
opt-out behavior PEP 817 wants for installers that are unaware of variants.

## 2. Zip listing

Same set of entries; the variant differs from the stock only in
`variant.json` (different content) and `_demo.cpython-312-darwin.so`
(different binary because the TBB-on build defines `ITK_VARIANT_DEMO_TBB=1`).
The `.so` files happen to be the same size in this trivial demo but their
sha256 hashes differ — see § 4.

| Path | Stock | Variant |
|---|---:|---:|
| `itk_variant_demo-0.0.1.dist-info/METADATA` | 236 B | 236 B |
| `itk_variant_demo-0.0.1.dist-info/RECORD` | 602 B | 602 B |
| `itk_variant_demo-0.0.1.dist-info/WHEEL` | 131 B | 131 B |
| `itk_variant_demo-0.0.1.dist-info/variant.json` | **194 B** | **314 B** |
| `itk_variant_demo/__init__.py` | 58 B | 58 B |
| `itk_variant_demo/_demo.cpp` | 414 B | 414 B |
| `itk_variant_demo/_demo.cpython-312-darwin.so` | 148 232 B | 148 232 B |

## 3. `variant.json` content

**Stock (null variant fallback):**

```json
{
    "$schema": "https://variants-schema.wheelnext.dev/v0.0.3.json",
    "default-priorities": {
        "namespace": []
    },
    "providers": {},
    "variants": {
        "null": {}
    }
}
```

**Variant (tbbon):**

```json
{
    "$schema": "https://variants-schema.wheelnext.dev/v0.0.3.json",
    "default-priorities": {
        "namespace": []
    },
    "providers": {},
    "variants": {
        "tbbon": {
            "itk": {
                "threading": [
                    "tbb"
                ]
            }
        }
    }
}
```

Two things to notice:

1. The `$schema` URL is embedded inside the file, so installers can fetch
   the right schema for any wheel at parse time — making `variant.json`
   self-describing in a way the `WHEEL` file is not.
2. `variants` is a map keyed by label. Each wheel today carries one entry,
   but the structure leaves room for a future "fat" wheel that carries
   multiple variants in one file.

## 4. `RECORD` content

**Stock:**

```
itk_variant_demo/__init__.py,sha256=Zvr_rr_M4S23MQOfq3nl9BcYnU37yRFpWZoFqM2HaVE,58
itk_variant_demo/_demo.cpp,sha256=AxM0nISmp4a6az1PYGAcz4gc4HMsaMQ1wde_-HWGdGM,414
itk_variant_demo/_demo.cpython-312-darwin.so,sha256=Zf-_02zs64mqoS7py1FHejqOJclmaZq6yb5XA8UlYd4,148232
itk_variant_demo-0.0.1.dist-info/METADATA,sha256=ZjwudxnjqxZdvCLCjLl1kpoJljmjLnL01_z0-QyhkRM,236
itk_variant_demo-0.0.1.dist-info/WHEEL,sha256=owkrl7Nk171deLp5sQB_yH3crvR9P4H6K6uM5IBlTBA,131
itk_variant_demo-0.0.1.dist-info/variant.json,sha256=N0_-KEdB5DOkINATJdkyfXtpAs075SLai0rSvB-beBE,194
itk_variant_demo-0.0.1.dist-info/RECORD,,
```

**Variant:**

```
itk_variant_demo/__init__.py,sha256=Zvr_rr_M4S23MQOfq3nl9BcYnU37yRFpWZoFqM2HaVE,58
itk_variant_demo/_demo.cpp,sha256=AxM0nISmp4a6az1PYGAcz4gc4HMsaMQ1wde_-HWGdGM,414
itk_variant_demo/_demo.cpython-312-darwin.so,sha256=5UECkwZM4e00rZUy0foH2vengw2Q1UIEfTCVRJNT7pA,148232
itk_variant_demo-0.0.1.dist-info/METADATA,sha256=ZjwudxnjqxZdvCLCjLl1kpoJljmjLnL01_z0-QyhkRM,236
itk_variant_demo-0.0.1.dist-info/WHEEL,sha256=owkrl7Nk171deLp5sQB_yH3crvR9P4H6K6uM5IBlTBA,131
itk_variant_demo-0.0.1.dist-info/variant.json,sha256=Mp3a1VnGXCdxnE1_dTQg3L4GBLNB_NS8-W3O4ayhIdA,314
itk_variant_demo-0.0.1.dist-info/RECORD,,
```

Two lines differ between the variants: `variant.json` (different content +
size) and `_demo.cpython-312-darwin.so` (different hash because
`-DITK_VARIANT_DEMO_TBB=ON` was set for the variant build but not for the
stock/null one). The other entries — sources, METADATA, WHEEL — are
byte-identical. So a variant build genuinely produces a *different binary*,
not just a metadata-tagged copy.

## 5. `WHEEL` (unchanged)

Both wheels' `WHEEL` files are 131 bytes and produce the same sha256 in
RECORD, so no field of `WHEEL` is touched. PR #1284's design choice is
that variant identity lives entirely in `variant.json` plus the filename
suffix — it does not introduce new tags into `WHEEL`. This is the right
call: it keeps existing wheel tooling that only inspects `WHEEL` working
unmodified, and it means that if PEP 817 were withdrawn or replaced, the
remaining `variant.json` could simply be ignored and the wheel would
revert to a normal wheel modulo its filename.

## 6. Installer behavior (today, on a non-aware installer)

Tested via `pip install --dry-run` (pip 25.x) on the same machine that
built the wheels:

```
$ pip install --dry-run itk_variant_demo-0.0.1-cp312-cp312-macosx_15_0_arm64-tbbon.whl
ERROR: Invalid build number: cp312 in
       'itk_variant_demo-0.0.1-cp312-cp312-macosx_15_0_arm64-tbbon'
```

```
$ pip install --dry-run itk_variant_demo-0.0.1-cp312-cp312-macosx_15_0_arm64.whl
Processing ./itk_variant_demo-0.0.1-cp312-cp312-macosx_15_0_arm64.whl
Would install itk_variant_demo-0.0.1
```

This is the desired behavior on a variant-unaware installer: pip parses
filenames with PEP 427's optional-build-tag grammar, which means it
**right-aligns** the components and tries to interpret the last
unaccounted-for slot (here, `cp312` between the version and the next
known segment) as a build number. Because build numbers must start with
a digit, the wheel is refused outright — pip never sees the binary,
never extracts it, and never installs an artifact whose variant features
might not match the host. The same wheel without the `-tbbon` suffix
installs cleanly. To consume the variant wheel today, an operator must
either drop the suffix manually or use a variants-aware installer
(none exists on PyPI as of experiment time).

This refusal is not the cleanest possible PEP 817 reject path — a
"build number" error message is misleading — but it is **safe**, which
is the more important property.

## See also

- [`findings.md`](findings.md) — gotchas and production-build hook points.
- [`pilot/`](../pilot/) — the fork-built reference wheels.
