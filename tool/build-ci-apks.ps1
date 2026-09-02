# Builds non-shippable release-mode APKs in CI. Debug signing is explicit; the production
# build remains tool/build-apks.ps1 and still requires the private Luqma upload key.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$out = Join-Path $root 'build\ci-apks'
New-Item -ItemType Directory -Force -Path $out | Out-Null

$defines = @(
    '--dart-define=LUQMA_SUPABASE_URL=https://ci.invalid',
    '--dart-define=LUQMA_SUPABASE_PUBLISHABLE_KEY=sb_publishable_ci_smoke'
)

foreach ($app in @('customer_app', 'merchant_app', 'admin_app')) {
    Write-Host "`n===== release smoke: $app =====" -ForegroundColor Cyan
    Push-Location (Join-Path $root "apps\$app")
    try {
        flutter build apk --release --target-platform android-arm64 --split-per-abi `
            --android-project-arg=luqma.debugSigning=true @defines
        if ($LASTEXITCODE -ne 0) { throw "$app release smoke failed" }

        $apk = Join-Path (Get-Location) 'build\app\outputs\flutter-apk\app-arm64-v8a-release.apk'
        $blob = [IO.File]::ReadAllText($apk, [Text.Encoding]::ASCII)
        if ($blob -match 'sb_secret_[A-Za-z0-9_-]+' -or $blob -match '"service_role"') {
            throw "$app embeds a privileged Supabase credential marker"
        }
        foreach ($jwt in ([regex]'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{20,}').Matches($blob)) {
            $payload = $jwt.Value.Split('.')[1].Replace('-', '+').Replace('_', '/')
            switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
            try { $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) }
            catch { continue }
            if ($json -match '"role"\s*:\s*"service_role"') {
                throw "$app embeds a service_role key"
            }
        }
        Copy-Item $apk (Join-Path $out "luqma-$($app -replace '_app$','')-ci.apk") -Force
    } finally {
        Pop-Location
    }
}

Get-ChildItem $out -Filter *.apk | Select-Object Name, Length
