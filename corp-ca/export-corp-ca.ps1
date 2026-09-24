# Exports the corporate TLS-interception CA chain (Cummins Prisma) to corp-ca-bundle.crt
# so that it can be baked into container build stages.
#
# Usage (PowerShell, from anywhere):
#   ./corp-ca/export-corp-ca.ps1
#
# Re-run this whenever the proxy CA is rotated.

$ErrorActionPreference = 'Stop'

$Hosts = @(
    'index.crates.io',
    'static.crates.io',
    'github.com',
    'ghcr.io',
    'pypi.org',
    'files.pythonhosted.org',
    'services.gradle.org',
    'repo.maven.apache.org',
    'plugins.gradle.org',
    'deb.debian.org'
)

# Only certificates whose subject matches this pattern are exported.
# Everything else is a genuine public root that the base images already trust.
$CorpPattern = 'Cummins'

$seen = @{}
$out = New-Object System.Collections.Generic.List[string]

foreach ($h in $Hosts) {
    try {
        $global:els = @()
        $tcp = New-Object System.Net.Sockets.TcpClient($h, 443)
        $cb = {
            param($sn, $cert, $ch, $err)
            $global:els = @($ch.ChainElements)
            return $true
        }
        $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, $cb)
        $ssl.AuthenticateAsClient($h)
        $ssl.Dispose()
        $tcp.Close()

        # index 0 is the leaf certificate - skip it, we only want CAs
        for ($i = 1; $i -lt $global:els.Count; $i++) {
            $c = $global:els[$i].Certificate
            if ($c.Subject -notmatch $CorpPattern) { continue }
            if ($seen.ContainsKey($c.Thumbprint)) { continue }
            $seen[$c.Thumbprint] = $true

            Write-Host "  + [$h] $($c.Subject)"
            $out.Add("# $($c.Subject)")
            $out.Add('-----BEGIN CERTIFICATE-----')
            $out.Add([Convert]::ToBase64String($c.RawData, 'InsertLineBreaks'))
            $out.Add('-----END CERTIFICATE-----')
        }
    }
    catch {
        Write-Host "  ! skipped $h : $($_.Exception.Message)"
    }
}

if ($seen.Count -eq 0) {
    Write-Warning 'No corporate CA certificates found. Are you on the corporate network / VPN?'
    exit 1
}

$dest = Join-Path $PSScriptRoot 'corp-ca-bundle.crt'
Set-Content -Path $dest -Value $out -Encoding ascii
Write-Host "Wrote $($seen.Count) certificate(s) to $dest"
Write-Host 'Next: ./corp-ca/build-patched-bases.ps1'
