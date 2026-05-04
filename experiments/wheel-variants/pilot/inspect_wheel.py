"""Dump variant-relevant pieces of a wheel for human + automated inspection.

For each wheel passed in (or every *.whl under a given directory), prints:
- the filename and its parsed components
- the dist-info file listing
- the contents of variant.json (if present)
- the RECORD line for variant.json (so we can spot-check the hash)

Run from the sandbox:
    pixi run python pilot/inspect_wheel.py pilot/dist
"""

from __future__ import annotations

import json
import re
import sys
import zipfile
from pathlib import Path

WHEEL_NAME_RE = re.compile(
    r"^(?P<dist>[^-]+)-(?P<ver>[^-]+)"
    r"(?:-(?P<build>\d[^-]*))?"
    r"-(?P<py>[^-]+)-(?P<abi>[^-]+)-(?P<plat>[^-]+?)"
    r"(?:-(?P<variant>[0-9a-z._]{1,16}))?\.whl$"
)


def inspect(wheel: Path) -> None:
    print(f"\n=== {wheel.name} ===")
    m = WHEEL_NAME_RE.match(wheel.name)
    if not m:
        print("  (filename does not match wheel grammar)")
        return
    parts = {k: v for k, v in m.groupdict().items() if v}
    print(f"  parsed: {parts}")

    with zipfile.ZipFile(wheel) as zf:
        names = zf.namelist()
        dist_info = [
            n for n in names if "/" in n and n.split("/", 1)[0].endswith(".dist-info")
        ]
        print("  dist-info entries:")
        for n in sorted(dist_info):
            print(f"    {n}")

        variant_paths = [n for n in dist_info if n.endswith("/variant.json")]
        if not variant_paths:
            print("  variant.json: ABSENT")
        else:
            for vp in variant_paths:
                payload = json.loads(zf.read(vp))
                print(f"  variant.json @ {vp}:")
                print("    " + json.dumps(payload, indent=2).replace("\n", "\n    "))

        record_paths = [n for n in dist_info if n.endswith("/RECORD")]
        for rp in record_paths:
            record_text = zf.read(rp).decode()
            variant_lines = [
                ln for ln in record_text.splitlines() if "variant.json" in ln
            ]
            if variant_lines:
                print("  RECORD line(s) for variant.json:")
                for ln in variant_lines:
                    print(f"    {ln}")


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(
            "usage: inspect_wheel.py <wheel-or-dir> [<wheel-or-dir> ...]",
            file=sys.stderr,
        )
        return 2

    targets: list[Path] = []
    for arg in argv[1:]:
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

    for wheel in targets:
        inspect(wheel)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
