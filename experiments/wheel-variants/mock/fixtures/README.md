# mock/fixtures/

Drop a **real** ITK wheel here for the Phase-2 mock to operate on. The wheel
is **not** committed (`*.whl` is gitignored at the experiment root).

## Where to get one

Any of:

- A wheel produced by `pixi run build-itk-wheels` from the project root
  (look in `dist/` of that build).
- A CI artifact from
  [InsightSoftwareConsortium/ITKPythonBuilds](https://github.com/InsightSoftwareConsortium/ITKPythonBuilds/releases).
- A `pip download itk --no-deps -d .` from a fresh venv on the host platform.

The Phase-2 wrapper (`mock/repack_itk_wheel.sh`) globs `*.whl` here, so the
exact filename does not matter — pick any compatible wheel.

## After running the mock

The output goes back into this same directory with a `-tbbon` suffix appended
to the filename. Both files (input + output) stay gitignored.
