param([string]$Only)

# Builds the three non-shippable release-mode APKs in one go, for a desk or a full local
# run. The GitHub gate no longer calls this: it runs `build-ci-release.ps1` once per app
# in a matrix, so one app's failure does not hide another's and the job stays under its
# time ceiling.
#
# Debug signing is explicit; the production build remains `tool/build-apks.ps1` and still
# requires the private Luqma upload key.

$ErrorActionPreference = 'Stop'

$targets = @('customer_app', 'merchant_app', 'admin_app')
if ($Only) {
    $targets = @($targets | Where-Object { $_ -eq "${Only}_app" -or $_ -eq $Only })
    if ($targets.Count -eq 0) {
        throw "No app called '$Only'. Use customer, merchant or admin."
    }
}

foreach ($app in $targets) {
    & (Join-Path $PSScriptRoot 'build-ci-release.ps1') -App $app
    if ($LASTEXITCODE -ne 0) { throw "$app release smoke failed" }
}

Write-Host "`nDone. CI artifacts in build\ci-apks" -ForegroundColor Green
Get-ChildItem (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\ci-apks') -Filter *.apk |
    Select-Object Name, @{n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } } |
    Format-Table -AutoSize
