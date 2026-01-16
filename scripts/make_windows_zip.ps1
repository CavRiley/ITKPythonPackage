<#  make_windows_zip.ps1
    It will compute all other paths from the script location.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---- compute paths from this script location ----
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path          # ...\ITKPythonPackage\scripts
$IPPDir      = Split-Path -Parent $ScriptDir                            # ...\ITKPythonPackage
$BuildScript = Join-Path $ScriptDir "build_wheels.py"                   # ...\ITKPythonPackage\scripts\build_wheels.py
$PythonExe   = Get-Command python | Select-Object -ExpandProperty Source

$BuildRoot    = "C:\"
$ITKGitTag    = if ($env:ITK_GIT_TAG) { $env:ITK_GIT_TAG } else { "v6.0b02" }

# Derived paths: adjust these roots if you want different defaults
$ItkSourceDir   = Join-Path (Split-Path -Qualifier $BuildRoot) "si"      # C:\si
$BuildDirRoot   = Join-Path (Split-Path -Qualifier $BuildRoot) "wb"      # C:\wb

if (-not (Test-Path -LiteralPath $ItkSourceDir)) {
    Write-Host "Creating ITK source dir: $ItkSourceDir"
    New-Item -ItemType Directory -Path $ItkSourceDir -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $BuildDirRoot)) {
    Write-Host "Creating Build dir root: $BuildDirRoot"
    New-Item -ItemType Directory -Path $BuildDirRoot -Force | Out-Null
}

# ---- basic validation and directory creation ----
if (-not (Test-Path -LiteralPath $PythonExe))   { throw "Python not found: $PythonExe" }
if (-not (Test-Path -LiteralPath $BuildScript)) { throw "build_wheels.py not found: $BuildScript" }
if (-not (Test-Path -LiteralPath $BuildRoot))    { throw "Repo root not found: $BuildRoot" }

# ---- run in repo root ----
Push-Location $IPPDir
try {
    $platformEnvs = @("windows-py39", "windows-py310", "windows-py311")

    foreach ($envName in $platformEnvs) {
        Write-Host "=== Building wheels for $envName ==="
        & $PythonExe $BuildScript `
            --platform-env $envName `
            --itk-source-dir $ItkSourceDir `
            --build-dir-root $BuildDirRoot `
            --build-itk-tarball-cache `
            --lib-paths '' '' `
            --itk-module-deps '' `
            --build-dir-root 'C:\wb' `
            --itk-git-tag $ITKGitTag `
            --itk-source-dir 'C:\si' `
            --itk-pythonpackage-org InsightSoftwareConsortium `
            --itk-pythonpackage-tag HEAD `
            --no-use-sudo `
            --no-use-ccache

        if ($LASTEXITCODE -ne 0) {
            throw "build_wheels.py failed for $envName (exit code $LASTEXITCODE)"
        }
    }
}

finally {
    Pop-Location
}