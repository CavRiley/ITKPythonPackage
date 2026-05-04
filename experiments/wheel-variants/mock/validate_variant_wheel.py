"""Validate that a wheel is a well-formed PEP 817 variant wheel.

Checks:
  1. The filename has a label suffix matching ``[0-9a-z._]{1,16}``.
  2. The dist-info contains exactly one ``variant.json``.
  3. The ``variant.json`` parses (against variantlib) and declares the same
     label that the filename advertises.
  4. ``RECORD`` lists ``variant.json`` with a hash matching the file body.
  5. Every other RECORD entry's hash + size matches the actual file body.
  6. ``WHEEL`` and ``METADATA`` are unchanged in name/spec — this script does
     not check their content semantics, just that they exist.

Usage:
    pixi run python mock/validate_variant_wheel.py mock/fixtures/*-tbbon.whl
"""

from __future__ import annotations

import base64
import hashlib
import json
import re
import sys
import zipfile
from pathlib import Path

VARIANT_LABEL_RE = re.compile(r"^[0-9a-z._]{1,16}$")
WHEEL_NAME_RE = re.compile(
    r"^(?P<dist>[^-]+)-(?P<ver>[^-]+)"
    r"(?:-(?P<build>\d[^-]*))?"
    r"-(?P<py>[^-]+)-(?P<abi>[^-]+)-(?P<plat>[^-]+?)"
    r"-(?P<variant>[0-9a-z._]{1,16})\.whl$"
)


def b64_sha256(data: bytes) -> str:
    digest = hashlib.sha256(data).digest()
    return base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")


def parse_record(record_text: str) -> dict[str, tuple[str | None, int | None]]:
    """RECORD lines: 'arcname,hash_spec,size'. Empty hash_spec/size for RECORD itself."""
    out: dict[str, tuple[str | None, int | None]] = {}
    for line in record_text.splitlines():
        if not line.strip():
            continue
        # An arcname can contain commas only if quoted, but the wheel spec
        # disallows commas in filenames, so naive split is safe here.
        arcname, hash_spec, size = line.rsplit(",", 2)
        out[arcname] = (hash_spec or None, int(size) if size else None)
    return out


PLAIN_WHEEL_NAME_RE = re.compile(
    r"^(?P<dist>[^-]+)-(?P<ver>[^-]+)"
    r"(?:-(?P<build>\d[^-]*))?"
    r"-(?P<py>[^-]+)-(?P<abi>[^-]+)-(?P<plat>[^-]+?)\.whl$"
)


