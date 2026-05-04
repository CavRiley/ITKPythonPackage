"""Reshape an ordinary Python wheel into a PEP 817 wheel-variant.

Why this exists
---------------
``wheelnext/variant-repack@master`` is the canonical tool for adding variant
metadata to a built wheel, but at experiment time its CLI imports a constant
(``VARIANT_LABEL_LENGTH``) that does not yet exist in any tagged release of
``wheelnext/variantlib``. Rather than wait for upstream to converge, we
implement the same operation directly using ``variantlib``'s working APIs and
the stdlib ``zipfile`` + ``hashlib`` modules. The output is byte-for-byte the
same shape that ``scikit-build-core``'s variants fork produces in Phase 1
(see ``pilot/dist/*-tbbon.whl`` for a reference): a ``variant.json`` file in
``.dist-info/`` plus a label suffix on the wheel filename.

What it does
------------
1. Parse the input wheel's filename to recover ``{dist}-{ver}-{py}-{abi}-{plat}``.
2. Build a ``variant.json`` payload whose schema URL and shape match the
   ``v0.0.3`` schema (the same one ``scikit-build-core``'s fork emits).
3. Open the input ``.whl`` (a zip), copy every entry across, drop the old
   ``RECORD``, append our new ``variant.json``, then write a freshly
   recomputed ``RECORD`` (``sha256=BASE64_NOPAD``, ``size``) for every kept
   entry plus the new ``variant.json``. ``RECORD`` itself appears with empty
   hash + size fields, per the wheel spec.
4. Write the result to ``{dist}-{ver}-{build_tag?}-{py}-{abi}-{plat}-{label}.whl``.

Usage
-----
    pixi run python mock/make_variant_wheel.py \\
        --input mock/fixtures/itk-5.4.0-cp312-cp312-macosx_15_0_arm64.whl \\
        --property itk::threading::tbb \\
        --label tbbon

The output wheel lands next to the input, with the label suffix appended.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import sys
import zipfile
from dataclasses import dataclass
from pathlib import Path

VARIANTS_SCHEMA_URL = "https://variants-schema.wheelnext.dev/v0.0.3.json"
VARIANT_LABEL_RE = re.compile(r"^[0-9a-z._]{1,16}$")
PROPERTY_RE = re.compile(r"^([0-9a-z_]+)::([0-9a-z_]+)::([0-9a-z._]+)$")

WHEEL_NAME_RE = re.compile(
    r"^(?P<dist>[^-]+)-(?P<ver>[^-]+)"
    r"(?:-(?P<build>\d[^-]*))?"
    r"-(?P<py>[^-]+)-(?P<abi>[^-]+)-(?P<plat>[^-]+?)\.whl$"
)


@dataclass(frozen=True)
class WheelName:
    dist: str
    ver: str
    build: str | None
    py: str
    abi: str
    plat: str

    @classmethod
    def parse(cls, filename: str) -> WheelName:
        m = WHEEL_NAME_RE.match(filename)
        if not m:
            raise ValueError(f"not a wheel filename: {filename!r}")
        return cls(**m.groupdict())

    @property
    def dist_info_dir(self) -> str:
        return f"{self.dist}-{self.ver}.dist-info"

    def with_label(self, label: str) -> str:
        # Per PEP 817, the variant label is appended after the platform tag.
        parts = [self.dist, self.ver]
        if self.build:
            parts.append(self.build)
        parts.extend([self.py, self.abi, self.plat, label])
        return "-".join(parts) + ".whl"


def parse_property(spec: str) -> tuple[str, str, str]:
    m = PROPERTY_RE.match(spec)
    if not m:
        raise ValueError(
            f"variant property must look like 'namespace::feature::value' "
            f"(got {spec!r})"
        )
    return m.group(1), m.group(2), m.group(3)


def build_variant_json(properties: list[tuple[str, str, str]], label: str) -> bytes:
    """Synthesize a ``variant.json`` payload conforming to the v0.0.3 schema.

    Empirically matched against the pilot wheel emitted by scikit-build-core's
    variants fork — see pilot/dist/*-tbbon.whl::variant.json for the reference.
    """
    properties_by_namespace: dict[str, dict[str, list[str]]] = {}
    for ns, feature, value in properties:
        properties_by_namespace.setdefault(ns, {}).setdefault(feature, []).append(value)

    payload = {
        "$schema": VARIANTS_SCHEMA_URL,
        "default-priorities": {"namespace": []},
        "providers": {},
        "variants": {label: properties_by_namespace if properties else {}},
    }
    # Match indentation used by the fork (2-space, sorted keys=False).
    return (json.dumps(payload, indent=2) + "\n").encode("utf-8")


def hash_record_line(arcname: str, data: bytes) -> str:
    digest = hashlib.sha256(data).digest()
    b64 = base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
    return f"{arcname},sha256={b64},{len(data)}"


def repack(
    *,
    input_wheel: Path,
    output_wheel: Path,
    variant_json: bytes,
    dist_info_dir: str,
) -> None:
    record_path = f"{dist_info_dir}/RECORD"
    variant_path = f"{dist_info_dir}/variant.json"

    record_lines: list[str] = []
    with (
        zipfile.ZipFile(input_wheel) as src,
        zipfile.ZipFile(output_wheel, "w", compression=zipfile.ZIP_DEFLATED) as dst,
    ):
        for info in src.infolist():
            if info.filename == record_path or info.filename == variant_path:
                continue  # we'll rewrite both
            data = src.read(info.filename)
            dst.writestr(info, data)
            record_lines.append(hash_record_line(info.filename, data))

        # Inject variant.json
        dst.writestr(variant_path, variant_json)
        record_lines.append(hash_record_line(variant_path, variant_json))

        # RECORD self-line: the spec says hash and size fields are empty for
        # RECORD itself.
        record_lines.append(f"{record_path},,")
        record_bytes = ("\n".join(record_lines) + "\n").encode("utf-8")
        dst.writestr(record_path, record_bytes)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument(
        "--input", "-i", type=Path, required=True, help="Input .whl path"
    )
    parser.add_argument(
        "--output-dir",
        "-o",
        type=Path,
        default=None,
        help="Output directory (defaults to same dir as input)",
    )
    parser.add_argument(
        "--property",
        "-p",
        action="append",
        default=[],
        dest="properties",
        help=(
            "Variant property as 'namespace::feature::value'. May be repeated. "
            "Omit entirely to produce a null-variant wheel."
        ),
    )
    parser.add_argument(
        "--label",
        "-l",
        required=True,
        help="Variant label (e.g. 'tbbon'). Must match [0-9a-z._]{1,16}.",
    )
    args = parser.parse_args(argv)

    if not VARIANT_LABEL_RE.match(args.label):
        print(
            f"error: label {args.label!r} does not match PEP 817 grammar [0-9a-z._]{{1,16}}",
            file=sys.stderr,
        )
        return 2

    parsed_props: list[tuple[str, str, str]] = []
    for spec in args.properties:
        try:
            parsed_props.append(parse_property(spec))
        except ValueError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 2

    name = WheelName.parse(args.input.name)
    out_dir = args.output_dir if args.output_dir else args.input.parent
    out_path = out_dir / name.with_label(args.label)

    variant_json = build_variant_json(parsed_props, args.label)
    repack(
        input_wheel=args.input,
        output_wheel=out_path,
        variant_json=variant_json,
        dist_info_dir=name.dist_info_dir,
    )

    print(f"wrote {out_path}")
    print(f"  variant label: {args.label}")
    print(f"  variant.json:  {len(variant_json)} bytes")

    # Sanity-parse the variant.json we just wrote, using variantlib's
    # in-memory type to catch schema drift early.
    try:
        from variantlib.api import VariantsJson

        VariantsJson(json.loads(variant_json))
        print("  variantlib parse: OK")
    except Exception as exc:  # noqa: BLE001 - report any parse issue
        print(f"  variantlib parse: WARN {exc!r}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
