param([string]$Only, [string]$PublishableKey)

# The two builds Google Play will accept.
#
# Play does not take an APK for a new app: the first listing, every closed-testing build
# and every production release go up as an Android App Bundle, and Play derives the
# per-device APKs from it. `tool/build-apks.ps1` still produces the signed APKs for
# direct installs and for the merchant's handset; this script is the store path.
#
#   powershell -ExecutionPolicy Bypass -File tool\build-aab.ps1
#
# AdminApp is deliberately absent. It is distributed as a direct APK and never listed on
# Play, so a bundle for it would be an artifact nobody can use.
#
# The bundle is signed by the same release key as the APKs (each app's Gradle file reads
# signing/key.properties). Keep that key: once Play App Signing is enrolled with it, the
# key is the identity of the listing, and an APK already on a tester's phone can only be
# updated by a bundle signed with the same identity.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'release-common.ps1')

$outDir = Join-Path $root 'build\aab'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$targets = @('customer_app', 'merchant_app')
if ($Only) {
  $targets = @($targets | Where-Object { $_ -eq "${Only}_app" -or $_ -eq $Only })
  if ($targets.Count -eq 0) {
    throw "No Play app called '$Only'. Use customer or merchant; AdminApp is a direct APK."
  }
}

# Fetched after the argument check: a typo should not spend a network round-trip first.
$publishable = if ($PublishableKey) { $PublishableKey } else { Get-LuqmaPublishableKey }
$defines = Get-LuqmaReleaseDefines -PublishableKey $publishable

foreach ($app in $targets) {
  Write-Host "`n=== $app (app bundle) ===" -ForegroundColor Cyan
  Push-Location (Join-Path $root "apps\$app")
  try {
    # Clean first, for the same reason the APK build does: a release should be made from
    # the code in front of you, not from a kernel some earlier build left behind.
    & flutter clean | Out-Null
    & flutter build appbundle --release --target-platform android-arm64 @defines
    if ($LASTEXITCODE -ne 0) { throw "$app failed to build an app bundle" }

    $built = Join-Path (Get-Location) 'build\app\outputs\bundle\release\app-release.aab'
    if (-not (Test-Path $built)) {
      throw "$app produced no app-release.aab at $built"
    }

    # The bundle is a zip; `Assert-NoPrivilegedKeys` reads its entries rather than the
    # file as one text blob, so a key inside libapp.so is still found.
    Assert-NoPrivilegedKeys $built

    $name = $app -replace '_app$', ''
    $destination = Join-Path $outDir "luqma-$name.aab"
    Copy-Item $built $destination -Force

    Write-Host "  $destination" -ForegroundColor Green
  } finally {
    Pop-Location
  }
}

Write-Host "`nDone. App bundles in $outDir" -ForegroundColor Green
Get-ChildItem $outDir -Filter *.aab |
  Select-Object Name, @{n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } } |
  Format-Table -AutoSize

Write-Host @"
Before uploading:
  - versionName/versionCode are read from each app's pubspec.yaml. The first Play build
    should be 1.0.0+N, not 0.9.0: Play accepts the name, but the force-update gate and
    the owner's support script compare against 1.0.0.
  - upload with the same keystore, and enroll Play App Signing with that key rather than
    letting Google generate a new one, or every APK already installed will refuse the
    Play update.
"@