def validate(wheel_path: Path) -> tuple[str, list[str]]:
    """Return (status, errors). status in {'pass', 'fail', 'skip'}."""
    errors: list[str] = []

    m = WHEEL_NAME_RE.match(wheel_path.name)
    if not m:
        # Distinguish "not a variant wheel at all" (skip) from "broken
        # wheel-grammar" (fail) — the latter is much rarer.
        if PLAIN_WHEEL_NAME_RE.match(wheel_path.name):
            return ("skip", ["plain wheel (no variant label suffix)"])
        return ("fail", [f"filename {wheel_path.name!r} does not match wheel grammar"])
    advertised_label = m.group("variant")
    if not VARIANT_LABEL_RE.match(advertised_label):
        errors.append(f"filename label {advertised_label!r} violates PEP 817 grammar")
        return ("fail", errors)

    dist_info = f"{m.group('dist')}-{m.group('ver')}.dist-info"
    variant_path = f"{dist_info}/variant.json"
    record_path = f"{dist_info}/RECORD"

    with zipfile.ZipFile(wheel_path) as zf:
        names = set(zf.namelist())

        if variant_path not in names:
            errors.append(f"missing {variant_path}")
            return ("fail", errors)
        if record_path not in names:
            errors.append(f"missing {record_path}")
            return ("fail", errors)

        # variant.json shape + declared label
        variant_bytes = zf.read(variant_path)
        try:
            payload = json.loads(variant_bytes)
        except json.JSONDecodeError as exc:
            errors.append(f"variant.json is not valid JSON: {exc}")
            return ("fail", errors)

        variants_dict = payload.get("variants", {})
        if advertised_label not in variants_dict:
            errors.append(
                f"variant.json declares variants {sorted(variants_dict)!r}, "
                f"which does not include the filename label {advertised_label!r}"
            )

        # variantlib parse (best-effort — schema may evolve).
        try:
            from variantlib.api import VariantsJson

            VariantsJson(payload)
        except Exception as exc:  # noqa: BLE001 - bubble up as warning
            errors.append(f"variantlib refuses payload: {exc!r}")

        # RECORD hash + size sanity
        record_text = zf.read(record_path).decode("utf-8")
        record = parse_record(record_text)

        if record_path not in record:
            errors.append("RECORD does not include a self-entry")
        else:
            hash_spec, size = record[record_path]
            if hash_spec or size:
                errors.append(
                    "RECORD self-line should have empty hash and size; "
                    f"got hash={hash_spec!r}, size={size!r}"
                )

        if variant_path not in record:
            errors.append("RECORD does not list variant.json")
        else:
            hash_spec, size = record[variant_path]
            if hash_spec is None or not hash_spec.startswith("sha256="):
                errors.append(f"variant.json RECORD hash is not sha256: {hash_spec!r}")
            else:
                expected_b64 = hash_spec.split("=", 1)[1]
                actual_b64 = b64_sha256(variant_bytes)
                if expected_b64 != actual_b64:
                    errors.append(
                        f"variant.json hash mismatch: RECORD says {expected_b64}, "
                        f"actual is {actual_b64}"
                    )
            if size != len(variant_bytes):
                errors.append(
                    f"variant.json size mismatch: RECORD says {size}, "
                    f"actual is {len(variant_bytes)}"
                )

        # Spot-check every other RECORD entry against the live file body.
        for arcname, (hash_spec, size) in record.items():
            if arcname == record_path:
                continue
            if arcname not in names:
                errors.append(f"RECORD lists {arcname!r} but it is not in the zip")
                continue
            data = zf.read(arcname)
            if hash_spec is None or not hash_spec.startswith("sha256="):
                errors.append(f"{arcname}: RECORD hash is not sha256 ({hash_spec!r})")
                continue
            expected_b64 = hash_spec.split("=", 1)[1]
            actual_b64 = b64_sha256(data)
            if expected_b64 != actual_b64:
                errors.append(
                    f"{arcname}: hash mismatch (RECORD={expected_b64}, actual={actual_b64})"
                )
            if size != len(data):
                errors.append(
                    f"{arcname}: size mismatch (RECORD={size}, actual={len(data)})"
                )

        # WHEEL/METADATA presence
        for required in (f"{dist_info}/WHEEL", f"{dist_info}/METADATA"):
            if required not in names:
                errors.append(f"missing {required}")

    return ("fail" if errors else "pass", errors)


def main(argv: list[str]) -> int:
    if not argv:
        print(
            "usage: validate_variant_wheel.py <wheel-or-dir> [<wheel-or-dir> ...]",
            file=sys.stderr,
        )
        return 2

    targets: list[Path] = []
    for arg in argv:
        p = Path(arg)
        if p.is_dir():
            targets.extend(sorted(p.glob("*.whl")))
        elif p.suffix == ".whl":
            targets.append(p)
        else:
            print(f"warning: skipping non-wheel {arg}", file=sys.stderr)

    if not targets:
        print("no wheels found", file=sys.stderr)
        return 1

    overall = 0
    for wheel in targets:
        status, errs = validate(wheel)
        if status == "pass":
            print(f"PASS {wheel.name}")
        elif status == "skip":
            note = f" ({errs[0]})" if errs else ""
            print(f"SKIP {wheel.name}{note}")
        else:
            overall = 1
            print(f"FAIL {wheel.name}")
            for e in errs:
                print(f"  - {e}")
    return overall


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
