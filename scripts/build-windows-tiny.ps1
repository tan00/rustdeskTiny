param(
    [string]$PythonPath = "python",
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $projectRoot 'dist\windows-x64-release'
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
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
Write-Host "RustDeskTiny output: $OutputRoot"
