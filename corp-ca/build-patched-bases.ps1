# Builds CA-patched copies of every base image used by the commercial-sdv-stack
# docker-compose build. Run this once (and again whenever the proxy CA rotates).
#
#   ./corp-ca/export-corp-ca.ps1          # refresh the CA bundle
#   ./corp-ca/build-patched-bases.ps1     # rebuild the patched base images
#
# Afterwards build the stack with the override file:
#   cd commercial-sdv-stack
#   docker compose -f docker-compose.yaml -f docker-compose.corp-ca.yaml build

$ErrorActionPreference = 'Stop'

# upstream image  ->  local patched tag
$Bases = [ordered]@{
    'ghcr.io/rust-cross/rust-musl-cross:x86_64-musl'  = 'corp-ca/rust-musl-cross:x86_64-musl'
    'ghcr.io/rust-cross/rust-musl-cross:aarch64-musl' = 'corp-ca/rust-musl-cross:aarch64-musl'
    'rust:1.88-slim-trixie'                           = 'corp-ca/rust:1.88-slim-trixie'
    'debian:trixie-slim'                              = 'corp-ca/debian:trixie-slim'
    'gradle:8-jdk21'                                  = 'corp-ca/gradle:8-jdk21'
    'eclipse-temurin:21-jre'                          = 'corp-ca/eclipse-temurin:21-jre'
    'python:3.12-slim-trixie'                         = 'corp-ca/python:3.12-slim-trixie'
}

$bundle = Join-Path $PSScriptRoot 'corp-ca-bundle.crt'
if (-not (Test-Path $bundle)) {
    Write-Error "corp-ca-bundle.crt not found. Run ./corp-ca/export-corp-ca.ps1 first."
}

$failed = @()
$dockerfile = Join-Path $PSScriptRoot 'Dockerfile.ca-patch'
foreach ($base in $Bases.Keys) {
    $tag = $Bases[$base]
    Write-Host "==> $base  ->  $tag" -ForegroundColor Cyan
    # docker writes build progress to stderr; don't let that trip $ErrorActionPreference
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    docker build --build-arg "BASE=$base" -f $dockerfile -t $tag $PSScriptRoot 2>&1 |
        ForEach-Object { Write-Host $_ }
    $code = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($code -ne 0) { $failed += $base }
}

if ($failed.Count -gt 0) {
    Write-Warning "Failed to patch: $($failed -join ', ')"
    exit 1
}
Write-Host 'All base images patched.' -ForegroundColor Green
