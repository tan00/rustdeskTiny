param(
    [string]$PythonPath = "python",
    [string]$OutputRoot,
    [string]$InstallerOutput
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $projectRoot 'dist\windows-x64-release'
}
if ([string]::IsNullOrWhiteSpace($InstallerOutput)) {
    $InstallerOutput = Join-Path $projectRoot 'dist\RustDeskTiny-install.exe'
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$InstallerOutput = [IO.Path]::GetFullPath($InstallerOutput)
$distRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'dist')) + [IO.Path]::DirectorySeparatorChar
if (-not ($OutputRoot + [IO.Path]::DirectorySeparatorChar).StartsWith(
        $distRoot,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputRoot must be inside $distRoot"
}

if ([string]::IsNullOrWhiteSpace($env:VCPKG_ROOT)) {
    throw 'VCPKG_ROOT is not set'
}
if ([string]::IsNullOrWhiteSpace($env:LIBCLANG_PATH)) {
    throw 'LIBCLANG_PATH is not set'
}
foreach ($required in @(
        (Join-Path $env:VCPKG_ROOT 'vcpkg.exe'),
        (Join-Path $env:LIBCLANG_PATH 'libclang.dll'))) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required build dependency is missing: $required"
    }
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter is not available'
}

$previousWrapper = $env:RUSTC_WRAPPER
$previousRustLog = $env:RUST_LOG
try {
    $env:RUSTC_WRAPPER = ''
    $env:RUST_LOG = 'info'
    Push-Location $projectRoot
    try {
        & flutter_rust_bridge_codegen `
            --rust-input ./src/flutter_ffi.rs `
            --dart-output ./flutter/lib/generated_bridge.dart `
            --llvm-path (Split-Path -Parent $env:LIBCLANG_PATH)
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter bridge generation failed with exit code $LASTEXITCODE"
        }
        & $PythonPath build.py --portable --flutter --skip-portable-pack --rustdesk-tiny
        if ($LASTEXITCODE -ne 0) {
            throw "RustDesk build failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}
finally {
    $env:RUSTC_WRAPPER = $previousWrapper
    $env:RUST_LOG = $previousRustLog
}

$runner = Join-Path $projectRoot 'flutter\build\windows\x64\runner\Release'
if (-not (Test-Path -LiteralPath $runner -PathType Container)) {
    throw "Flutter release directory is missing: $runner"
}
if (Test-Path -LiteralPath $OutputRoot) {
    Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}
Copy-Item -LiteralPath $runner -Destination $OutputRoot -Recurse

$sourceExe = @('rustdesk.exe', 'RustDesk.exe') |
    ForEach-Object { Join-Path $OutputRoot $_ } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
if (-not $sourceExe) {
    throw 'RustDesk executable was not produced'
}
$tinyExe = Join-Path $OutputRoot 'RustDeskTiny.exe'
if ($sourceExe -ne $tinyExe) {
    Move-Item -LiteralPath $sourceExe -Destination $tinyExe -Force
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'LICENCE') -Destination $OutputRoot
$portableDir = Join-Path $projectRoot 'libs\portable'
Push-Location $portableDir
try {
    & $PythonPath -m pip install -r requirements.txt
    if ($LASTEXITCODE -ne 0) {
        throw "Portable packer dependencies failed with exit code $LASTEXITCODE"
    }
    & $PythonPath '.\generate.py' -f $OutputRoot -o . -e $tinyExe
    if ($LASTEXITCODE -ne 0) {
        throw "RustDesk portable packer failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
$generatedInstaller = Join-Path $projectRoot 'target\release\rustdesk-portable-packer.exe'
if (-not (Test-Path -LiteralPath $generatedInstaller -PathType Leaf)) {
    throw "RustDesk portable packer output is missing: $generatedInstaller"
}
$installerParent = Split-Path -Parent $InstallerOutput
if (-not (Test-Path -LiteralPath $installerParent -PathType Container)) {
    New-Item -ItemType Directory -Path $installerParent -Force | Out-Null
}
Copy-Item -LiteralPath $generatedInstaller -Destination $InstallerOutput -Force
Write-Host "RustDeskTiny output: $OutputRoot"
Write-Host "RustDeskTiny installer: $InstallerOutput"
