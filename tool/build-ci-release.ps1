param(
    [Parameter(Mandatory)][string]$App,
    [switch]$Bundle
)

# One app, one release artifact, in CI.
#
# This used to be one job that built all three APKs after the test suite. It took longer
# than the job's 45-minute ceiling, so the scheduled gate was cancelled at the build step
# for five days running — the checks passed and nobody could see it. Building one app per
# runner makes each artifact's failure its own line, and lets the two Play apps produce an
# AAB in parallel with the admin APK.
#
# The artifacts are signed with the debug key on purpose: they exist to prove the release
# graph compiles and to be scanned, never to be installed on a customer's phone.
# `tool/build-apks.ps1` and `tool/build-aab.ps1` are the signed paths.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'release-common.ps1')

$apps = @('customer_app', 'merchant_app', 'admin_app')
if ($App -notin $apps) {
    throw "No app called '$App'. Use customer_app, merchant_app or admin_app."
}

$name = $App -replace '_app$', ''
if ($Bundle -and $name -eq 'admin') {
    throw 'AdminApp is a direct APK and never a Play listing, so it has no app bundle.'
}

$defines = @(
    '--dart-define=LUQMA_SUPABASE_URL=https://ci.invalid',
    '--dart-define=LUQMA_SUPABASE_PUBLISHABLE_KEY=sb_publishable_ci_smoke'
)

$applicationIds = @{
    customer_app = 'com.luqma.customer'
    merchant_app = 'com.luqma.merchant'
    admin_app    = 'com.luqma.admin'
}

# The same forbidden list the signed build checks. MapLibre declares both location
# permissions in its AAR; the app manifests remove them, and this fails the smoke build
# if a dependency ever puts them back. AdminApp is not a Play listing and is left alone.
$forbiddenPermissions = @{
    customer_app = @(
        'android.permission.ACCESS_FINE_LOCATION',
        'android.permission.ACCESS_COARSE_LOCATION'
    )
    merchant_app = @(
        'android.permission.ACCESS_FINE_LOCATION',
        'android.permission.ACCESS_COARSE_LOCATION',
        'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS'
    )
    admin_app = @()
}

Push-Location (Join-Path $root "apps\$App")
try {
    if ($Bundle) {
        Write-Host "`n===== release app bundle: $App =====" -ForegroundColor Cyan
        & flutter build appbundle --release --target-platform android-arm64 `
            --android-project-arg=luqma.debugSigning=true @defines
        if ($LASTEXITCODE -ne 0) { throw "$App app bundle failed" }

        $built = Join-Path (Get-Location) 'build\app\outputs\bundle\release\app-release.aab'
        Assert-NoPrivilegedKeys $built

        $out = Join-Path $root 'build\ci-aab'
        New-Item -ItemType Directory -Force -Path $out | Out-Null
        Copy-Item $built (Join-Path $out "luqma-$name-ci.aab") -Force
        Write-Host "  $(Join-Path $out "luqma-$name-ci.aab")" -ForegroundColor Green
    } else {
        Write-Host "`n===== release APK: $App =====" -ForegroundColor Cyan
        & flutter build apk --release --target-platform android-arm64 `
            --android-project-arg=luqma.debugSigning=true @defines
        if ($LASTEXITCODE -ne 0) { throw "$App release smoke failed" }

        $built = Join-Path (Get-Location) 'build\app\outputs\flutter-apk\app-release.apk'
        Assert-NoPrivilegedKeys $built
        Test-ReleaseApk -Path $built -ApplicationId $applicationIds[$App] `
            -ForbiddenPermissions $forbiddenPermissions[$App] -MinimumTargetSdk 36 | Out-Null

        $out = Join-Path $root 'build\ci-apks'
        New-Item -ItemType Directory -Force -Path $out | Out-Null
        Copy-Item $built (Join-Path $out "luqma-$name-ci.apk") -Force
        Write-Host "  $(Join-Path $out "luqma-$name-ci.apk")" -ForegroundColor Green
    }
} finally {
    Pop-Location
}
